#!/usr/bin/env bash

set -euo pipefail

service="${1:-lychee}"
name="${2:-}"
instance_dir_arg="${3:-}"

INSTANCE_DIR="${instance_dir:-${instance_dir_arg:-}}"
if [ -z "$INSTANCE_DIR" ] && [ -n "${TGDB_DIR:-}" ] && [ -n "${name:-}" ]; then
  INSTANCE_DIR="$TGDB_DIR/$name"
fi
if [ -z "$INSTANCE_DIR" ]; then
  echo "❌ 無法判斷 instance_dir（$service/$name）。" >&2
  exit 1
fi

env_path="$INSTANCE_DIR/.env"
if [ ! -f "$env_path" ]; then
  echo "❌ 找不到 .env：$env_path（$service/$name）。" >&2
  exit 1
fi

current="$(grep -m1 '^APP_KEY=' "$env_path" 2>/dev/null | sed 's/^APP_KEY=//')"

_validate_key() {
  local key="${1:-}"
  [ -n "$key" ] || return 1
  case "$key" in
    base64:*) ;;
    *) return 1 ;;
  esac
  if python3 - "$key" <<'PY' >/dev/null 2>&1
import base64, sys
key = sys.argv[1]
raw = key[len('base64:'):]
try:
    decoded = base64.b64decode(raw, validate=True)
except Exception:
    raise SystemExit(1)
raise SystemExit(0 if len(decoded) == 32 else 1)
PY
  then
    return 0
  fi
  return 1
}

if _validate_key "$current"; then
  echo "🔐 APP_KEY：$current"
  exit 0
fi

_gen_app_key() {
  local key=""

  if command -v openssl >/dev/null 2>&1; then
    key="$(openssl rand -base64 32 2>/dev/null | tr -d '\n' || true)"
  fi

  if [ -z "${key:-}" ] && command -v python3 >/dev/null 2>&1; then
    key="$(python3 - <<'PY'
import base64, os
print(base64.b64encode(os.urandom(32)).decode(), end='')
PY
)"
  fi

  if [ -z "${key:-}" ]; then
    return 1
  fi

  printf 'base64:%s' "$key"
  return 0
}

app_key_value="$(_gen_app_key)" || {
  echo "❌ 無法產生 APP_KEY（需要 openssl 或 python3）：$env_path（$service/$name）。" >&2
  exit 1
}

tmp="${env_path}.tmp.$$"
trap 'rm -f "$tmp" 2>/dev/null || true' EXIT

awk -v v="$app_key_value" '
  BEGIN { done=0 }
  /^APP_KEY=/ {
    if (done == 0) {
      print "APP_KEY=" v
      done=1
      next
    }
  }
  { print }
  END {
    if (done == 0) {
      print "APP_KEY=" v
    }
  }
' "$env_path" >"$tmp"

chmod 600 "$tmp" 2>/dev/null || true
mv -f "$tmp" "$env_path"
chmod 600 "$env_path" 2>/dev/null || true

trap - EXIT
rm -f "$tmp" 2>/dev/null || true

echo "✅ 已產生 APP_KEY（$service/$name）。"
echo "🔐 APP_KEY：$app_key_value"
