# TUI Refinements — Design Spec

Date: 2026-07-17
Status: Approved

## Overview

6 refinements across 3 files to improve TUI usability. Victim gets auto-deploy with loading screen. Attacker gets arrow-key navigation with highlight, IP input modal, and flicker-free rendering. Footer made configurable to fix victim showing attacker labels.

---

## Changes

### 1. Victim Auto-Deploy Loading Screen
- Before TUI init, show step-by-step status: bait → containers → monitor
- On failure: error screen with retry/back options
- On success: pause 2s, transition to live dashboard

### 2. Victim Dashboard Shows Active Immediately
- After deploy + TUI init, call `_refresh_all()` once before event loop
- All services `[UP]`, all vulns `[ACTIVE]` from first frame

### 3. Configurable Footer (ansi_tui.sh)
- New variable: `TUI_FOOTER_TEXT` — set by caller before `tui_draw_footer`
- Attacker: `"<H> HOME | <T> TARGET | <C> RUN CVEs | <A> RUN ALL | <L> LOGS | <Q> BACK"`
- Victim: `"<D> DEPLOY | <T> TEARDOWN | <M> MALWARE | <B> BAIT | <Q> BACK"`

### 4. Attacker Arrow-Key Highlight Navigation
- Track `TUI_CURSOR_VECTOR` index
- Arrow UP/DOWN moves highlight through 18 vectors + A, C, H
- Highlighted line rendered with reverse-video (ANSI inverse)
- `Enter` executes highlighted vector
- Number keys 1-9 still work as shortcuts
- `A`, `C`, `H` keys still work

### 5. Attacker IP Input Modal
- On entering attacker console with no saved target: show centered input box
- Prompt: "Enter Target IP:" with cursor
- Validate IPv4 on Enter
- Invalid → stay in input, show error below
- Valid → save, load target state, proceed to TUI

### 6. Flicker-Free Rendering (ansi_tui.sh)
- Remove `clear` from `tui_draw_layout()`
- Each `tui_draw_*` function uses `tput cup` to position cursor before writing
- Panel redraw overwrites only its region — no full-screen clear
- Right panel (logs) updates incrementally without redrawing other panels

---

## Files Modified

| File | Changes |
|------|---------|
| `bait_n_break/tui/ansi_tui.sh` | `TUI_FOOTER_TEXT` variable, remove `clear`, incremental draws |
| `bait_n_break/tui/victim_dashboard.sh` | Auto-deploy + loading screen, live init, custom footer |
| `bait_n_break/tui/attacker_console.sh` | Arrow highlight nav, IP input modal, custom footer |
