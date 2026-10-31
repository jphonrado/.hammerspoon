# Orlando 20-second and single-click update

Based on implemented-hammerspoon at 44e1b48a62a53003ceae2a61db4e601a408359f4; local repaired commit 6161187. GitHub has not been updated by this session.

The complete revised source is in Orlando-Hammerspoon/. For an existing installation, the runtime changes are in study/config.lua and study/controller.lua. Preserve existing recordings, participant records, local recordingProfile values and mainStudyEnabled setting. Saved Hammerspoon calibration keys are unchanged.

The included patch passes git apply --check against the baseline above:

    git switch implemented-hammerspoon
    git apply --check /path/to/Orlando-20s-single-click.patch
    git apply /path/to/Orlando-20s-single-click.patch

If your local config differs (for example it already says 30 seconds), merge rather than overwrite it: set timeoutSeconds=20, version="2.2.1", add mouseReleaseWaitSeconds=2.0 and mouseClickDiagnostics=true, and use the revised controller.lua. Keep your measured recording/device profile. Reload Hammerspoon after installing. Never run old and new controllers simultaneously.

Read Orlando-Hammerspoon/docs/CLICK_FIX.md for the finding and Mac verification. Deadline is 20 seconds AFTER reveal, excluding audio. Single clicks should complete with their natural release; do not instruct participants to double-click as a workaround.

111 Lua behavioral cases + 15 Python encoding cases and 10 Lua syntax checks pass. The old release-swallowing behavior was reproduced in a simulation, not on the study Mac. A saved native Mac/Chrome/OBS test is still required to confirm the reported symptom is resolved.

NASA-TLX stays in Google Forms; titles, audio, target positions and opening mechanism are preserved. Historical delivery patch/readme files and legacy logs are omitted from this package to avoid confusion.
