-- Adapter tests use fake Hammerspoon surfaces. They do not validate macOS APIs.
local Controller = require("study.controller")
local Model = require("study.model")
local Materials = require("study.materials")
local Config = require("study.config")
local Storage = require("study.storage")
local Allocation = require("study.allocation")
local results = {}

local function eq(actual, expected, message)
    assert(actual == expected, (message or "Value") .. ": expected " .. tostring(expected)
        .. ", got " .. tostring(actual))
end
local function test(name, body)
    local ok, message = pcall(body)
    results[#results + 1] = {name = name, passed = ok, error = not ok and tostring(message) or nil}
    print((ok and "PASS " or "FAIL ") .. name .. (ok and "" or (": " .. tostring(message))))
end

local function fixture(group)
    local env = {time = 10, timers = {}, title = "Study Start", notices = {},buttons={},
        front = true, audioAvailable = true, playCalls = 0, lockEnabled = false,
        position = {x = 500, y = 400}, frame = {x = 40, y = 40, w = 1000, h = 700}}
    local hs = {timer = {}, eventtap = {event = {types = {}}}, canvas = {windowLevels = {overlay = 1}},
        settings = {}, mouse = {}, window = {}, sound = {}, alert = {}, dialog = {}}
    local saved = {
        [Config.settingsPrefix .. "pointer"] = {x = 500, y = 400},
        [Config.settingsPrefix .. "mask_H"] = {x = 0,y = 0,w = 1000,h = 90,
            frame_w = 1000,frame_h = 700,screen_id = "1"},
        [Config.settingsPrefix .. "mask_V"] = {x = 0,y = 0,w = 230,h = 700,
            frame_w = 1000,frame_h = 700,screen_id = "1"},
    }
    hs.settings.get = function(key) return saved[key] end
    hs.settings.set = function(key,value) saved[key] = value end
    hs.timer.absoluteTime = function() return env.time * 1e9 end
    hs.timer.secondsSinceEpoch = function() return 1700000000 + env.time end
    local function timer(delay, callback, repeating)
        local object = {at = env.time + delay, callback = callback, stopped = false, interval = repeating and delay}
        function object:stop() self.stopped = true end
        env.timers[#env.timers + 1] = object
        return object
    end
    hs.timer.doAfter = function(delay,callback) return timer(delay,callback,false) end
    hs.timer.doEvery = function(delay,callback) return timer(delay,callback,true) end
    function env.advance(delta)
        local target = env.time + delta
        for _ = 1,10000 do
            local nextTimer
            for _,item in ipairs(env.timers) do
                if not item.stopped and item.at <= target and (not nextTimer or item.at < nextTimer.at) then
                    nextTimer = item
                end
            end
            if not nextTimer then env.time = target; return end
            env.time = nextTimer.at
            if nextTimer.interval then nextTimer.at = nextTimer.at + nextTimer.interval
            else nextTimer.stopped = true end
            nextTimer.callback()
        end
        error("Fake timer loop did not settle")
    end
    hs.alert.show = function(message) env.notices[#env.notices + 1] = message end
    hs.dialog.blockAlert = function(title,message,first)
        env.dialogs = env.dialogs or {}
        env.dialogs[#env.dialogs + 1] = {title = title,message = message,first = first}
        if env.dialogAnswers and #env.dialogAnswers > 0 then
            return table.remove(env.dialogAnswers,1)
        end
        return first
    end
    hs.mouse.absolutePosition = function(value)
        if value then env.position = {x = value.x,y = value.y} end
        return {x = env.position.x,y = env.position.y}
    end
    for index,key in ipairs({"leftMouseDown","leftMouseUp","rightMouseDown","rightMouseUp",
        "otherMouseDown","otherMouseUp","mouseMoved","leftMouseDragged",
        "rightMouseDragged","otherMouseDragged","scrollWheel"}) do
        hs.eventtap.event.types[key] = index
    end
    hs.eventtap.checkMouseButtons=function()return env.buttons end
    hs.eventtap.event.properties={mouseEventButtonNumber=1,mouseEventClickState=2,mouseEventWindowUnderMousePointer=3}
    hs.eventtap.new = function(events,callback)
        local gate=false
        for _,typ in ipairs(events) do if typ==hs.eventtap.event.types.mouseMoved then gate=true end end
        local tap = {callback = callback, enabled = false,isGate=gate}
        function tap:start() self.enabled = true;if self.isGate then env.lockEnabled = true end end
        function tap:stop() self.enabled = false;if self.isGate then env.lockEnabled = false end end
        function tap:isEnabled() return self.enabled end
        return tap
    end
    hs.eventtap.keyStroke = function(_,key)
        env.keyStrokeKey = key
        if not env.neutralFails then env.title = "Study Start" end
    end
    local app = {name = function() return "Google Chrome" end,
        isFrontmost=function()return not env.inactiveApp end,
        activate=function()env.inactiveApp=false;env.activated=true;return true end}
    local win = {}
    function win:id() return 7 end
    function win:application() return app end
    function win:isMinimized() return false end
    function win:frame() return env.frame end
    function win:screen() return {id = function() return 1 end} end
    function win:title() return env.title end
    function win:focus() env.front = true end
    function win:focusTab(index)
        env.focusTabArg = index
        env.focusTabCalls = (env.focusTabCalls or 0) + 1
        if not env.neutralFails then env.title = "Study Start"; return true end
        return false
    end
    hs.window.get = function(id) return id == 7 and not env.windowMissing and win or nil end
    hs.window.frontmostWindow = function() return env.front and win or nil end
    function env.mouseEvent(name,button)
        local ev={}
        function ev:getType()return hs.eventtap.event.types[name]end
        function ev:getProperty(prop)
            if prop==1 then return button or (name:find("right") and 1 or 0)end
            if prop==2 then return 1 end
            if prop==3 then return 7 end
        end
        function ev:location()return {x=env.position.x,y=env.position.y}end
        function ev:timestamp()return env.time*1e9 end
        return ev
    end
    hs.canvas.new = function(frame)
        local canvas = {rect = frame}
        function canvas:appendElements() return self end
        function canvas:clickActivating() return self end
        function canvas:level() return self end
        function canvas:show() self.visible = true; return self end
        function canvas:bringToFront() return self end
        function canvas:delete() self.visible = false; return self end
        return canvas
    end
    hs.sound.getByFile = function()
        if not env.audioAvailable then return nil end
        local sound = {}
        function sound:setCallback(fn) self.callback = fn; return self end
        function sound:play() env.playCalls = env.playCalls + 1; return true end
        function sound:stop() self.stopped = true end
        env.sound = sound
        return sound
    end
    local store = {events = {},trials = {},checkpoints = {},closed = false,closedCalls = 0,
        afterClosedCalls = 0,interruptedCalls = 0}
    function store:guard()
        if self.closed then self.afterClosedCalls = self.afterClosedCalls + 1; return nil,"Closed" end
        return true
    end
    function store:event(name,ctx)
        if not self:guard() then return nil,"Closed" end
        if self.failEvent == name then return nil,"Injected event write failure" end
        self.events[#self.events + 1] = {name = name,context = ctx};return true
    end
    function store:trial(record)
        if not self:guard() then return nil,"Closed" end
        self.trials[#self.trials + 1] = record;return true
    end
    function store:checkpoint(snapshot)
        if not self:guard() then return nil,"Closed" end
        if self.failNextCheckpoint then self.failNextCheckpoint = false; return nil,"Injected checkpoint failure" end
        self.checkpoints[#self.checkpoints + 1] = snapshot;return true
    end
    function store:close(status)
        if not self:guard() then return nil,"Closed" end
        self.closedCalls = self.closedCalls + 1;self.closed = true;self.status = status;return true
    end
    function store:markInterrupted()
        if not self:guard() then return nil,"Closed" end
        self.interruptedCalls = self.interruptedCalls + 1;self.closed = true;return true
    end
    local c = Controller.new(hs,"/dummy-controller")
    -- Existing manual-mode regression checks remain independent of the new
    -- default. Automation cases below opt in explicitly on their own instance.
    c.cfg = setmetatable({autoAdvance = false},{__index = Config})
    local plan = Materials.buildPlan(group or 1)
    c.model = Model.new(plan)
    c.meta = {participant = "TEST001",group = group or 1,plan = plan}
    c.store = store;c.windowID = 7;c.approvedFrame = env.frame
    -- Detach the approved value from the mutable simulated window rectangle.
    c.approvedFrame = {x = env.frame.x,y = env.frame.y,w = env.frame.w,h = env.frame.h}
    return c,env,store
end

local function startPrompt(c,env)
    local before = env.playCalls
    c:approveSetup()
    eq(c.model.phase,"READY")
    eq(env.lockEnabled,true)
    c:startTrial()
    eq(c.model.phase,"PROMPT")
    eq(env.playCalls,before + 1)
end
local function running(c,env)
    startPrompt(c,env)
    env.sound.callback(true)
    env.advance(Config.postPromptDelaySeconds)
    eq(c.model.phase,"RUNNING")
    eq(env.lockEnabled,false)
end

test("adapter blocks navigation in ready and outcome hold",function()
    local c,e,s = fixture()
    running(c,e)
    c:finish("completed_manual")
    eq(c.model.phase,"OUTCOME")
    eq(e.lockEnabled,true)
    eq(c.mask,nil,"Correct target display retained during hold")
    eq(s.trials[1].retrieval_time_s,nil,"No final time inferred from acknowledgment")
    e.advance(Config.outcomeHoldSeconds)
    eq(c.model.phase,"READY")
    eq(e.lockEnabled,true)
    assert(c.mask and c.mask.visible)
    eq(c.setupApproved,false)
end)

test("adapter partial prompt pause consumes and cannot auto replay",function()
    local c,e,s = fixture()
    startPrompt(c,e)
    c:emergency("Partial audio interruption")
    eq(c.model.phase,"PAUSED")
    eq(c.model.trialIndex,2)
    eq(#s.trials,1)
    eq(s.trials[1].status,"interrupted")
    eq(s.trials[1].timed_started,false)
    eq(e.lockEnabled,false)
    e.advance(3)
    eq(e.playCalls,1)
    c:setup()
    eq(c.model.phase,"SETUP")
    eq(c.model.trialIndex,2)
end)

test("adapter missing audio before exposure retains scheduled entry",function()
    local c,e,s = fixture()
    e.audioAvailable = false
    c:approveSetup();c:startTrial()
    eq(c.model.phase,"PAUSED")
    eq(c.model.trialIndex,1)
    eq(#s.trials,0)
    eq(e.playCalls,0)
end)

test("adapter verifies neutral activation with a bounded wait",function()
    local c,e,s = fixture()
    e.neutralFails = true;e.title = "Wrong page"
    c:approveSetup();c:startTrial()
    e.advance(Config.neutralWaitSeconds + 0.1)
    eq(c.model.phase,"PAUSED")
    eq(c.model.trialIndex,1)
    eq(e.playCalls,0)
    eq(#s.trials,0)
    eq(e.lockEnabled,false)
end)

test("adapter catches moved window before prompt exposure",function()
    local c,e,s = fixture()
    c:approveSetup()
    e.frame.x = e.frame.x + 40
    c:startTrial()
    eq(c.model.phase,"PAUSED")
    eq(e.playCalls,0)
    eq(c.setupApproved,false)
    eq(e.lockEnabled,false)
end)

test("adapter immediate post-reveal selection uses preverified neutral baseline",function()
    local c,e,s = fixture()
    running(c,e)
    e.title = c.model:currentTrial().targetTitle
    c:poll()
    eq(c.model.phase,"OUTCOME")
    eq(s.trials[1].status,"completed_auto")
    eq(s.trials[1].aux_selection_count,1)
    eq(s.trials[1].aux_first_correct,1)
    eq(s.trials[1].aux_incorrect_count,0)
end)

test("adapter timeout without selection leaves final outcomes for video",function()
    local c,e,s = fixture()
    running(c,e)
    e.advance(Config.timeoutSeconds)
    eq(c.model.phase,"OUTCOME")
    eq(s.trials[1].status,"timeout")
    eq(s.trials[1].retrieval_time_s,nil)
    eq(s.trials[1].auto_detection_elapsed_s,nil)
    eq(s.trials[1].aux_first_correct,nil)
end)

test("adapter checkpoint failure cannot acquire a new fatal input lock",function()
    local c,e = fixture()
    c:approveSetup()
    c.store.failNextCheckpoint = true
    c:startTrial()
    eq(c.fatal,true)
    eq(e.playCalls,0)
    eq(e.lockEnabled,false,"Storage failure must release and retain released input")
    eq(c.mask,nil,"Storage failure must not remask after stopping")
end)

test("adapter verified-start event failure cannot play the prompt",function()
    local c,e = fixture()
    c:approveSetup()
    c.store.failEvent = "START_STATE_VERIFIED"
    c:startTrial()
    eq(c.fatal,true)
    eq(e.playCalls,0)
    eq(e.lockEnabled,false)
    eq(c.mask,nil)
end)

test("adapter pause after session completion never writes closed records",function()
    local c,e,s = fixture()
    c.model.phase = "SESSION_COMPLETE";s.closed = true
    c:emergency("Pause pressed after completion")
    eq(s.afterClosedCalls,0)
    eq(c.fatal,false)
    eq(e.lockEnabled,false)
end)

test("adapter ending an already completed session cannot mark it interrupted",function()
    local c,_,s = fixture()
    c.model.phase = "SESSION_COMPLETE";s.closed = true
    c:endSession()
    eq(s.afterClosedCalls,0)
    eq(s.interruptedCalls,0)
    eq(c.fatal,false)
end)

test("adapter selects the LAST tab as Study Start (6 low, 16 high)",function()
    for _,case in ipairs({{group=1,expected=6},{group=2,expected=16}}) do
        local c,e = fixture(case.group)
        eq(c.model:currentBlock().expectedTabCount,case.expected)
        c:approveSetup();c:startTrial()
        eq(e.focusTabArg,case.expected,"focusTab must target the last tab")
        eq(c.model.phase,"PROMPT")
    end
end)

test("adapter falls back to Cmd+9 (last tab), never Cmd+1",function()
    local c,e = fixture()
    -- focusTab refuses (returns false) but the fallback keystroke works.
    c.hs.window.get(7).focusTab = function() return false end
    c:approveSetup();c:startTrial()
    eq(e.keyStrokeKey,"9","Fallback must be Cmd+9")
    eq(c.model.phase,"PROMPT")
end)

test("adapter completes 24 trial outcomes for each of the four allocation groups",function()
    for group = 1,4 do
        local c,e,s = fixture(group)
        for blockIndex = 1,4 do
            for trialIndex = 1,6 do
                if c.model.phase == "READY" then c:setup() end
                eq(c.model.phase,"SETUP")
                local expected = c.meta.plan[blockIndex].trials[trialIndex]
                running(c,e)
                e.title = expected.targetTitle
                c:poll()
                eq(c.model.phase,"OUTCOME")
                local record = s.trials[#s.trials]
                eq(record.block,blockIndex)
                eq(record.trial,expected.id)
                eq(record.target_id,expected.targetID)
                eq(record.target_title,expected.targetTitle)
                eq(record.condition,c.meta.plan[blockIndex].name)
                eq(record.content_set,c.meta.plan[blockIndex].contentSet)
                e.advance(Config.outcomeHoldSeconds)
            end
            eq(c.model.phase,"BLOCK_COMPLETE")
            c:nextBlock()
        end
        eq(c.model.phase,"SESSION_COMPLETE")
        eq(#s.trials,24)
        eq(e.playCalls,24)
        eq(s.closedCalls,1)
        eq(s.afterClosedCalls,0)
        local seen = {}
        for _,record in ipairs(s.trials) do
            local key = record.block .. ":" .. record.trial
            assert(not seen[key],"Duplicate outcome " .. key)
            seen[key] = true
        end
    end
end)

test("adapter rejects stale mask dimensions in either orientation",function()
    for _,group in ipairs({1,3}) do
        local c,e = fixture(group)
        local orientation = c.model:currentBlock().orientation
        local spec = c.hs.settings.get(Config.settingsPrefix .. "mask_" .. orientation)
        spec.frame_w = spec.frame_w + 50
        c:approveSetup()
        eq(c.model.phase,"SETUP")
        eq(c.setupApproved,false)
        eq(e.lockEnabled,false)
        eq(e.playCalls,0)
    end
end)

local function automaticFixture(group)
    local c,e,s = fixture(group)
    c.cfg.autoAdvance = true
    c.cfg.autoAdvanceAfterTimeout = true
    return c,e,s
end

local function observedCorrect(c,e)
    e.title = c.model:currentTrial().targetTitle
    c:poll()
    eq(c.model.phase,"OUTCOME")
end

local function settleAutomatic(c,e)
    e.advance(c.cfg.outcomeHoldSeconds)
    eq(c.model.phase,"READY")
    assert(c.autoNextPending,"A within-block automatic continuation must be pending")
    eq(e.lockEnabled,true)
    assert(c.mask and c.mask.visible,"Countdown must keep the tabs masked")
end

test("automatic block approval does not start the first prompt without Return",function()
    local c,e = automaticFixture()
    c:approveSetup()
    eq(c.model.phase,"READY")
    assert(c.autoBlockApproval)
    e.advance(c.cfg.interTrialDelaySeconds + 0.1)
    eq(e.playCalls,0)
    eq(c.autoNextPending,nil)
end)

test("automatic completion countdown resets neutral and pointer before the next prompt",function()
    local c,e,s = automaticFixture()
    running(c,e)
    e.position = {x = 120,y = 100}
    observedCorrect(c,e)
    eq(#s.trials,1)
    eq(c.mask,nil,"Recording hold must retain the selected target")
    settleAutomatic(c,e)
    eq(c.model.trialIndex,2)
    local key = c.autoNextPending.scheduled_key
    assert(key)
    c:finish("completed_manual")
    eq(#s.trials,1,"Repeated completion cannot duplicate the recorded outcome")
    c:startTrial()
    eq(e.playCalls,1,"Return cannot bypass the fixed automatic countdown")
    e.advance(c.cfg.interTrialDelaySeconds - 0.01)
    eq(e.playCalls,1)
    e.advance(0.02)
    eq(c.model.phase,"PROMPT")
    eq(e.playCalls,2)
    eq(e.focusTabArg,6,"The groupmate's LAST-neutral convention is preserved")
    eq(e.title,"Study Start")
    eq(e.position.x,500)
    eq(e.position.y,400)
    eq(c.autoNextPending,nil)
    eq(e.lockEnabled,true)
    local approvals = 0
    for _,event in ipairs(s.events) do
        if event.name == "PREFLIGHT_APPROVED" then approvals = approvals + 1 end
    end
    eq(approvals,1,"Automatic continuation must not fabricate fresh manual approvals")
end)

test("automatic flow completes all four groups with one approval per block and stops for TLX",function()
    for group = 1,4 do
        local c,e,s = automaticFixture(group)
        for blockIndex = 1,4 do
            running(c,e)
            for trialIndex = 1,6 do
                if trialIndex > 1 then
                    eq(c.model.phase,"PROMPT")
                    e.sound.callback(true)
                    e.advance(c.cfg.postPromptDelaySeconds)
                    eq(c.model.phase,"RUNNING")
                end
                local expected = c.meta.plan[blockIndex].trials[trialIndex]
                observedCorrect(c,e)
                local record = s.trials[#s.trials]
                eq(record.block,blockIndex)
                eq(record.trial,expected.id)
                eq(record.target_id,expected.targetID)
                eq(record.target_title,expected.targetTitle)
                eq(record.content_set,c.meta.plan[blockIndex].contentSet)
                e.advance(c.cfg.outcomeHoldSeconds)
                if trialIndex < 6 then
                    assert(c.autoNextPending)
                    e.advance(c.cfg.interTrialDelaySeconds)
                end
            end
            eq(c.model.phase,"BLOCK_COMPLETE")
            eq(c.autoNextPending,nil)
            local plays = e.playCalls
            e.advance(c.cfg.interTrialDelaySeconds + 0.2)
            eq(e.playCalls,plays,"No automatic jump across the workload-rating boundary")
            c:nextBlock()
            eq(c.autoBlockApproval,nil,"The next block needs its own visible-tab check")
        end
        eq(c.model.phase,"SESSION_COMPLETE")
        eq(#s.trials,24)
        eq(e.playCalls,24)
        eq(s.closedCalls,1)
        eq(s.afterClosedCalls,0)
        local approvals = 0
        for _,event in ipairs(s.events) do
            if event.name == "PREFLIGHT_APPROVED" then approvals = approvals + 1 end
        end
        eq(approvals,4)
        local seen = {}
        for _,record in ipairs(s.trials) do
            local identity = record.block .. ":" .. record.trial
            assert(not seen[identity],"Duplicate automatic outcome " .. identity)
            seen[identity] = true
        end
    end
end)

test("automatic target detection accepts only the explicit legacy title for the same page",function()
    local c,e,s = automaticFixture(4) -- Animals is the first block; P2 then P3.
    running(c,e)
    observedCorrect(c,e);settleAutomatic(c,e)
    e.advance(c.cfg.interTrialDelaySeconds)
    e.sound.callback(true);e.advance(c.cfg.postPromptDelaySeconds)
    local trial=c.model:currentTrial()
    eq(trial.targetID,"P3")
    assert(#trial.targetTitleAliases==1)
    e.title=trial.targetTitle .. " unrelated page"
    c:poll()
    eq(c.model.phase,"RUNNING","A similar title must not finish the trial")
    e.title=trial.targetTitleAliases[1] .. " - Google Chrome"
    c:poll()
    eq(c.model.phase,"OUTCOME")
    eq(#s.trials,2)
    eq(s.trials[2].target_title,trial.targetTitle,"Canonical group title remains the record identity")
    eq(s.trials[2].aux_first_correct,0,"The earlier unrelated selection is retained")
    settleAutomatic(c,e)
    e.advance(c.cfg.interTrialDelaySeconds)
    eq(e.playCalls,3)
end)

test("automatic scheduling event failure releases input and cannot start another trial",function()
    local c,e,s = automaticFixture()
    running(c,e);observedCorrect(c,e)
    s.failEvent="AUTO_NEXT_TRIAL_SCHEDULED"
    e.advance(c.cfg.outcomeHoldSeconds+c.cfg.interTrialDelaySeconds+0.2)
    eq(c.fatal,true);eq(e.playCalls,1);eq(#s.trials,1)
    eq(c.autoNextPending,nil);eq(c.autoBlockApproval,nil)
    eq(e.lockEnabled,false);eq(c.mask,nil)
end)

test("interrupted audio in an automatic block revokes progression without replay",function()
    local c,e,s=automaticFixture()
    startPrompt(c,e)
    e.sound.callback(false)
    e.advance(c.cfg.interTrialDelaySeconds+0.2)
    eq(c.model.phase,"PAUSED");eq(c.model.trialIndex,2)
    eq(#s.trials,1);eq(s.trials[1].status,"interrupted")
    eq(c.autoBlockApproval,nil);eq(c.autoNextPending,nil)
    eq(e.playCalls,1);eq(e.lockEnabled,false)
end)

test("manual configuration keeps facilitator-paced trial starts",function()
    local c,e,s = fixture()
    running(c,e)
    observedCorrect(c,e)
    e.advance(c.cfg.outcomeHoldSeconds + Config.interTrialDelaySeconds + 0.2)
    eq(c.model.phase,"READY")
    eq(c.autoNextPending,nil)
    eq(e.playCalls,1)
    eq(#s.trials,1)
    c:startTrial()
    eq(e.playCalls,1,"A manual-mode trial still requires explicit setup approval")
end)

test("scrolling block falls back to manual trials instead of claiming a scroll reset",function()
    local c,e,s = automaticFixture()
    e.dialogAnswers = {"Checks complete","Manual trials"}
    running(c,e)
    eq(c.autoBlockApproval,nil)
    observedCorrect(c,e)
    e.advance(c.cfg.outcomeHoldSeconds + c.cfg.interTrialDelaySeconds + 0.2)
    eq(c.model.phase,"READY")
    eq(c.autoNextPending,nil)
    eq(e.playCalls,1)
    eq(#s.trials,1)
end)

test("pause cancels an automatic countdown without replaying the completed trial",function()
    local c,e,s = automaticFixture()
    running(c,e);observedCorrect(c,e);settleAutomatic(c,e)
    c:emergency("Participant break / facilitator pause")
    eq(c.model.phase,"PAUSED")
    eq(c.model.trialIndex,2)
    eq(c.autoNextPending,nil)
    eq(c.autoBlockApproval,nil)
    eq(e.lockEnabled,false)
    e.advance(c.cfg.interTrialDelaySeconds + 1)
    eq(e.playCalls,1)
    eq(#s.trials,1)
    c:setup();running(c,e)
    eq(c.model.trialIndex,2)
    eq(e.playCalls,2)
end)

test("Setup cancels an automatic countdown and requires fresh approval",function()
    local c,e,s = automaticFixture()
    running(c,e);observedCorrect(c,e);settleAutomatic(c,e)
    c:setup()
    eq(c.model.phase,"SETUP")
    eq(c.autoNextPending,nil)
    eq(c.autoBlockApproval,nil)
    eq(c.setupApproved,false)
    eq(e.lockEnabled,false)
    e.advance(c.cfg.interTrialDelaySeconds + 1)
    eq(e.playCalls,1)
    eq(#s.trials,1)
end)

test("emergency during recording hold cannot create a later automatic prompt",function()
    local c,e,s = automaticFixture()
    running(c,e);observedCorrect(c,e)
    c:emergency("Emergency during recording hold")
    eq(c.model.phase,"PAUSED")
    eq(c.model.trialIndex,2)
    eq(c.autoNextPending,nil)
    eq(c.autoBlockApproval,nil)
    e.advance(c.cfg.outcomeHoldSeconds + c.cfg.interTrialDelaySeconds + 1)
    eq(e.playCalls,1)
    eq(#s.trials,1)
end)

test("moved window cancels automatic continuation before another exposure",function()
    local c,e,s = automaticFixture()
    running(c,e);observedCorrect(c,e);settleAutomatic(c,e)
    e.frame.x = e.frame.x + 40
    e.advance(c.cfg.interTrialDelaySeconds + 0.2)
    eq(c.model.phase,"PAUSED")
    eq(c.autoNextPending,nil)
    eq(c.autoBlockApproval,nil)
    eq(e.playCalls,1)
    eq(#s.trials,1)
    eq(e.lockEnabled,false)
end)

test("focus loss cancels automatic continuation without bringing Chrome back silently",function()
    local c,e,s = automaticFixture()
    running(c,e);observedCorrect(c,e);settleAutomatic(c,e)
    e.front = false
    e.advance(c.cfg.interTrialDelaySeconds + 0.2)
    eq(c.model.phase,"PAUSED")
    eq(c.autoNextPending,nil)
    eq(e.front,false)
    eq(e.playCalls,1)
    eq(#s.trials,1)
    eq(e.lockEnabled,false)
end)

test("missing study window cancels automatic continuation",function()
    local c,e,s = automaticFixture()
    running(c,e);observedCorrect(c,e);settleAutomatic(c,e)
    e.windowMissing = true
    e.advance(c.cfg.interTrialDelaySeconds + 0.2)
    eq(c.model.phase,"PAUSED")
    eq(c.autoNextPending,nil)
    eq(e.playCalls,1)
    eq(#s.trials,1)
    eq(e.lockEnabled,false)
end)

test("stale mask calibration cannot expose an automatic next trial",function()
    local c,e,s = automaticFixture()
    running(c,e);observedCorrect(c,e);settleAutomatic(c,e)
    local orientation = c.model:currentBlock().orientation
    local spec = c.hs.settings.get(Config.settingsPrefix .. "mask_" .. orientation)
    spec.frame_w = spec.frame_w + 50
    e.advance(c.cfg.interTrialDelaySeconds + 0.2)
    eq(c.model.phase,"PAUSED")
    eq(c.autoNextPending,nil)
    eq(e.playCalls,1)
    eq(#s.trials,1)
    eq(e.lockEnabled,false)
end)

test("checkpoint failure during automatic preparation releases input without a new prompt",function()
    local c,e,s = automaticFixture()
    running(c,e);observedCorrect(c,e);settleAutomatic(c,e)
    s.failNextCheckpoint = true
    e.advance(c.cfg.interTrialDelaySeconds + 0.2)
    eq(c.fatal,true)
    eq(c.autoNextPending,nil)
    eq(e.playCalls,1)
    eq(#s.trials,1)
    eq(e.lockEnabled,false)
    eq(c.mask,nil)
end)

test("automatic-start event failure cannot play another prompt",function()
    local c,e,s = automaticFixture()
    running(c,e);observedCorrect(c,e);settleAutomatic(c,e)
    s.failEvent = "AUTO_TRIAL_START_REQUESTED"
    e.advance(c.cfg.interTrialDelaySeconds + 0.2)
    eq(c.fatal,true)
    eq(c.autoNextPending,nil)
    eq(e.playCalls,1)
    eq(#s.trials,1)
    eq(e.lockEnabled,false)
end)

test("missing next audio stops before exposure and retains the pending scheduled entry",function()
    local c,e,s = automaticFixture()
    running(c,e);observedCorrect(c,e);settleAutomatic(c,e)
    e.audioAvailable = false
    e.advance(c.cfg.interTrialDelaySeconds + 0.2)
    eq(c.model.phase,"PAUSED")
    eq(c.model.trialIndex,2)
    eq(c.autoNextPending,nil)
    eq(c.autoBlockApproval,nil)
    eq(e.playCalls,1)
    eq(#s.trials,1)
    eq(e.lockEnabled,false)
end)

test("failed automatic neutral reset stops before the next target prompt",function()
    local c,e,s = automaticFixture()
    running(c,e);observedCorrect(c,e);settleAutomatic(c,e)
    e.neutralFails = true
    e.advance(c.cfg.interTrialDelaySeconds + c.cfg.neutralWaitSeconds + 0.2)
    eq(c.model.phase,"PAUSED")
    eq(c.model.trialIndex,2)
    eq(e.playCalls,1)
    eq(#s.trials,1)
    eq(e.lockEnabled,false)
end)

test("timeout follows the configured automatic countdown without inventing a completed time",function()
    local c,e,s = automaticFixture()
    running(c,e)
    e.advance(c.cfg.timeoutSeconds)
    eq(c.model.phase,"OUTCOME")
    eq(s.trials[1].status,"timeout")
    eq(s.trials[1].retrieval_time_s,nil)
    eq(s.trials[1].aux_first_correct,nil)
    settleAutomatic(c,e)
    e.advance(c.cfg.interTrialDelaySeconds)
    eq(c.model.phase,"PROMPT")
    eq(e.playCalls,2)
    eq(#s.trials,1)
end)

test("timeout can explicitly retain manual progression while normal completions are automatic",function()
    local c,e,s = automaticFixture()
    c.cfg.autoAdvanceAfterTimeout = false
    running(c,e)
    e.advance(c.cfg.timeoutSeconds)
    e.advance(c.cfg.outcomeHoldSeconds + c.cfg.interTrialDelaySeconds + 0.2)
    eq(c.model.phase,"READY")
    eq(c.autoNextPending,nil)
    eq(e.playCalls,1)
    eq(#s.trials,1)
    eq(s.trials[1].status,"timeout")
end)

test("manual target acknowledgment keeps the same automatic within-block flow",function()
    local c,e,s = automaticFixture()
    running(c,e)
    c:finish("completed_manual")
    settleAutomatic(c,e)
    e.advance(c.cfg.interTrialDelaySeconds)
    eq(c.model.phase,"PROMPT")
    eq(e.playCalls,2)
    eq(s.trials[1].status,"completed_manual")
    eq(s.trials[1].retrieval_time_s,nil)
end)

test("an interrupted automatic trial consumes its exposed entry and never restarts itself",function()
    local c,e,s = automaticFixture()
    running(c,e)
    c:emergency("Trial invalidated by facilitator")
    eq(c.model.phase,"PAUSED")
    eq(c.model.trialIndex,2)
    eq(#s.trials,1)
    eq(s.trials[1].status,"interrupted")
    eq(c.autoNextPending,nil)
    eq(c.autoBlockApproval,nil)
    e.advance(c.cfg.interTrialDelaySeconds + 1)
    eq(e.playCalls,1)
end)

local function sessionFixture(inputs,enableMain,verifyProfile)
    local c,e,s = fixture()
    c.model = nil;c.store = nil;c.meta = nil
    e.promptCalls = 0;e.createCalls = 0
    c.hs.dialog.textPrompt = function()
        e.promptCalls = e.promptCalls + 1
        return "OK",inputs[e.promptCalls]
    end
    c.hs.fs = {attributes = function() return {mode = "file"} end}
    local originalCreate = Storage.create
    local originalEnabled = Config.mainStudyEnabled
    local originalProfile = Config.recordingProfile
    if enableMain ~= nil then Config.mainStudyEnabled = enableMain end
    if verifyProfile then
        Config.recordingProfile = {}
        for key in pairs(originalProfile) do Config.recordingProfile[key] = "DUMMY_VERIFIED_FOR_TEST_ONLY" end
    end
    Storage.create = function(_,meta)
        e.createCalls = e.createCalls + 1;e.createdMeta = meta
        return s
    end
    local ok,message = pcall(function() c:newSession() end)
    Storage.create = originalCreate
    Config.mainStudyEnabled = originalEnabled
    Config.recordingProfile = originalProfile
    if not ok then error(message) end
    return c,e,s
end

test("adapter rejects invalid group before creating session records",function()
    local c,e = sessionFixture({"pilot","PILOT001","0"})
    eq(e.createCalls,0)
    eq(c.model,nil)
    eq(e.promptCalls,3)
end)

test("adapter main mode uses the shared runtime settings",function()
    local c,e = sessionFixture({"main","P001"},false)
    eq(e.createCalls,1)
    eq(e.promptCalls,2)
    eq(c.meta.group,Allocation.P001.group)
end)

test("adapter main mode does not require recording profile verification",function()
    local c,e = sessionFixture({"main","P001"},true,false)
    eq(e.createCalls,1)
    eq(e.promptCalls,2)
    eq(c.meta.group,Allocation.P001.group)
end)

test("adapter rejects an unknown main participant without asking for a random group",function()
    local c,e = sessionFixture({"main","P999"},true,true)
    eq(e.createCalls,0)
    eq(c.model,nil)
    eq(e.promptCalls,2)
end)

test("adapter main participant obtains its frozen roster group and practice order",function()
    local c,e = sessionFixture({"main","P001"},true,true)
    eq(e.createCalls,1)
    eq(e.promptCalls,2,"Main mode must use its allocated group rather than another input")
    eq(c.meta.group,Allocation.P001.group)
    eq(c.meta.practice_first,Allocation.P001.practiceFirst)
    eq(c.model.phase,"SETUP")
    eq(c.model:currentBlock().name,Materials.buildPlan(Allocation.P001.group)[1].name)
    assert(c.meta.session_id and #c.meta.session_id > 0)
end)

test("unexpected control exception releases input and guards interrupted session",function()
    local c,e,s=fixture()
    c:approveSetup()
    eq(e.lockEnabled,true)
    local ok,err=c:guard(function()error("Injected native API failure")end)
    eq(ok,nil)
    assert(tostring(err):find("Injected native API failure",1,true))
    eq(c.fatal,true)
    eq(e.lockEnabled,false)
    eq(c.mask,nil)
    eq(s.interruptedCalls,1)
end)

test("unexpected timer callback error cannot leave input locked",function()
    local c,e,s=fixture()
    c:approveSetup()
    c:after("injected",0.01,function()error("Injected timer failure")end)
    e.advance(0.02)
    eq(c.fatal,true)
    eq(e.lockEnabled,false)
    eq(s.interruptedCalls,1)
end)

test("unexpected audio completion error invokes protected cleanup",function()
    local c,e,s=fixture()
    startPrompt(c,e)
    c.model.waitReveal=function()error("Injected audio completion failure")end
    e.sound.callback(true)
    eq(c.fatal,true)
    eq(e.lockEnabled,false)
    eq(s.interruptedCalls,1)
    eq(e.playCalls,1)
end)

test("loader chains unrelated shutdown once and does not retain stale HCI hooks",function()
    local names={"controller","config","model","storage","materials","allocation"}
    local savedModules={}
    for _,name in ipairs(names) do savedModules[name]=package.loaded["study."..name] end
    local oldRequire,oldHs,oldPath=require,hs,package.path
    local oldController,oldHook,oldPrevious=HCI2000Controller,HCI2000ShutdownHook,HCI2000PreviousShutdown
    local created,previousCalls={},0
    local fakeHs={shutdownCallback=function()previousCalls=previousCalls+1 end}
    _G.hs=fakeHs;_G.HCI2000Controller=nil;_G.HCI2000ShutdownHook=nil;_G.HCI2000PreviousShutdown=nil
    _G.require=function(name)
        if name~="study.controller" then return oldRequire(name) end
        return {new=function()
            local c={shutdowns=0,installs=0}
            function c:shutdown()self.shutdowns=self.shutdowns+1 end
            function c:install()self.installs=self.installs+1 end
            function c:guard(fn)return fn()end
            created[#created+1]=c
            return c
        end}
    end
    local ok,message=pcall(function()
        assert(loadfile(PACKAGE_ROOT.."/init.lua"))()
        assert(loadfile(PACKAGE_ROOT.."/init.lua"))()
        eq(#created,2)
        eq(created[1].shutdowns,1,"Repeated dofile stops the prior instance")
        fakeHs.shutdownCallback()
        eq(created[1].shutdowns,1,"Shutdown hook must not invoke stale controller")
        eq(created[2].shutdowns,1)
        eq(previousCalls,1)
        eq(created[1].installs,1);eq(created[2].installs,1)
    end)
    _G.require=oldRequire;_G.hs=oldHs;package.path=oldPath
    _G.HCI2000Controller=oldController;_G.HCI2000ShutdownHook=oldHook;_G.HCI2000PreviousShutdown=oldPrevious
    for _,name in ipairs(names) do package.loaded["study."..name]=savedModules[name] end
    if not ok then error(message) end
end)

test("timeout with wrong selections retains counts without inventing no-selection",function()
    local c,e,s=fixture()
    running(c,e)
    e.title="Wrong tab";c:poll()
    e.advance(c.cfg.timeoutSeconds)
    local r=s.trials[1]
    eq(r.status,"timeout");eq(r.total_tab_switches,1);eq(r.incorrect_selections,1)
    eq(r.first_selection_correct,false);eq(r.no_selection,nil)
    eq(r.retrieval_time_s,nil);eq(r.aux_incorrect_pages[1],"Wrong tab")
end)

test("timeout without observable selection leaves first correctness and no-selection unknown",function()
    local c,e,s=fixture()
    running(c,e);e.advance(c.cfg.timeoutSeconds)
    eq(s.trials[1].first_selection_correct,nil);eq(s.trials[1].no_selection,nil)
    eq(s.trials[1].total_tab_switches,0)
end)

test("participant break does not invent technical loss",function()
    local c,e,s=fixture()
    running(c,e);c:emergency("Participant requests a break")
    eq(s.trials[1].status,"interrupted");eq(s.trials[1].technical_loss,nil)
    eq(s.trials[1].retrieval_time_s,nil)
end)

test("disabled detector leaves unavailable selection counts blank",function()
    local c,e,s=fixture()
    c.cfg.autoDetectTarget=false
    running(c,e);c:finish("completed_manual")
    eq(s.trials[1].total_tab_switches,nil);eq(s.trials[1].aux_selection_count,nil)
    eq(s.trials[1].first_selection_correct,nil);eq(s.trials[1].retrieval_time_s,nil)
end)

test("endpoint is captured before event disk latency",function()
    local c,e,s=fixture()
    running(c,e)
    local onset=c.revealTime
    local event=s.event
    function s:event(name,ctx)
        if name=="TITLE_CHANGE_OBSERVED" then e.time=e.time+0.6 end
        return event(self,name,ctx)
    end
    e.time=onset+0.2;e.title=c.model:currentTrial().targetTitle;c:poll()
    assert(math.abs(s.trials[1].retrieval_time_s-0.2)<1e-8)
    assert(math.abs(s.trials[1].auto_detection_elapsed_s-0.2)<1e-8)
end)

test("reveal timestamp excludes checkpoint disk latency before mask removal",function()
    local c,e,s=fixture()
    startPrompt(c,e);e.sound.callback(true)
    local checkpoint=s.checkpoint
    function s:checkpoint(snapshot)
        if snapshot.phase=="RUNNING" then
            assert(c.mask==nil,"Mask must already be hidden before the running checkpoint")
            e.time=e.time+0.7
        end
        return checkpoint(self,snapshot)
    end
    e.advance(Config.postPromptDelaySeconds)
    assert(c.hideReturnedTime>=c.revealTime)
    assert(c.hideReturnedTime-c.revealTime<1e-8)
end)

test("observed target beyond deadline remains an incomplete software outcome",function()
    local c,e,s=fixture()
    running(c,e)
    e.time=c.revealTime+c.cfg.timeoutSeconds+0.01
    e.title=c.model:currentTrial().targetTitle;c:poll()
    eq(s.trials[1].status,"timeout");eq(s.trials[1].retrieval_time_s,nil)
end)

test("returning to neutral is incorrect; repeated active-title samples do not add selections",function()
    local c,e,s=fixture()
    running(c,e)
    e.title="Wrong tab";c:poll();c:poll()
    e.title="Study Start";c:poll();c:poll()
    e.title=c.model:currentTrial().targetTitle;c:poll()
    eq(s.trials[1].total_tab_switches,3);eq(s.trials[1].incorrect_selections,2)
    eq(s.trials[1].first_selection_correct,false)
end)

test("accessibility transitions between polls are observed and deduplicated",function()
    local c,e,s=fixture()
    local observer={running=false}
    function observer:callback(fn)self.fn=fn end
    function observer:addWatcher()return self end
    function observer:start()self.running=true end
    function observer:isRunning()return self.running end
    function observer:stop()self.running=false end
    c.hs.axuielement={observer={new=function()return observer end},windowElement=function(w)return w end}
    c.hs.window.get(7):application().pid=function()return 321 end
    running(c,e)
    e.title="Wrong tab";observer.fn()
    e.title="Study Start";observer.fn()
    e.title=c.model:currentTrial().targetTitle;observer.fn()
    eq(s.trials[1].detection_mode,"accessibility_and_poll")
    eq(s.trials[1].total_tab_switches,3);eq(s.trials[1].incorrect_selections,2)
    eq(observer.running,false)
end)

test("unsupported accessibility notifications retain honest polling fallback",function()
    local c,e,s=fixture()
    c.hs.axuielement={observer={new=function()error("not supported")end}}
    running(c,e);e.title=c.model:currentTrial().targetTitle;c:poll()
    eq(s.trials[1].detection_mode,"poll_only")
end)

test("observer fallback logging failure cannot reveal or relock a fatal trial",function()
    local c,e,s=fixture()
    c.hs.axuielement={observer={new=function()error("not supported")end}}
    startPrompt(c,e);s.failEvent="TITLE_OBSERVER_UNAVAILABLE"
    e.sound.callback(true);e.advance(Config.postPromptDelaySeconds)
    eq(c.fatal,true);eq(e.lockEnabled,false);eq(c.mask,nil)
    assert(c.model.phase~="RUNNING")
end)

test("lost mouse tap before reveal interrupts rather than starting unprotected",function()
    local c,e,s=fixture()
    startPrompt(c,e);c.mouseTap.enabled=false
    e.sound.callback(true);e.advance(Config.postPromptDelaySeconds)
    eq(c.model.phase,"PAUSED");eq(s.trials[1].status,"interrupted")
    eq(s.trials[1].timed_started,false)
end)

test("observed polling gaps are recorded rather than claiming 50ms precision",function()
    local c,e,s=fixture()
    running(c,e);e.time=c.revealTime+0.4;c:poll()
    e.title=c.model:currentTrial().targetTitle;c:poll()
    assert(s.trials[1].max_poll_gap_s>=0.39)
    local seen=false
    for _,event in ipairs(s.events) do if event.name=="POLL_GAP" then seen=true end end
    eq(seen,true)
end)

test("trial timeout is 20 seconds from reveal, excluding the audio prompt",function()
    local c,e,s=fixture()
    eq(c.cfg.timeoutSeconds,20)
    startPrompt(c,e);e.advance(12)
    eq(c.model.phase,"PROMPT")
    e.sound.callback(true);e.advance(Config.postPromptDelaySeconds)
    local reveal=c.revealTime
    e.advance(19.99);eq(c.model.phase,"RUNNING")
    e.advance(0.02);eq(c.model.phase,"OUTCOME")
    eq(s.trials[1].status,"timeout");eq(s.trials[1].retrieval_time_s,nil)
    assert(math.abs(s.trials[1].observed_duration_s-20)<1e-6)
end)

test("target mouse-down followed by completion still delivers its mouse-up to Chrome",function()
    local c,e,s=fixture()
    running(c,e)
    eq(c.clickTraceTap.callback(e.mouseEvent("leftMouseDown")),false)
    e.buttons={[1]=true,left=true}
    e.title=c.model:currentTrial().targetTitle;c:poll()
    eq(c.model.phase,"OUTCOME");assert(c.mouseTap)
    e.buttons={}
    eq(c.mouseTap.callback(e.mouseEvent("leftMouseUp")),false,"Matching release must not be swallowed")
    e.advance(Config.outcomeHoldSeconds)
    eq(c.model.phase,"READY");eq(#s.trials,1)
    local found=false
    for _,event in ipairs(s.events) do
        if event.name=="MOUSE_INPUT_TRACE" then
            for _,input in ipairs(event.context.detail.events) do
                if input.decision=="pass_existing_release" then found=true end
            end
        end
    end
    eq(found,true,"The passed release must be auditable")
end)

test("right and extra buttons preserve only the release of a pre-lock press",function()
    for _,case in ipairs({{index=2,name="rightMouseUp",button=1},{index=5,name="otherMouseUp",button=4}}) do
        local c,e=fixture()
        e.buttons={[case.index]=true}
        assert(c:lock())
        e.buttons={}
        eq(c.mouseTap.callback(e.mouseEvent(case.name,case.button)),false)
        eq(c.mouseTap.callback(e.mouseEvent(case.name,case.button)),true,"Only one matching release passes")
    end
end)

test("new masked clicks remain blocked across repeated lock calls",function()
    local c,e=fixture()
    assert(c:lock())
    eq(c.mouseTap.callback(e.mouseEvent("leftMouseDown")),true)
    e.buttons={[1]=true}
    local original=c.mouseTap
    assert(c:lock());eq(c.mouseTap,original,"Retain the gate and button history")
    e.buttons={}
    eq(c.mouseTap.callback(e.mouseEvent("leftMouseUp")),true)
end)

test("held target click delays reset until release without extending retrieval time",function()
    local c,e,s=fixture()
    running(c,e)
    e.time=c.revealTime+0.4;e.buttons={[1]=true}
    e.title=c.model:currentTrial().targetTitle;c:poll()
    e.advance(Config.outcomeHoldSeconds+0.1)
    eq(c.model.phase,"OUTCOME");eq(c.mask,nil)
    eq(e.focusTabCalls,1,"No neutral reset while the target click is held")
    assert(math.abs(s.trials[1].retrieval_time_s-0.4)<1e-8)
    e.buttons={};eq(c.mouseTap.callback(e.mouseEvent("leftMouseUp")),false)
    e.advance(0.03);eq(c.model.phase,"READY")
    assert(math.abs(s.trials[1].retrieval_time_s-0.4)<1e-8)
end)

test("unreleased outcome click stops safely without a second outcome or replay",function()
    local c,e,s=fixture()
    c.cfg.autoAdvance=true
    running(c,e);e.buttons={[1]=true}
    e.title=c.model:currentTrial().targetTitle;c:poll()
    e.advance(Config.outcomeHoldSeconds+Config.mouseReleaseWaitSeconds+0.1)
    eq(c.model.phase,"PAUSED");eq(c.model.trialIndex,2)
    eq(#s.trials,1);eq(e.playCalls,1);eq(e.lockEnabled,false)
end)

test("a held button before reset retains the unexposed trial",function()
    local c,e,s=fixture()
    c:approveSetup();e.buttons={[1]=true};c:startTrial()
    eq(c.model.phase,"PAUSED");eq(c.model.trialIndex,1)
    eq(#s.trials,0);eq(e.playCalls,0)
end)

test("premature held click cannot leak into the timed trial at reveal",function()
    local c,e,s=fixture()
    startPrompt(c,e)
    eq(c.mouseTap.callback(e.mouseEvent("leftMouseDown")),true)
    e.buttons={[1]=true}
    e.sound.callback(true);e.advance(Config.postPromptDelaySeconds)
    eq(c.model.phase,"PAUSED");eq(c.model.trialIndex,2)
    eq(s.trials[1].status,"interrupted");eq(s.trials[1].timed_started,false)
end)

test("a fully blocked pre-reveal click does not eat the first real click",function()
    local c,e,s=fixture()
    startPrompt(c,e)
    eq(c.mouseTap.callback(e.mouseEvent("leftMouseDown")),true)
    eq(c.mouseTap.callback(e.mouseEvent("leftMouseUp")),true)
    e.sound.callback(true);e.advance(Config.postPromptDelaySeconds)
    eq(c.mouseTap,nil)
    eq(c.clickTraceTap.callback(e.mouseEvent("leftMouseDown")),false)
    eq(c.clickTraceTap.callback(e.mouseEvent("leftMouseUp")),false)
    e.title=c.model:currentTrial().targetTitle;c:poll()
    eq(s.trials[1].total_tab_switches,1);eq(s.trials[1].first_selection_correct,true)
end)

test("Setup activates Chrome without a synthetic click and checks app activity",function()
    local c,e,s=fixture()
    e.inactiveApp=true
    c.hs.eventtap.leftClick=function()error("Synthetic study clicks are forbidden")end
    startPrompt(c,e)
    eq(e.activated,true);eq(e.inactiveApp,false)
    e.inactiveApp=true -- Window can still be geometrically foremost, app inactive.
    e.sound.callback(true);e.advance(Config.postPromptDelaySeconds)
    eq(c.model.phase,"PAUSED");eq(s.trials[1].timed_started,false)
end)

test("click trace is diagnostic only and does not count clicks as selections",function()
    local c,e,s=fixture()
    running(c,e)
    for _=1,2 do
        eq(c.clickTraceTap.callback(e.mouseEvent("leftMouseDown")),false)
        eq(c.clickTraceTap.callback(e.mouseEvent("leftMouseUp")),false)
    end
    e.title=c.model:currentTrial().targetTitle;c:poll()
    eq(s.trials[1].total_tab_switches,1)
    eq(s.trials[1].incorrect_selections,0)
end)

test("queued release is preserved even when the instantaneous physical poll is already up",function()
    local c,e=fixture()
    running(c,e)
    c.clickTraceTap.callback(e.mouseEvent("leftMouseDown"))
    e.buttons={} -- Physical release happened; its event has not reached Chrome yet.
    e.title=c.model:currentTrial().targetTitle;c:poll()
    e.advance(Config.outcomeHoldSeconds+0.05)
    eq(c.model.phase,"OUTCOME","Do not reset before the queued release is delivered")
    eq(c.mouseTap.callback(e.mouseEvent("leftMouseUp")),false)
    e.advance(0.03);eq(c.model.phase,"READY")
end)

test("matching-release protection also works with diagnostic logging disabled",function()
    local c,e,s=fixture()
    c.cfg.mouseClickDiagnostics=false
    running(c,e)
    c.clickTraceTap.callback(e.mouseEvent("leftMouseDown"))
    e.title=c.model:currentTrial().targetTitle;c:poll()
    eq(c.mouseTap.callback(e.mouseEvent("leftMouseUp")),false)
    for _,event in ipairs(s.events) do assert(event.name~="MOUSE_INPUT_TRACE") end
end)

test("a single click completes the next automatic trial after releasing the prior click",function()
    local c,e,s=fixture()
    c.cfg.autoAdvance=true
    running(c,e)
    for trialIndex=1,2 do
        eq(c.clickTraceTap.callback(e.mouseEvent("leftMouseDown")),false)
        e.buttons={[1]=true}
        e.title=c.model:currentTrial().targetTitle;c:poll()
        e.buttons={};eq(c.mouseTap.callback(e.mouseEvent("leftMouseUp")),false)
        eq(#s.trials,trialIndex);eq(s.trials[trialIndex].total_tab_switches,1)
        e.advance(Config.outcomeHoldSeconds+Config.interTrialDelaySeconds+0.02)
        if trialIndex==1 then
            eq(c.model.phase,"PROMPT")
            e.sound.callback(true);e.advance(Config.postPromptDelaySeconds)
        end
    end
end)

test("pause with a held click does not leave stale button history on resume",function()
    local c,e,s=fixture()
    running(c,e)
    c.clickTraceTap.callback(e.mouseEvent("leftMouseDown"));e.buttons={[1]=true}
    c:emergency("Participant break")
    e.buttons={} -- Natural release after emergency, with no controller tap installed.
    c:setup();running(c,e)
    eq(c.model.phase,"RUNNING");eq(c.model.trialIndex,2)
    eq(c.mouseTap,nil);eq(#s.trials,1)
end)

return results
