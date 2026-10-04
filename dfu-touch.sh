#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
#
# Put a NocFree & half into its UF2 bootloader from macOS, by opening its USB
# CDC serial port at 1200 baud. The macOS counterpart of dfu-touch.ps1, and of
# the `stty -F ... 1200` commands in the fork's docs/recovery.md -- BSD stty
# spells the device flag -f, not -F.
#
# Both halves of this firmware expose a CDC ACM interface; setting the line
# rate to 1200 baud asks the half to warm-reboot into its preserved UF2
# bootloader, the same convention Arduino and Adafruit tooling use.
#
# This path does NOT depend on the keymap, the split link, Bluetooth or
# pairing. It is the route that still works when Fn+Esc / Fn+Delete cannot.
#
# It does NOT work on factory NocFree firmware. Confirmed on v2.4.5: the port
# does not exist. Coming from stock, the only routes are Fn+5 (left) and Fn+0
# (right), each held 5 seconds.
#
#   ./dfu-touch.sh                     list the halves this Mac can see
#   ./dfu-touch.sh --half left         find the left half and touch it
#   ./dfu-touch.sh --port /dev/cu.usbmodem14201

set -euo pipefail

# ZMK's USB identity, as built into these images. ioreg prints these in
# decimal, so they are converted here rather than by hand -- 0x1d50 is 7504,
# and writing 6480 instead (which is 0x1950) makes this script find nothing at
# all while looking like it works.
VID=$((16#1d50))
PID=$((16#615e))

usage() { sed -n '3,22p' "$0" | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }

PORT=""; HALF=""
while [ $# -gt 0 ]; do
    case "$1" in
        --port) PORT="${2:-}"; shift 2 ;;
        --half) HALF="$(printf '%s' "${2:-}" | tr '[:upper:]' '[:lower:]')"; shift 2 ;;
        -h|--help) usage 0 ;;
        *) echo "unknown argument: $1" >&2; usage 1 ;;
    esac
done
if [ -n "$HALF" ] && [ "$HALF" != left ] && [ "$HALF" != right ]; then
    echo "--half takes left or right" >&2; exit 1
fi

# The callout device (/dev/cu.*) and the USB product string live in different
# nodes of the IOService plane, and `ioreg -c IOUSBHostDevice` returns the
# whole bus under a single root, so properties cannot be grouped by hand.
# Rooting the query at the product string instead gives one subtree per half,
# with that half's serial and its callout device inside it and nothing else.
#
# Pairing the two is the whole point: the bootloader volume is named
# "NocFree &" on BOTH halves and cannot tell you which one you are looking at.
# The product string can.
LEFT_NAME="${NOCFREE_LEFT_NAME:-NocFree &}"
RIGHT_NAME="${NOCFREE_RIGHT_NAME:-NocFree & Right}"

find_halves() {
    local half name
    for half in left right; do
        if [ "$half" = left ]; then name="$LEFT_NAME"; else name="$RIGHT_NAME"; fi
        ioreg -p IOService -r -n "$name" -l -w0 2>/dev/null | awk \
            -v half="$half" -v name="$name" -v vid="$VID" -v pid="$PID" '
            function val(line,   x) { x = substr(line, index(line, "= ") + 2); gsub(/"/, "", x); return x }
            /"idVendor" =/          { if (v == "") v = $NF }
            /"idProduct" =/         { if (p == "") p = $NF }
            /"USB Serial Number" =/ { if (s == "") s = val($0) }
            /"IOCalloutDevice" =/   { if (c == "") c = val($0) }
            END {
                if (c != "" && v == vid && p == pid)
                    printf "%s\t%s\t%s\t%s\n", c, half, name, s
            }
        '
    done
}

FOUND="$(find_halves || true)"

touch_port() {
    local port="$1" which="$2"
    [ -e "$port" ] || { echo "no such port: $port" >&2; exit 1; }
    echo "Touching $port ($which) at 1200 baud..."
    if ! stty -f "$port" 1200 2>/dev/null; then
        echo "Could not open $port." >&2
        echo "If this half is running factory firmware, use Fn+5 (left) or Fn+0 (right), held 5 s." >&2
        exit 1
    fi
    sleep 1
    echo "Sent. A volume named 'NocFree &' should appear under /Volumes within a few seconds."
    echo "The volume does not say which half it is -- CURRENT.UF2 is the only proof."
    echo "Back up CURRENT.UF2 off it before writing anything, or let ./flash.sh do it."
}

if [ -n "$PORT" ]; then
    known="$(printf '%s\n' "$FOUND" | awk -F'\t' -v p="$PORT" '$1 == p { print $2 }')"
    touch_port "$PORT" "${known:-unidentified}"
    exit 0
fi

if [ -z "$FOUND" ]; then
    echo "No NocFree CDC port found (VID 0x1d50 PID 0x615e)." >&2
    echo "Check the half is cabled directly -- a hub or a charge-only cable will do this too." >&2
    echo "Factory firmware does not expose this interface: from stock, use Fn+5 (left) or" >&2
    echo "Fn+0 (right), held 5 seconds." >&2
    exit 1
fi

if [ -n "$HALF" ]; then
    match="$(printf '%s\n' "$FOUND" | awk -F'\t' -v h="$HALF" '$2 == h { print $1 }')"
    n="$(printf '%s' "$match" | grep -c . || true)"
    if [ "$n" -eq 0 ]; then
        echo "No $HALF half found. Seen:" >&2
        printf '%s\n' "$FOUND" | awk -F'\t' '{ printf "  %s = %s\n", $1, $2 }' >&2
        exit 1
    fi
    if [ "$n" -gt 1 ]; then
        echo "Ambiguous: $HALF matched $n ports. Use --port explicitly." >&2
        exit 1
    fi
    touch_port "$match" "$HALF"
    exit 0
fi

printf '%-28s %-6s %-16s %s\n' PORT HALF PRODUCT SERIAL
printf '%-28s %-6s %-16s %s\n' ---- ---- ------- ------
printf '%s\n' "$FOUND" | awk -F'\t' '{ printf "%-28s %-6s %-16s %s\n", $1, $2, $3, $4 }'
echo
echo "The serials are per keyboard and stable across firmware. Write this unit's two"
echo "values down: checking the serial before writing is what stops you flashing the"
echo "wrong half when both are cabled."
echo
echo "Run with --half left|right or --port /dev/cu.usbmodemN to trigger the bootloader."
