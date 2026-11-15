# Measurement records and session guards

Schema version: **2.1** (new run folders only; 2.0 folders also had `video_coding.csv` and the
`video_verified`/`coder` columns). Final study measurements come from the controller's own records in
`main_data.csv`. Video is not coded; an optional OBS backup may be kept to clarify an unusual trial.

## Record layout

Records are stored under `records/<mode>/<participant>/<session_id>/` (the base
directory is configured by the controller). Modes are `test`, `pilot`, and
`main`. IDs contain only letters, digits, hyphens and underscores. Participant
names and consent records do not belong in this folder.

- `session.json`: participant/group/run identity, approved block plan, versions,
  settings supplied by the controller, creation time and terminal session status.
- `checkpoint.json`: most recent controller snapshot. It supports audit/recovery
  review, **not automatic replay or resume**.
- `events.csv`: append-only controller commands and observed title transitions.
- `trials_aux.csv`: one terminal audit record per scheduled trial that was
  exposed, with the raw polling observations behind `main_data.csv`.
- `main_data.csv`: **the analysis table**, one row per exposed trial. See
  "Final outcomes" below.


At participant level, `ACTIVE.json` and `.session-lock/` reserve the participant.
They survive interruption/reload so a new first trial cannot silently restart an
already exposed session. `COMPLETED.json` blocks main-study participant reuse
after clean completion. Do not remove guards to retry exposed scored trials.
Any recovery requires documented review of prior recordings/exposures and the
study's interruption rules. A clean cancellation is allowed only before any
prompt exposure or outcome.

## Common columns

Every CSV row carries `session_id`, `mode`, `participant`, `group`, `block`,
`condition`, `orientation`, `tab_load`, `content_set`, `trial`, `target_id`, and
`target_title`. Session-level events may leave trial-specific columns empty.
Trial outcome records require the block, condition, set, trial and target fields.
Plan-derived fields add `is_repeat` (0/1), `target_task_position` (1-based task
position, equal to browser position with neutral-LAST), `task_tab_count` (5/15),
and `visible_tab_count` (6/16). These describe the approved plan, not an automatic
measurement of the actual native layout.

## Event and trial log fields

- `wall_epoch`: wall-clock seconds for matching records to sessions/recordings.
- `monotonic_s`: boot-relative seconds supplied by the controller.
- `elapsed_s`: auxiliary elapsed interval, never a rendered-frame guarantee.
- `observed_title`: title seen at a polling sample or accessibility callback.
- `observation_source`: `poll` or `accessibility` for observed transitions.
- `aux_selection_count`, `aux_incorrect_count`, `aux_first_correct`: polling
  observations. A 0 remains 0; an unavailable value remains blank.
- `reveal_command_monotonic_s`: time the controller requested reveal, not proof
  of the first visible video frame.
- `mask_hide_returned_monotonic_s`: boot-relative marker immediately after mask
  deletion returned. The command/return markers bracket software work; neither
  establishes the rendered onset. Disk writes occur after mask removal.
- `endpoint_monotonic_s`: observed endpoint captured before transition/outcome
  storage. `observed_duration_s` is the elapsed observed interval, including
  incomplete attempts; it is not completed RT for a timeout/interruption.
- `detection_mode`: `accessibility_and_poll`, `poll_only`, or `manual`.
- `max_poll_gap_s`: largest actual polling gap during the timed attempt.
- `aux_incorrect_pages`: JSON list of wrong titles observed, including a return
  to Study Start. Notifications may coalesce and samples may miss activations.
- `auto_detection_elapsed_s`: time to automatic title detection.
- `manual_ack_elapsed_s`: time to the facilitator's completion acknowledgment.
  This includes facilitator reaction delay and is not final retrieval time.
- `prompt_exposed`, `timed_started`: separate flags; an interrupted prompt can
  be exposed even before the timed interval starts.
- `verification_required`: legacy flag, always true in `trials_aux.csv`; not used for analysis.
- `status`, `reason`, `phase`, `event`, `detail`: controller state/outcome and
  interruption/context markers. Consult the controller README for its statuses.

## Final outcomes (`main_data.csv`)

`main_data.csv` is the analysis table: one row per exposed trial, written by the controller when
the trial ends. All measures are software observations of the active Chrome window's title,
sampled every 0.05 s with accessibility notifications as a backup. Video is not coded.

- `controller_status`: `completed_auto`, `completed_manual`, `timeout` or `interrupted`.
- `measurement_source`: `controller_poll_only` or `controller_accessibility_and_poll`.
- `retrieval_time_s`: seconds from the controller's reveal command to the first observed title equal
  to the target. Filled only for `completed_auto`; blank for timeouts, interruptions and manual
  completion.
- `total_tab_switches`: observed title changes in the timed interval, including the final correct one
  and any return to Study Start. Blank if title detection was disabled.
- `incorrect_selections`: observed title changes to any page other than the target (Study Start
  included).
- `first_selection_correct`: true if the first observed title change was the target, false if it was
  not; blank if none was observed.
- `no_selection`: true for a timeout with zero observed title changes; false for a completed trial or
  a timeout with at least one; blank for an interruption or when detection was disabled.
- `technical_loss`: true for an interruption not started by a person (window or focus change,
  input-lock loss, audio failure, mask or click-tap failure, controller reload); false otherwise.
  Interruptions started by a person (participant break/pause, facilitator pause, invalidate, end
  session, Esc) are not technical loss.
- `notes`: free text, blank from the controller.

For a completed trial `total_tab_switches = incorrect_selections + 1`. Timeouts have no completed
retrieval time. Manual completion (`.`) records no retrieval time, because the controller cannot
establish the endpoint.

Limitations: `retrieval_time_s` starts at the reveal command, not the first visible frame, and ends at
the sample or notification that first shows the target title, so it can differ from the true time by
about one sampling interval. A very brief activation between samples could be missed, and
re-selecting the already active tab is not a title change and is not counted. `POLL_GAP` events in
`events.csv` and `max_poll_gap_s` in `trials_aux.csv` show where sampling was late, and the
`MOUSE_INPUT_TRACE` events can be used to cross-check selection counts.

## Linking surveys

NASA-TLX is collected through separate Google Forms; the controller does not collect or score it.
Join the block ratings to `main_data.csv` by participant code AND condition (for example `H-L`),
never by block order or row order. Keep test and pilot data separate from main results.

## Integrity behavior

Run directories must be new. Each append validates the exact CSV header and
preserves zeros, booleans and proper quoting. Duplicate terminal trial identities,
missing required identity values, malformed JSON/CSV headers and write failures
stop storage and are returned to the controller. Existing blank P001 files from
the original ZIP are not reused.

JSON writes use a temporary file and rename. On platforms that cannot replace an
existing destination through rename, the prior JSON is retained under a unique
`.previous-*` name before replacement. A failed replacement attempts to restore
the prior file; old data are not silently deleted. These files are administrative
snapshots, not additional participant observations.

## Automatic progression and synced materials (controller 2.1.0)

`AUTO_NEXT_TRIAL_SCHEDULED` and `AUTO_TRIAL_START_REQUESTED` are auxiliary events. A block-level all-tabs-visible approval is not a new manual preflight for each trial. `checkpoint.json` records `auto_block_approval` and `auto_next_pending`; these do not authorize automatic resume after a crash/reload. Configured continuation includes ordinary timeouts, which still have no completed retrieval time.

Session provenance includes the current delivered recording hashes and a materials-definition fingerprint. The earlier source-manifest hash identifies its historical input, not a claim that all synced title edits match the old HTML. Trial identity retains the canonical target title; `observed_title` preserves the actual label detected. Only explicitly listed legacy aliases for that same target are accepted. Use a consistent title version during the main study. Study Start is LAST under the synced controller contract.

## Mouse transition diagnostics (controller 2.2.1)

The configured trial deadline is 20 seconds from the controller's reveal command. New events named `MOUSE_INPUT_TRACE` contain a bounded JSON `detail` object with button-event names, monotonic receipt times, native timestamps, pointer coordinates, click counts, window-under-pointer IDs and routing decisions: `pass`, `blocked`, or `pass_existing_release`. The capture is buffered in memory and written outside the timed interval to avoid per-click disk delay; a crash can lose an unflushed buffer. It does not count clicks as selections or guarantee every OS event was captured. `mouseClickDiagnostics=false` disables logging, not release-pair protection.

The minimum outcome display hold remains 0.30 seconds. If every button is physically up for `unobservedReleaseSettleSeconds` (0.15 s) after the hold but the gate never saw the release (it reached Chrome while the outcome was being stored), the controller logs `MOUSE_RELEASE_UNOBSERVED` and continues normally (controller 2.3.1). If a click is still held/queued, reset waits for its release up to a further two seconds, outside RT. The existing completed row remains valid if this later wait causes a pause; no second terminal row or replay is created. A held button before reveal produces an interruption with no started timing interval.
