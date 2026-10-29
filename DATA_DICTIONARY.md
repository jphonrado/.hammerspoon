# Measurement records and session guards

Schema version: **1.0**. Raw software observations are auxiliary. Final study
measurements come from the saved video and are entered separately.

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
- `trials_aux.csv`: one terminal auxiliary record per scheduled trial that was
  exposed. Counts and times are software observations requiring video review.
- `video_coding.csv`: identity/status rows plus **blank** final measurement
  columns. Enter the video-coded results here, preferably in a separately saved
  analysis copy while retaining the original generated records.

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

## Auxiliary events and outcomes

- `wall_epoch`: wall-clock seconds for matching records to sessions/recordings.
- `monotonic_s`: boot-relative seconds supplied by the controller.
- `elapsed_s`: auxiliary elapsed interval, never a rendered-frame guarantee.
- `observed_title`: title seen when the polling detector sampled the window.
- `aux_selection_count`, `aux_incorrect_count`, `aux_first_correct`: polling
  observations. A 0 remains 0; an unavailable value remains blank.
- `reveal_command_monotonic_s`: time the controller requested reveal, not proof
  of the first visible video frame.
- `auto_detection_elapsed_s`: time to automatic title detection.
- `manual_ack_elapsed_s`: time to the facilitator's completion acknowledgment.
  This includes facilitator reaction delay and is not final retrieval time.
- `prompt_exposed`, `timed_started`: separate flags; an interrupted prompt can
  be exposed even before the timed interval starts.
- `verification_required`: always true in `trials_aux.csv`.
- `status`, `reason`, `phase`, `event`, `detail`: controller state/outcome and
  interruption/context markers. Consult the controller README for its statuses.

## Video-coded outcomes

`video_status`, `video_file`, `video_start_frame`, `video_target_frame`,
`frame_rate`, `retrieval_time_s`, `total_tab_switches`, `incorrect_selections`,
`first_selection_correct`, `no_selection`, `technical_loss`, `coder`, and `notes`
are left blank by the controller. `controller_status` retains the auxiliary
outcome for comparison; it does not decide the final coded outcome.

Completed retrieval time uses the agreed visible onset and first target-active
frame. Timeouts have no completed retrieval-time value. A genuine no-selection
attempt is distinct from an unobservable selection caused by recording failure.
For a completed, verified trial, total switches = incorrect selections + 1.

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
