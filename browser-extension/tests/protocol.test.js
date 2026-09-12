import assert from "node:assert/strict";
import test from "node:test";
import {
  BROWSER_TO_HOST_LIMIT,
  ChunkAssembler,
  encodeLogicalMessage,
  fnv1a,
  makeLogicalMessage,
  utf8ByteLength
} from "../protocol.js";

test("round trips unicode and a payload larger than 1 MB out of order", () => {
  const message = makeLogicalMessage("browser.captureResult", {
    title: "Beamhop 光束跃迁 🚀",
    body: "中文🙂abc".repeat(180_000)
  }, "request-large");
  const chunks = encodeLogicalMessage(message);
  assert.ok(chunks.length > 20);
  for (const chunk of chunks) {
    assert.ok(utf8ByteLength(JSON.stringify(chunk)) < BROWSER_TO_HOST_LIMIT);
  }

  const assembler = new ChunkAssembler();
  let result;
  for (const chunk of chunks.toReversed()) result = assembler.accept(chunk);
  assert.equal(result.status, "complete");
  assert.deepEqual(result.message, message);
});

test("accepts duplicate chunks without corrupting a transfer", () => {
  const message = makeLogicalMessage("test", { value: "x".repeat(100_000) }, "duplicate");
  const chunks = encodeLogicalMessage(message);
  const assembler = new ChunkAssembler();
  assert.equal(assembler.accept(chunks[0]).status, "partial");
  assert.equal(assembler.accept(chunks[0]).status, "partial");
  let result;
  for (const chunk of chunks.slice(1)) result = assembler.accept(chunk);
  assert.equal(result.status, "complete");
  assert.deepEqual(result.message, message);
});

test("rejects checksum corruption", () => {
  const message = makeLogicalMessage("test", { value: "safe" }, "checksum");
  const [chunk] = encodeLogicalMessage(message);
  chunk.checksum = fnv1a(new TextEncoder().encode("different"));
  const result = new ChunkAssembler().accept(chunk);
  assert.equal(result.status, "error");
  assert.equal(result.code, "CHECKSUM_MISMATCH");
});

test("expires abandoned transfers and permits a clean retry", () => {
  let now = 1_000;
  const assembler = new ChunkAssembler({ timeoutMs: 100, now: () => now });
  const message = makeLogicalMessage("test", { value: "x".repeat(100_000) }, "timeout");
  const chunks = encodeLogicalMessage(message, { transferId: "first-attempt" });
  assert.equal(assembler.accept(chunks[0]).status, "partial");
  now += 101;
  assert.deepEqual(assembler.cleanup(), [{
    transferId: "first-attempt",
    requestId: "timeout",
    code: "REASSEMBLY_TIMEOUT"
  }]);

  let result;
  const retry = encodeLogicalMessage(message, { transferId: "second-attempt" });
  for (const chunk of retry) result = assembler.accept(chunk);
  assert.equal(result.status, "complete");
});

test("rejects inconsistent transfer metadata", () => {
  const message = makeLogicalMessage("test", { value: "x".repeat(100_000) }, "metadata");
  const chunks = encodeLogicalMessage(message);
  const assembler = new ChunkAssembler();
  assert.equal(assembler.accept(chunks[0]).status, "partial");
  chunks[1].total += 1;
  const result = assembler.accept(chunks[1]);
  assert.equal(result.code, "CHUNK_METADATA_MISMATCH");
});

test("uses the protocol checksum vector shared with the Swift host", () => {
  const bytes = new TextEncoder().encode("Beamhop 光束 🚀");
  assert.equal(fnv1a(bytes), "6e49a1bd");
});

test("rejects malformed envelope fields before allocating a transfer", () => {
  const result = new ChunkAssembler().accept({
    protocolVersion: 1,
    type: "chunk",
    transferId: "bad",
    index: 0,
    total: 1,
    byteLength: -1,
    checksum: "00000000",
    encoding: "base64",
    payload: "e30="
  });
  assert.equal(result.code, "INVALID_CHUNK");
});

test("bounds concurrent incomplete transfers", () => {
  const assembler = new ChunkAssembler();
  for (let index = 0; index < 8; index += 1) {
    const message = makeLogicalMessage("test", { value: "x".repeat(100_000) }, `request-${index}`);
    const chunks = encodeLogicalMessage(message, { transferId: `transfer-${index}` });
    assert.equal(assembler.accept(chunks[0]).status, "partial");
  }
  const ninth = encodeLogicalMessage(
    makeLogicalMessage("test", { value: "x".repeat(100_000) }, "request-9"),
    { transferId: "transfer-9" }
  );
  assert.equal(assembler.accept(ninth[0]).code, "TOO_MANY_TRANSFERS");
});

test("rejects chunks that exceed their declared logical byte length", () => {
  const [chunk] = encodeLogicalMessage(makeLogicalMessage("test", { value: "hello" }, "length"));
  chunk.byteLength = 1;
  assert.equal(new ChunkAssembler().accept(chunk).code, "BYTE_LENGTH_EXCEEDED");
});
