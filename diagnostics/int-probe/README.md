# INT sweep — diagnostic, not firmware

## RESULT: `int none`. The INT line is not wired on this unit's left half.

Both probes came back negative — P0.31 alone saw no edges, and a 32-pin sweep
saw no transitions on anything. Deep sleep and interrupt-driven idle need
hardware, not firmware. The main README records the conclusion; what follows
is how it was established, so it can be re-run on another unit.

Finds the PCA9555 interrupt line, if it is reachable at all.

docs/limitations.md in the fork names the unused expander INT line as what
stands between this port and both interrupt-driven idle and deep sleep.

## RESULT: INT confirmed live on P0.31.

    qwert asdfg zxcvb  ->  int l1 p31e120

15 left-half keys, 120 edges. The two earlier negatives came from binding the
readout to Fn+P: P is a right-half key and there is an Fn on both halves, so
reaching for the right-hand Fn meant no left-half key event occurred at all.
The probe watched one half and was triggered from the other.

The main README carries the conclusion and what it unlocks. What follows is
how the probe works, so it can be re-run -- on the right half, its INT is
P0.05, set via CONFIG_NOCFREE_INT_PROBE_PIN.

