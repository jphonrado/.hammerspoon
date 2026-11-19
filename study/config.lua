-- Researcher settings. No Python or browser extension is required.
return {
  version = "2.3.1",
  chromeAppName = "Google Chrome",
  neutralTitle = "Study Start",
  postPromptDelaySeconds = 0.40,
  timeoutSeconds = 20,
  mouseReleaseWaitSeconds = 2.0, -- After outcome only; never added to retrieval time.
  unobservedReleaseSettleSeconds = 0.15, -- Buttons physically up this long after the hold = release already delivered.
  mouseClickDiagnostics = true, -- Buffer button events; write outside the timed interval.
  pollIntervalSeconds = 0.05,
  pollGapWarningSeconds = 0.20, -- Log POLL_GAP when a title sample is this late (a very brief selection could be missed).
  accessibilityNotifications = true, -- Best effort, with title polling as backup.
  neutralWaitSeconds = 2.0,
  activationWaitSeconds = 2.0, -- Before exposure only: wait for Chrome to become the active app after Hammerspoon dialogs.
  windowTolerancePixels = 3,
  outcomeHoldSeconds = 0.30, -- Provisional: confirm in the pilot that the correct page is visible during the hold.
  autoDetectTarget = true, -- Title polling is the source of the final measures; keep true for the main study.
  autoAdvance = true, -- Approved all-tabs-visible blocks continue automatically.
  interTrialDelaySeconds = 3.0, -- Masked pause before the next scheduled prompt.
  autoAdvanceAfterTimeout = true, -- Ordinary timeouts continue; interruptions never do.
  lockWatchdogSeconds = 120, -- A release stops/interrupts; it never silently continues.
  mainStudyEnabled = true,
  maskColor = {red=0.52,green=0.52,blue=0.52,alpha=1},
  settingsPrefix = "hci2000_v2_",
  modifiers = {"ctrl","alt","cmd"},
  -- Only relevant if an optional OBS backup recording is made; it is not coded.
  recordingProfile = {
    macOSVersion = "Tahoe 26.6.2",
    hammerspoonVersion = "UNVERIFIED",
    obsVersion = "UNVERIFIED",
    captureMode = "UNVERIFIED: must include separate Hammerspoon mask",
    resolution = "UNVERIFIED",
    frameRate = "UNVERIFIED",
    audioCapture = "UNVERIFIED",
    chromeVersion = "UNVERIFIED",
    displayScaling = "UNVERIFIED",
    pageZoom = "UNVERIFIED",
    verticalPanelWidth = "UNVERIFIED",
    mouseSettings = "logitech G304 1600 DPI",
  },
}
