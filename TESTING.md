# Test protocol: interrupt-driven idle

Written before the change, not after, because the last two experiments here
were both invalidated by their own procedure rather than by the hardware.

## The lesson that produced this file

A probe watching the LEFT half's INT line was triggered by `Fn`+`P`. `P` is a
right-half key, and this keymap has an `Fn` on **both** halves. Reaching for
the right-hand `Fn` meant the whole gesture happened on the right half, so the
left half's INT had nothing to report and the probe read zero. Twice.

**On a split keyboard, always state which half a key belongs to.** The left
half carries: Esc, F1-F6, 1-6, Tab Q W E R T, Caps A S D F G, LShift < Z X C
V B, and the left bottom row. Everything else is the right half.

## What is being changed

The scanner stops polling when nothing is pressed and instead waits on the
PCA9555 INT line: left P0.31, right P0.05, active low, pulled up. A level
interrupt rather than an edge one, so a key change arriving between the last
read and arming cannot be lost -- INT is still asserted, so the interrupt
fires immediately.

A fallback poll stays armed alongside it. If the interrupt never fires, the
keyboard degrades to one scan per second rather than going dead.

## Before flashing

    ./dfu-touch.sh                  both halves listed, serials match
                                    left  <this unit's nRF52833 device id>
                                    right <this unit's nRF52833 device id>

Recovery is proven on this unit and independent of the keymap, so a firmware
that will not type is not a firmware that is lost:

    ./dfu-touch.sh --half left      USB CDC, 1200 baud
    Fn+Esc held 1.5 s               left half, from the keymap

## The tests

Flash the LEFT half only. Each test says which half its keys are on.

1. **Left half types.** Type `qwert asdfg zxcvb`. All 15 characters appear,
   in order, no repeats and no drops.

2. **Right half types.** Type `yuiop hjkl nm`. Confirms the split link is up.

3. **Wake from idle, left half.** Stop typing for 10 seconds. Press `q`.
   It must appear immediately -- no perceptible delay. This is the test the
   whole change exists for: the scanner is parked on the interrupt and `q`
   is what fires it.

4. **Wake from idle, right half.** Idle 10 s, press `y`. The right half is
   still polling at this stage, so this should behave exactly as it does now.

5. **Autorepeat.** Hold `a` (left half). Characters repeat at the host's rate.

6. **Fast typing.** Type a sentence quickly using both halves. No drops, no
   transpositions, no stuck modifiers.

7. **Layers.** `Caps`+`J`/`K`/`L` (Caps is left, JKL right) give arrows.
   `Fn`+`F1` (left `Fn`, left F1) dims the display.

8. **Recovery still works.** `./dfu-touch.sh --half left` returns the
   bootloader volume.

## Failure modes, and what each means

    dead after idle, revives         the interrupt is not firing; the fallback
    within ~1 s                      poll is carrying it. Check int-gpios and
                                     the pin against the porting guide.

    dead after idle, stays dead      both the interrupt and the fallback are
                                     broken. Recover with ./dfu-touch.sh
                                     --half left, then ./flash.sh left home.

    first key after idle lost,       INT cleared without the scan consuming
    second works                     the state. A level interrupt should make
                                     this impossible; if it happens, the
                                     interrupt is being armed before the read
                                     that clears INT.

    keys repeat or stick             the interrupt is re-firing while INT is
                                     still asserted -- it is not being
                                     disabled inside the handler.

## Not in scope for this change

Deep sleep. It needs a pm_action hook and INT cleared immediately before
System OFF, and it should be a separate change tested on top of a working
interrupt idle, not bundled with it.

## Results, 2026-09-15

Both halves, patches/0001, builds 77497ac2 (left) and 24c39344 (right).

    1  left half types          pass   qwert asdfg zxcvb
    2  right half types         pass   yuiop hjkl nm
    3  wake from idle, left     PASS   q immediate after 10 s
    4  wake from idle, right    PASS   y immediate after 10 s
    5  autorepeat               pass
    6  fast typing              pass
    7  layers                   pass
    8  recovery                 pass   dfu-touch used ~10 times during this work

Tests 3 and 4 are the ones the change exists for. 4 was a control in the
left-only stage and became a real test once the right half carried the patch
too -- its INT is P0.05 and had never been exercised.

Reported as "everything feels normal", which covers 5 through 7 as a group
rather than individually.

## Deep sleep, 2026-09-15

patches/0002, both halves, CONFIG_ZMK_SLEEP=y with a 60 s test timeout.

    sleeps                   PASS   Bluetooth link drops at the timeout, which
                                    is how you can tell System OFF was reached
                                    rather than merely idle
    wakes on a keypress      PASS   left half
    waking press discarded   yes    expected -- consumed as the wake trigger

Test it on battery. ZMK gates sleep on !is_usb_power_present(), so a cabled
keyboard never sleeps and the test silently does nothing.

NOT measured: current draw, asleep or awake. The power case for any of this
rests on an ammeter nobody has put on it yet.
