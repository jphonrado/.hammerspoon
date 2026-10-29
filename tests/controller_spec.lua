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
    local env = {time = 10, timers = {}, title = "Study Start", notices = {},
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
    hs.dialog.blockAlert = function(_,_,first) return first end
    hs.mouse.absolutePosition = function(value)
        if value then env.position = {x = value.x,y = value.y} end
        return {x = env.position.x,y = env.position.y}
    end
    for index,key in ipairs({"leftMouseDown","leftMouseUp","rightMouseDown","rightMouseUp",
        "otherMouseDown","otherMouseUp","mouseMoved","leftMouseDragged",
        "rightMouseDragged","otherMouseDragged","scrollWheel"}) do
        hs.eventtap.event.types[key] = index
    end
    hs.eventtap.new = function(_,callback)
        local tap = {callback = callback, enabled = false}
        function tap:start() self.enabled = true; env.lockEnabled = true end
        function tap:stop() self.enabled = false; env.lockEnabled = false end
        function tap:isEnabled() return self.enabled end
        return tap
    end
    hs.eventtap.keyStroke = function(_,key)
        env.keyStrokeKey = key
        if not env.neutralFails then env.title = "Study Start" end
    end
    local app = {name = function() return "Google Chrome" end}
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
        if not env.neutralFails then env.title = "Study Start"; return true end
        return false
    end
    hs.window.get = function(id) return id == 7 and not env.windowMissing and win or nil end
    hs.window.frontmostWindow = function() return env.front and win or nil end
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

test("adapter main mode remains disabled until explicitly configured",function()
    local c,e = sessionFixture({"main"},false)
    eq(e.createCalls,0)
    eq(c.model,nil)
    eq(e.promptCalls,1)
end)

test("adapter rejects main mode with unverified recording settings",function()
    local c,e = sessionFixture({"main"},true,false)
    eq(e.createCalls,0)
    eq(c.model,nil)
    eq(e.promptCalls,1)
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

return results