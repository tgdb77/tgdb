#!/bin/bash

# DERP 功能載入器

HEADSCALE_DERPER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/derper"

# shellcheck source=src/advanced/headscale/derper/common.sh
source "$HEADSCALE_DERPER_DIR/common.sh"
# shellcheck source=src/advanced/headscale/derper/deploy.sh
source "$HEADSCALE_DERPER_DIR/deploy.sh"
# shellcheck source=src/advanced/headscale/derper/headscale.sh
source "$HEADSCALE_DERPER_DIR/headscale.sh"
# shellcheck source=src/advanced/headscale/derper/manage.sh
source "$HEADSCALE_DERPER_DIR/manage.sh"
