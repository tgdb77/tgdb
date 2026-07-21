#!/bin/bash

# Tailscale 功能載入器

HEADSCALE_TAILSCALE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/tailscale"

# shellcheck source=src/advanced/headscale/tailscale/common.sh
source "$HEADSCALE_TAILSCALE_DIR/common.sh"
# shellcheck source=src/advanced/headscale/tailscale/join.sh
source "$HEADSCALE_TAILSCALE_DIR/join.sh"
# shellcheck source=src/advanced/headscale/tailscale/exit_node.sh
source "$HEADSCALE_TAILSCALE_DIR/exit_node.sh"
# shellcheck source=src/advanced/headscale/tailscale/ssh.sh
source "$HEADSCALE_TAILSCALE_DIR/ssh.sh"
# shellcheck source=src/advanced/headscale/tailscale/drive.sh
source "$HEADSCALE_TAILSCALE_DIR/drive.sh"
# shellcheck source=src/advanced/headscale/tailscale/menu.sh
source "$HEADSCALE_TAILSCALE_DIR/menu.sh"
