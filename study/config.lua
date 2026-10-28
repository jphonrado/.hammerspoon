-- Researcher settings. No Python or browser extension is required.
return {
  version = "2.0.0",
  chromeAppName = "Google Chrome",
  neutralTitle = "Study Start",
  postPromptDelaySeconds = 0.40,
  timeoutSeconds = 60,
  pollIntervalSeconds = 0.05,
  neutralWaitSeconds = 2.0,
  windowTolerancePixels = 3,
  outcomeHoldSeconds = 0.30, -- Provisional: verify the correct page is visible in OBS.
  autoDetectTarget = true, -- Auxiliary title polling; final measures come from video.
  lockWatchdogSeconds = 120, -- A release stops/interrupts; it never silently continues.
  mainStudyEnabled = false, -- Enable only after completing docs/MAC_CHECKLIST.md.
  maskColor = {red=0.52,green=0.52,blue=0.52,alpha=1},
  settingsPrefix = "hci2000_v2_",
  modifiers = {"ctrl","alt","cmd"},
  recordingProfile = {
    macOSVersion = "UNVERIFIED",
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
    mouseSettings = "UNVERIFIED",
  },
}
