# 20-second deadline and intermittent-click investigation

29 October 2026. Baseline: `implemented-hammerspoon` at
`44e1b48a62a53003ceae2a61db4e601a408359f4`. Patched controller: **2.2.1**.

## Deadline

`study/config.lua` now sets `timeoutSeconds = 20`. The limit runs from mask
disappearance/software reveal, not from audio playback. The checked GitHub
baseline still contained 60 seconds; the requested final value is 20 regardless
of whether the study Mac's local copy had already been edited to 30.
Timeouts remain incomplete, with no completed retrieval time. Normal automatic
within-block progression is retained. NASA-TLX remains in Google Forms.

## What was found

The old `lock()` event callback returned `true` for every mouse event, including
mouse-up. `finish()` installed that lock as soon as it detected the correct tab.
If a tab activates on the down half of a click, the release half can therefore
be swallowed by the new lock. Chrome has received a down without its matching
up, which is a plausible explanation for stuck/drag-like or extra-click behavior.
Pointer/neutral reset could also occur while that click was still held.

This controller-level fault is reproduced with simulated events: on the exact
baseline, a matching pre-lock release is blocked. The same regression now passes.
`CLICK_REPRO_BEFORE.json` preserves the intentionally failing baseline replay.
**This does not prove it is the only cause of the reported Mac symptom.** Actual
Chrome/OS behavior and the user's hardware have not been reproduced here.

## Changes

- Preserve exactly the release of a button press Chrome already received.
  Block new presses, pointer motion, dragging and scrolling during protected phases.
- Track passed downs as well as physical button state, so a release queued during
  a title/log callback is still allowed. Reuse an existing gate rather than
  treating a masked held press as a new pre-lock click.
- After the minimum 0.30-second target display hold, wait for the existing click
  to finish before remasking, neutral reset or pointer reset. This wait is
  bounded by a further two seconds, occurs after the measured endpoint, and
  never changes the saved RT. An expired wait pauses without duplicating the
  completed outcome or replaying the prompt.
- Reject a held button before reset or reveal. Before exposure, the entry stays
  available; after the prompt may have been heard, interruption consumes it under
  the existing no-replay rule. Do not press a mouse button until reveal; holding
  the mouse itself is fine. No variable audio-to-reveal waiting is introduced.
- Activate Chrome during Setup and verify both the selected window and active
  application before starting/revealing. No synthetic activation click is sent.
- Buffer button diagnostics in memory and write `MOUSE_INPUT_TRACE` events after
  the timed interval. The trace includes pass/block decisions, point, native
  timestamp, click count and window ID. It is not the selection-count measure.
  A crash can lose an unflushed buffer. `mouseClickDiagnostics=false` disables
  trace logging while preserving the passive monitor and release-pair fix.

## Verify on the study Mac

Use test/pilot mode and save OBS. For **all four H/V × low/high configurations**:

1. Complete several consecutive automatic trials using one ordinary click per
   requested tab. Check the first click after reveal and after a previous target.
2. Deliberately hold the correct-tab button beyond detection for about half a
   second, then release. The release should finish normally; no drag, extra tab
   activation or second click should be needed. Reset must wait for release.
3. Check wrong → correct and wrong → neutral → correct. Counts still represent
   activations, not the number of mouse down/up events.
4. Deliberately press under the mask and release before reveal: neither half
   should activate a tab. A fresh first click after reveal should work.
5. Deliberately hold a button through reveal: the trial should stop, remain
   untimed, and not replay the exposed cue. This is a controlled test of failure
   handling, not a scored navigation trial.
6. Leave the mouse untouched after reveal. Timeout should occur at about 20
   seconds in OBS and have blank completed RT in the logs.
7. Confirm Chrome stays active and that both masks disappear completely. If a
   single click still fails, retain the OBS clip, the run folder, condition,
   trial ID and `MOUSE_INPUT_TRACE` rows. They distinguish input blocking,
   inactive-window behavior and a click that arrived without a tab activation.

Keep the actual browser/display settings fixed during this verification. Do not
introduce double-clicking as a participant instruction to work around the bug.

## Local checks

111 Lua behavioral cases (12 model, 24 storage/material integration, 75 adapter),
10 Lua syntax checks, and 15 Python encoding cases pass. Cases cover matching
left/right/extra-button releases, queued release delivery, held clicks, next-trial
single clicks, premature actions, focus, diagnostics-off behavior and the exact
20-second deadline. These are software simulations; native validation is pending.

API references: [mouse-button state and event taps](https://www.hammerspoon.org/docs/hs.eventtap.html),
[button-event properties](https://www.hammerspoon.org/docs/hs.eventtap.event.html),
[active application](https://www.hammerspoon.org/docs/hs.application.html#isFrontmost).
