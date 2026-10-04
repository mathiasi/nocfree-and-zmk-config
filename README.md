# NocFree & — ISO firmware (ZMK), macOS

A ZMK user-config repository for two NocFree & keyboards. `./build.sh` (or
CI) writes the images to `firmware/`; nothing else here is flashable.

| Half  | File | Unit |
|-------|------|------|
| LEFT  | firmware/zmk_nocfree_and_left_ISO_home.uf2   | home (macOS) |
| LEFT  | firmware/zmk_nocfree_and_left_ISO_office.uf2 | office (Windows) -- not yet in this repo |
| RIGHT | firmware/zmk_nocfree_and_right_ISO.uf2       | both |

The `zmk_` prefix distinguishes these from NocFree's own images, which are
named `NocFree_and_V2.4.5_*.uf2`.

SHA256:

    left (home)  b7b811bf0b8c3253ba47bc377d4c3bf5c76fd4d835528a0d66ba672453e296d6
    right        76059637c40f86dc3f150b1b1790f541dd0d4682211b4430afcf7beb298551c2

The home unit still runs the build from before the repository was
restructured (left 89df0ae6..., right 51b29c33...; the left half's last
readback, backups/CURRENT-20260925-223612.uf2, matches it on all 950 blocks). The code is the same; the
link layout is not -- see "Reproducibility" below. There is no need to reflash
for it. firmware/previous_*.uf2 keeps those two images so `flash.sh
--identify` can still recognise them.

Verify before flashing:

    shasum -a 256 firmware/zmk_nocfree_and_left_ISO_home.uf2

Most of this README describes the home unit's macOS configuration. The office
unit runs the same build configured for Windows. Two things differ, both described under Keymap below: the bottom
row, and the two ISO keys that macOS maps the opposite way round from every
other host. Everything else — the Fn layer, the Nav layer, the recovery keys,
the Kconfig — is identical.

## Repository layout

The standard ZMK user-config shape, so GitHub Actions can build it with ZMK's
own reusable workflow:

    config/west.yml         pinned sources: ZMK, and the board port
    config/home.keymap      the home unit's keymap (macOS)
    config/office.keymap    the office unit's keymap (Windows) -- to be added
    config/nocfree_and.conf Kconfig, shared by both units
    build.yaml              what to build: board x keymap -> artifact name
    zephyr/module.yml       makes this repository a Zephyr module, so that
    CMakeLists.txt, Kconfig   modules/ is compiled in
    modules/ble-profile-name/   per-profile Bluetooth names
    patches/                changes to the board port; see Local patches
    .github/workflows/      CI; refuses to run while patches/ is non-empty
    diagnostics/int-probe/  the probe that established the INT line works
    firmware/               build output (ignored by git)
    backups/                flash.sh readbacks (ignored by git)
    stock-rollback/         vendor factory images (ignored by git)

The two keymaps are separate files on purpose and must never be copied
between units. See the header of config/home.keymap for where they differ.
A keymap-only change needs only that unit's LEFT half reflashed: the right
image is shared by both units, because the peripheral never links a keymap.

## Tools

    ./build.sh                     rebuild every image in build.yaml
    ./dfu-touch.sh                 list the halves, or drop one into its bootloader
    ./flash.sh left home|office    write a left image to a mounted bootloader volume
    ./flash.sh right               write the right image

All three are macOS scripts. `build.sh` runs the toolchain inside Apple's
`container`, so nothing but git is installed on the host. `dfu-touch.ps1` is
the Windows counterpart of `dfu-touch.sh` and is kept for the other machine.

## Keymap

Three layers: Base, Fn, and Nav (held with Caps Lock).

Caps Lock held is the navigation layer; tapped it is still Caps Lock.

    Caps + I     up
    Caps + J/K/L left / down / right

Everything else on that layer is transparent, so Caps + anything else types
what it normally would. The physical arrow cluster still works.

Top row unmodified -- the shortcuts, which is what the caps are printed with:

    F1 / F2         display brightness down / up
    F3 / F4         Mission Control / Spotlight
    F5 / F6         backlight off / on  (starts OFF at boot; see below)
    F7..F12         prev, play/pause, next, mute, volume down, volume up

Hold Fn for everything else:

    Fn+F1..F12      the real F1-F12
    Fn+Esc          tap resets the left half, hold 1.5 s for its bootloader
    Fn+Home         Print Screen
    Fn+1..Fn+4      Bluetooth profile 0..3
    Fn+6            Bluetooth profile 4
    Fn+Backspace    clear the selected Bluetooth profile
    Fn+U / Fn+B     send HID over USB / Bluetooth
    Fn+i            type the battery level as "bat NN" (a stub, reads 100)

All of the above are verified working on macOS 27, which is worth stating
because ZMK's own keycode table disagrees: it marks C_AC_SEARCH and
C_AC_DESKTOP_SHOW_ALL_WINDOWS as unsupported on macOS and lists the two
brightness codes as untested. On this machine all four work. Treat that table
as a hint, not as an answer, and test on the hardware.

This inverts the row NocFree ships, which puts plain F1-F12 unmodified and the
shortcuts behind Fn. Inverted, the base layer does what the legends say and the
F-numbers are the hidden meaning, which is how Apple's own keyboards behave.

### The matching macOS setting

The inversion does nothing useful on its own. With "Use F1, F2, etc. keys as
standard function keys" OFF -- the macOS default -- macOS rewrites F1-F12 into
media keys before any app sees them, so Fn+F1 arrives as brightness-down and a
real F1 cannot be produced at all. Turn it ON:

    System Settings -> Keyboard -> Keyboard Shortcuts... -> Function Keys

In recent macOS that toggle is per-keyboard, so apply it to this one. Check it
from a shell with:

    defaults read -g com.apple.keyboard.fnState     1 = on, absent = off

The base layer is unaffected by the setting in either position, because it
sends consumer usages rather than F-numbers. Only the Fn layer depends on it.

The five Bluetooth profiles advertise under their own names -- "NocFree & BLE1"
through "NocFree & BLE5", numbered to match the key that selects them, so Fn+1
pairs as BLE1. Without that they would all appear to macOS as one name and
there would be no way to tell which slot you were pairing. It comes from
modules/ble-profile-name; see Build provenance.

Bottom row, the factory order, matching the Mac legends on the retail keycaps:

    left    Fn  Ctrl  Option  Command  [Space]
    right   [Space]  Command  Fn  Option  left down right

Command lands under either thumb, which is where macOS wants it — every system
shortcut is a Command chord. Option needs no special placement either: a
Nordic layout on macOS takes its third-level characters — @ $ { [ ] } and the
backslash and pipe — from Option, and an Option key already sits one out from
each thumb.

This is the one place the Windows sibling differs. There, those same
characters come from AltGr, which the factory row puts three keys right of the
space bar behind Command and Fn, so that build moves AltGr in beside the space
bar and puts Ctrl/Win/Alt into PC order. Neither departure buys anything on
macOS. To rebuild the Windows row from `config/home.keymap`: swap LALT with
LGUI on the left, RGUI with RALT on the right -- but the office unit has its
own keymap and its own differences, so start from that file, not this one.

## Telling the halves apart

Board-ID on the bootloader volume is "NocFree &" on BOTH halves, so a mounted
volume does not tell you which one you are looking at. Two reliable ways:

    Running ZMK:  ./dfu-touch.sh   (reads the USB product string)

        PORT                  HALF   PRODUCT          SERIAL
        ----                  ----   -------          ------
        /dev/cu.usbmodem...   left   NocFree &        <this unit's nRF52833 device id>
        /dev/cu.usbmodem...   right  NocFree & Right  <this unit's nRF52833 device id>

    THE SERIALS ARE PER KEYBOARD. Run dfu-touch.sh once on a new unit and
    write its two values down. They are stable across firmware: the same id
    appears under ZMK, under factory firmware, and in the bootloader's
    mass-storage device id. Checking the serial before writing is what stops
    you flashing the wrong half when both are cabled -- the bootloader volume
    itself cannot tell you which half it is.

    In the bootloader: copy CURRENT.UF2 off the volume and compare its blocks
    against the candidate images. That is a readback of whatever is actually
    installed, so it is proof rather than inference. `./flash.sh --identify`
    does exactly this and writes nothing.

    Blocks, not hashes. CURRENT.UF2 is synthesised by the bootloader from what
    is in flash -- a dump of the whole region, erased pages and all -- so it is
    not a copy of the file that was written and its checksum matches nothing.
    What is stable is the payload at each address.

    Nor is it byte-exact. A UF2 file pads its final block with 0x00, while the
    flash behind that padding is never written and reads 0xFF, so the last
    block always disagrees. A block counts as consistent when every byte either
    agrees or is exactly that padding. On this unit the left half then matches
    NocFree_and_V2.4.5_Left_ISO.uf2 on all 617 blocks -- so the rollback image
    in stock-rollback/ is confirmed to be this unit's own factory firmware,
    not merely a plausible one.

The safest habit on macOS is simply to cable one half at a time. `flash.sh`
refuses to run when two bootloader volumes are mounted, for the same reason.

## Entering the bootloader

Both the factory combinations and the port's own are bound, so either muscle
memory works. Tap resets that half; hold 1.5 s reaches the bootloader.

    Fn+5  or  Fn+Esc      left half
    Fn+0  or  Fn+Delete   right half

This works because ZMK reset behaviours act on the half whose key triggered
them, and 5 and Esc are both left-half keys while 0 and Delete are both
right-half ones -- the same split the factory combinations rely on.

Binding Fn+5 and Fn+0 displaced two Bluetooth controls one key outward:
profile 4 moved to Fn+6, clear-profile to Fn+Backspace.

Third route, independent of Bluetooth, the split link and the keymap:

    ./dfu-touch.sh --half left
    ./dfu-touch.sh --half right

This opens the half's USB CDC port at 1200 baud, the Arduino convention. It is
the BSD spelling (`stty -f`) of the `stty -F ... 1200` commands in the fork's
docs/recovery.md.

CONFIRMED on the sibling unit: this does NOT work on factory firmware v2.4.5 --
the port is not exposed at all. **Coming from stock, Fn+5 and Fn+0 (held 5 s)
are the only routes into the bootloader.** Once ZMK is on, you have three.

Use that one if a half will not pair. The right half needs its own USB cable
for its bootloader volume to appear either way.

## Layout

Positional HID. Set the national layout in macOS under System Settings →
Keyboard → Input Sources (Norwegian, Danish, Swedish or Finnish). No firmware
change is needed for Nordic.

macOS also decides ISO versus ANSI per keyboard rather than from the input
source, and ZMK gives it no country code to guess from. Check whether it has
ever classified this one:

    defaults read com.apple.keyboardtype

An empty result means it has not. Set it under System Settings → Keyboard →
Change Keyboard Type…, which asks you to press the key right of left Shift.

That is worth doing, but on this unit it was NOT the problem, and the rest of
this section is the part that bites.

### The two ISO keys are crossed on macOS

macOS maps HID 0x35 (GRAVE) and 0x64 (NON_US_BSLH) the opposite way round from
Windows and Linux, on any ISO keyboard that is not an Apple one. Bound
positionally -- which is the whole premise of this keymap -- each of the two
ISO-only keys then types the other's character.

MEASURED on this unit, macOS 27, Danish layout, keyboard type already ISO:

    key left of 1, sending GRAVE          typed  <  >     wanted  $  §
    key left of Z, sending NON_US_BSLH    typed  $  §     wanted  <  >

The keymap compensates: the key left of 1 sends NON_US_BSLH, the key left of Z
sends GRAVE. Each key then produces its own legend. This is the only place the
firmware describes a host rather than the hardware, and it is the second
reason this keymap is not portable back to Windows.

The third ISO key, NON_US_HASH left of the ISO Enter, is not part of the swap
and is bound normally. It lives on the right half.

## Returning to stock

The stock images travel with this folder:

    stock-rollback/
        NocFree_and_V2.4.5_Left_ISO.uf2      <- left half
        NocFree_and_V2.4.5_Right_ISO.uf2     <- right half
        NocFree_and_V2.4.5_Dongle.uf2        <- dongle (never touched by ZMK)

    ./flash.sh --stock left      writes the first of these
    ./flash.sh --stock right     writes the second

    They sit in their own folder so they cannot be confused with the ZMK
    images in firmware/. They are not committed to git -- they are the
    vendor's to distribute -- so a fresh clone does not have them. Newer factory versions come from NocFree LINK -> Firmware
    Update; the vendor's recovery tool ships in the same archive as
    NocFreeFirmwareCare_<version>.exe, which is Windows-only.

Use the ISO files. Left ANSI and Left ISO are DIFFERENT images. The right
half's ANSI and ISO images are byte-identical, because the left half is the
central and carries the keymap for both halves -- the same split ZMK uses.

Verified by decoding every block of the official images, which `flash.sh`
re-checks for whatever it is about to write:

  - all start at 0x27000, the same application base this ZMK build targets,
    on v2.4.5 as well as v2.3.0
  - family id 0x621E937A, identical to the ZMK images
  - all stay inside the application region, highest address 0x4D900

These images are v2.4.5, the version that shipped on the sibling unit. If this
unit came with a different factory version, the backup `flash.sh` takes before
every write is the accurate way back to *its* stock, not these files.

The full round trip is PROVEN on the sibling unit, 2026-09-15:

    stock v2.4.5 -> ZMK -> stock v2.4.5 -> ZMK

Each transition was verified by USB identity: ZMK enumerates as 1D50:615E,
factory firmware as 2886:8029, both carrying the same chip serial. The factory
firmware booted normally despite ZMK's leftover NVS at 0x65000-0x6CFFF, which
had been the one unknown. That unit was also flashed 2.4.0 -> 2.4.5 by
drag-and-drop beforehand: the UF2 bootloader has no version check, it writes
the blocks at the addresses in the file, so putting a factory image over ZMK is
the same operation in the other direction.

Settings and pairings will not survive. This firmware writes its own NVS at
0x65000-0x6CFFF, overwriting whatever the factory firmware kept there. Expect
to re-pair and reconfigure. The factory filesystem at 0x6D000-0x73FFF is never
mapped or written and does survive. The official images do not write
0x65000-0x6CFFF either, so ZMK's leftover settings stay in flash after a
revert.

## Flashing order

This unit is coming from stock, so BOTH halves need flashing: the build
carries a Kconfig change, which is compiled into both. Only later,
keymap-only changes need the left half alone, because the peripheral never
links the keymap.

Cable one half at a time. `flash.sh` backs up CURRENT.UF2 and proves the
application base out of it before every write; if 0x27000 does not hold an
application, it stops.

Two things about this board are worth knowing, because the obvious checks
both fail on it.

INFO_UF2.TXT carries no application start address. It reports the model, the
bootloader build and the SoftDevice, and nothing else:

    UF2 Bootloader 0.9.2-39-g0147d71
    Model: NocFree &
    Board-ID: NocFree &
    Date: Dec 26 2025
    SoftDevice: S140 7.3.0

Earlier revisions of these instructions said to check an application start
address here. There is none to check.

And the lowest address in CURRENT.UF2 is not the application base either. The
bootloader dumps from 0x1000, so a readback opens in SoftDevice territory --
on this unit, 0x01000-0x6D000, of which 0x01000-0x4D900 is programmed.

What settles it is what sits AT 0x27000. An ARM Cortex-M image begins with a
vector table, and on this unit that address reads SP=0x20020000, the top of
the 128 KiB SRAM, with a Thumb-aligned reset vector inside the application
region. That is the application base established from the silicon. The
SoftDevice line corroborates it: S140 7.x bases the application at 0x27000.

  1. Fn+5 held 5 s on the LEFT half. `./flash.sh left home`
  2. Confirm it types over USB.
  3. Test both recovery routes: `./dfu-touch.sh --half left`, and Fn+Esc held
     1.5 s. Either one returning the volume closes the loop.
  4. If both fail, stop. The right half is still stock and the factory images
     are in hand.
  5. If they work, the left half is sitting in its bootloader after step 3, so
     write it again -- `./flash.sh left home` -- to bring it back up.
  6. Then flash RIGHT: Fn+0 held 5 s, then `./flash.sh right`.

Note: with ZMK on the left and factory firmware on the right, the two halves
will NOT talk to each other. The split protocols are unrelated. A dead right
half between steps 1 and 6 is expected, not a fault.

## Building

    ./build.sh

Everything runs in a container; no Zephyr toolchain, no west and no Python
are installed on the host. It is a local twin of the CI build and reads the
same inputs: `config/west.yml` for sources, `build.yaml` for what to build,
`config/` for keymaps and Kconfig, and this repository as a module. The one
thing it adds is applying `patches/`, which CI cannot do.

It builds in `~/.cache/zmk-nocfree/ws` (about 3 GB, outside this folder) and
writes the images to `firmware/`. The first run downloads Zephyr and its
modules; later runs reuse them. `container system start` first if the runtime
is not up. (`~/.cache/zmk-nocfree/src`, where earlier versions cloned the
board port, is no longer used.)

### CI

`.github/workflows/build.yml` calls ZMK's reusable `build-user-config`
workflow, pinned to the same ZMK commit as `config/west.yml`; each push
builds every `build.yaml` entry and attaches the images to the run. It is
deliberately blocked for now: it cannot apply `patches/`, and an image
without patches/0002 but with CONFIG_ZMK_SLEEP on sleeps and never wakes on a
keypress. To unblock it, put the patches on a fork:

    fork github.com/Thie1e/NocFree-and-zmk, then in a clone of the fork:
    git checkout -b nocfree-zmk2 08bc83bfa269e21275449d691e9b48eecf9e3544
    git am /path/to/this/repo/patches/*.patch
    git push -u origin nocfree-zmk2

then point the `nocfree` remote in `config/west.yml` at the fork, set the
revision to the new head, and delete `patches/`. `build.sh` keeps working
unchanged, with nothing left to apply.

## Build provenance

All of it is pinned in config/west.yml:

Source: github.com/Thie1e/NocFree-and-zmk branch iso-de
        at 08bc83bfa269e21275449d691e9b48eecf9e3544
        plus patches/ -- see "Local patches" below
ZMK pinned to 6e2ef41e022d555b10f116e395832913f71717b3
Toolchain pinned by digest rather than by a moving tag:

    zmkfirmware/zmk-build-arm@sha256:edb1c953438c6f720ddb79c3762f3972013b7fbbaf4fff3592fc869983e7afc5

    what :stable was on 2025-10-02 -- Zephyr SDK 0.16.9, arm-zephyr-eabi-gcc
    12.2.0. `stable` moving is the one loose end left by pinning the fork
    commit and the ZMK commit, and a moved toolchain changes the bytes.

Flash use: left 95.76%, right 76.95% of the 248 KiB code partition.
All written blocks lie in 0x27000-0x61F00. SoftDevice S140, the UF2 bootloader
and the factory filesystem are never written.

The fork's own suite -- 84 tests -- passes against these artifacts. Run from
a checkout of the fork, against the workspace build.sh leaves behind. Build
directories are now named after build.yaml artifacts (build/nocfree_and_left_ISO_home
rather than build/left), so check what the suite expects before relying on it:

    NOCFREE_BUILD_DIR=~/.cache/zmk-nocfree/ws/build ./tests/run.sh

Both deviations from the fork default are applied as user-config overrides, so
the upstream repository is untouched: config/home.keymap and config/nocfree_and.conf
(idle timeout 60 s instead of 60 min, so the backlight actually switches off,
plus the BLE stability settings documented in that file).

`modules/ble-profile-name/` is built into the LEFT half, and only the left. It
is an out-of-tree ZMK module that names the advertised device after the active
profile ("NocFree & BLE3"), the way the factory firmware does, so five profiles
are distinguishable to a host instead of all looking alike.

Left only, and not by preference. It references `zmk_ble_set_device_name()`,
`zmk_ble_active_profile_index()` and the profile-changed event, none of which
exist in a peripheral build, so compiling it into the right half does not
merely bloat that image -- it fails at link time with four undefined
references. Its Kconfig therefore depends on ZMK_SPLIT_ROLE_CENTRAL: every
build gets the same module list, as CI requires, and on the right half the
module switches itself off.

### Reproducibility, checked rather than assumed

The build is bit-reproducible, and checking it is worth the few minutes,
because the check caught something. Rebuilding the *Windows* configuration
from a clean workspace on a second machine reproduced the sibling unit's
images:

    right  a078308f...  identical, first attempt
    left   2d8120a6...  identical only once module-ble-profile-name was added

The left half not matching is how the module's presence in that build was
established. The provenance note here used to say the module was not part of
the build; the hashes said otherwise, and the file timestamps agreed with the
hashes -- the right half was built before the module was written and never
rebuilt afterwards, which is harmless, because the peripheral cannot link it.

Restructuring into a standard zmk-config repository (2026-10-04) changed
both hashes without changing any code. The board port used to be added as an
extra module and is now a west project, and the profile-name module is now
built through this repository's own module entry. Both change library names
and link order, so functions land at different addresses: the images are
the same size, with about 24,000 bytes changed in short runs across the
whole image, which is what relocated branch targets look like. This was
checked, not assumed: the same workspace, with the board port passed back in
as an extra module at its old paths, rebuilt 89df0ae6... and 51b29c33...
exactly. So the sources, patches and keymap carried over unchanged, and the
new hashes come from the layout alone.

The right-half image WAS byte-identical to the one the Windows sibling runs,
for as long as the only differences were keymap ones -- the peripheral never
links the keymap. That stopped being true with patches/0001: it changes the
kscan driver and both board devicetrees, so both images now differ from the
sibling's and both halves need reflashing for it.

## Bluetooth

Profiles advertise as "NocFree & BLE1" through "BLE5", so the pairing list
shows which slot you are on rather than five identical entries.

First pairing is unstable and settles by itself. Observed on both units and on
both operating systems: the link cycles for a while after a fresh pair, then is
fine. Give it a few minutes before changing anything.

### If it does not settle

The first thing to try is the connection interval, which has NOT been changed
here and is worth understanding before it is. This firmware asks the host for
7.5-15 ms, which is ZMK's default:

    CONFIG_BT_PERIPHERAL_PREF_MIN_INT=6     7.5 ms
    CONFIG_BT_PERIPHERAL_PREF_MAX_INT=12    15 ms

Apple's Accessory Design Guidelines do not allow that. They ask for an interval
minimum of at least 15 ms and a multiple of 15, an interval maximum of at least
minimum + 15, latency at most 30 and supervision timeout at most 6 s. macOS
rejects requests outside those rather than honouring them. This config already
satisfies the last two -- latency 0 and a 4 s timeout, both set for stability
in nocfree_and.conf -- but not the first two. An Apple-compliant pair would be:

    CONFIG_BT_PERIPHERAL_PREF_MIN_INT=12    15 ms
    CONFIG_BT_PERIPHERAL_PREF_MAX_INT=24    30 ms

Two reasons it is not applied pre-emptively. The link has not been shown to
need it here. And CONFIG_BT_PERIPHERAL_PREF_* applies to whichever half is
acting as a peripheral -- the left half on the host link, but also the RIGHT
half on the split link, where a slower interval is latency paid on every
keystroke from that hand. Fixing the host link alone means a left-only conf
that build.sh passes explicitly, rather than editing nocfree_and.conf.

Either way it is a Kconfig change, so both halves recompile and both need
reflashing. That is the cost to weigh against a link that currently works.

## The PCA9555 INT line: working

The scanner no longer polls the expanders when nothing is pressed. It parks on
the PCA9555 INT line and is woken by it. **Confirmed on both halves,
2026-09-15:** after ten seconds idle, the first key on either half is
immediate, and the interrupt handler's firings track key events.

The fork's docs/limitations.md lists deep sleep and interrupt-driven idle as
blocked because the INT line is unused. Unused by that port is not the same as
unwired, and the distinction had never been tested.

### The evidence it was wired

The vendor's porting guide -- github.com/NocFreeKB/NocFree-and-zmk, cited
throughout the fork's docs -- says so directly:

    The PCA9555 INT signal connects to the controller and wakes it when a
    key state changes.

    PCA9555 interrupt | D1 | P0.31 | Active low; input pull-up; may be
    used as a wake source

Factory v2.4.5 agrees: pinMode(D1, INPUT_PULLUP) then attachInterrupt(D1,
handler, FALLING). g_ADigitalPinMap in that image resolves D1 to P0.31 -- found
by searching for the table's shape, because the address docs/backlight.md
publishes is from v2.3.0 and has moved. D5 decoding to P0.20 confirms the right
table was found. A 1 ms polled sweep then measured about eight transitions per
keystroke on P0.31 and nothing on any other reachable pin.

### The pins are per half and not interchangeable

    left    P0.31   (D1).  The right half uses P0.31 as its battery-divider enable.
    right   P0.05   (D0).  The left half uses P0.05 as its battery-divider enable.

Which is why they live in each board .dts and never in the shared .dtsi.

### What the change does

Falling edge, matching the factory firmware. After arming, the line is sampled
once: if INT is already asserted its edge has gone, so a scan is queued rather
than waiting for one that will never arrive. A fallback scan stays scheduled
alongside, so a line that never asserts degrades the keyboard to one scan a
second instead of killing it. A spin guard falls back to plain polling if eight
consecutive arms find INT already asserted.

The subtle part is scheduling, and it is worth knowing about before touching
this driver. kscan_pca9555_reschedule() accumulates onto an ABSOLUTE deadline,
which is correct while a timer is its only caller. An interrupt-driven scan
breaks that: the deadline stays in the future, so the debounce rescan that
follows is computed as deadline + 3 ms rather than now + 3 ms and lands most of
a fallback period away. Presses never resolve and the keyboard reads as dead
rather than slow. Any out-of-band scan resets the deadline to now.

### Deep sleep works, but is not enabled by default

patches/0002 adds the wake path and it is verified on hardware, both halves on
battery: at the sleep timeout the Bluetooth link drops, and a keypress brings
the keyboard back.

System OFF wakes on SENSE/DETECT, which is level-based. The GPIOTE edge event
the scanner runs on does not survive System OFF, so the pm_action suspend hook
re-arms the pin level-triggered. The storm that makes a level interrupt
unusable while running cannot happen there -- no CPU is left to re-enter the
handler. INT is cleared first, by reading the expanders directly rather than
through a scan, because a stale assertion turns System OFF into an immediate
wake and the keyboard never sleeps at all.

Three things to know before enabling it:

  - **The waking keypress is discarded.** It is consumed as the wake trigger.
  - **Waking is a reboot, not a resume.** The chip comes up from scratch and
    Bluetooth has to re-establish, which takes seconds. Each half sleeps on its
    own timer and its own INT, so the split link re-forms separately.
  - **ZMK never sleeps on USB power.** activity.c gates on
    !is_usb_power_present(), so this only ever applies on battery.

To enable it, add to nocfree_and.conf:

    CONFIG_ZMK_SLEEP=y
    CONFIG_ZMK_IDLE_SLEEP_TIMEOUT=900000

900000 is ZMK's default, 15 minutes. The hardware testing used 60000 so the
wake path could be exercised in a minute; at that setting every pause of a
minute costs a lost keystroke and a reconnect, which is not worth it in daily
use. This is a Kconfig change, so both halves recompile and both need
reflashing.

If it ever sleeps and will not wake: USB power is itself a wake source on this
silicon, so plugging in should recover it. Failing that, the left half's
three-position switch is off in the middle and the right half has an on-off
switch -- but both only cut power when unplugged.

### Not established

Whether a level interrupt would also work. One was tried first and stormed --
2,299,361 handler entries across 11 arms -- but that measurement was taken with
a diagnostic module compiled in that reconfigured the pin without
GPIO_ACTIVE_LOW, clearing the invert bit, so the interrupt was armed against
the wrong sense. It has not been retried. Edge is used because it matches the
factory firmware and is measured working.

Power actually saved is also unmeasured. The claim is only that the I2C bus
stops being driven about 1.5 ms in every 10 ms while idle.

## Local patches

    patches/0001-kscan-interrupt-idle.patch     scanner parks on INT when idle
    patches/0002-kscan-sleep-wake-source.patch   INT as a System OFF wake source

Changes the fork cannot carry as user config: the kscan driver and both board
devicetrees. build.sh resets the board port's checkout in the west workspace
to the pinned commit and applies everything in patches/ in order, failing
loudly if one does not apply, so the pinned commit plus this directory remains
the whole input set. They are in `git format-patch` form, so `git am` moves
them onto a fork as-is -- see CI under Building for why that is the next step.

This is the first thing here that is not a user-config override, and it is the
reason the build is no longer stock upstream. Worth offering to the fork:
docs/limitations.md is wrong on this point and the author verified the backlight
pin the same evidence-first way.

See diagnostics/int-probe/ for the diagnostics that established the line
works, and TESTING.md for the protocol -- including the two mistakes that made
two earlier probes report the opposite.

## Caveats

Community firmware, not vendor supported, flashed at your own risk.
No deep sleep: the keyboard never powers down. Measured, not assumed -- see
below.
Battery readout is a stub and reads 100% permanently.
Backlight is on/off only, starts off at every boot, and switches itself off
after 60 s without a keystroke -- coming back as soon as you type. That last
one is nocfree_and.conf cutting the board's one-hour idle timeout, because
with AUTO_OFF_IDLE the backlight would otherwise stay lit for an hour after
the last keystroke, on both halves, and on battery that is the dominant drain.
Raising it is a Kconfig change: both halves recompile, both need reflashing.

Brightness is also scaled per half in the board devicetree -- left 25 %, right
30 % -- so F6 drives 25 % duty on the left, not 100 %. Those figures were tuned
by eye on a different unit, to match the halves and to keep a capacitor from
whining at low duty. If this unit wants more light, that is the number to
raise.
Developed and tested on Linux; the Windows sibling is in daily use. This macOS
configuration differs from it only in the bottom row.

Two macOS-specific notes, neither a defect in the firmware:

  - Fn+Home sends Print Screen, which macOS does not act on. Screenshots are
    Cmd-Shift-3/4/5. The binding is left in place so the two configurations
    stay identical everywhere but the bottom row.
  - macOS deliberately delays Caps Lock, so a very quick tap may not toggle it.
    Holding Caps Lock is the Nav layer and is unaffected.
