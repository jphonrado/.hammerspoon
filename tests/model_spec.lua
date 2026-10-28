-- Run from the controller package root: lua tests/model_spec.lua
local Model = require("study.model")
local passed = 0

local function equal(actual, expected, label)
    assert(actual == expected, (label or "Value") .. ": expected "
        .. tostring(expected) .. ", got " .. tostring(actual))
end

local function test(name, body)
    local ok, err = pcall(body)
    if not ok then error(name .. ": " .. tostring(err), 0) end
    passed = passed + 1
    print("PASS " .. name)
end

local function plan(blocks, trials)
    local result = {}
    for b = 1, blocks or 4 do
        result[b] = { name = "Condition" .. b, contentSet = "Set" .. b, trials = {} }
        for t = 1, trials or 6 do
            result[b].trials[t] = { id = "T" .. t, targetID = "P" .. t, targetTitle = "Target " .. t }
        end
    end
    return result
end

local function running(model)
    assert(model:ready())
    assert(model:prepare())
    assert(model:prompt())
    assert(model:waitReveal())
    assert(model:reveal())
end

test("full four-block run consumes exactly 24 trials", function()
    local m = Model.new(plan())
    for b = 1, 4 do
        for t = 1, 6 do
            running(m)
            equal(m.blockIndex, b)
            equal(m.trialIndex, t)
            m.currentRecord.aux_elapsed_s = 0.25
            local ok, record = m:finish("completed_manual", "Observed correct")
            assert(ok)
            equal(record.aux_elapsed_s, 0.25)
            equal(record.timed_interval_started, true)
            equal(m.phase, "OUTCOME")
            equal(m.trialIndex, t, "Cursor retained during display hold")
            assert(not m:finish("completed_manual"), "Duplicate finish must reject")
            assert(m:settleOutcome())
        end
        equal(m.phase, "BLOCK_COMPLETE")
        assert(not m:prepare(), "Next block needs explicit transition")
        assert(m:nextBlock())
    end
    equal(m.phase, "SESSION_COMPLETE")
    equal(#m.outcomes, 24)
    assert(not m:nextBlock())
end)

test("unexposed preparation interruption retains scheduled trial", function()
    local m = Model.new(plan())
    assert(m:ready()); assert(m:prepare())
    assert(m:interrupt("Missing audio before playback"))
    equal(m.phase, "PAUSED")
    equal(m.trialIndex, 1)
    equal(#m.outcomes, 0)
    equal(m.lastInterruption.prompt_exposed, false)
    assert(m:resume())
    equal(m.phase, "READY")
    assert(m:prepare())
end)

test("partial prompt interruption consumes and cannot replay", function()
    local m = Model.new(plan())
    assert(m:ready()); assert(m:prepare()); assert(m:prompt())
    local ok, record = m:interrupt("Partial audio")
    assert(ok)
    equal(record.status, "interrupted")
    equal(record.timed_interval_started, false)
    equal(m.trialIndex, 2)
    equal(m.phase, "PAUSED")
    equal(#m.outcomes, 1)
    assert(not m:prepare(), "A paused procedure cannot start automatically")
    assert(m:resume()); assert(m:prepare())
    equal(m:currentTrial().id, "T2")
end)

test("interruption during post-prompt delay consumes exposed trial", function()
    local m = Model.new(plan())
    assert(m:ready()); assert(m:prepare()); assert(m:prompt()); assert(m:waitReveal())
    assert(m:pause("Break requested"))
    equal(m.trialIndex, 2)
    equal(#m.outcomes, 1)
    equal(m.outcomes[1].timed_interval_started, false)
end)

test("running interruption preserves timed exposure and pauses", function()
    local m = Model.new(plan())
    running(m)
    assert(m:interrupt("Window lost"))
    equal(m.outcomes[1].timed_interval_started, true)
    equal(m.outcomes[1].prompt_exposed, true)
    equal(m.phase, "PAUSED")
    equal(m.trialIndex, 2)
    assert(m:interrupt("Repeated emergency key"))
    equal(#m.outcomes, 1)
end)

test("pause during outcome hold cannot duplicate completed outcome", function()
    local m = Model.new(plan())
    running(m)
    assert(m:finish("completed_auto"))
    assert(m:pause("Break after completion"))
    equal(#m.outcomes, 1)
    equal(m.outcomes[1].status, "completed_auto")
    equal(m.trialIndex, 2)
    equal(m.phase, "PAUSED")
    equal(m.lastInterruption.phase, "OUTCOME")
    assert(m:resume())
    equal(m.phase, "READY")
end)

test("last-trial interruption resumes to block complete", function()
    local m = Model.new(plan(2, 1))
    running(m)
    assert(m:interrupt("Interrupted last entry"))
    equal(m.resumePhase, "BLOCK_COMPLETE")
    assert(not m:ready(), "ready cannot bypass a completed block")
    equal(m.phase, "PAUSED")
    assert(not m:resetPreflight())
    assert(m:resume())
    equal(m.phase, "BLOCK_COMPLETE")
    assert(m:nextBlock())
    equal(m.blockIndex, 2)
    equal(m.trialIndex, 1)
end)

test("illegal jumps and exposed reset are rejected", function()
    local m = Model.new(plan())
    assert(not m:reveal())
    assert(not m:prompt())
    assert(not m:nextBlock())
    assert(m:ready()); assert(m:prepare()); assert(m:prompt())
    assert(not m:resetPreflight())
    assert(not m:finish("timeout"))
    assert(not m:ready())
    equal(m.phase, "PROMPT")
end)

test("snapshot is detached and serializable data", function()
    local m = Model.new(plan())
    running(m)
    assert(m:finish("timeout")); assert(m:settleOutcome())
    local snapshot = m:snapshot()
    equal(snapshot.phase, "READY")
    equal(snapshot.outcomes[1].status, "timeout")
    snapshot.outcomes[1].status = "changed copy"
    equal(m.outcomes[1].status, "timeout")
end)

test("pause in setup returns to setup and requires readiness", function()
    local m = Model.new(plan())
    assert(m:pause("Setup break")); assert(m:resume())
    equal(m.phase, "SETUP")
    assert(not m:prepare())
    assert(m:ready()); assert(m:prepare())
end)

test("rejected empty completion does not consume", function()
    local m = Model.new(plan())
    running(m)
    assert(not m:finish(""))
    equal(m.phase, "RUNNING")
    equal(m.exposed, true)
    equal(#m.outcomes, 0)
end)

test("plan is copied at construction", function()
    local original = plan()
    local m = Model.new(original)
    original[1].trials[1].targetTitle = "Changed externally"
    equal(m:currentTrial().targetTitle, "Target 1")
end)

print("Model tests passed: " .. passed)
return passed
