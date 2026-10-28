-- Behavioral cross-module checks. Requires the isolated bridges in run_checks.py.
-- No real Hammerspoon or browser automation is invoked by this suite.
local Model = require("study.model")
local Materials = require("study.materials")
local Storage = require("study.storage")
local Allocation = require("study.allocation")
local results = {}
local hs = {
    fs = {attributes = TEST_BRIDGE.attributes, mkdir = TEST_BRIDGE.mkdir, rmdir = TEST_BRIDGE.rmdir},
    json = {encode = TEST_BRIDGE.json_encode, decode = TEST_BRIDGE.json_decode},
}

local function equal(actual, expected, label)
    assert(actual == expected, (label or "Value") .. ": expected " .. tostring(expected)
        .. ", got " .. tostring(actual))
end
local function test(name, body)
    TEST_FAIL_OPEN_PREFIX = nil
    local ok, message = xpcall(body, debug.traceback)
    TEST_FAIL_OPEN_PREFIX = nil
    results[#results + 1] = {name = name, passed = ok, error = ok and nil or tostring(message)}
end
local function meta(group, mode, participant, session)
    return {mode = mode or "test", participant = participant or "TEST001", group = group or 1,
        session_id = session or "RUN1", plan = Materials.buildPlan(group or 1),
        versions = {controller = "test-build", materials = Materials.version}}
end
local function makeStore(caseName, metadata)
    local base = TEST_ROOT .. "/" .. caseName
    local store, message = Storage.create(base, metadata or meta(), hs)
    assert(store, message)
    return store, base
end
local function rows(store, filename)
    return TEST_BRIDGE.csv_rows(store.path .. "/" .. filename)
end
local function running(model)
    assert(model:ready()); assert(model:prepare()); assert(model:prompt())
    assert(model:waitReveal()); assert(model:reveal())
end
local function finishOne(model, store, status)
    local ok, record = model:finish(status or "completed_auto", "Dummy outcome")
    assert(ok, record)
    record.aux_selection_count = 1
    record.aux_incorrect_count = 0
    record.aux_first_correct = 1
    record.auto_detection_elapsed_s = 0.125
    assert(store:trial(record))
    assert(store:checkpoint(model:snapshot()))
    return record
end

test("all four paper groups complete exactly 24 scheduled entries with verified identity", function()
    local allPairs = {}
    for group = 1, 4 do
        local plan = Materials.buildPlan(group)
        local model = Model.new(plan)
        local store = makeStore("full-24-group-" .. group, meta(group))
        local seen = {}
        for blockIndex, block in ipairs(plan) do
            equal(#block.trials, 6)
            local pair = block.name .. "/" .. block.contentSet
            allPairs[pair] = (allPairs[pair] or 0) + 1
            for trialIndex, trial in ipairs(block.trials) do
                running(model)
                assert(store:event("PROMPT_STARTED", {phase = "PROMPT", prompt_exposed = true}))
                local record = finishOne(model, store)
                equal(record.condition, block.name)
                equal(record.content_set, block.contentSet)
                equal(record.target_id, trial.targetID)
                equal(record.target_title, trial.targetTitle)
                equal(record.trial_id, "T" .. trialIndex)
                equal(model.phase, "OUTCOME")
                equal(model.trialIndex, trialIndex, "Display hold retains current entry")
                assert(not model:prepare(), "Display hold must not start another trial")
                assert(not seen[record.scheduled_key], "Duplicate scheduled outcome")
                seen[record.scheduled_key] = true
                assert(model:settleOutcome())
            end
            equal(model.phase, "BLOCK_COMPLETE")
            assert(not model:prepare(), "Block transition requires facilitator action")
            assert(model:nextBlock())
        end
        equal(model.phase, "SESSION_COMPLETE")
        equal(#model.outcomes, 24)
        equal(#rows(store, "trials_aux.csv"), 24)
        local coded = rows(store, "video_coding.csv")
        equal(#coded, 24)
        for _, row in ipairs(coded) do
            equal(row.retrieval_time_s, "", "Final retrieval time must await video coding")
            equal(row.first_selection_correct, "", "Polling accuracy must not become final")
            equal(row.total_tab_switches, "", "Polling counts must not become final")
        end
        assert(store:close("completed"))
    end
    local count = 0
    for _, occurrences in pairs(allPairs) do equal(occurrences, 1); count = count + 1 end
    equal(count, 16, "Every condition receives every content set across the four groups")
end)

test("paper condition orders and six-trial schedules are preserved", function()
    local expectedConditions = {
        {"H-L", "H-H", "V-L", "V-H"}, {"H-H", "H-L", "V-H", "V-L"},
        {"V-L", "V-H", "H-L", "H-H"}, {"V-H", "V-L", "H-H", "H-L"},
    }
    local expectedSets = {{"A","B","C","D"},{"C","D","A","B"},
        {"D","C","B","A"},{"B","A","D","C"}}
    local schedules = {A = "P1P2P1P3P4P5", B = "P2P3P4P2P5P1",
        C = "P3P4P5P1P3P2", D = "P4P5P1P2P3P4"}
    for group = 1, 4 do
        for index, block in ipairs(Materials.buildPlan(group)) do
            equal(block.name, expectedConditions[group][index])
            equal(block.contentSet, expectedSets[group][index])
            local identifiers = {}
            for _, trial in ipairs(block.trials) do identifiers[#identifiers + 1] = trial.targetID end
            equal(table.concat(identifiers), schedules[block.contentSet])
            equal(#block.taskOrder, block.expectedTabCount - 1)
            equal(block.expectedTabCount, block.tabLoad == "low" and 6 or 16)
        end
    end
end)

test("frozen allocation has four per group, permuted blocks, balanced familiarization", function()
    local groups, practice = {}, {}
    for block = 1, 4 do
        local inBlock = {}
        for offset = 1, 4 do
            local number = (block - 1) * 4 + offset
            local entry = assert(Allocation[string.format("P%03d", number)])
            equal(entry.allocationBlock, block)
            assert(not inBlock[entry.group], "Each allocation block needs each sequence once")
            inBlock[entry.group] = true
            groups[entry.group] = (groups[entry.group] or 0) + 1
            assert(entry.practiceFirst == "H" or entry.practiceFirst == "V")
            local key = entry.group .. entry.practiceFirst
            practice[key] = (practice[key] or 0) + 1
        end
    end
    for group = 1, 4 do
        equal(groups[group], 4)
        equal(practice[group .. "H"], 2)
        equal(practice[group .. "V"], 2)
    end
end)

for _, phase in ipairs({"PROMPT", "WAIT_REVEAL", "RUNNING"}) do
    test("interruption in " .. phase .. " persists exposure and consumes exactly once", function()
        local model = Model.new(Materials.buildPlan(1))
        local store = makeStore("interrupt-" .. phase)
        assert(model:ready()); assert(model:prepare()); assert(model:prompt())
        if phase ~= "PROMPT" then assert(model:waitReveal()) end
        if phase == "RUNNING" then assert(model:reveal()) end
        local ok, record = model:interrupt("Deliberate interruption")
        assert(ok, record); assert(store:trial(record))
        equal(record.prompt_exposed, true)
        equal(record.timed_interval_started, phase == "RUNNING")
        equal(model.phase, "PAUSED"); equal(model.trialIndex, 2)
        assert(not model:prepare(), "Pause must not automatically replay")
        assert(model:interrupt("Repeated emergency")); equal(#model.outcomes, 1)
        assert(model:resume()); assert(model:prepare()); assert(model:prompt())
        equal(model:currentTrial().id, "T2")
        local trialRows = rows(store, "trials_aux.csv")
        equal(#trialRows, 1)
        equal(trialRows[1].prompt_exposed, "true")
        equal(trialRows[1].timed_started, tostring(phase == "RUNNING"))
    end)
end

test("unexposed setup failure retains the planned entry without an outcome", function()
    local model = Model.new(Materials.buildPlan(1))
    local store = makeStore("unexposed-failure")
    assert(model:ready()); assert(model:prepare()); assert(model:interrupt("Audio file unavailable"))
    equal(model.trialIndex, 1); equal(#model.outcomes, 0)
    assert(store:checkpoint(model:snapshot()))
    equal(#rows(store, "trials_aux.csv"), 0)
    assert(model:resume()); assert(model:prepare())
    equal(model:currentTrial().id, "T1")
end)

test("break during outcome hold preserves one completion and resumes at the next entry", function()
    local model = Model.new(Materials.buildPlan(1))
    local store = makeStore("pause-outcome")
    running(model); finishOne(model, store)
    assert(model:pause("Requested break")); equal(model.phase, "PAUSED")
    equal(#model.outcomes, 1); equal(model.trialIndex, 2)
    assert(model:resume()); equal(model.phase, "READY")
    equal(#rows(store, "trials_aux.csv"), 1)
end)

test("zero, false, missing values and quoted event text survive CSV round trip", function()
    local store = makeStore("csv-values")
    assert(store:event("OBSERVATION", {elapsed_s = 0, aux_selection_count = 0,
        aux_incorrect_count = 0, aux_first_correct = 0, detail = 'Wrong, "quoted"\nsecond line'}))
    local event = rows(store, "events.csv")[1]
    equal(event.elapsed_s, "0"); equal(event.aux_selection_count, "0")
    equal(event.aux_first_correct, "0"); equal(event.observed_title, "")
    equal(event.detail, 'Wrong, "quoted"\nsecond line')
    assert(store:trial({block = 1, condition = "H-L", content_set = "A", trial = "T1",
        target_id = "P1", target_title = "Target", status = "interrupted",
        prompt_exposed = true, timed_started = false, aux_selection_count = 0}))
    local trial = rows(store, "trials_aux.csv")[1]
    equal(trial.timed_started, "false"); equal(trial.aux_selection_count, "0")
    equal(trial.auto_detection_elapsed_s, ""); equal(trial.manual_ack_elapsed_s, "")
end)

test("manual completion and timeout never fill final video-coded measures", function()
    local store = makeStore("manual-timeout")
    for index, status in ipairs({"completed_manual", "timeout"}) do
        assert(store:trial({block = 1, condition = "H-L", content_set = "A", trial = "T" .. index,
            target_id = "P" .. index, target_title = "Target " .. index, status = status,
            prompt_exposed = true, timed_started = true, manual_ack_elapsed_s = index == 1 and 0.9 or nil,
            aux_selection_count = 0, aux_incorrect_count = 0}))
    end
    for _, record in ipairs(rows(store, "video_coding.csv")) do
        equal(record.retrieval_time_s, ""); equal(record.first_selection_correct, "")
        equal(record.total_tab_switches, ""); equal(record.no_selection, "")
    end
    equal(rows(store, "trials_aux.csv")[2].manual_ack_elapsed_s, "")
end)

test("malformed existing log header is rejected and records are not silently appended", function()
    local store = makeStore("bad-header")
    local path = store.path .. "/events.csv"
    TEST_BRIDGE.write_file(path, ",,,\n,,\n")
    local before = TEST_BRIDGE.read_file(path)
    local ok, message = store:event("WILL_NOT_APPEND", {})
    assert(not ok and tostring(message):find("header/schema mismatch", 1, true))
    equal(TEST_BRIDGE.read_file(path), before)
    assert(not store:checkpoint({phase = "READY"}), "Storage must remain stopped after failure")
end)

test("write failure fails closed and retains an active-session guard", function()
    local store, base = makeStore("write-failure")
    TEST_FAIL_OPEN_PREFIX = store.path
    local ok, message = store:event("FAIL", {})
    assert(not ok and tostring(message):find("Injected write failure", 1, true))
    TEST_FAIL_OPEN_PREFIX = nil
    assert(not store:event("AFTER_FAILURE", {}))
    local info = assert(Storage.inspectParticipant(base, "test", "TEST001", hs))
    equal(info.blocked, true)
end)

test("fresh reload is blocked instead of replaying an active or interrupted participant", function()
    local store, base = makeStore("reload-block")
    local replacement, message = Storage.create(base, meta(1, "test", "TEST001", "RUN2"), hs)
    assert(not replacement and message)
    assert(store:markInterrupted("Controller reload during prompt"))
    local info = assert(Storage.inspectParticipant(base, "test", "TEST001", hs))
    equal(info.blocked, true); equal(info.active.status, "interrupted")
    assert(not Storage.create(base, meta(1, "test", "TEST001", "RUN3"), hs))
end)

test("main participant completion cannot be silently collected a second time", function()
    local store, base = makeStore("main-repeat", meta(1, "main", "P001", "RUN1"))
    local model = Model.new(Materials.buildPlan(1))
    for block = 1, 4 do
        for trial = 1, 6 do
            running(model); finishOne(model, store); assert(model:settleOutcome())
        end
        assert(model:nextBlock())
    end
    assert(store:close("completed"))
    local info = assert(Storage.inspectParticipant(base, "main", "P001", hs))
    equal(info.blocked, true); assert(info.completed)
    assert(not Storage.create(base, meta(1, "main", "P001", "RUN2"), hs))
end)

test("main session cannot be finalized before all scheduled entries have an outcome", function()
    local store, base = makeStore("main-incomplete", meta(1, "main", "P002", "RUN1"))
    local ok, message = store:close("completed")
    assert(not ok and tostring(message):find("24 scheduled trials", 1, true))
    equal(assert(Storage.inspectParticipant(base, "main", "P002", hs)).blocked, true)
end)

test("clean test close permits a new unique run but never reuses an existing session path", function()
    local store, base = makeStore("fresh-session")
    assert(store:close("completed"))
    assert(not Storage.create(base, meta(), hs))
    local new = assert(Storage.create(base, meta(1, "test", "TEST001", "RUN2"), hs))
    assert(new:close("cancelled_unexposed"))
end)

test("exposure cannot be erased through cancelled_unexposed", function()
    local store, base = makeStore("false-unexposed")
    assert(store:event("PROMPT_STARTED", {prompt_exposed = true}))
    assert(not store:close("cancelled_unexposed"))
    equal(assert(Storage.inspectParticipant(base, "test", "TEST001", hs)).blocked, true)
end)

test("duplicate terminal outcome is rejected without a second video-coding row", function()
    local store = makeStore("duplicate-row")
    local record = {block = 1, condition = "H-L", content_set = "A", trial = "T1",
        target_id = "P1", target_title = "Target", status = "completed_auto"}
    assert(store:trial(record)); assert(not store:trial(record))
    equal(#rows(store, "trials_aux.csv"), 1)
    equal(#rows(store, "video_coding.csv"), 1)
end)

test("malformed participant markers fail closed and are preserved", function()
    local store, base = makeStore("malformed-marker")
    local marker = store.participantPath .. "/ACTIVE.json"
    TEST_BRIDGE.write_file(marker, "not valid json")
    local info, message = Storage.inspectParticipant(base, "test", "TEST001", hs)
    assert(not info and tostring(message):find("Malformed JSON", 1, true))
    equal(TEST_BRIDGE.read_file(marker), "not valid json")
end)

test("unsafe identifiers and invalid allocation groups are rejected before creating runs", function()
    local base = TEST_ROOT .. "/invalid-input"
    for _, participant in ipairs({"", "../outside", "person/name", "person name"}) do
        assert(not Storage.create(base, meta(1, "test", participant), hs))
    end
    for _, group in ipairs({0, 5, 1.5}) do
        local metadata = meta(); metadata.group = group
        assert(not Storage.create(base, metadata, hs))
    end
    local metadata = meta(); metadata.session_id = "../outside"
    assert(not Storage.create(base, metadata, hs))
end)

test("non-finite observations are rejected rather than written as valid numbers", function()
    local store = makeStore("non-finite")
    assert(not store:event("INVALID_NUMBER", {elapsed_s = math.huge}))
    equal(#rows(store, "events.csv"), 0)
end)

return results
