#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
#
# Write one UF2 image to a mounted NocFree & bootloader volume, from macOS.
#
#   ./flash.sh left home      write firmware/zmk_nocfree_and_left_ISO_home.uf2
#   ./flash.sh left office    write firmware/zmk_nocfree_and_left_ISO_office.uf2
#   ./flash.sh right          write firmware/zmk_nocfree_and_right_ISO.uf2
#   ./flash.sh --stock left   write stock-rollback/NocFree_and_V2.4.5_Left_ISO.uf2
#   ./flash.sh --identify     say what is on the volume and write nothing
#   ./flash.sh --image X.uf2  write an image from elsewhere, same checks
#
# This is the drag-and-drop from README.md with the checks that section asks
# for done for you, in order: exactly one bootloader volume mounted, CURRENT.UF2
# backed up, the application base read back out of it and required to be
# 0x27000, the readback identified block-wise against the images in firmware/
# and stock-rollback/, and every block of the image about to be written
# confirmed to land inside the application region.
#
# The base is read back rather than taken from INFO_UF2.TXT, which on this
# board does not report one at all.
#
# It cannot tell you which half the volume is. Nothing can: Board-ID reads
# "NocFree &" on both. Cable ONE half at a time and keep track of which key
# you pressed to get here. The CURRENT.UF2 identification below is the
# cross-check -- it is a readback of what is actually installed.
#
# The left half takes a unit as well, because the two keyboards run different
# keymaps and the keymap lives in the left image. There is no default: a home
# keymap on the office unit types, but types the wrong characters. The right
# image is the same for both units.

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUPS="$REPO/backups"

# Read the application base out of a firmware readback, and prove it.
#
# The lowest address in CURRENT.UF2 is NOT the application base: the bootloader
# dumps from 0x1000, so the readback opens in SoftDevice territory. What
# settles it is what sits AT the expected base -- an ARM Cortex-M image starts
# with a vector table, initial stack pointer then reset vector, and those are
# checkable. Prints "ok <sp> <reset>" when 0x27000 holds a real application.
uf2_appbase() {
    python3 - "$1" <<'UF2'
import struct, sys
BASE, TOP = 0x27000, 0x73000
mem = {}
with open(sys.argv[1], "rb") as f:
    while True:
        b = f.read(512)
        if len(b) < 512:
            break
        m0, m1, fl, addr, size, seq, tot, fid = struct.unpack("<8I", b[:32])
        if m0 != 0x0A324655 or m1 != 0x9E5D5157:
            sys.exit(1)
        mem[addr] = b[32:32 + size]
blk = mem.get(BASE)
if not blk or len(blk) < 8 or blk[:8] == b"\xff" * 8:
    sys.exit(1)
sp, rv = struct.unpack("<2I", blk[:8])
if not (0x20000000 <= sp <= 0x20040000):
    sys.exit(1)
if not (BASE <= rv < TOP and rv & 1):
    sys.exit(1)
print("ok 0x%08X 0x%08X" % (sp, rv))
UF2
}

# Decode a UF2 file and print: <lowest addr> <highest addr> <blocks> <families>
uf2_scan() {
    python3 - "$1" <<'UF2'
import struct, sys
lo = hi = None
fam = set()
n = 0
with open(sys.argv[1], "rb") as f:
    while True:
        b = f.read(512)
        if len(b) < 512:
            break
        m0, m1, flags, addr, size, seq, total, fid = struct.unpack("<8I", b[:32])
        if m0 != 0x0A324655 or m1 != 0x9E5D5157:
            sys.exit(1)
        lo = addr if lo is None else min(lo, addr)
        hi = addr + size if hi is None else max(hi, addr + size)
        if flags & 0x2000:
            fam.add(fid)
        n += 1
if lo is None:
    sys.exit(1)
print("0x%05X 0x%05X %d %s"
      % (lo, hi, n, ",".join("0x%08X" % x for x in sorted(fam)) or "none"))
UF2
}

# Identify a readback against candidate images, block by block.
#
# Not by hash: CURRENT.UF2 is synthesised by the bootloader out of flash, so
# it is not a copy of the file that was written and its checksum matches
# nothing. And not by demanding every byte, either -- a UF2 file pads its last
# block with 0x00 while the flash behind it is simply never written and reads
# 0xFF. A block counts as consistent when every byte either agrees or is that
# padding. Prints "<blocks matched> <blocks total> <path>" for the best
# candidate.
uf2_match() {
    python3 - "$@" <<'UF2'
import struct, sys

def decode(path):
    mem = {}
    with open(path, "rb") as f:
        while True:
            b = f.read(512)
            if len(b) < 512:
                break
            m0, m1, fl, addr, size, seq, tot, fid = struct.unpack("<8I", b[:32])
            if m0 != 0x0A324655 or m1 != 0x9E5D5157:
                raise ValueError("not uf2")
            mem[addr] = b[32:32 + size]
    return mem

def consistent(want, got):
    if got is None:
        return False
    if want == got:
        return True
    if len(want) != len(got):
        return False
    # Tolerate only file-padding against erased flash.
    return all(w == g or (w == 0 and g == 0xFF) for w, g in zip(want, got))

try:
    current = decode(sys.argv[1])
except Exception:
    sys.exit(1)

best = None
for cand in sys.argv[2:]:
    try:
        blocks = decode(cand)
    except Exception:
        continue
    if not blocks:
        continue
    hits = sum(1 for a, d in blocks.items() if consistent(d, current.get(a)))
    if best is None or hits / len(blocks) > best[0] / best[1]:
        best = (hits, len(blocks), cand)

if best:
    print("%d %d %s" % best)
UF2
}

STOCK=0; IDENTIFY=0; ASSUME_YES=0; HALF=""; UNIT=""; IMAGE=""
while [ $# -gt 0 ]; do
    case "$1" in
        --stock)    STOCK=1; shift ;;
        --identify) IDENTIFY=1; shift ;;
        --image)    IMAGE="${2:-}"; shift 2 ;;
        -y|--yes)   ASSUME_YES=1; shift ;;
        -h|--help)  sed -n '4,32p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        left|right|Left|Right|LEFT|RIGHT)
            HALF="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"; shift ;;
        home|office)
            UNIT="$1"; shift ;;
        *) echo "unknown argument: $1" >&2; exit 1 ;;
    esac
done
[ "$IDENTIFY" -eq 1 ] || [ -n "$HALF" ] || [ -n "$IMAGE" ] || {
    echo "say which half: ./flash.sh left home|office, or ./flash.sh right" >&2; exit 1; }
if [ "$HALF" = left ] && [ "$STOCK" -eq 0 ] && [ -z "$UNIT" ]; then
    echo "say which keyboard: ./flash.sh left home  or  ./flash.sh left office" >&2
    echo "The keymaps differ, and the keymap is in the left image." >&2
    exit 1
fi
if [ -n "$UNIT" ] && { [ "$HALF" != left ] || [ "$STOCK" -eq 1 ]; }; then
    echo "home/office only applies to the ZMK left image; the others are shared" >&2
    exit 1
fi
if [ -n "$IMAGE" ] && [ -n "$HALF" ]; then
    echo "--image and a half are mutually exclusive: --image names the file itself" >&2
    exit 1
fi

# 1. Exactly one bootloader volume. Detect by content, not by name: the volume
#    label is not something to bet a write on, INFO_UF2.TXT is.
vols=()
for v in /Volumes/*; do
    [ -f "$v/INFO_UF2.TXT" ] && vols+=("$v")
done
if [ "${#vols[@]}" -eq 0 ]; then
    echo "No UF2 bootloader volume mounted." >&2
    echo "Get one: ./dfu-touch.sh --half left|right   (ZMK only), or Fn+5 / Fn+0 held 5 s." >&2
    exit 1
fi
if [ "${#vols[@]}" -gt 1 ]; then
    echo "More than one bootloader volume is mounted:" >&2
    printf '  %s\n' "${vols[@]}" >&2
    echo "Unplug all but the half you mean to write. They are indistinguishable by name." >&2
    exit 1
fi
VOL="${vols[0]}"
echo "Volume:  $VOL"

# 2. Record what the bootloader says about itself.
#
# Context, not a gate. The Adafruit-style INFO_UF2.TXT this board ships
# reports the model, the bootloader build and the SoftDevice, and nothing
# else -- there is no application-start line in it to check, whatever the
# flashing instructions used to say. The SoftDevice version is the useful
# line: S140 7.x places the application base at 0x27000, which is where every
# image this script writes begins.
info="$(tr -d '\r' < "$VOL/INFO_UF2.TXT")"
printf '%s\n' "$info" | sed 's/^/         /'
sd="$(printf '%s\n' "$info" | sed -n 's/^SoftDevice:[[:space:]]*//p')"

# 3. Back up CURRENT.UF2, and establish the partition map FROM it. Where the
#    installed application actually starts is a readback, so it is proof;
#    anything the INFO file asserted would only have been inference.
mkdir -p "$BACKUPS"
stamp="$(date +%Y%m%d-%H%M%S)"
backup="$BACKUPS/CURRENT-$stamp.uf2"
if [ -f "$VOL/CURRENT.UF2" ]; then
    cp -X "$VOL/CURRENT.UF2" "$backup"
    echo "Backup: $backup ($(wc -c < "$backup" | tr -d ' ') bytes)"

    if vt="$(uf2_appbase "$backup")"; then
        set -- $vt
        echo "App base: 0x27000 confirmed -- vector table there reads SP=$2 reset=$3"
    else
        echo >&2
        echo "STOP: 0x27000 does not hold a valid application vector table on this" >&2
        echo "board, so it is not the application base and these images do not belong" >&2
        echo "here. Writing one risks the SoftDevice or the bootloader." >&2
        echo "Nothing has been written; $backup is the readback." >&2
        exit 1
    fi
    best="$(uf2_match "$backup" "$REPO"/firmware/*.uf2 "$REPO"/stock-rollback/*.uf2 || true)"
    if [ -n "$best" ]; then
        set -- $best
        hits="$1"; total="$2"; name="${3#$REPO/}"
        if [ "$hits" -eq "$total" ]; then
            echo "Installed: $name"
        elif [ $((hits * 2)) -lt "$total" ]; then
            #
            # Under half the blocks is not a weak match, it is no match: the
            # installed firmware is simply not in this folder. Naming the
            # nearest file anyway is worse than saying nothing, because this
            # line is what people use to confirm which half they have cabled,
            # and a 3-of-764 "closest" reads exactly like an identification.
            #
            echo "Installed: nothing here resembles it ($hits/$total blocks at best)."
            echo "           A build that was never saved to this folder, most likely."
            echo "           This line cannot tell you which half you are holding today."
        else
            echo "Installed: closest is $name ($hits/$total blocks)"
            echo "           Not an exact match -- a different factory version, or a board"
            echo "           that has written to its own application region."
        fi
    else
        echo "Installed: nothing in this folder resembles it. The backup above is your"
        echo "           way back."
    fi
else
    # No readback available. Fall back to the SoftDevice line, which fixes the
    # application base for this family, and say plainly that it is inference.
    echo "Backup: no CURRENT.UF2 on the volume -- nothing to read back."
    case "$sd" in
        "S140 7."*)
            echo "App base: assuming 0x27000 from SoftDevice $sd (inferred, not read back)" ;;
        *)
            echo >&2
            echo "STOP: no CURRENT.UF2 to read back, and the SoftDevice line reads" >&2
            echo "'${sd:-<absent>}' rather than S140 7.x, so the application base" >&2
            echo "cannot be established. Nothing has been written." >&2
            exit 1 ;;
    esac
fi

[ "$IDENTIFY" -eq 1 ] && exit 0

# 4. Pick the image.
if [ -n "$IMAGE" ]; then
    # A one-off image -- a diagnostic build, or a firmware kept outside this
    # folder. It goes through every check below unchanged; the only thing
    # skipped is looking the path up from a half name.
    IMG="$IMAGE"
elif [ "$STOCK" -eq 1 ]; then
    case "$HALF" in
        left)  IMG="$REPO/stock-rollback/NocFree_and_V2.4.5_Left_ISO.uf2" ;;
        right) IMG="$REPO/stock-rollback/NocFree_and_V2.4.5_Right_ISO.uf2" ;;
    esac
else
    case "$HALF" in
        left)  IMG="$REPO/firmware/zmk_nocfree_and_left_ISO_${UNIT}.uf2" ;;
        right) IMG="$REPO/firmware/zmk_nocfree_and_right_ISO.uf2" ;;
    esac
fi
[ -f "$IMG" ] || { echo "missing image: $IMG" >&2; exit 1; }

echo
echo "Write:   ${IMG#$REPO/}"
echo "         $(shasum -a 256 "$IMG" | cut -d' ' -f1)"

# 5. Confirm every block lands in the application region. Cheap, and it is the
#    check that separates "a UF2 file" from "a UF2 file for this partition map".
if ! scan="$(uf2_scan "$IMG")"; then
    echo "STOP: $IMG is not a valid UF2 file. Nothing written." >&2
    exit 1
fi
set -- $scan
echo "         $3 blocks, $1-$2, family $4"
if [ "$1" != "0x27000" ]; then
    echo "STOP: image starts at $1, below the 0x27000 application base." >&2
    echo "That region holds the SoftDevice. Nothing written." >&2
    exit 1
fi
if [ "$(printf '%d' "$2")" -gt "$(printf '%d' 0x73000)" ]; then
    echo "STOP: image writes past the application region. Nothing written." >&2
    exit 1
fi

# 6. Write.
if [ "$ASSUME_YES" -ne 1 ]; then
    echo
    printf 'Write this image to %s? [y/N] ' "$VOL"
    read -r reply </dev/tty
    case "$reply" in y|Y|yes|YES) ;; *) echo "Nothing written."; exit 1 ;; esac
fi

echo "Writing..."
# The volume disconnects itself the moment the last block lands, so cp
# reporting an I/O error here is the normal ending, not a failure. -X keeps
# macOS from trying to put extended attributes on a FAT bootloader volume.
cp -X "$IMG" "$VOL/" 2>/dev/null || true
sync
echo "Sent. The half reboots into the new firmware on its own."
echo "Confirm it came up as ZMK:  ./dfu-touch.sh     (it should list this half)"
