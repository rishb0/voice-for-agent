#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Tests for choose_selection in menu.sh.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export VFA_LIB=1
# shellcheck source=/dev/null
source "$ROOT/menu.sh"

STATE="$(mktemp -d)"
trap 'rm -rf "$STATE"' EXIT

PASS=0
FAIL=0

check() {
  local name="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    echo "PASS: $name"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $name"
    echo "  expected: $expected"
    echo "  actual:   $actual"
    FAIL=$((FAIL + 1))
  fi
}

reset_state() {
  rm -f "$STATE/last-primary" "$STATE/last-clipboard" "$STATE/last-source"
}

# Primary and clipboard both empty.
reset_state
check "empty inputs stay empty" "" \
  "$(choose_selection auto "" "" "$STATE")"

# Only the clipboard has text.
reset_state
check "clipboard used when primary is empty" "copied text" \
  "$(choose_selection auto "" "copied text" "$STATE")"
check "clipboard source recorded" "clipboard" "$(cat "$STATE/last-source")"

# Only the primary selection has text.
reset_state
check "primary used when clipboard is empty" "selected text" \
  "$(choose_selection auto "selected text" "" "$STATE")"
check "primary source recorded" "primary" "$(cat "$STATE/last-source")"

# Both hold the same text.
reset_state
check "identical text uses primary" "same" \
  "$(choose_selection auto "same" "same" "$STATE")"

# First press with two different values prefers the primary selection.
reset_state
check "first press prefers primary" "old selection" \
  "$(choose_selection auto "old selection" "old clipboard" "$STATE")"

# A TUI copies the new selection to the clipboard while the X11 primary
# selection stays stale. The clipboard must win.
check "stale primary, fresh clipboard uses clipboard" "new selection" \
  "$(choose_selection auto "old selection" "new selection" "$STATE")"
check "clipboard source recorded after switch" "clipboard" "$(cat "$STATE/last-source")"

# Pressing again with nothing changed repeats the same source.
check "unchanged state repeats clipboard" "new selection" \
  "$(choose_selection auto "old selection" "new selection" "$STATE")"

# A normal app updates the primary selection while the clipboard stays stale.
check "fresh primary, stale clipboard uses primary" "browser selection" \
  "$(choose_selection auto "browser selection" "new selection" "$STATE")"
check "primary source recorded after switch" "primary" "$(cat "$STATE/last-source")"

# Forced modes ignore the other source.
reset_state
check "forced clipboard mode" "clip" \
  "$(choose_selection clipboard "sel" "clip" "$STATE")"
reset_state
check "forced primary mode" "sel" \
  "$(choose_selection primary "sel" "clip" "$STATE")"

# Unknown mode behaves like auto.
reset_state
check "unknown mode falls back to auto" "sel" \
  "$(choose_selection nonsense "sel" "clip" "$STATE")"

# Wayland without wl-clipboard: the clipboard is the safer first choice.
reset_state
check "wayland default uses clipboard first" "clip" \
  "$(choose_selection auto "sel" "clip" "$STATE" clipboard)"
check "wayland default records clipboard" "clipboard" "$(cat "$STATE/last-source")"

# After history exists, a fresh primary still wins over an unchanged clipboard.
check "fresh primary beats stale clipboard" "new sel" \
  "$(choose_selection auto "new sel" "clip" "$STATE" clipboard)"

# Both changed at once: the caller default decides.
check "both changed follows clipboard default" "clip2" \
  "$(choose_selection auto "other sel" "clip2" "$STATE" clipboard)"

echo
if [ "$FAIL" -eq 0 ]; then
  echo "SUMMARY: $PASS passed, 0 failed"
  exit 0
fi
echo "SUMMARY: $PASS passed, $FAIL failed"
exit 1
