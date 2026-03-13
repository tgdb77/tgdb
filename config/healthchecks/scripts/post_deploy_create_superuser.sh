#!/bin/bash

set -euo pipefail

SERVICE="${1:-healthchecks}"
NAME="${2:-}"
INSTANCE_DIR_ARG="${3:-}"
HOST_PORT_ARG="${4:-}"

INSTANCE_DIR="${instance_dir:-${INSTANCE_DIR_ARG:-}}"
HOST_PORT="${host_port:-${HOST_PORT_ARG:-}}"
ADMIN_EMAIL="${HEALTHCHECKS_ADMIN_EMAIL:-${admin_email:-}}"
ADMIN_PASSWORD="${HEALTHCHECKS_ADMIN_PASSWORD:-${admin_password:-}}"
TIMEOUT="${HEALTHCHECKS_POST_DEPLOY_TIMEOUT:-90}"

if [ -z "$NAME" ]; then
  echo "❌ 找不到容器名稱，無法建立 Healthchecks 超級管理員。($SERVICE)" >&2
  exit 1
fi

if [ -z "$ADMIN_EMAIL" ] || [ -z "$ADMIN_PASSWORD" ]; then
  echo "❌ 缺少超級管理員帳號或密碼，無法建立 Healthchecks 超級管理員。($SERVICE/$NAME)" >&2
  exit 1
fi

if ! command -v podman >/dev/null 2>&1; then
  echo "❌ 系統未安裝 podman，無法建立 Healthchecks 超級管理員。($SERVICE/$NAME)" >&2
  exit 1
fi

if ! podman container exists "$NAME" >/dev/null 2>&1; then
  echo "❌ 找不到 Healthchecks 容器：$NAME" >&2
  exit 1
fi

if [[ ! "$TIMEOUT" =~ ^[0-9]+$ ]] || [ "$TIMEOUT" -le 0 ] 2>/dev/null; then
  TIMEOUT=90
fi

healthchecks_db_ready() {
  podman exec "$NAME" \
    /opt/healthchecks/manage.py shell -c \
    "from django.contrib.auth import get_user_model; get_user_model().objects.count()" \
    >/dev/null 2>&1
}

echo "ℹ️ 正在等待 Healthchecks 就緒後建立超級管理員..."
if [ -n "$INSTANCE_DIR" ]; then
  echo "   - 實例目錄：$INSTANCE_DIR"
fi
if [ -n "$HOST_PORT" ]; then
  echo "   - 登入位址：http://127.0.0.1:${HOST_PORT}/accounts/login/"
fi

ready=0
waited=0
while [ "$waited" -lt "$TIMEOUT" ]; do
  if command -v curl >/dev/null 2>&1 && [ -n "$HOST_PORT" ]; then
    if curl -fsS -o /dev/null --max-time 3 "http://127.0.0.1:${HOST_PORT}/accounts/login/" 2>/dev/null; then
      ready=1
      break
    fi
  else
    if healthchecks_db_ready; then
      ready=1
      break
    fi
  fi
  sleep 2
  waited=$((waited + 2))
done

if [ "$ready" -ne 1 ]; then
  if ! healthchecks_db_ready; then
    echo "❌ 等待 Healthchecks 容器就緒逾時，無法建立超級管理員。($SERVICE/$NAME)" >&2
    exit 1
  fi
fi

PY_CODE="$(cat <<'PY'
import hashlib
import os
from django.contrib.auth import get_user_model

email = os.environ["HC_ADMIN_EMAIL"].strip().lower()
password = os.environ["HC_ADMIN_PASSWORD"]

User = get_user_model()


def build_username(value: str) -> str:
    candidate = value
    if len(candidate) <= 150:
        return candidate

    digest = hashlib.sha1(value.encode("utf-8")).hexdigest()[:8]
    return f"{candidate[:141]}-{digest}"


def unique_username(value: str) -> str:
    base = build_username(value)
    candidate = base
    index = 1
    while User.objects.filter(username__iexact=candidate).exists():
        suffix = f"-{index}"
        head = base[: 150 - len(suffix)]
        candidate = f"{head}{suffix}"
        index += 1
    return candidate


def normalized_existing_username(user_obj) -> str:
    current = getattr(user_obj, "username", "").strip()
    if not current:
        return unique_username(email)

    lowered = current.lower()
    conflict = User.objects.filter(username__iexact=lowered).exclude(pk=user_obj.pk).exists()
    if conflict:
        return current
    return lowered


user = User.objects.filter(email__iexact=email).first()

if user is None:
    username = unique_username(email)
    User.objects.create_superuser(username=username, email=email, password=password)
    print("created")
else:
    changed = False
    if not getattr(user, "username", ""):
        user.username = unique_username(email)
        changed = True
    else:
        normalized_username = normalized_existing_username(user)
        if user.username != normalized_username:
            user.username = normalized_username
            changed = True
    if len(user.username) > 150:
        user.username = build_username(user.username)
        changed = True
    if getattr(user, "email", "").strip().lower() != email:
        user.email = email
        changed = True
    if hasattr(user, "is_superuser") and not user.is_superuser:
        user.is_superuser = True
        changed = True
    if hasattr(user, "is_staff") and not user.is_staff:
        user.is_staff = True
        changed = True
    user.set_password(password)
    changed = True
    if changed:
        user.save()
    print("updated")
PY
)"

result="$(podman exec \
  -e "HC_ADMIN_EMAIL=$ADMIN_EMAIL" \
  -e "HC_ADMIN_PASSWORD=$ADMIN_PASSWORD" \
  "$NAME" \
  /opt/healthchecks/manage.py shell -c "$PY_CODE" 2>&1)" || {
  echo "❌ 建立 Healthchecks 超級管理員失敗。($SERVICE/$NAME)" >&2
  printf '%s\n' "$result" >&2
  exit 1
}

case "$result" in
  *created*)
    echo "✅ 已建立 Healthchecks 超級管理員：$ADMIN_EMAIL"
    ;;
  *updated*)
    echo "✅ 已更新既有 Healthchecks 超級管理員密碼與權限：$ADMIN_EMAIL"
    ;;
  *)
    echo "✅ 已執行 Healthchecks 超級管理員初始化：$ADMIN_EMAIL"
    [ -n "$result" ] && printf '%s\n' "$result"
    ;;
esac
