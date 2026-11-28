# HCI2000 Hammerspoon study controller

Controller for **Effects of Browser Tab Orientation & Tab Load on Navigation Performance**, version **2.3.1** (software-only measurement).

Hammerspoon runs this folder on the study Mac; **Python is not needed to run the experiment.** The controller masks and reveals Chrome's tab strip, plays the target prompt, runs the trial schedule, and writes the final measures itself to `main_data.csv` (retrieval time, first-selection correctness, selection counts, `no_selection`, `technical_loss`) by watching the Chrome window title. **NASA-TLX is collected separately in Google Forms.** Video is not coded; an OBS recording is an optional backup only. See `DATA_DICTIONARY.md` for exact column definitions and limits.

## Files

```text
.hammerspoon/
  init.lua                Hammerspoon loader
  study/config.lua        Timing, automatic-progression and main-mode settings
  study/controller.lua    Mac UI, masks, input lock, audio and trial orchestration
  study/model.lua         Trial-state and exposure rules
  study/storage.lua       Record files, header checks and restart guards
  study/materials.lua     Targets, condition orders, tab positions, titles
  study/allocation.lua    Main allocation: frozen P001-P016, then P017+ by fixed rule (no cap)
  orlando_audio/          20 target prompt recordings
  records/                Session records (test / pilot / main)
  docs/PREPARATION.md     Block preparation sheet (target positions, tab order)
  docs/MAC_CHECKLIST.md   Native study-Mac verification record
  DATA_DICTIONARY.md      Record layout and column meanings
  tests/, tools/          Developer tests (Python + lupa)
```

Each run is written to `records/<mode>/<participant>/<session_id>/`: `main_data.csv` (the analysis table, one row per trial), `events.csv`, `trials_aux.csv`, `session.json` and `checkpoint.json`. Participant folders also hold `ACTIVE.json` / `.session-lock/` while a session is open and `COMPLETED.json` after a main session finishes. Do not put names or consent forms here.

## Install on the study Mac

1. Back up the Mac's existing `~/.hammerspoon/` configuration and any existing study records.
2. Disable the previous experiment controller so the old and new versions do not bind the same hotkeys. Preserve unrelated personal Hammerspoon customizations.
3. Place the **contents of this repository** in `~/.hammerspoon/`, so that these paths exist:

```text
~/.hammerspoon/init.lua
~/.hammerspoon/study/controller.lua
~/.hammerspoon/orlando_audio/A_P1.m4a
```

The repository's `init.lua` is already the loader. **Do not replace it with a line that loads itself, and do not nest the files inside a second `.hammerspoon` directory.** If the Mac has personal customizations, integrate them carefully without loading the original experiment code twice.

4. Reload Hammerspoon. Grant the permissions needed by the installed Hammerspoon (and OBS, if you record a backup), then test them. The HCI menu and a loaded message should appear.
5. Keep the HTML content project available separately on the Mac. Open its launcher to prepare the assigned topic/load. This package does not open or rearrange browser tabs for you.
6. Follow `docs/MAC_CHECKLIST.md` in **test/pilot mode** first. The controller permits main mode with the same runtime settings as test and pilot; the checklist remains recommended for validating the setup.

Use one dedicated Chrome study window/profile, the fixed external mouse and the intended display settings. Use direct HTML files or the documented plain static server for scored sessions rather than Live Server's injected reloading code.

## Automatic progression settings

`study/config.lua` defaults to:

```lua
autoAdvance = true,
interTrialDelaySeconds = 3.0,
autoAdvanceAfterTimeout = true,
```

These are researcher settings, not participant controls. The trial limit is **20 seconds after mask disappearance**, excluding the prompt. A completed automatic/manual acknowledgment or ordinary timeout starts a three-second masked countdown after the minimum 0.30-second outcome hold and completion of the current mouse-button release. The next trial then resets and verifies Study Start, the pointer, and the bound window before playing its scheduled prompt. The first prompt of each block remains an explicit start.

Automatic mode requires the researcher to confirm once at block preparation that **all task tabs AND Study Start are visible without tab-list scrolling, collapsed sections, or hidden tabs**. The controller checks window/frame, neutral title, mask geometry, and pointer; it does not prove tab order, exact count, panel width, or visibility automatically. If scrolling is needed, choose **Manual trials** and reset the viewport before each trial. No unvalidated scrolling automation is claimed. Do not change geometry or reduce tab size merely to obtain automatic mode outside the frozen study settings.

Set `autoAdvance=false` to retain per-trial manual setup. Set `autoAdvanceAfterTimeout=false` to wait for manual preparation after a timeout. Test, pilot and main use the same runtime settings; main still uses the frozen participant allocation and completion guards. Pause, emergency, Setup, interrupted/invalid trials, loss of the study window/focus/frame, and storage/audio failures cancel continuation and require review/setup. Neither mode automatically enters a new condition, resumes a crashed run, or replays an exposed prompt.

## Session workflow

Keep preparation and researcher answer sheets out of the participant's view. Perform calibrations and manual setup only outside a timed trial.

1. **New session:** press `Ctrl+Alt+Cmd+B`, choose test/pilot/main, and enter the coded participant. Main IDs (P001, P002, ... with no upper limit) take their group and practice order from `study/allocation.lua`; issue them in order without skipping codes. Test/pilot requests the assigned group.
2. Review participant, group, practice order and four blocks. Prepare the assigned topic/load/orientation with the HTML launcher, close unrelated tabs, and move **Study Start to LAST**. Follow `docs/PREPARATION.md`.
3. Enter **Setup** (`Ctrl+Alt+Cmd+S`). Save the study window/frame with **W**, common pointer with **C**, and H/V mask corners with **H**/**V** as needed. Keep preparation outside the participant's view. Recalibrate after display/window changes.
4. Press **A** with the same modifiers. Confirm actual tab count/order, orientation, panel width, aids, starting viewport (and OBS, if recording a backup). Then choose **All tabs visible** for automatic block flow, or **Manual trials** if scrolling/reset checks are needed. This choice records the scope of the approval accurately.
5. Press **Return** with the modifiers to start the first trial. The controller selects the last neutral tab and verifies its title, frame and pointer before playing the prompt. Tabs stay masked/input locked until audio completion and the configured reveal delay.
6. When the participant selects the correct target, completion is recorded automatically. The correct page remains visible for at least 0.30 seconds; its click release is delivered before reset, then the mask returns and the next prompt begins after a three-second countdown. **Do not press S/A/Return between ordinary automatic trials.** Wrong selections do not end a trial. **.** remains a manual completion acknowledgment if detection is unavailable; it produces no retrieval time.
7. **P** pauses/cancels the next prompt and **Esc** provides emergency release (both with modifiers). A break during an exposed trial documents/consumes it without replay. Resume through **S → A → Return**, approving the current setup again. In manual/scrolling mode, use this sequence between trials to restore the tab-list viewport.
8. After six scheduled entries, the controller stops for that condition's TLX ratings. Press **N** after the ratings to prepare the next block; approve and start it explicitly. After the final block, **N** closes the session. Complete the weighting/interview under the study protocol.
9. Retain the original run folder (`main_data.csv`, `events.csv`, `trials_aux.csv`) and any optional OBS backup. `main_data.csv` is the analysis source; check `POLL_GAP` events and click traces if a trial looks odd.

All letter/key shortcuts below use **Ctrl+Alt+Cmd** together. On macOS, Alt is Option.

| Key | Action |
|---|---|
| B | New checked session |
| S | Enter researcher Setup / resume through setup |
| A | Approve setup and choose all-visible automatic flow or manual trials |
| Return | Start the first approved trial; cannot bypass an active countdown |
| . | Correct target observed manually; no retrieval time is recorded |
| P | Pause/break; an exposed entry is documented and consumed |
| I | Invalidate/interruption; no automatic exposed-prompt replay |
| Esc | Emergency stop, release input and preserve interruption context |
| N | Next block / finalize after last block and ratings |
| W | Save study Chrome window/frame, Setup only |
| C | Save common absolute pointer position, Setup only |
| H / V | Two-corner mask calibration for that orientation, Setup only |
| T | Show current participant/group/block/trial/phase |
| E | End session; exposed/interrupted sessions retain their review guard |

During input lock, use keyboard shortcuts: new mouse clicks, including the HCI menu, are intentionally blocked. A release matching a press Chrome already received passes through so its click cannot get stuck. Keep click buttons released until the tabs are revealed; participants can keep holding the mouse itself. The pointer itself is also held still while input is locked (from approval or trial start, through the prompt, and during the pause between trials) and is freed the moment the mask drops; each trial still starts from the saved pointer position. Set `freezePointerWhileMasked = false` in `study/config.lua` to turn this off. Esc with the modifiers is always the emergency release. The input-lock watchdog also stops the procedure rather than silently allowing a trial to continue.

## Breaks, failures and restarts

- A preparation failure before prompt exposure keeps that scheduled entry available. Use Setup, fix the cause and approve again.
- From the instant playback is attempted, exposure is conservatively recorded. A partial, interrupted or uncertain prompt is not silently replayed as a replacement scored trial.
- A break during an exposed trial records an interrupted outcome and advances to the remaining schedule. Resume with Setup; a break does not create a replacement trial.
- Timeout means incomplete: no completed retrieval time is inserted. A timeout with no observed title change is flagged `no_selection`; an incorrect first selection is recorded in `first_selection_correct`.
- A completed/manual/timeout outcome is written once. Manual completion records no time, and polling can miss a very brief selection (see `DATA_DICTIONARY.md`).
- On storage failure, the procedure stops and releases input. Do not keep running on a guessed logging state.
- On reload/crash/interrupted end, `ACTIVE.json` and `.session-lock/` can remain. The controller refuses to start that participant again automatically. This release intentionally has **no automatic resume**.
- An unexpected native callback error also stops the controller and attempts synchronous input/record cleanup. Read the Hammerspoon Console and preserve the guarded session; do not keep starting prompts after an error.
- Preserve the entire run and review its checkpoint, events, prompt exposure and outcomes (and any backup recording) with the research team. Do not delete a guard merely to replay exposed items. Continuation/replacement must follow a documented study decision; an AI must not infer permission to remove markers or rewrite old records.
- Do not delete a run while Hammerspoon is still running it. The controller retains the run in memory and reports the missing record directory on its next checkpoint; stop or reload Hammerspoon first, then remove test records if needed.
- A completely unexposed session can be cancelled cleanly. Main participants with a finalized session cannot be collected again through a fresh default session.

## Google Forms

NASA-TLX is collected through separate Google Forms. Join block ratings to `main_data.csv` by participant code plus condition, never by block order or row order. No form, questionnaire UI, workload scoring or audio is changed by the controller.

## Developer tests

The Lua logic is tested with simulated Hammerspoon APIs (no real Chrome, input hooks or audio):

```text
python3 tools/run_checks.py                                   # uses .dev-cache/python if present
python3 tools/run_checks.py --lua-python-path PATH_TO_LUPA     # or point at an isolated lupa install
```

Expected: 10/10 Lua syntax checks, model 12, integration 25, controller 79 cases. The report is written to `.dev-cache/LOCAL_CHECKS.json` (git-ignored). Passing these checks does not replace `docs/MAC_CHECKLIST.md` on the study laptop.

## Open issues

- **Start cue:** the controller's start cue is the disappearance of the gray tab mask, 0.40 s after the prompt audio ends. The paper still describes a spoken **"Go"**. Reconcile the paper, instructions and recordings before main collection.
- **Study Start position:** the HTML launcher opens Study Start first; move it to the **last** tab before approving each block.

Earlier change history, patches and audits are in the Git history.
