#!/bin/bash

# Headscale 核心功能載入器

HEADSCALE_CORE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=src/advanced/headscale/common.sh
source "$HEADSCALE_CORE_DIR/common.sh"
# shellcheck source=src/advanced/headscale/actions.sh
source "$HEADSCALE_CORE_DIR/actions.sh"
# shellcheck source=src/advanced/headscale/upgrade.sh
source "$HEADSCALE_CORE_DIR/upgrade.sh"
# shellcheck source=src/advanced/headscale/deploy.sh
source "$HEADSCALE_CORE_DIR/deploy.sh"
# shellcheck source=src/advanced/headscale/menu.sh
source "$HEADSCALE_CORE_DIR/menu.sh"
