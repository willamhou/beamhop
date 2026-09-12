#!/usr/bin/env bash
set -euo pipefail

usage() {
  printf '%s\n' "Usage: $0 --host /absolute/path/to/BeamhopNativeHost --extension-id ID [--browser NAME ...] [--base-dir DIR] [--dry-run]"
  printf '%s\n' "Browsers: chrome, chrome-canary, chromium, arc, brave, edge, all (default: all installed)"
}

host_path=""
extension_id=""
base_dir="${HOME}/Library/Application Support"
dry_run=0
browsers=()

while (($#)); do
  case "$1" in
    --host) host_path="${2:-}"; shift 2 ;;
    --extension-id) extension_id="${2:-}"; shift 2 ;;
    --browser) browsers+=("${2:-}"); shift 2 ;;
    --base-dir) base_dir="${2:-}"; shift 2 ;;
    --dry-run) dry_run=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) printf 'Unknown argument: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done

[[ "$host_path" = /* ]] || { printf '%s\n' '--host must be an absolute path' >&2; exit 2; }
[[ -f "$host_path" && -x "$host_path" ]] || { printf '%s\n' '--host must point to an executable file' >&2; exit 2; }
[[ "$extension_id" =~ ^[a-p]{32}$ ]] || { printf '%s\n' '--extension-id must be a 32-character Chromium extension id (a-p)' >&2; exit 2; }
[[ "$host_path" != *$'\n'* && "$host_path" != *$'\r'* ]] || { printf '%s\n' '--host cannot contain newlines' >&2; exit 2; }

if ((${#browsers[@]} == 0)); then browsers=(all); fi

declare -A browser_paths=(
  [chrome]="Google/Chrome"
  [chrome-canary]="Google/Chrome Canary"
  [chromium]="Chromium"
  [arc]="Arc/User Data"
  [brave]="BraveSoftware/Brave-Browser"
  [edge]="Microsoft Edge"
)

selected=()
for browser in "${browsers[@]}"; do
  if [[ "$browser" == all ]]; then
    for candidate in chrome chrome-canary chromium arc brave edge; do
      [[ -d "$base_dir/${browser_paths[$candidate]}" ]] && selected+=("$candidate")
    done
  elif [[ -n "${browser_paths[$browser]:-}" ]]; then
    selected+=("$browser")
  else
    printf 'Unsupported browser: %s\n' "$browser" >&2
    exit 2
  fi
done

((${#selected[@]} > 0)) || { printf '%s\n' 'No installed Chromium browser directories found; pass --browser explicitly to create one.' >&2; exit 1; }

json_host=${host_path//\\/\\\\}
json_host=${json_host//\"/\\\"}
umask 077
for browser in "${selected[@]}"; do
  target_dir="$base_dir/${browser_paths[$browser]}/NativeMessagingHosts"
  target_file="$target_dir/com.beamhop.bridge.json"
  if ((dry_run)); then
    printf '[dry-run] %s -> %s\n' "$browser" "$target_file"
    continue
  fi
  mkdir -p "$target_dir"
  temporary=$(mktemp "$target_dir/.com.beamhop.bridge.XXXXXX")
  printf '{\n  "name": "com.beamhop.bridge",\n  "description": "Beamhop browser bridge",\n  "path": "%s",\n  "type": "stdio",\n  "allowed_origins": ["chrome-extension://%s/"]\n}\n' \
    "$json_host" "$extension_id" > "$temporary"
  chmod 600 "$temporary"
  mv -f "$temporary" "$target_file"
  printf 'Installed %s manifest: %s\n' "$browser" "$target_file"
done
