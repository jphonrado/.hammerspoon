# Encode navigation data and link the survey

The controller runs on the Mac without Python. The optional exporter below uses
Python 3.10+ with no extra packages. Keep coded participant IDs and preserve the
raw run. **NASA-TLX stays in Google Forms; this controller does not collect or
score it.** No questionnaire UI or survey response template is added here.

## What is captured

| Measure/context | Automatic output | Final source |
|---|---|---|
| Orientation, load, content set, block/trial order, target, repeat, original ordinal position, tab counts | Every trial CSV | Frozen plan; researcher checks actual native layout |
| Retrieval time | Software reveal/detection interval in main_data.csv and trials_aux.csv | First unmasked OBS frame to first correct target-active frame |
| First-selection correctness, incorrect selections, total switches | Observed title transitions, including return to neutral | OBS-coded selections; repeated active-tab clicks are not switches |
| Timeout/interruption | Explicit outcome/reason; completed RT stays blank | OBS distinguishes timeout after errors, no selection, break, and technical loss |
| NASA-TLX | Participant/condition keys for linking data | Separate Google Forms survey |
| Preference, comfort, recall or interview notes | No inferred response | Actual survey/interview instrument |

The controller does not prove native orientation, tab order/count, sidebar width,
audio wording, OBS recording, or every rapid activation. Accessibility
notifications are best effort; poll_only is an explicit fallback. Neither
provides video-frame precision. Continue the researcher's layout/recording checks.

## Make an analysis copy

Replace these example paths with the actual finished run and NEW output folders.
Run from the repository root. Do this after finishing the run so raw statuses are stable.

```bash
python3 tools/encode_session.py prepare records/pilot/PILOT001/SESSION_ID --out coding/PILOT001
```

This creates a video worksheet with every scheduled trial. Entries lacking a
terminal raw outcome are marked no_terminal_outcome: a crash can leave an
exposed trial without an outcome row. Review video/checkpoint/exposure events;
do not assume it was unexposed. Existing output folders are never overwritten.

Fill video_coding.csv in the coding folder:

- Leave identity columns unchanged. Set video_status to completed, timeout,
  interrupted, technical_loss, or not_exposed. Blank is uncoded.
- Supply video_file, coder, and explicit technical_loss=0/1 for coded exposed
  trials. A break may have technical_loss=0; interruption does not imply loss.
- For completion, enter the first unmasked frame, first correct target frame,
  actual frame rate, total switches, incorrect switches, first-selection
  correctness, and no_selection=0. RT is (target-start)/fps. Use a constant
  frame rate and consistent frame indexing. Typed RTs disagreeing by more than
  one frame are rejected; the frame-derived value is exported.
- For timeout, leave completed RT and target frame blank. Code observable
  selections. no_selection=1 requires zero switches/errors and blank first
  correctness. A timeout after errors has no_selection=0, incorrect first
  selection, and equal total/incorrect switches.
- Missing/unobservable selections stay missing. Mark technical loss when the
  recording cannot support the needed observations, and explain it in notes.

## Export

```bash
python3 tools/encode_session.py export records/pilot/PILOT001/SESSION_ID --coding coding/PILOT001 --out analysis/PILOT001
```

- analysis_trials.csv: all scheduled identities and OBS-coded values, with
  controller status, source, and review flag. No estimate fills missing coding.
- condition_summary.csv: completed-trial mean RT with n; first-selection error
  rate with n; separately named activation error rate; selection/timeout counts.
- survey_join_keys.csv: one row per condition with participant code, condition,
  session, block, orientation, load, and content set for linking Google Forms.

**First-selection error rate** is incorrect first selections divided by
observable first selections; no-selection trials do not enter that denominator.
**Observed selection error rate** pools incorrect/total activations and is a
different descriptive measure. Use the measure prespecified in the paper.
Completed RT excludes timeouts. Interrupted/technical-loss rows remain available
but are excluded from these descriptive summaries. Repeat trials are included
and flagged; no new exclusion is imposed.

## Join Google Forms separately

Use **participant code AND condition** to match a condition summary to its TLX
response. Block number is presentation order and is not interchangeable with
condition, since orders are counterbalanced. The canonical condition codes are:

| Code | Orientation | Load |
|---|---|---|
| H-L | Horizontal | Low |
| H-H | Horizontal | High |
| V-L | Vertical | Low |
| V-H | Vertical | High |

Map the actual Forms labels to these codes explicitly when combining results;
this tool does not guess survey question names or rewrite the form. Keep pilot,
test and main records distinct. Check for missing/duplicate responses before a
join. If a single Forms response has four condition-specific sets of items,
reshape it to one participant/condition row before joining. Participant-wide
weighting items remain participant-wide under the paper's existing protocol.

Two coders can prepare distinct folders and reconcile their OBS coding under the
paper's checking procedure. This exporter does not calculate inter-rater
reliability or infer the correct answer when coders disagree.
