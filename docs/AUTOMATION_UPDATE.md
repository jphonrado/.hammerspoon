# Automatic trial flow restored: version 2.1.0

This update starts from the synced group revision `ff67ebb`. It preserves the group's last-tab reset, title changes, recordings and new focus tests, and retains the issue-2/3/4 logging, input, timing, interruption and session safeguards.

## What researchers do

Prepare and verify each condition once. Move Study Start to the LAST tab (6 or16), approve setup, choose **All tabs visible** only when every task tab and Study Start really fit without scrolling, then press the start shortcut once.

Normal within-condition flow is:

`correct target / ordinary timeout → save outcome → 0.30-second recording hold → cover tabs → 3-second countdown → verify neutral-LAST / pointer / window → next prompt`

After six scheduled trials, stop for TLX and prepare the next condition. There is no automatic jump across this boundary. Pause/Setup/emergency or an interruption/failure cancels automatic continuation and requires setup again. Exposed prompts are not silently replayed.

All shortcuts use Ctrl+Alt+Cmd. **P** pauses, **Esc** releases/stops in an emergency, **S** opens Setup, **A** approves, **Return** starts the first approved trial, and **N** advances after ratings. Do not press S/A/Return between ordinary automatic trials. Manual mode retains those steps if scrolling is needed or `autoAdvance=false`.

## What was preserved and corrected

- Study Start remains LAST under the groupmate's implementation; direct focus selects6/16 and the fallback is Cmd+9. The actual local HTML launcher still opens neutral first, so moving it to the end is a block-preparation step.
- The group's canonical title edits and nine replacement recordings are preserved. Nine targets also accept explicit earlier HTML titles, because the local HTML clone still uses them. Matching is exact, never fuzzy. Use one actual title version consistently for main sessions.
- Current audio hashes and materials-definition metadata have been refreshed. Original ZIP/audio provenance remains separate. Recordings were not transcribed or native-playback validated by this update.
- CSV outcome rows, video-coded blank final fields, active/completed participant guards, known neutral baseline, masks, bounded preparation, bound window, pointer reset and error cleanup remain.
- Automatic next-trial events identify retained block approval; they do not pretend that per-trial manual checks happened. Actual native order, visibility, panel width and OBS status still need researcher verification.

## Verification and limits

The final local suite passes **81 behavioral cases and10 Lua syntax checks**, including full automatic24-entry runs for all four groups, no replay/duplicates, block stops, timeout options, pause/countdown cancellation, failure cleanup, exact title aliases and last-neutral regressions. These are simulated Mac-adapter checks, not evidence from the actual study Mac.

Complete `MAC_CHECKLIST.md` in test/pilot mode. Main-study mode remains disabled by default. The paper work is on hold; its older neutral-first wording and the launcher instructions must be coordinated with this neutral-last setup before main collection.
