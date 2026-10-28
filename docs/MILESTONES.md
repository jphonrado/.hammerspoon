# Milestone implementation record

Updated 29 October 2026. Original issue numbers are 2 (measurement), 3 (controller) and 4 (session/allocation).

| Milestone | Implementation/local verification | Native Mac verification |
|---|---|---|
| 2A | Implemented: fresh checked records, preserved zero/missing distinctions, auxiliary versus video fields, boot-relative elapsed clock, visible failure handling | Actual destination/permissions to check |
| 2B | Implemented: coding worksheet, dummy examples, OBS procedure, fixed post-outcome display hold | NOT RUN: saved overlay/pointer/audio/target-frame evidence |
| 3A | Implemented: verified neutral baseline before input release, selected window/frame checks, dimension-aware masks, locked masked phases and explicit Setup | NOT RUN: native Chrome, Accessibility, input hooks, masks and manual viewport checks |
| 3B | Implemented: exposure-aware outcomes, no silent replay, facilitator pacing, guarded callbacks, shutdown cleanup and explicit block transition | NOT RUN: actual audio failure/break/emergency behavior |
| 4A | Implemented: required session entry, roster group, unique run, active/completed guards and no automatic resume | NOT RUN: actual Mac dialogs/reload/storage behavior |
| 4B | Implemented: frozen 16-slot roster, practice balance, preparation sheet and complete 24-entry simulations across all four groups | NOT RUN: complete real-device dummy sessions and participant pilot |

## Local evidence

`LOCAL_CHECKS.json` records **10/10 Lua syntax checks** and **55 passing behavioral cases**:

- 12 pure lifecycle cases.
- 21 storage/material/allocation integration cases using real temporary files.
- 22 Mac-adapter/loader cases using simulated Hammerspoon APIs.

The adapter checks include all four groups' complete 24-entry flows, stale-mask rejection, session gates, no renewed lock after failed logging, interruption handling, completed-session guards, exception cleanup and shutdown-hook chaining. The separate model/storage integration also verifies each group and the 16-slot allocation. These are simulations, not participant observations or native-device validation.

The original ZIP and its 20 recordings are fingerprinted in `PROVENANCE.json`. The new operational package excludes the unusable original P001 logs. Example records are explicitly labeled simulated test data and contain no video-coded outcomes.

## Still required before main collection

Use `MAC_CHECKLIST.md` on the actual study Mac. The controller defaults to test/pilot use; main mode requires explicit configuration after that work. The spoken-Go versus mask-reveal documentation/audio conflict, separate practice materials and the paper's analysis/reporting work remain separate audit items. Completing software implementation does not mark those as resolved.
