# Actual study-Mac verification record

Status: **NOT RUN**. Do not change this to passed based on Windows/simulated tests.

Operator: __________  Date: __________  Controller version: __________
Mac/macOS: __________  Chrome: __________  Hammerspoon: __________  OBS (optional backup): __________
Display/scaling/window: __________  Mouse/settings: __________
Optional OBS backup (source/resolution/fps/audio): __________
Recording filenames/session IDs: __________

## 2A - Records

- [ ] New test session creates populated event/outcome files with the documented headers.
- [ ] A zero stays zero; missing final measures stay blank.
- [ ] Actual output location is writable; a write failure visibly stops and releases input.
- [ ] `main_data.csv` has the final measure columns, with no `video_coding.csv` and no `video_verified`/`coder` columns.

## 2B - Actual measurements

- [ ] (Optional) If an OBS backup is recorded, it shows the mask, pointer, active tab and prompt audio clearly enough to clarify a disputed trial.
- [ ] Automatic completion leaves the correct page visible for the outcome hold before masking.
- [ ] Test correct; wrong-correct; wrong-neutral-correct; already-active click; rapid wrong-correct.
- [ ] Test timeout with no selection; timeout after errors; manual completion. The deadline is 20 seconds AFTER reveal, excluding audio.
- [ ] Use ONE click per tab in H-L/H-H/V-L/V-H over several consecutive trials; confirm no lost first clicks.
- [ ] Hold the correct-target button through detection, then release: Chrome receives that release before mask/reset; no stuck drag or extra selection follows.
- [ ] Check buffered MOUSE_INPUT_TRACE (pass, blocked, pass_existing_release), including a queued release and the first click of the next trial.
- [ ] Hold a button before reveal: controller stops without leaking a partial click into a timed trial; already exposed prompt is not replayed.
- [ ] Click-count cross-check: for several trials, the title changes in `events.csv` match the clicks in `MOUSE_INPUT_TRACE` and what you saw on screen.
- [ ] Check accessibility title notifications and poll-only fallback; confirm that rapid wrong-neutral-correct transitions are all counted in `events.csv`.
- [ ] Reveal command/return bracket and observed endpoint are consistent with a stopwatch or the optional backup recording within the documented detection limits.
- [ ] Run a test session and check `main_data.csv`: correct/incorrect/timeout counts, `no_selection` on a timeout with no click, `technical_loss` false after a participant break (P) and true after a forced fault.
- [ ] Google Forms results can be matched by coded participant AND condition; NASA-TLX remains outside this controller.

## 3A - Native setup and input

- [ ] One dedicated Chrome study window is bound and its approved frame remains fixed.
- [ ] Study Start is LAST (6/16) and becomes active before prompt playback.
- [ ] Common pointer coordinate lies in the content area for both orientations.
- [ ] H/V masks cover all relevant native tab labels, with the same approved frame/display.
- [ ] Clicking/dragging/scrolling under the mask cannot change participant state unnoticed.
- [ ] Native tab order, orientation, panel width and exact 6/16 total tabs are correct.
- [ ] Automatic mode is enabled only after confirming every task tab AND Study Start fit without scrolling; verify this separately in all four configurations.
- [ ] If scrolling is required, Manual trials is selected and the tab-list viewport is reset before each trial. No automatic scroll reset is assumed.
- [ ] Prohibited hover aids/search/grouping/pinning/shortcuts are disabled or prevented by procedure.
- [ ] Moved/resized/lost window, failed neutral activation and failed input permission stop preparation/trial.

## 3B - Automatic progression, failures and pacing

- [ ] One explicit initial start runs all six normal trials within a block without repeated S/A/Return.
- [ ] Outcome hold, three-second masked countdown, neutral-LAST reset, pointer reset and full next prompt occur as described.
- [ ] Ordinary timeout advances as configured without inventing a completed time; timeout-auto-off waits instead.
- [ ] P/Esc/Setup cancels a pending countdown; resuming does not replay the finished target.
- [ ] Window/focus/frame/mask, audio and storage failure cannot expose the next prompt silently.
- [ ] No automatic transition crosses the TLX/condition boundary.
- [ ] Current canonical and permitted legacy target titles are recognized exactly; unrelated titles are rejected.
- [ ] Confirm one consistent actual title/audio version is used for all main sessions; reconcile neutral-LAST with launcher and paper setup instructions.

- [ ] Pause before exposure retains the entry; pause during/after prompt consumes and documents it.
- [ ] Missing/unreadable audio before exposure stops; interrupted/uncertain playback is not replayed as a scored replacement.
- [ ] Break request prevents the next prompt from starting automatically.
- [ ] Completed/timeout/interrupted entries each have exactly one terminal row.
- [ ] Emergency release works, stops audio/timers and releases mouse input.
- [ ] Watchdog release stops the procedure; it does not continue a trial silently.
- [ ] Next block requires ratings and explicit researcher preparation/approval.

## 4A/4B - Sessions and complete runs

- [ ] Test/pilot/main identities are separate; no names or consent records are stored with measures.
- [ ] Main roster group and practice order match `study/allocation.lua` (P001-P016 frozen template; P017 onward from its fixed rule).
- [ ] Invalid/missing codes or groups cannot start; duplicate/reloaded sessions are guarded.
- [ ] Run a complete 24-entry dummy session for each of the four groups on the Mac.
- [ ] Targets/audio/conditions/sets agree with the preparation sheet in every block.
- [ ] Raw records, any optional backup recording and the survey responses can be linked unambiguously (participant code + condition).
- [ ] Repeat measurement checks after any controller/settings revision.

## Remaining protocol decisions

- [ ] Paper/figures, recordings and neutral-page instructions agree on the start cue (mask disappearance).
- [ ] Recordings have been listened to; actual spoken wording and consistent volume verified.
- [ ] Separate practice materials and participant forms are ready.
- [ ] Participant pilot completed separately from main data; remaining issues documented.
- [ ] Actual profile values entered in study/config.lua before collecting main-study data.

Notes, failures, changes and evidence: __________________________________________

This is an operational verification record, not automatic research approval or a substitute for the group's course/university requirements.
