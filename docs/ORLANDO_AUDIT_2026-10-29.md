# Orlando implementation audit — 29 October 2026

Audited baseline: `jphonrado/.hammerspoon`, **implemented-hammerspoon**,
`ed02f4bbd947162a1e5088843a48226a865a018c`. This review supersedes findings from
the older `main` branch; that branch was not used as the repair base.

## What the implementation branch already did

Automatic exact-title completion, wrong-title tracking, neutral-LAST reset,
pointer reset/lock, prerecorded playback, mask disappearance as start cue,
timeout handling, a 0.30-second endpoint display hold, and three-second automatic
within-block continuation were present. It also already separated manual
acknowledgment from software detection, used a monotonic clock, preserved
exposures across failures, and wrote run-specific files with restart guards.
The original positions, paper assignments and target identities are retained.

The implementation therefore did **not** have all its automation removed.
Some earlier revisions intentionally used manual progression; the audited branch
restored/configured progression with `autoAdvance=true`. No extension is added.

## Confirmed gaps repaired

1. Every timeout was written as `no_selection=true`, including timeouts with
   observed incorrect selections. That field now remains unknown until coding;
   observed counts, including incomplete-trial counts, are preserved.
2. Every interruption was written as `technical_loss=true`, although a voluntary
   break need not lose data. Classification now belongs to the recording check.
3. Reveal time was captured before checkpoint/event writes preceding mask
   removal, making disk latency part of estimated RT. Removal is now bracketed
   before those writes. Video still determines the actual visible onset.
4. The automatic endpoint was recomputed after writing the observed-transition
   event. It is now captured before event/storage latency and reused consistently.
5. Detection-disabled trials could retain zero-valued unavailable observations.
   Such counts stay blank, while genuine observed 0/false values are preserved.
6. Polling alone could miss transitions between 50-ms samples. A best-effort
   window-title accessibility observer now supplements polling. Detector mode,
   actual maximum sample gap, observed source and wrong-page list are recorded.
   Notifications can coalesce and polling can miss events: OBS remains primary.
7. Trial outputs lacked repeat/position/count columns. They now include the
   original task position, repeat flag, and 5/15 task and 6/16 visible counts.
8. Final encoding lacked a checked export path. A standard-library exporter now
   validates OBS coding, preserves missing data, and produces trial/condition
   tables and participant/condition survey join keys. **NASA-TLX stays in the
   separate Google Forms survey**; it is neither collected nor scored here.

## Remaining native or researcher work

Run the Mac checklist using the patched package. Confirm actual audio wording
(`Target: <exact title>.`, no spoken Go), mask visibility in OBS, all-tabs-visible
geometry, neutral-LAST, pointer, native permissions, and rapid-selection coding.
All title/audio files are preserved; no recording was transcribed or re-recorded
in this audit. Enter the measured sidebar width, recording FPS, device/browser
settings. Continue collecting questionnaire responses through Google Forms.
Review actual tab layout/order at setup;
the controller does not automatically certify it.

Keep original raw logs and recordings. `main_data.csv` remains an **unverified
automatic estimate sheet**; `analysis_trials.csv` from the encoding tool uses
OBS-coded values only. No-selection, technical loss and missing first selection
are distinct. NASA-TLX, preference and comfort cannot be inferred from clicks.

No paper was edited. Echo should eventually document the final validated
controller version, new fields, timing brackets/detection limits, neutral-LAST,
exact-title recordings, and the retained OBS coding procedure after piloting.
