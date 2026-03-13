#!/usr/bin/env bash

# Ollama 部署後模型建議：
# - 依主機 RAM / NVIDIA VRAM 粗估可先嘗試的模型級別
# - 只輸出提示，不會自動拉取模型

set -u

SERVICE_NAME="${1:-}"
APP_NAME="${2:-}"
INSTANCE_DIR="${3:-}"
HOST_PORT="${4:-11434}"

_fmt_num_or_unknown() {
  local v="${1:-}"
  if [[ "$v" =~ ^[0-9]+$ ]] && [ "$v" -gt 0 ] 2>/dev/null; then
    printf '%s' "$v"
  else
    printf '未知'
  fi
}

ram_gib=""
if [ -r /proc/meminfo ]; then
  mem_total_kb="$(awk '/^MemTotal:/ {print $2; exit}' /proc/meminfo 2>/dev/null || true)"
  if [[ "$mem_total_kb" =~ ^[0-9]+$ ]] && [ "$mem_total_kb" -gt 0 ] 2>/dev/null; then
    ram_gib=$(( (mem_total_kb + 1024 * 1024 - 1) / (1024 * 1024) ))
  fi
fi

vram_gib=""
if command -v nvidia-smi >/dev/null 2>&1; then
  first_gpu_mem_mib="$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits 2>/dev/null | head -n 1 | tr -d '[:space:]')"
  if [[ "$first_gpu_mem_mib" =~ ^[0-9]+$ ]] && [ "$first_gpu_mem_mib" -gt 0 ] 2>/dev/null; then
    vram_gib=$(( (first_gpu_mem_mib + 1024 - 1) / 1024 ))
  fi
fi

# 預設建議：低硬體先用輕量模型
recommended_model="gemma3:1b"
recommended_tier="入門（CPU/低記憶體）"

if [[ "$vram_gib" =~ ^[0-9]+$ ]] && [ "$vram_gib" -ge 20 ] 2>/dev/null; then
  recommended_model="gemma3:12b"
  recommended_tier="高階 GPU（約 20GB+ VRAM）"
elif [[ "$vram_gib" =~ ^[0-9]+$ ]] && [ "$vram_gib" -ge 10 ] 2>/dev/null; then
  recommended_model="gemma3:4b"
  recommended_tier="中階 GPU（約 10GB+ VRAM）"
elif [[ "$ram_gib" =~ ^[0-9]+$ ]] && [ "$ram_gib" -ge 48 ] 2>/dev/null; then
  recommended_model="gemma3:12b"
  recommended_tier="高記憶體 CPU（約 48GB+ RAM）"
elif [[ "$ram_gib" =~ ^[0-9]+$ ]] && [ "$ram_gib" -ge 24 ] 2>/dev/null; then
  recommended_model="gemma3:4b"
  recommended_tier="中高記憶體 CPU（約 24GB+ RAM）"
fi

echo "ℹ️ Ollama 硬體偵測：RAM 約 $(_fmt_num_or_unknown "$ram_gib") GiB，NVIDIA VRAM 約 $(_fmt_num_or_unknown "$vram_gib") GiB。"
echo "ℹ️ 建議先拉模型（$recommended_tier）：podman exec -it ${APP_NAME} ollama pull ${recommended_model}"
echo "ℹ️ 啟動對話測試：podman exec -it ${APP_NAME} ollama run ${recommended_model}"
echo "ℹ️ API 測試：curl http://127.0.0.1:${HOST_PORT}/api/tags"

# 避免 shellcheck 提示未使用位置參數
if [ -n "${SERVICE_NAME:-}" ] && [ -n "${INSTANCE_DIR:-}" ]; then
  :
fi
