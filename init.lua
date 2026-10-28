-- Orlando HCI Trial Controller
-- Hammerspoon / Lua controller for browser-tab retrieval experiments.
--
-- PURPOSE
--   Hammerspoon handles the repeatable trial-state mechanics:
--   mask -> neutral tab -> mouse reset -> prerecorded target prompt
--   -> fixed delay -> mask disappears (START) -> timeout/logging.
--
-- IMPORTANT
--   1. Keep Chrome in a normal window, not macOS full-screen.
--   2. Keep the neutral tab as browser tab #1 for every condition.
--   3. Prepare tab orientation, tab count, vertical-panel width, and tab order
--      before starting a condition. This script deliberately does not change them.
--   4. OBS/video remains the authoritative source for retrieval-time coding.
--      The Lua timestamps are a secondary audit trail only.
--   5. Calibrate the study mouse point and Chrome window frame before testing.
--   6. Trials end automatically when Chrome's window title shows the target page
--      (CONFIG.autoDetectTarget). Ctrl+Alt+Cmd+. remains as a manual fallback.
--      Detection timestamps are polled (~50 ms), so OBS stays the authoritative timer.
--   7. Set SESSION.participant and SESSION.orderGroup (1-4) before each participant.
--      Condition order and content-set pairing follow Table 1 of the paper.

------------------------------------------------------------
-- 1. USER CONFIGURATION
------------------------------------------------------------

local CONFIG = {
    chromeAppName = "Google Chrome",

    -- Neutral tab is permanently the first browser tab.
    neutralTabIndex = 1,

    -- Delay after the prerecorded prompt finishes and before the mask disappears.
    -- Pilot this value. The disappearance itself is the participant's start cue.
    postPromptDelaySeconds = 0.40,

    -- Automatic maximum trial duration after reveal.
    timeoutSeconds = 60.0,

    -- Small setup pause after Chrome/tab/cursor reset before prompt playback.
    setupSettleSeconds = 0.20,

    -- Automatic target detection. While a trial is RUNNING, the script polls
    -- Chrome's window title (which contains the active tab's page title).
    -- When the title contains the target's title, the trial ends automatically.
    -- Every other title change is logged as an incorrect selection.
    -- The Ctrl+Alt+Cmd+. hotkey still works as a manual fallback.
    autoDetectTarget = true,
    pollIntervalSeconds = 0.05,

    -- Auto-advance: after a trial ends (target found, facilitator OK, or timeout),
    -- the next trial starts by itself after this pause. The first trial of each
    -- condition is still started with Ctrl+Alt+Cmd+Return, and auto-advance stops
    -- at the end of a condition. Pressing Ctrl+Alt+Cmd+Return during the pause
    -- starts the next trial immediately. Invalid trials never auto-advance.
    autoAdvance = true,
    interTrialDelaySeconds = 3.0,

    -- Event log detail. false = hide routine housekeeping rows (tab resets, mouse
    -- resets, mask-hide command) from the CSV; they still print to the console.
    verboseLog = false,

    -- Where prerecorded target prompts are stored.
    audioDirectory = hs.configdir .. "/orlando_audio",

    -- CSV logs are stored here.
    logDirectory = hs.configdir .. "/orlando_logs",

    -- Neutral mask appearance. RGB values are 0..1.
    maskColor = { red = 0.52, green = 0.52, blue = 0.52, alpha = 1.0 },

    -- Mask geometry is RELATIVE TO THE CHROME WINDOW FRAME.
    -- These are fallback starter values only. Calibrated masks saved with
    -- Ctrl+Alt+Cmd+H (horizontal) and Ctrl+Alt+Cmd+V (vertical) override them.
    -- The correct mask (H or V) is chosen automatically from the current condition.
    -- H: covers a top strip containing horizontal tabs.
    -- V: covers a left strip containing the vertical-tab panel.
    mask = {
        H = {
            xOffset = 0,
            yOffset = 0,
            rightInset = 0,
            height = 58,
        },
        V = {
            xOffset = 0,
            yOffset = 0,
            width = 280,
            bottomInset = 0,
        },
    },

    -- If a calibrated Chrome frame exists, restore it before every trial.
    restoreChromeWindowFrame = true,

    -- Keep false during real sessions so no Hammerspoon alerts appear in OBS.
    -- Turn true only during dry runs/calibration if useful.
    researcherAlerts = false,
}

------------------------------------------------------------
-- 1b. CONTENT SETS, TARGETS, AND COUNTERBALANCING (from the paper)
------------------------------------------------------------
-- Audio files are named <Set>_<TargetID>.m4a, e.g. A_P1.m4a.
-- Prompt wording (recorded externally), e.g. "Find the page about Basketball."
-- Whether the audio ends with a spoken "Go" depends on your final design:
--   * Mask design (this script): record WITHOUT "Go"; the mask disappearing is the cue.
--   * Paper design (no mask): record WITH "Go".
-- targetTitle is only used in the CSV log.

local SETS = {
    A = { -- Sports
        titles = {
            P1 = "Basketball Passing and Scoring",
            P2 = "Swimming Strokes and Relays",
            P3 = "Track Cycling Race Formats",
            P4 = "Field Hockey Scoring Rules",
            P5 = "Wrestling Grips and Scoring",
        },
        sequence = { "P1", "P2", "P1", "P3", "P4", "P5" },
    },
    B = { -- Animals
        titles = {
            P1 = "Red Panda Forest Life",
            P2 = "Fennec Fox Desert Adaptations",
            P3 = "Giant Panda Bamboo Diet",
            P4 = "Polar Bear Hunting From Ice",
            P5 = "Snow Leopard Mountain Adaptations",
        },
        sequence = { "P2", "P3", "P4", "P2", "P5", "P1" },
    },
    C = { -- Nature
        titles = {
            P1 = "Waterfalls Shape Rocky Landscapes",
            P2 = "Volcanoes Lava and Landforms",
            P3 = "Coral Reefs Support Marine Life",
            P4 = "Mangroves Stabilize Coastal Sediment",
            P5 = "Mountains Formation and Erosion",
        },
        sequence = { "P3", "P4", "P5", "P1", "P3", "P2" },
    },
    D = { -- Science
        titles = {
            P1 = "Gravity Mass and Attraction",
            P2 = "Light Waves and Visible Colors",
            P3 = "Planets Orbits and Composition",
            P4 = "Mirrors Reflect Light",
            P5 = "Optical Lenses Redirect Light",
        },
        sequence = { "P4", "P5", "P1", "P2", "P3", "P4" },
    },
}

-- Table 1: condition name + content set, in presentation order.
local ORDERS = {
    [1] = { {"H-L","A"}, {"H-H","B"}, {"V-L","C"}, {"V-H","D"} },
    [2] = { {"H-H","C"}, {"H-L","D"}, {"V-H","A"}, {"V-L","B"} },
    [3] = { {"V-L","D"}, {"V-H","C"}, {"H-L","B"}, {"H-H","A"} },
    [4] = { {"V-H","B"}, {"V-L","A"}, {"H-H","D"}, {"H-L","C"} },
}

local function buildConditions(group)
    local order = ORDERS[group]
    assert(order, "SESSION.orderGroup must be 1, 2, 3, or 4")
    local conditions = {}
    for _, entry in ipairs(order) do
        local name, setKey = entry[1], entry[2]
        local set = SETS[setKey]
        local trials = {}
        for i, pid in ipairs(set.sequence) do
            trials[i] = {
                id = "T" .. i,
                targetID = pid,
                targetTitle = set.titles[pid],
                audio = setKey .. "_" .. pid .. ".m4a",
            }
        end
        conditions[#conditions + 1] = {
            name = name,
            contentSet = setKey,
            orientation = name:sub(1, 1), -- "H" or "V"
            trials = trials,
        }
    end
    return conditions
end

-- Edit this before each participant.
local SESSION = {
    participant = "P001",
    orderGroup = 3, -- 1-4, from your allocation schedule
}
SESSION.conditions = buildConditions(SESSION.orderGroup)

------------------------------------------------------------
-- 2. INTERNAL STATE
------------------------------------------------------------

local state = {
    conditionIndex = 1,
    trialIndex = 1,
    phase = "IDLE", -- IDLE, PREPARING, PROMPT, POST_PROMPT, RUNNING, CONDITION_COMPLETE, SESSION_COMPLETE
    maskCanvas = nil,
    maskOrientation = nil,
    activeSound = nil,
    setupTimer = nil,
    delayTimer = nil,
    timeoutTimer = nil,
    pollTimer = nil,
    nextTrialTimer = nil,
    lastTitle = nil,
    selectionCount = 0,
    trialRec = nil,
    revealEpoch = nil,
}

local SETTINGS_MOUSE_KEY = "orlandoMouseStart"
local SETTINGS_WINDOW_KEY = "orlandoChromeFrame"

------------------------------------------------------------
-- 3. SMALL UTILITIES
------------------------------------------------------------

local function researcherAlert(message)
    if CONFIG.researcherAlerts and state.phase ~= "RUNNING" then
        hs.alert.show(message, 1.0)
    end
end

local function currentCondition()
    return SESSION.conditions[state.conditionIndex]
end

local function currentTrial()
    local c = currentCondition()
    if not c then return nil end
    return c.trials[state.trialIndex]
end

local function csvEscape(value)
    local s = tostring(value or "")
    if s:find('[,\n\r"]') then
        s = '"' .. s:gsub('"', '""') .. '"'
    end
    return s
end

local function ensureDirectory(path)
    local attr = hs.fs.attributes(path)
    if attr and attr.mode == "directory" then return true end
    local ok, err = hs.fs.mkdir(path)
    if not ok then
        print("[Orlando] Could not create directory: " .. path .. " | " .. tostring(err))
        return false
    end
    return true
end

local function eventsPath()
    ensureDirectory(CONFIG.logDirectory)
    return string.format("%s/%s_events.csv", CONFIG.logDirectory, SESSION.participant)
end

local function trialsPath()
    ensureDirectory(CONFIG.logDirectory)
    return string.format("%s/%s_trials.csv", CONFIG.logDirectory, SESSION.participant)
end

-- "2026-10-28 15:12:05.425" (millisecond precision, local time)
local function timestampString(epoch)
    return os.date("%Y-%m-%d %H:%M:%S", math.floor(epoch))
        .. string.format(".%03d", math.floor((epoch % 1) * 1000))
end

local function appendCsv(path, header, values)
    local exists = hs.fs.attributes(path) ~= nil
    local f, err = io.open(path, "a")
    if not f then
        print("[Orlando] LOG ERROR: " .. tostring(err))
        return false
    end
    if not exists then f:write(header .. "\n") end
    local out = {}
    for i = 1, #values do out[i] = csvEscape(values[i]) end
    f:write(table.concat(out, ",") .. "\n")
    f:close()
    return true
end

local function conditionMeta(condition)
    if not condition then return "", "" end
    local orient = (condition.orientation == "H") and "horizontal" or "vertical"
    local load = (condition.name:sub(3, 3) == "L") and "low" or "high"
    return orient, load
end

-- Page name without Chrome's " - Google Chrome - <profile>" suffix.
local function cleanPageTitle(title)
    return (tostring(title):gsub("%s%-%sGoogle Chrome.*$", ""))
end

-- EVENTS FILE: one row per event, parsed into columns (<participant>_events.csv).
local EVENT_HEADER = "local_time,epoch_s,participant,order_group,condition,orientation,tab_load,content_set,trial,target_id,target_title,phase,event,selection_number,elapsed_s,first_selection,window_title,detail"

local QUIET_EVENTS = {
    NEUTRAL_TAB_RESET = true,
    NEUTRAL_TAB_FALLBACK = true,
    MOUSE_RESET = true,
    REVEAL_COMMAND = true,
}

local function logEvent(eventName, detail, fields)
    fields = fields or {}
    local condition = currentCondition()
    local trial = currentTrial()
    local now = hs.timer.secondsSinceEpoch()

    print("[Orlando] " .. eventName .. (detail and (" | " .. detail) or ""))
    if QUIET_EVENTS[eventName] and not CONFIG.verboseLog then return end

    local orient, load = conditionMeta(condition)
    appendCsv(eventsPath(), EVENT_HEADER, {
        timestampString(now),
        string.format("%.6f", now),
        SESSION.participant,
        SESSION.orderGroup,
        condition and condition.name or "",
        orient,
        load,
        condition and condition.contentSet or "",
        trial and trial.id or "",
        trial and trial.targetID or "",
        trial and trial.targetTitle or "",
        state.phase,
        eventName,
        fields.selection_number or "",
        fields.elapsed_s and string.format("%.3f", fields.elapsed_s) or "",
        fields.first_selection or "",
        fields.window_title or "",
        detail or "",
    })
end

-- TRIALS FILE: one row per scored trial attempt (<participant>_trials.csv).
-- retrieval_time_s = mask drops -> correct tab active. obs_retrieval_time_s and notes are for manual video checks.
local TRIAL_HEADER = "participant,order_group,condition,orientation,tab_load,content_set,trial,attempt,target_id,target_title,status,retrieval_time_s,total_tab_switches,incorrect_selections,first_selection_correct,incorrect_pages,mask_drop_time,obs_retrieval_time_s,notes"

local attemptCounts = {}

-- Called when a trial is revealed (timing starts).
local function newTrialRecord(revealEpoch)
    local key = state.conditionIndex .. ":" .. state.trialIndex
    attemptCounts[key] = (attemptCounts[key] or 0) + 1
    state.trialRec = {
        attempt = attemptCounts[key],
        revealEpoch = revealEpoch,
        nSelections = 0,
        nIncorrect = 0,
        firstCorrect = nil,   -- 1 / 0 once a first selection is seen
        incorrectPages = {},
    }
end

-- status: completed_auto, completed_manual, timeout, invalid, aborted
local function writeTrialRow(status, endEpoch, elapsed)
    local rec = state.trialRec
    local condition = currentCondition()
    local trial = currentTrial()
    if not rec or not condition or not trial then return end

    local orient, load = conditionMeta(condition)
    local tracked = CONFIG.autoDetectTarget -- selection counts only exist when detection ran
    local totalSwitches = tracked and rec.nSelections or ""
    local incorrect = tracked and rec.nIncorrect or ""
    local firstCorrect = (tracked and rec.firstCorrect ~= nil) and rec.firstCorrect or ""

    -- Retrieval time = mask drops -> correct tab becomes active.
    -- Only completed trials get a value; timeouts/aborted/invalid stay blank.
    local retrieval = ""
    if (status == "completed_auto" or status == "completed_manual") and elapsed then
        retrieval = string.format("%.3f", elapsed)
    end

    appendCsv(trialsPath(), TRIAL_HEADER, {
        SESSION.participant,
        SESSION.orderGroup,
        condition.name,
        orient,
        load,
        condition.contentSet,
        trial.id,
        rec.attempt,
        trial.targetID,
        trial.targetTitle,
        status,
        retrieval,
        totalSwitches,
        incorrect,
        firstCorrect,
        table.concat(rec.incorrectPages, "; "),
        timestampString(rec.revealEpoch),
        "", "",
    })
    state.trialRec = nil
end

-- If a trial is in progress when the facilitator aborts/unmasks, keep a row for it.
local function recordAbortIfRunning()
    if state.phase == "RUNNING" and state.trialRec then
        local now = hs.timer.secondsSinceEpoch()
        writeTrialRow("aborted", now, state.revealEpoch and (now - state.revealEpoch) or nil)
    end
end

local function stopTimer(timerName)
    if state[timerName] then
        state[timerName]:stop()
        state[timerName] = nil
    end
end

local function stopAllTimers()
    stopTimer("setupTimer")
    stopTimer("delayTimer")
    stopTimer("timeoutTimer")
    stopTimer("pollTimer")
    stopTimer("nextTrialTimer")
end

local function stopSound()
    if state.activeSound then
        local snd = state.activeSound
        state.activeSound = nil
        pcall(function()
            snd:setCallback(nil)
            snd:stop()
        end)
    end
end

------------------------------------------------------------
-- 4. CHROME / WINDOW CONTROL
------------------------------------------------------------

local function getChrome()
    return hs.application.get(CONFIG.chromeAppName)
end

local function getChromeWindow()
    local app = getChrome()
    if not app then return nil, "Google Chrome is not running." end

    local win = app:mainWindow()
    if not win then
        local wins = app:visibleWindows()
        win = wins and wins[1] or nil
    end
    if not win then return nil, "No visible Chrome window was found." end
    return win, nil
end

local function captureChromeWindowFrame()
    if state.phase == "RUNNING" then return end
    local win, err = getChromeWindow()
    if not win then researcherAlert(err); return end
    local f = win:frame()
    local saved = { x = f.x, y = f.y, w = f.w, h = f.h }
    hs.settings.set(SETTINGS_WINDOW_KEY, saved)
    researcherAlert("Orlando: Chrome frame saved")
    print("[Orlando] Saved Chrome frame: " .. hs.inspect(saved))
end

local function restoreChromeWindowFrame(win)
    if not CONFIG.restoreChromeWindowFrame then return end
    local saved = hs.settings.get(SETTINGS_WINDOW_KEY)
    if saved and saved.x and saved.y and saved.w and saved.h then
        win:setFrame({ x = saved.x, y = saved.y, w = saved.w, h = saved.h }, 0)
    end
end

local function resetNeutralTab(win, app)
    -- Hammerspoon supports focusTab() for Chrome. If Accessibility exposes the
    -- tab group poorly on a particular Chrome build, fall back to Cmd+1.
    local ok = false
    local success, result = pcall(function()
        return win:focusTab(CONFIG.neutralTabIndex)
    end)
    if success and result == true then ok = true end

    if not ok then
        app:activate(false)
        win:focus()
        hs.eventtap.keyStroke({"cmd"}, tostring(CONFIG.neutralTabIndex), 0, app)
        logEvent("NEUTRAL_TAB_FALLBACK", "Used Cmd+" .. tostring(CONFIG.neutralTabIndex))
    else
        logEvent("NEUTRAL_TAB_RESET", "focusTab(" .. tostring(CONFIG.neutralTabIndex) .. ")")
    end
end

------------------------------------------------------------
-- 5. MOUSE CALIBRATION / RESET
------------------------------------------------------------

local function captureMouseStart()
    if state.phase == "RUNNING" then return end
    local p = hs.mouse.absolutePosition()
    local saved = { x = p.x, y = p.y }
    hs.settings.set(SETTINGS_MOUSE_KEY, saved)
    researcherAlert(string.format("Mouse start saved: %.0f, %.0f", p.x, p.y))
    print("[Orlando] Saved mouse start: " .. hs.inspect(saved))
end

local function resetMouse()
    local p = hs.settings.get(SETTINGS_MOUSE_KEY)
    if not p or not p.x or not p.y then
        return false, "No calibrated mouse starting point. Use the calibration hotkey first."
    end
    hs.mouse.absolutePosition({ x = p.x, y = p.y })
    logEvent("MOUSE_RESET", string.format("x=%.1f;y=%.1f", p.x, p.y))
    return true, nil
end

------------------------------------------------------------
-- 6. TAB-REGION MASK
------------------------------------------------------------

local function deleteMask()
    if state.maskCanvas then
        state.maskCanvas:delete(0)
        state.maskCanvas = nil
        state.maskOrientation = nil
    end
end

-- Calibrated mask (saved in Hammerspoon settings) wins over CONFIG defaults.
local function getMaskSpec(orientation)
    local saved = hs.settings.get("orlandoMask_" .. orientation)
    if type(saved) == "table" then return saved end
    return CONFIG.mask[orientation]
end

local function computeMaskFrame(orientation, chromeFrame)
    local m = getMaskSpec(orientation)
    if not m then return nil end

    if orientation == "H" then
        local x = chromeFrame.x + (m.xOffset or 0)
        local y = chromeFrame.y + (m.yOffset or 0)
        local w = chromeFrame.w - (m.xOffset or 0) - (m.rightInset or 0)
        local h = m.height
        return { x = x, y = y, w = w, h = h }
    end

    if orientation == "V" then
        local x = chromeFrame.x + (m.xOffset or 0)
        local y = chromeFrame.y + (m.yOffset or 0)
        local w = m.width
        local h = chromeFrame.h - (m.yOffset or 0) - (m.bottomInset or 0)
        return { x = x, y = y, w = w, h = h }
    end

    return nil
end

local function showMask()
    local condition = currentCondition()
    if not condition then return false, "No current condition." end

    local win, err = getChromeWindow()
    if not win then return false, err end
    local frame = computeMaskFrame(condition.orientation, win:frame())
    if not frame then return false, "Could not compute mask frame." end

    -- Reuse an already-visible mask when possible. This prevents a tiny
    -- delete/recreate flash between trials. If orientation changes, rebuild it.
    if state.maskCanvas and state.maskOrientation == condition.orientation then
        state.maskCanvas:frame(frame)
        state.maskCanvas:show(0)
        state.maskCanvas:bringToFront(true)
        return true, nil
    end

    deleteMask()

    state.maskCanvas = hs.canvas.new(frame)
    state.maskCanvas:appendElements({
        type = "rectangle",
        action = "fill",
        fillColor = CONFIG.maskColor,
        frame = { x = "0%", y = "0%", w = "100%", h = "100%" },
    })
    state.maskOrientation = condition.orientation
    state.maskCanvas:clickActivating(false)
    state.maskCanvas:show(0)
    state.maskCanvas:bringToFront(true)
    return true, nil
end

local function hideMask()
    if state.maskCanvas then
        state.maskCanvas:hide(0)
    end
end

local function toggleMaskForCalibration()
    if state.phase == "RUNNING" then return end
    if state.maskCanvas and state.maskCanvas:isShowing() then
        hideMask()
        researcherAlert("Mask hidden")
    else
        local ok, err = showMask()
        if not ok then researcherAlert("Mask error: " .. tostring(err)) end
    end
end

-- Two-press mask calibration. Hover the pointer over the TOP-LEFT corner of the
-- area to cover (tab strip or vertical-tab panel) and press the hotkey, then hover
-- the BOTTOM-RIGHT corner and press it again. The rectangle is saved relative to
-- the Chrome window, so save the Chrome frame first (Ctrl+Alt+Cmd+W).
local calib = { orientation = nil, topLeft = nil }

local function calibrateMask(orientation)
    if state.phase == "RUNNING" then return end
    local win, err = getChromeWindow()
    if not win then hs.alert.show(tostring(err), 2); return end
    local f = win:frame()
    local p = hs.mouse.absolutePosition()

    if calib.orientation ~= orientation or not calib.topLeft then
        calib.orientation = orientation
        calib.topLeft = { x = p.x, y = p.y }
        hs.alert.show(orientation .. " mask: top-left saved. Move to BOTTOM-RIGHT and press again.", 2)
        print(string.format("[Orlando] %s mask top-left: %.0f, %.0f", orientation, p.x, p.y))
        return
    end

    local tl = calib.topLeft
    local x1, y1 = math.min(tl.x, p.x), math.min(tl.y, p.y)
    local x2, y2 = math.max(tl.x, p.x), math.max(tl.y, p.y)
    calib.orientation, calib.topLeft = nil, nil

    local spec
    if orientation == "H" then
        spec = {
            xOffset = x1 - f.x,
            yOffset = y1 - f.y,
            rightInset = (f.x + f.w) - x2,
            height = y2 - y1,
        }
    else
        spec = {
            xOffset = x1 - f.x,
            yOffset = y1 - f.y,
            width = x2 - x1,
            bottomInset = (f.y + f.h) - y2,
        }
    end
    hs.settings.set("orlandoMask_" .. orientation, spec)
    print("[Orlando] Saved " .. orientation .. " mask: " .. hs.inspect(spec))

    -- Brief preview of the saved mask (separate from the trial mask).
    local frame = computeMaskFrame(orientation, f)
    if frame then
        local preview = hs.canvas.new(frame)
        preview:appendElements({
            type = "rectangle", action = "fill", fillColor = CONFIG.maskColor,
            frame = { x = "0%", y = "0%", w = "100%", h = "100%" },
        })
        preview:show(0)
        preview:bringToFront(true)
        hs.timer.doAfter(1.5, function() preview:delete(0) end)
    end
    hs.alert.show(orientation .. " mask saved", 1.5)
end

------------------------------------------------------------
-- 7. PROMPT / REVEAL / TIMEOUT
------------------------------------------------------------

-- Forward declarations; defined in section 8.
local advanceAfterOutcome
local prepareAndRunCurrentTrial

local function scheduleNextTrial(reason)
    if not CONFIG.autoAdvance then return end
    if state.phase ~= "IDLE" then return end
    stopTimer("nextTrialTimer")
    logEvent("NEXT_TRIAL_SCHEDULED",
        string.format("after=%s;delay=%.1f", reason, CONFIG.interTrialDelaySeconds))
    state.nextTrialTimer = hs.timer.doAfter(CONFIG.interTrialDelaySeconds, function()
        state.nextTrialTimer = nil
        if state.phase == "IDLE" then prepareAndRunCurrentTrial() end
    end)
end

local function startTargetDetection()
    if not CONFIG.autoDetectTarget then return end
    stopTimer("pollTimer")

    local win0 = getChromeWindow()
    state.lastTitle = win0 and (win0:title() or "") or ""
    state.selectionCount = 0

    state.pollTimer = hs.timer.doEvery(CONFIG.pollIntervalSeconds, function()
        if state.phase ~= "RUNNING" then return end
        local win = getChromeWindow()
        if not win then return end

        local title = win:title() or ""
        if title == state.lastTitle then return end
        state.lastTitle = title

        local trial = currentTrial()
        if not trial then return end

        local rec = state.trialRec
        if not rec then return end
        rec.nSelections = rec.nSelections + 1

        local elapsed = state.revealEpoch and (hs.timer.secondsSinceEpoch() - state.revealEpoch) or 0
        local isTarget = title:find(trial.targetTitle, 1, true) ~= nil
        if rec.nSelections == 1 then rec.firstCorrect = isTarget and 1 or 0 end

        local fields = {
            selection_number = rec.nSelections,
            elapsed_s = elapsed,
            first_selection = (rec.nSelections == 1) and (isTarget and "correct" or "incorrect") or "",
            window_title = cleanPageTitle(title),
        }

        if isTarget then
            advanceAfterOutcome("AUTO_COMPLETE", "Target detected via window title", fields)
        else
            rec.nIncorrect = rec.nIncorrect + 1
            table.insert(rec.incorrectPages, cleanPageTitle(title))
            logEvent("TAB_ACTIVATED_INCORRECT", "Non-target tab activated", fields)
        end
    end)
end

local function revealCurrentTrial()
    if state.phase ~= "POST_PROMPT" then return end

    logEvent("REVEAL_COMMAND", "Mask hide requested")
    hideMask()

    -- The authoritative start timestamp is still the FIRST VIDEO FRAME in OBS
    -- where the tab interface is visible. This log is only an auxiliary marker.
    state.revealEpoch = hs.timer.secondsSinceEpoch()
    state.phase = "RUNNING"
    newTrialRecord(state.revealEpoch)
    logEvent("TRIAL_REVEALED", "Mask removed (start cue)")

    startTargetDetection()

    stopTimer("timeoutTimer")
    state.timeoutTimer = hs.timer.doAfter(CONFIG.timeoutSeconds, function()
        if state.phase == "RUNNING" then
            local elapsed = hs.timer.secondsSinceEpoch() - (state.revealEpoch or hs.timer.secondsSinceEpoch())
            stopTimer("pollTimer")
            logEvent("TIMEOUT", "Trial time limit reached", {
                elapsed_s = elapsed,
                selection_number = state.trialRec and state.trialRec.nSelections or nil,
            })
            writeTrialRow("timeout", hs.timer.secondsSinceEpoch(), elapsed)
            showMask()
            state.phase = "IDLE"
            state.revealEpoch = nil

            -- Move to the next trial automatically after timeout.
            state.trialIndex = state.trialIndex + 1
            local c = currentCondition()
            if c and state.trialIndex > #c.trials then
                state.phase = "CONDITION_COMPLETE"
                logEvent("CONDITION_COMPLETE", "Last trial timed out")
                researcherAlert("Condition complete")
            else
                -- Reset backstage while still masked. Do not play the next prompt yet.
                local win, err = getChromeWindow()
                if win then
                    local app = getChrome()
                    restoreChromeWindowFrame(win)
                    app:activate(false)
                    win:focus()
                    resetNeutralTab(win, app)
                    resetMouse()
                else
                    print("[Orlando] Post-timeout reset error: " .. tostring(err))
                end
                researcherAlert("Timeout. Ready for next trial")
                scheduleNextTrial("TIMEOUT")
            end
        end
    end)
end

local function playCurrentPrompt()
    local trial = currentTrial()
    if not trial then
        researcherAlert("No current trial")
        return
    end

    local path = CONFIG.audioDirectory .. "/" .. trial.audio
    local sound = hs.sound.getByFile(path)
    if not sound then
        state.phase = "IDLE"
        logEvent("ERROR", "Audio file not found: " .. path)
        researcherAlert("Audio missing: " .. trial.audio)
        return
    end

    state.activeSound = sound
    state.phase = "PROMPT"
    logEvent("PROMPT_START", trial.audio)

    sound:setCallback(function(completed, _soundObject)
        if state.activeSound ~= sound then return end
        state.activeSound = nil

        if not completed then
            if state.phase == "PROMPT" then
                state.phase = "IDLE"
                logEvent("PROMPT_INTERRUPTED", trial.audio)
                researcherAlert("Prompt interrupted")
            end
            return
        end

        if state.phase ~= "PROMPT" then return end
        logEvent("PROMPT_END", trial.audio)
        state.phase = "POST_PROMPT"

        stopTimer("delayTimer")
        state.delayTimer = hs.timer.doAfter(CONFIG.postPromptDelaySeconds, function()
            state.delayTimer = nil
            revealCurrentTrial()
        end)
    end)

    sound:play()
end

------------------------------------------------------------
-- 8. TRIAL CONTROL
------------------------------------------------------------

prepareAndRunCurrentTrial = function()
    if state.phase == "RUNNING" or state.phase == "PROMPT" or state.phase == "POST_PROMPT" or state.phase == "PREPARING" then
        researcherAlert("Trial already active")
        return
    end

    local condition = currentCondition()
    local trial = currentTrial()
    if not condition or not trial then
        researcherAlert("No current trial")
        return
    end

    stopAllTimers()
    stopSound()
    state.phase = "PREPARING"
    state.revealEpoch = nil

    -- FIRST: mask the tab interface, so all backstage reset operations are hidden.
    local maskOK, maskErr = showMask()
    if not maskOK then
        state.phase = "IDLE"
        researcherAlert("Mask error: " .. tostring(maskErr))
        logEvent("ERROR", "Mask failed: " .. tostring(maskErr))
        return
    end
    logEvent("TRIAL_PREPARE", condition.name .. "/" .. trial.id)

    local win, err = getChromeWindow()
    if not win then
        state.phase = "IDLE"
        researcherAlert(err)
        logEvent("ERROR", err)
        return
    end

    local app = getChrome()
    restoreChromeWindowFrame(win)
    app:activate(false)
    win:focus()
    resetNeutralTab(win, app)

    local mouseOK, mouseErr = resetMouse()
    if not mouseOK then
        state.phase = "IDLE"
        researcherAlert(mouseErr)
        logEvent("ERROR", mouseErr)
        return
    end

    stopTimer("setupTimer")
    state.setupTimer = hs.timer.doAfter(CONFIG.setupSettleSeconds, function()
        state.setupTimer = nil
        playCurrentPrompt()
    end)
end

local function resetBackstageWithoutStarting()
    stopAllTimers()
    stopSound()
    showMask()
    state.revealEpoch = nil

    local win, err = getChromeWindow()
    if not win then
        logEvent("ERROR", "Backstage reset: " .. tostring(err))
        return
    end

    local app = getChrome()
    restoreChromeWindowFrame(win)
    app:activate(false)
    win:focus()
    resetNeutralTab(win, app)
    resetMouse()
end

advanceAfterOutcome = function(outcome, detail, fields)
    if state.phase ~= "RUNNING" then
        researcherAlert("No running trial")
        return
    end

    local elapsed = nil
    if state.revealEpoch then elapsed = hs.timer.secondsSinceEpoch() - state.revealEpoch end
    stopTimer("timeoutTimer")
    stopTimer("pollTimer")

    -- The facilitator hotkey timestamp is NOT the retrieval-time endpoint.
    -- OBS coding stops at the first frame where the correct target became active.
    fields = fields or {}
    fields.elapsed_s = elapsed
    logEvent(outcome, detail, fields)

    local statusByOutcome = {
        AUTO_COMPLETE = "completed_auto",
        FACILITATOR_COMPLETE = "completed_manual",
        TRIAL_INVALID = "invalid",
    }
    writeTrialRow(statusByOutcome[outcome] or outcome, hs.timer.secondsSinceEpoch(), elapsed)

    -- Immediately cover the interface after the facilitator acknowledges the outcome.
    showMask()
    state.phase = "IDLE"
    state.revealEpoch = nil

    state.trialIndex = state.trialIndex + 1
    local condition = currentCondition()
    if condition and state.trialIndex > #condition.trials then
        state.phase = "CONDITION_COMPLETE"
        logEvent("CONDITION_COMPLETE", "All scheduled trials finished")
        researcherAlert("Condition complete")
        return
    end

    resetBackstageWithoutStarting()
    researcherAlert("Ready for next trial")
    if outcome ~= "TRIAL_INVALID" then scheduleNextTrial(outcome) end
end

local function markCorrectAndAdvance()
    advanceAfterOutcome("FACILITATOR_COMPLETE", "Correct target observed")
end

local function markInvalidAndAdvance()
    advanceAfterOutcome("TRIAL_INVALID", "Facilitator marked invalid")
end

local function abortAndRetrySameTrial()
    if state.phase == "SESSION_COMPLETE" then return end
    recordAbortIfRunning()
    logEvent("TRIAL_ABORT_RETRY", "Same trial will be rerun")
    stopAllTimers()
    stopSound()
    state.phase = "IDLE"
    state.revealEpoch = nil
    resetBackstageWithoutStarting()
    researcherAlert("Trial reset. Same trial retained")
end

local function advanceCondition()
    if state.phase ~= "CONDITION_COMPLETE" then
        researcherAlert("Finish current condition first")
        return
    end

    state.conditionIndex = state.conditionIndex + 1
    state.trialIndex = 1

    if state.conditionIndex > #SESSION.conditions then
        state.phase = "SESSION_COMPLETE"
        showMask()
        logEvent("SESSION_COMPLETE", "All conditions finished")
        researcherAlert("Orlando session complete")
        return
    end

    state.phase = "IDLE"
    showMask()
    local c = currentCondition()
    logEvent("CONDITION_READY", c.name .. "; set=" .. c.contentSet .. "; orientation=" .. c.orientation)
    researcherAlert("Prepare condition: " .. c.name .. " / Set " .. c.contentSet)
end

------------------------------------------------------------
-- 9. STATUS / SESSION START
------------------------------------------------------------

local function statusText()
    local c = currentCondition()
    local t = currentTrial()
    return string.format(
        "Participant=%s | Order=%d | Condition=%s (%d/%d) | Trial=%s (%d/%d) | Phase=%s",
        SESSION.participant,
        SESSION.orderGroup,
        c and c.name or "NONE",
        state.conditionIndex,
        #SESSION.conditions,
        t and t.id or "NONE",
        state.trialIndex,
        c and #c.trials or 0,
        state.phase
    )
end

local function showStatus()
    local s = statusText()
    print("[Orlando] " .. s)
    if state.phase ~= "RUNNING" then researcherAlert(s) end
end

local function beginSession()
    ensureDirectory(CONFIG.audioDirectory)
    ensureDirectory(CONFIG.logDirectory)
    logEvent("SESSION_LOADED", statusText())
    print("\n[Orlando] Loaded.")
    print("[Orlando] Audio directory: " .. CONFIG.audioDirectory)
    print("[Orlando] Event log:  " .. eventsPath())
    print("[Orlando] Trial log:  " .. trialsPath())
    print("[Orlando] Order group " .. SESSION.orderGroup .. " condition plan:")
    for i, c in ipairs(SESSION.conditions) do
        print(string.format("[Orlando]   %d. %s (Set %s, %s)", i, c.name, c.contentSet,
            c.orientation == "H" and "horizontal" or "vertical"))
    end
    print("[Orlando] IMPORTANT: Calibrate Chrome frame and mouse start before scored trials.\n")
end

------------------------------------------------------------
-- 10. RESEARCHER HOTKEYS
------------------------------------------------------------
-- Chosen to be awkward enough that the participant is unlikely to trigger them.
-- Change them if they conflict with macOS/OBS shortcuts.

local MODS = {"ctrl", "alt", "cmd"}

-- Run CURRENT trial: mask/reset/prompt/reveal automatically.
hs.hotkey.bind(MODS, "return", function()
    prepareAndRunCurrentTrial()
end)

-- Facilitator saw the correct target become active. Remask + advance.
hs.hotkey.bind(MODS, ".", function()
    markCorrectAndAdvance()
end)

-- Mark current running trial invalid, remask + advance.
hs.hotkey.bind(MODS, "i", function()
    markInvalidAndAdvance()
end)

-- Abort/reset but KEEP the same trial number for a rerun.
hs.hotkey.bind(MODS, "r", function()
    abortAndRetrySameTrial()
end)

-- After condition's final trial: move to next condition in the SESSION plan.
hs.hotkey.bind(MODS, "n", function()
    advanceCondition()
end)

-- Show/hide current condition's mask for calibration only.
hs.hotkey.bind(MODS, "m", function()
    toggleMaskForCalibration()
end)

-- Capture current mouse position as the standardized study start coordinate.
hs.hotkey.bind(MODS, "c", function()
    captureMouseStart()
end)

-- Capture current Chrome window position and size as the standardized frame.
hs.hotkey.bind(MODS, "w", function()
    captureChromeWindowFrame()
end)

-- Calibrate the horizontal / vertical mask (press once per corner: top-left, then bottom-right).
hs.hotkey.bind(MODS, "h", function()
    calibrateMask("H")
end)

hs.hotkey.bind(MODS, "v", function()
    calibrateMask("V")
end)

-- Researcher status.
hs.hotkey.bind(MODS, "s", function()
    showStatus()
end)

-- Emergency unmask only. Does not advance anything.
hs.hotkey.bind(MODS, "escape", function()
    stopAllTimers()
    stopSound()
    hideMask()
    calib.orientation, calib.topLeft = nil, nil
    recordAbortIfRunning()
    state.phase = "IDLE"
    state.revealEpoch = nil
    logEvent("EMERGENCY_UNMASK", "Researcher emergency hotkey")
    researcherAlert("Emergency unmask")
end)

------------------------------------------------------------
-- 11. LOAD
------------------------------------------------------------

beginSession()

-- Helpful console summary:
print([[
ORLANDO HOTKEYS
  Ctrl+Alt+Cmd+Return : prepare + run current trial
  Ctrl+Alt+Cmd+.      : correct target observed, remask + advance
  Ctrl+Alt+Cmd+I      : mark invalid + advance
  Ctrl+Alt+Cmd+R      : abort/reset + RETRY same trial
  Ctrl+Alt+Cmd+N      : advance to next condition (after condition complete)
  Ctrl+Alt+Cmd+M      : toggle mask for calibration
  Ctrl+Alt+Cmd+C      : capture standardized mouse start
  Ctrl+Alt+Cmd+W      : capture standardized Chrome window frame
  Ctrl+Alt+Cmd+H      : calibrate HORIZONTAL mask (press at top-left, then bottom-right)
  Ctrl+Alt+Cmd+V      : calibrate VERTICAL mask (press at top-left, then bottom-right)
  Ctrl+Alt+Cmd+S      : status
  Ctrl+Alt+Cmd+Esc    : emergency unmask
]])