# Milestone implementation record

Updated 29 October 2026. Original issue numbers are 2 (measurement), 3 (controller) and 4 (session/allocation).

| Milestone | Implementation/local verification | Native Mac verification |
|---|---|---|
| 2A | Implemented: fresh checked records, preserved zero/missing distinctions, auxiliary versus video fields, boot-relative elapsed clock, visible failure handling | Actual destination/permissions to check |
| 2B | Implemented: coding worksheet, dummy examples, OBS procedure, fixed post-outcome display hold | NOT RUN: saved overlay/pointer/audio/target-frame evidence |
| 3A | Implemented: verified neutral baseline before input release, selected window/frame checks, dimension-aware masks, locked masked phases and explicit Setup | NOT RUN: native Chrome, Accessibility, input hooks, masks and manual viewport checks |
| 3B | Implemented: exposure-aware outcomes, no silent replay, guarded automatic within-block progression, approved visible-tab layout and manual overflow fallback, guarded callbacks, shutdown cleanup and explicit block transition | NOT RUN: actual audio failure/break/emergency behavior |
| 4A | Implemented: required session entry, roster group, unique run, active/completed guards and no automatic resume | NOT RUN: actual Mac dialogs/reload/storage behavior |
| 4B | Implemented: frozen 16-slot roster, practice balance, preparation sheet and complete 24-entry simulations across all four groups | NOT RUN: complete real-device dummy sessions and participant pilot |

## Local evidence

`LOCAL_CHECKS.json` records **10/10 Lua syntax checks** and **96 passing Lua behavioral cases** plus **15 Python encoding tests**:

- 12 pure lifecycle cases.
- 24 storage/material/allocation integration cases using real temporary files.
- 60 Mac-adapter/loader cases using simulated Hammerspoon APIs.

The adapter checks include all four groups' complete 24-entry flows, stale-mask rejection, session gates, no renewed lock after failed logging, interruption handling, completed-session guards, exception cleanup and shutdown-hook chaining. The separate model/storage integration also verifies each group and the 16-slot allocation. These are simulations, not participant observations or native-device validation.

The original ZIP/audio provenance and current synced recordings are distinguished in `PROVENANCE.json`. Nine group-replaced recordings are preserved, and exact legacy title aliases are documented in `TITLE_COMPATIBILITY.json`. Neutral-LAST focus tests from the synced commit are retained. The new operational package excludes the unusable original P001 logs. Example records are explicitly labeled simulated test data and contain no video-coded outcomes.

## Still required before main collection

Use `MAC_CHECKLIST.md` on the actual study Mac. The controller defaults to test/pilot use; main mode requires explicit configuration after that work. The spoken-Go versus mask-reveal documentation/audio conflict, separate practice materials and the paper's analysis/reporting work remain separate audit items. Completing software implementation does not mark those as resolved.

## Automation restoration after synced group edits

Version2.1.0 restores three-second automatic progression after normal completions/timeouts within an all-tabs-visible approved block. It retains recording hold, logs, verified neutral/pointer/frame reset, interruption/no-replay guards and manual condition boundaries. The original facilitator-paced behavior remains configurable and is used for scrolling layouts. This local record does not certify native playback/visibility; the updated Mac checklist remains NOT RUN.

## Orlando audit, version 2.2.0

Audited implemented-hammerspoon at ed02f4b. Fixed timeout/interruption classification, reveal/endpoint disk-latency contamination, unavailable-count handling, and added optional accessibility observations with polling fallback. Added repeat/position/count metadata and a checked OBS encoding/export tool. NASA-TLX remains in Google Forms; only participant/condition join keys are exported. See ORLANDO_AUDIT_2026-10-29.md and ENCODING.md. Native Mac verification remains NOT RUN.
