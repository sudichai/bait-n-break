#!/usr/bin/env bash
# Single entry point for bait-n-break. No logic of its own - sources libs
# and hands off to the top-level menu.

set -uo pipefail

BNB_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export BNB_ROOT

# shellcheck source=bait_n_break/shared/config.sh
source "${BNB_ROOT}/bait_n_break/shared/config.sh"
# shellcheck source=bait_n_break/shared/lib_ui.sh
source "${BNB_ROOT}/bait_n_break/shared/lib_ui.sh"
# shellcheck source=bait_n_break/shared/lib_state.sh
source "${BNB_ROOT}/bait_n_break/shared/lib_state.sh"

state_init

# shellcheck source=bait_n_break/tui/main_menu.sh
source "${BNB_ROOT}/bait_n_break/tui/main_menu.sh"

main_menu
