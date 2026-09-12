export const PROTOCOL_VERSION = 1;
export const BROWSER_TO_HOST_LIMIT = 64 * 1024;
export const HOST_TO_BROWSER_LIMIT = 1024 * 1024;
export const DEFAULT_RAW_CHUNK_BYTES = 44 * 1024;
export const DEFAULT_TIMEOUT_MS = 15_000;
export const MAX_LOGICAL_BYTES = 16 * 1024 * 1024;
export const MAX_CHUNKS = 512;
export const MAX_CONCURRENT_TRANSFERS = 8;

const encoder = new TextEncoder();
const decoder = new TextDecoder("utf-8", { fatal: true });

function randomId() {
  if (globalThis.crypto?.randomUUID) return globalThis.crypto.randomUUID();
  return `${Date.now().toString(36)}-${Math.random().toString(36).slice(2)}`;
}

export function utf8ByteLength(value) {
  return encoder.encode(value).byteLength;
}

export function fnv1a(bytes) {
  let hash = 0x811c9dc5;
  for (const byte of bytes) {
    hash ^= byte;
    hash = Math.imul(hash, 0x01000193) >>> 0;
  }
  return hash.toString(16).padStart(8, "0");
}

function bytesToBase64(bytes) {
  let binary = "";
  const stride = 0x8000;
  for (let offset = 0; offset < bytes.length; offset += stride) {
    binary += String.fromCharCode(...bytes.subarray(offset, offset + stride));
  }
  return btoa(binary);
}

function base64ToBytes(value) {
  const binary = atob(value);
  const result = new Uint8Array(binary.length);
  for (let index = 0; index < binary.length; index += 1) {
    result[index] = binary.charCodeAt(index);
  }
  return result;
}

export function makeLogicalMessage(route, payload, requestId = randomId()) {
  return {
    protocolVersion: PROTOCOL_VERSION,
    requestId,
    route,
    payload,
    sentAt: new Date().toISOString()
  };
}

export function encodeLogicalMessage(message, options = {}) {
  const rawChunkBytes = options.rawChunkBytes ?? DEFAULT_RAW_CHUNK_BYTES;
  const physicalLimit = options.physicalLimit ?? BROWSER_TO_HOST_LIMIT;
  const transferId = options.transferId ?? randomId();
  const bytes = encoder.encode(JSON.stringify(message));
  const checksum = fnv1a(bytes);
  const total = Math.max(1, Math.ceil(bytes.length / rawChunkBytes));
  const chunks = [];

  for (let index = 0; index < total; index += 1) {
    const slice = bytes.subarray(index * rawChunkBytes, (index + 1) * rawChunkBytes);
    const chunk = {
      protocolVersion: PROTOCOL_VERSION,
      type: "chunk",
      transferId,
      requestId: message.requestId ?? null,
      index,
      total,
      byteLength: bytes.length,
      checksum,
      encoding: "base64",
      payload: bytesToBase64(slice)
    };
    const size = utf8ByteLength(JSON.stringify(chunk));
    if (size >= physicalLimit) {
      throw new Error(`encoded chunk is ${size} bytes; limit is ${physicalLimit}`);
    }
    chunks.push(chunk);
  }
  return chunks;
}

export class ChunkAssembler {
  constructor({ timeoutMs = DEFAULT_TIMEOUT_MS, now = () => Date.now() } = {}) {
    this.timeoutMs = timeoutMs;
    this.now = now;
    this.transfers = new Map();
  }

  cleanup() {
    const expired = [];
    const current = this.now();
    for (const [transferId, transfer] of this.transfers) {
      if (current - transfer.updatedAt >= this.timeoutMs) {
        expired.push({ transferId, requestId: transfer.requestId, code: "REASSEMBLY_TIMEOUT" });
        this.transfers.delete(transferId);
      }
    }
    return expired;
  }

  accept(chunk) {
    this.cleanup();
    if (chunk?.type !== "chunk" || chunk.protocolVersion !== PROTOCOL_VERSION) {
      return { status: "error", code: "INVALID_ENVELOPE", transferId: chunk?.transferId };
    }
    if (typeof chunk.transferId !== "string" || typeof chunk.checksum !== "string" ||
        !Number.isInteger(chunk.byteLength) || chunk.byteLength < 0 || chunk.byteLength > MAX_LOGICAL_BYTES ||
        !Number.isInteger(chunk.index) || !Number.isInteger(chunk.total) ||
        chunk.total < 1 || chunk.total > MAX_CHUNKS || chunk.index < 0 || chunk.index >= chunk.total ||
        chunk.encoding !== "base64" || typeof chunk.payload !== "string") {
      return { status: "error", code: "INVALID_CHUNK", transferId: chunk.transferId };
    }

    let transfer = this.transfers.get(chunk.transferId);
    if (!transfer) {
      transfer = {
        requestId: chunk.requestId,
        total: chunk.total,
        byteLength: chunk.byteLength,
        checksum: chunk.checksum,
        parts: new Map(),
        receivedBytes: 0,
        updatedAt: this.now()
      };
      if (this.transfers.size >= MAX_CONCURRENT_TRANSFERS) {
        return { status: "error", code: "TOO_MANY_TRANSFERS", transferId: chunk.transferId };
      }
      this.transfers.set(chunk.transferId, transfer);
    }
    if (transfer.total !== chunk.total || transfer.byteLength !== chunk.byteLength ||
        transfer.checksum !== chunk.checksum) {
      this.transfers.delete(chunk.transferId);
      return { status: "error", code: "CHUNK_METADATA_MISMATCH", transferId: chunk.transferId };
    }
    try {
      const part = base64ToBytes(chunk.payload);
      const previousSize = transfer.parts.get(chunk.index)?.length ?? 0;
      const nextReceivedBytes = transfer.receivedBytes - previousSize + part.length;
      if (nextReceivedBytes > transfer.byteLength) {
        this.transfers.delete(chunk.transferId);
        return { status: "error", code: "BYTE_LENGTH_EXCEEDED", transferId: chunk.transferId };
      }
      transfer.parts.set(chunk.index, part);
      transfer.receivedBytes = nextReceivedBytes;
    } catch {
      this.transfers.delete(chunk.transferId);
      return { status: "error", code: "INVALID_BASE64", transferId: chunk.transferId };
    }
    transfer.updatedAt = this.now();
    if (transfer.parts.size !== transfer.total) {
      return {
        status: "partial",
        transferId: chunk.transferId,
        requestId: transfer.requestId,
        received: transfer.parts.size,
        total: transfer.total
      };
    }

    let offset = 0;
    const joined = new Uint8Array(transfer.byteLength);
    for (let index = 0; index < transfer.total; index += 1) {
      const part = transfer.parts.get(index);
      if (!part || offset + part.length > joined.length) {
        this.transfers.delete(chunk.transferId);
        return { status: "error", code: "BYTE_LENGTH_MISMATCH", transferId: chunk.transferId };
      }
      joined.set(part, offset);
      offset += part.length;
    }
    this.transfers.delete(chunk.transferId);
    if (offset !== transfer.byteLength || fnv1a(joined) !== transfer.checksum) {
      return { status: "error", code: "CHECKSUM_MISMATCH", transferId: chunk.transferId };
    }
    try {
      return {
        status: "complete",
        transferId: chunk.transferId,
        requestId: transfer.requestId,
        message: JSON.parse(decoder.decode(joined))
      };
    } catch {
      return { status: "error", code: "INVALID_LOGICAL_MESSAGE", transferId: chunk.transferId };
    }
  }
}

export function makeControl(type, fields = {}) {
  return { protocolVersion: PROTOCOL_VERSION, type, ...fields };
}
