# HCI2000 Hammerspoon study controller

Revised controller for **Effects of Browser Tab Orientation & Tab Load on Navigation Performance**.
Version **2.1.0**, updated 29 October 2026 from the group's synced `implemented-hammerspoon` branch (`ff67ebb`), retaining the earlier issue-2/3/4 repairs.

## What this folder is

This is the macOS experiment controller in the `.hammerspoon` Git repository. Its repository root contains `init.lua`, `study/` and `orlando_audio/`. The Python/HTML content project is separate in `hci_exp/Tab-Sets-for-Experiment`. Hammerspoon runs this package on the study Mac; **Python is not required to run the experiment controller**. Optional Python/Lupa tools are for developer tests only.

The controller masks/reveals Chrome's tab region, plays the group's current target recordings, manages the trial schedule, and writes auxiliary records. **Saved OBS video and manual coding remain the source of final retrieval times, first-selection accuracy and selection counts.** Polling observations are not silently promoted to final measurements.

### Verification status

The code was implemented and tested locally with Lua 5.4, simulated Hammerspoon APIs and real temporary record files. Exact test counts and source fingerprints are in `docs/LOCAL_CHECKS.json`.

The final local run passed **81 behavioral cases and all 10 Lua syntax checks** (12 model, 22 integration, 47 controller/loader). `docs/MILESTONES.md` tracks implementation versus native-device verification for 2A-4B.

**The actual macOS/Chrome/OBS checks have not been run here.** Input permissions, audio decoding/playback, native tab geometry, mask coverage and captured video must pass `docs/MAC_CHECKLIST.md` on the study laptop. Main-study mode is disabled by default; test and pilot modes work without declaring those checks complete.

| Milestone | Implemented work | Remaining study-Mac evidence |
|---|---|---|
| 2A | Checked fresh logs, explicit auxiliary fields, separate video-coding sheet, error propagation | Actual storage location and writable files |
| 2B | OBS/coding procedure and reproducible dummy examples | Saved video showing overlay, pointer, audio and identifiable target-active frames |
| 3A | Trial states, known neutral baseline, window/frame checks, masked input protection, calibration | Native Chrome/accessibility, cursor reset, mask coverage and input locking |
| 3B | Explicit exposure handling, pauses, no silent replay, controlled block transitions | Actual break/emergency/audio-failure behavior |
| 4A | Required coded identity, allocated group, unique run files, restart guards | Session dialogs/settings on the study Mac |
| 4B | Frozen allocation, preparation sheet and complete simulated sessions | Complete real-device dummy sessions and participant pilot |

## Changes from the original ZIP

The original archive is preserved. `docs/PROVENANCE.json` identifies its hash, original `init.lua` hash, current material manifest hash and all 20 copied audio hashes. `docs/ORIGINAL_INIT.lua.txt` is an unchanged reference snapshot for comparison; do not load that old script alongside the new controller.

| Original behavior | Revised behavior | Issue/milestone |
|---|---|---|
| One large `init.lua` mixed control, scheduling and records | Small loader plus separate configuration, materials, lifecycle, storage and Mac adapter modules | All |
| Participant `P001`, group `3` edited directly in source | Explicit session entry; main codes load their group/practice order from the allocation roster | 4A |
| Participant-only filenames could append after reload | New run-specific folder, active-session guard and main completion guard | 4A |
| Supplied P001 CSVs had no usable values | Legacy logs preserved separately and not reused; new header-checked records and visible errors | 2A |
| Automatic/hotkey times could look like final retrieval time | `auto_detection_elapsed_s` and `manual_ack_elapsed_s` separated from blank video-coded final fields | 2A |
| Wall-clock subtraction used for elapsed intervals | Boot-relative clock for auxiliary elapsed intervals; wall time retained for record matching | 2A |
| Detector's baseline read after input release | Verified Study Start baseline established before reveal/input release | 3A |
| Mask placement preceded window restoration | Approved geometry verified before mask construction; size/display calibration checked | 3A |
| Masked inter-trial periods could accept mouse input | Mouse/scroll lock during protected masked phases, explicit unlocked researcher Setup mode | 3A |
| Neutral activation requested without confirmation | Bounded neutral-title verification; failed preparation stops before audio exposure | 3A |
| Prompt exposure recorded only after reveal | Exposure intent checkpointed before playback; interrupted/uncertain prompts cannot silently replay | 3B |
| Retry hotkey could replay exposed scored entries | Exposed entries get an interruption outcome and are consumed; unexposed failures retain the entry | 3B |
| Original automatic next trial had no verified reset safeguards | Restored three-second automatic continuation inside an approved all-tabs-visible block; manual overflow fallback and explicit ratings/block boundary | 3B |
| Immediate reset could conceal the endpoint in video | Fixed 0.30-second post-outcome display hold, excluded from retrieval time; verify/refine in pilot | 2B/3B |
| Recalibration/settings changes possible during active phases | Calibration allowed only in Setup | 3A |
| Reload depended on runtime-local cleanup | Actual Hammerspoon shutdown hook preserves interruption/reload guards and chains unrelated callbacks | 3B/4A |
| Unexpected callback errors could interrupt cleanup | Guarded controls/timers/audio callbacks stop and release input on an exception | 3B |
| No demonstrated allocation validation | 16-slot permuted-block roster, balanced practice order, preparation sheet and checks | 4B |

The current conditions, group/content assignments, five target identities, six-trial schedules, common favicon and task-tab position lists are retained. The synced group changes to 24 page titles, nine target recordings, and Study Start at the LAST browser position are preserved. Exact legacy target-title aliases support the earlier HTML titles; they do not use fuzzy matching. All 20 delivered recordings match the synced baseline, including its nine replacements. History remains an extra content set outside the four scored sets.

### Start-cue dependency outside this repair

This package uses **the disappearance of the gray tab mask** as its operational start cue, matching the original Lua design and the group's current neutral page. It waits 0.40 seconds after the audio file ends before reveal.

The supplied paper and Python-generated prompt lists still mention spoken **Go**. The spoken content of the recordings has not been transcribed/changed. Reconcile paper, instructions and recordings before main collection. These code repairs do not resolve that separate issue automatically.

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

4. Reload Hammerspoon. Grant the permissions needed by the installed Hammerspoon/OBS versions, then test them. The HCI menu and a loaded message should appear.
5. Keep the HTML content project available separately on the Mac. Open its launcher to prepare the assigned topic/load. This package does not open or rearrange browser tabs for you.
6. Follow `docs/MAC_CHECKLIST.md` in **test/pilot mode** first. Fill the actual recording/device profile in `study/config.lua`. Enable `mainStudyEnabled` only after those checks and the remaining protocol requirements are resolved.

Use one dedicated Chrome study window/profile, the fixed external mouse and the intended display settings. Use direct HTML files or the documented plain static server for scored sessions rather than Live Server's injected reloading code.

### Synced changes preserved before this update

This release starts from the group's synced commit `ff67ebb`, not the obsolete first distribution. Its neutral-last reset (`focusTab(6/16)`, fallback `Cmd+9`), two focus regressions, revised canonical titles, and nine replacement recordings are retained. Current audio hashes and a combined materials-definition fingerprint are recorded in `docs/PROVENANCE.json`; original ZIP/audio fingerprints remain historical provenance. Audio wording and native playback were not verified here.

The existing local HTML launcher still opens Study Start first. **Move Study Start to LAST before approving the block**: browser tab 6 at low load, 16 at high load. Task-page browser indices now equal task positions; do not add one. This preserves the synced Lua contract. The earlier paper's neutral-first wording/table note and launcher instructions must be synchronized separately before main collection; this update does not edit those projects.

The local HTML pages also retain the earlier titles for nine scored targets. `docs/TITLE_COMPATIBILITY.json` lists the exact accepted canonical/legacy labels and all 24 page-title differences. Use one consistent title version across main participants and verify prompt/target identity; compatibility detection does not establish equal stimulus difficulty.

The original code remains in `docs/ORIGINAL_INIT.lua.txt` for comparison. Do not load it alongside the revised loader. Existing `orlando_logs/`, current `records/`, unrelated files, recordings, and Git history are preserved by the scoped local install. No Git staging, commit or remote push is performed.

### Automatic progression settings

`study/config.lua` defaults to:

```lua
autoAdvance = true,
interTrialDelaySeconds = 3.0,
autoAdvanceAfterTimeout = true,
```

These are researcher settings, not participant controls. A completed automatic/manual acknowledgment or ordinary timeout starts a three-second masked countdown after the 0.30-second outcome hold. The next trial then resets and verifies Study Start, the pointer, and the bound window before playing its scheduled prompt. The first prompt of each block remains an explicit start.

Automatic mode requires the researcher to confirm once at block preparation that **all task tabs AND Study Start are visible without tab-list scrolling, collapsed sections, or hidden tabs**. The controller checks window/frame, neutral title, mask geometry, and pointer; it does not prove tab order, exact count, panel width, visibility, or OBS status automatically. If scrolling is needed, choose **Manual trials** and reset the viewport before each trial. No unvalidated scrolling automation is claimed. Do not change geometry or reduce tab size merely to obtain automatic mode outside the frozen study settings.

Set `autoAdvance=false` to retain per-trial manual setup. Set `autoAdvanceAfterTimeout=false` to wait for manual preparation after a timeout. Pause, emergency, Setup, interrupted/invalid trials, loss of the study window/focus/frame, and storage/audio failures cancel continuation and require review/setup. Neither mode automatically enters a new condition, resumes a crashed run, or replays an exposed prompt.

## Session workflow

Keep preparation and researcher answer sheets out of the participant's view. Perform calibrations and manual setup only outside a timed trial.

1. **New session:** press `Ctrl+Alt+Cmd+B`, choose test/pilot/main, and enter the coded participant. Main IDs use the frozen roster; test/pilot requests the assigned group.
2. Review participant, group, practice order and four blocks. Prepare the assigned topic/load/orientation with the HTML launcher, close unrelated tabs, and move **Study Start to LAST**. Follow `docs/PREPARATION.md`.
3. Enter **Setup** (`Ctrl+Alt+Cmd+S`). Save the study window/frame with **W**, common pointer with **C**, and H/V mask corners with **H**/**V** as needed. Keep preparation outside the participant's view. Recalibrate after display/window changes.
4. Press **A** with the same modifiers. Confirm actual tab count/order, orientation, panel width, aids, starting viewport and OBS. Then choose **All tabs visible** for automatic block flow, or **Manual trials** if scrolling/reset checks are needed. This choice records the scope of the approval accurately.
5. Press **Return** with the modifiers to start the first trial. The controller selects the last neutral tab and verifies its title, frame and pointer before playing the prompt. Tabs stay masked/input locked until audio completion and the configured reveal delay.
6. When the participant selects the correct target, completion is recorded automatically. The correct page remains visible for 0.30 seconds for OBS, then the mask returns and the next prompt begins after a three-second countdown. **Do not press S/A/Return between ordinary automatic trials.** Wrong selections do not end a trial. **.** remains a manual completion acknowledgment if detection is unavailable; video supplies the final endpoint.
7. **P** pauses/cancels the next prompt and **Esc** provides emergency release (both with modifiers). A break during an exposed trial documents/consumes it without replay. Resume through **S → A → Return**, approving the current setup again. In manual/scrolling mode, use this sequence between trials to restore the tab-list viewport.
8. After six scheduled entries, the controller stops for that condition's TLX ratings. Press **N** after the ratings to prepare the next block; approve and start it explicitly. After the final block, **N** closes the session. Complete the weighting/interview under the study protocol.
9. Retain original logs and OBS files. Code final measures in a separate copy of `video_coding.csv`; compare and document discrepancies with auxiliary records. No automatic estimate becomes a final measurement without video review.

All letter/key shortcuts below use **Ctrl+Alt+Cmd** together. On macOS, Alt is Option.

| Key | Action |
|---|---|
| B | New checked session |
| S | Enter researcher Setup / resume through setup |
| A | Approve setup and choose all-visible automatic flow or manual trials |
| Return | Start the first approved trial; cannot bypass an active countdown |
| . | Correct target observed manually; exact measures require video |
| P | Pause/break; an exposed entry is documented and consumed |
| I | Invalidate/interruption; no automatic exposed-prompt replay |
| Esc | Emergency stop, release input and preserve interruption context |
| N | Next block / finalize after last block and ratings |
| W | Save study Chrome window/frame, Setup only |
| C | Save common absolute pointer position, Setup only |
| H / V | Two-corner mask calibration for that orientation, Setup only |
| T | Show current participant/group/block/trial/phase |
| E | End session; exposed/interrupted sessions retain their review guard |

During input lock, use keyboard shortcuts: mouse clicks, including the HCI menu, are intentionally blocked. Esc with the modifiers is always the emergency release. The input-lock watchdog also stops the procedure rather than silently allowing a trial to continue.

## Breaks, failures and restarts

- A preparation failure before prompt exposure keeps that scheduled entry available. Use Setup, fix the cause and approve again.
- From the instant playback is attempted, exposure is conservatively recorded. A partial, interrupted or uncertain prompt is not silently replayed as a replacement scored trial.
- A break during an exposed trial records an interrupted outcome and advances to the remaining schedule. Resume with Setup; a break does not create a replacement trial.
- Timeout means incomplete: no completed retrieval time is inserted. Genuine no-selection, an incorrect first selection and an unobservable selection are different coding outcomes.
- A completed/manual/timeout outcome is written once. Manual times/counts and all polling observations still need video verification.
- On storage failure, the procedure stops and releases input. Do not keep running on a guessed logging state.
- On reload/crash/interrupted end, `ACTIVE.json` and `.session-lock/` can remain. The controller refuses to start that participant again automatically. This release intentionally has **no automatic resume**.
- An unexpected native callback error also stops the controller and attempts synchronous input/record cleanup. Read the Hammerspoon Console and preserve the guarded session; do not keep starting prompts after an error.
- Preserve the entire run and review its video, checkpoint, prompt exposure and outcomes with the research team. Do not delete a guard merely to replay exposed items. Continuation/replacement must follow a documented study decision; an AI must not infer permission to remove markers or rewrite old records.
- A completely unexposed session can be cancelled cleanly. Main participants with a finalized session cannot be collected again through a fresh default session.

## Files and data

```text
.hammerspoon/
  init.lua                     Top-level Hammerspoon loader
  study/config.lua             Timing, recording profile and main-mode switch
  study/controller.lua         Mac UI, masks, input, audio and orchestration
  study/model.lua              Pure trial-state and exposure rules
  study/storage.lua            Record files, checks and restart guards
  study/materials.lua          Existing targets/orders/positions, generated once
  study/allocation.lua         Frozen 16-slot main allocation
  orlando_audio/               20 current synced recordings (9 replaced by group)
  records/                     New local test/pilot/main records
  DATA_DICTIONARY.md            CSV meanings and missing-value rules
  docs/PREPARATION.md           Target positions and tab-order reference
  docs/allocation.csv           Human-readable allocation/practice template
  docs/MAC_CHECKLIST.md         Required native-device checks
  docs/PROVENANCE.json          Original ZIP, source and audio fingerprints
  docs/LOCAL_CHECKS.json        Local test evidence, not a Mac approval
  examples/                    Clearly labeled simulated records
  tests/ and tools/            Optional developer tests
```

Each new run lives under `records/<mode>/<participant>/<session_id>/` with `session.json`, `checkpoint.json`, `events.csv`, `trials_aux.csv` and `video_coding.csv`. The checkpoint also records the approved frame, saved pointer, both mask calibrations, automatic block approval, and pending automatic trial identity. Checkpoints are audit snapshots, not automatic-resume authorization. Expected current-audio fingerprints and the materials-definition fingerprint identify this delivery; the source-manifest hash remains historical input provenance, and these are provenance, not a claim that playback/wording was validated on the Mac. Do not put participant names or consent forms here. See `DATA_DICTIONARY.md` for exact columns.

`reveal_command_monotonic_s` records a software request, not a visible frame. `auto_detection_elapsed_s` includes polling delay. `manual_ack_elapsed_s` includes facilitator reaction time. Final retrieval time uses the agreed recorded start and first correct target-active frame. Completed verified trials satisfy `total_tab_switches = incorrect_selections + 1`.

### For future developers and AI assistants

- Read this README, the data dictionary, local check report and actual Mac evidence before claiming readiness.
- Preserve existing title/topic/order/position relationships unless the research group explicitly changes the protocol.
- Do not silently synchronize the still-conflicting paper/audio cue by editing recordings or the HTML project.
- `materials.lua` and `allocation.lua` are versioned inputs. If regenerated, verify all mappings and update preparation sheets/tests/provenance together.
- Keep raw controller observations distinct from final coded data. Do not invent missing selections or outcomes to force agreement.
- Do not remove an active-session guard or auto-resume an exposed entry without documented recovery review.
- Development tests use Lua 5.4 through optional Python `lupa`; Hammerspoon execution itself is native Lua. Example records are simulated test data, never participant results.

Optional local developer check (Python with an isolated Lupa installation):

```text
python tools/run_checks.py --lua-python-path PATH_TO_ISOLATED_LUPA
```

## Method/API references

- Hammerspoon boot-relative clock: https://www.hammerspoon.org/docs/hs.timer.html#absoluteTime
- Canvas appearance versus click activation: https://www.hammerspoon.org/docs/hs.canvas.html#clickActivating
- Input hooks: https://www.hammerspoon.org/docs/hs.eventtap.html
- Sound loading/playback: https://www.hammerspoon.org/docs/hs.sound.html
- Chrome tab focusing: https://www.hammerspoon.org/docs/hs.window.html#focusTab

These references describe APIs; they do not establish that the group's hardware/OBS configuration has passed validation.
