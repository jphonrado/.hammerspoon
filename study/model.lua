-- Pure trial lifecycle. No Hammerspoon APIs, clocks, files or UI live here.
-- A scheduled entry is consumed once its prompt may have been heard, even when
-- its timed interval never began. Unexposed preparation failures retain it.
local Model = {}
Model.__index = Model

local function clone(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, item in pairs(value) do result[clone(key)] = clone(item) end
    return result
end

local function nonempty(value)
    return type(value) == "string" and value:match("%S") ~= nil
end

local function reject(self, action)
    return nil, action .. " is not permitted while phase is " .. self.phase
end

local function checkedPlan(plan)
    assert(type(plan) == "table" and #plan > 0, "A nonempty block plan is required")
    local result = clone(plan)
    for index, block in ipairs(result) do
        assert(type(block) == "table", "Invalid block " .. index)
        assert(type(block.trials) == "table" and #block.trials > 0,
            "Block " .. index .. " must contain scheduled trials")
        for trialIndex, trial in ipairs(block.trials) do
            assert(type(trial) == "table", "Invalid scheduled trial " .. trialIndex)
        end
    end
    return result
end

function Model.new(plan, opts)
    local self = setmetatable({}, Model)
    self.plan = checkedPlan(plan)
    self.phase = "SETUP"
    self.blockIndex = 1
    self.trialIndex = 1
    self.exposed = false
    self.currentRecord = nil
    self.outcomes = {}
    self.finishedKeys = {}
    self.resumePhase = nil
    self.lastInterruption = nil
    self.lastOutcome = nil
    self.options = opts or {}
    return self
end

function Model:currentBlock()
    return self.plan[self.blockIndex]
end

function Model:currentTrial()
    local block = self:currentBlock()
    return block and block.trials[self.trialIndex] or nil
end

function Model:scheduledKey()
    if not self:currentTrial() then return nil end
    return tostring(self.blockIndex) .. ":" .. tostring(self.trialIndex)
end

function Model:ready()
    if self.phase == "READY" then return true end
    if self.phase == "SETUP" or (self.phase == "PAUSED"
        and (self.resumePhase == "READY" or self.resumePhase == "SETUP")) then
        self.phase = "READY"
        self.resumePhase = nil
        return true
    end
    return reject(self, "ready")
end

function Model:prepare()
    if self.phase ~= "READY" then return reject(self, "prepare") end
    if not self:currentTrial() then return nil, "No scheduled trial is available" end
    if self.finishedKeys[self:scheduledKey()] then
        return nil, "The current scheduled trial already has a terminal outcome"
    end
    self.phase = "PREPARING"
    self.exposed = false
    self.currentRecord = nil
    self.lastInterruption = nil
    return true
end

function Model:prompt()
    if self.phase ~= "PREPARING" then return reject(self, "prompt") end
    local block, trial = self:currentBlock(), self:currentTrial()
    if not block or not trial then return nil, "No scheduled trial is available" end
    -- The adapter calls this before starting playback. A failed or uncertain
    -- playback therefore cannot silently erase possible prompt exposure.
    self.exposed = true
    self.currentRecord = {
        scheduled_key = self:scheduledKey(),
        block_index = self.blockIndex,
        trial_index = self.trialIndex,
        condition = block.name or block.condition,
        content_set = block.contentSet or block.content_set,
        trial_id = trial.id or trial.trial_id or ("T" .. self.trialIndex),
        target_id = trial.targetID or trial.target_id,
        target_title = trial.targetTitle or trial.target_title,
        prompt_exposed = true,
        timed_interval_started = false,
        terminal = false,
    }
    self.phase = "PROMPT"
    return true, self.currentRecord
end

function Model:waitReveal()
    if self.phase ~= "PROMPT" then return reject(self, "waitReveal") end
    self.phase = "WAIT_REVEAL"
    return true
end

function Model:reveal()
    if self.phase ~= "WAIT_REVEAL" then return reject(self, "reveal") end
    self.currentRecord.timed_interval_started = true
    self.phase = "RUNNING"
    return true, self.currentRecord
end

function Model:_terminal(status, detail)
    local record = self.currentRecord
    if not record or record.terminal then return nil, "No unfinished exposed trial" end
    if self.finishedKeys[record.scheduled_key] then
        return nil, "Scheduled trial already finalized: " .. record.scheduled_key
    end
    record.status = status
    record.detail = detail or ""
    record.terminal = true
    self.finishedKeys[record.scheduled_key] = true
    self.outcomes[#self.outcomes + 1] = record
    self.lastOutcome = record
    self.exposed = false
    return true, record
end

function Model:finish(status, detail)
    if self.phase ~= "RUNNING" then return reject(self, "finish") end
    if not nonempty(status) then return nil, "A terminal outcome status is required" end
    local ok, record = self:_terminal(status, detail)
    if not ok then return nil, record end
    -- Retain the finished cursor until the adapter has preserved an observable
    -- target-active frame. The cursor is advanced by settleOutcome(), never here.
    self.phase = "OUTCOME"
    return true, record
end

function Model:_advanceConsumed()
    local block = self:currentBlock()
    self.trialIndex = self.trialIndex + 1
    self.currentRecord = nil
    self.exposed = false
    if self.trialIndex > #block.trials then
        self.phase = "BLOCK_COMPLETE"
    else
        self.phase = "READY"
    end
    return self.phase
end

function Model:settleOutcome()
    if self.phase ~= "OUTCOME" then return reject(self, "settleOutcome") end
    self:_advanceConsumed()
    return true
end

function Model:interrupt(reason)
    if self.phase == "SESSION_COMPLETE" then return reject(self, "interrupt") end
    if self.phase == "PAUSED" then return true end
    local interruptedPhase = self.phase
    if self.phase == "OUTCOME" then
        -- An outcome already recorded must not be recorded twice when a pause
        -- or emergency event arrives during the post-outcome display hold.
        self:_advanceConsumed()
    end
    local wasExposed = self.exposed
    local record
    if wasExposed then
        local ok
        ok, record = self:_terminal("interrupted", reason or "Interrupted")
        if not ok then return nil, record end
        self:_advanceConsumed()
    elseif self.phase == "PREPARING" then
        self.phase = "READY"
    end
    self.lastInterruption = {
        reason = reason or "Interrupted",
        phase = interruptedPhase,
        prompt_exposed = wasExposed,
        consumed = wasExposed,
        scheduled_key = record and record.scheduled_key or self:scheduledKey(),
    }
    self.resumePhase = self.phase
    self.phase = "PAUSED"
    return true, record
end

function Model:pause(reason)
    return self:interrupt(reason or "Break requested")
end

function Model:resume()
    if self.phase ~= "PAUSED" then return reject(self, "resume") end
    local target = self.resumePhase
    if target ~= "SETUP" and target ~= "READY" and target ~= "BLOCK_COMPLETE" then
        return nil, "Invalid resume phase: " .. tostring(target)
    end
    self.phase = target
    self.resumePhase = nil
    return true
end

function Model:nextBlock()
    if self.phase ~= "BLOCK_COMPLETE" then return reject(self, "nextBlock") end
    self.blockIndex = self.blockIndex + 1
    self.trialIndex = 1
    self.exposed = false
    self.currentRecord = nil
    self.resumePhase = nil
    if self.blockIndex > #self.plan then
        self.phase = "SESSION_COMPLETE"
    else
        self.phase = "READY"
    end
    return true
end

function Model:resetPreflight()
    local permitted = self.phase == "SETUP" or self.phase == "READY"
        or self.phase == "PREPARING"
        or (self.phase == "PAUSED" and self.resumePhase ~= "BLOCK_COMPLETE")
    if not permitted or self.exposed then return reject(self, "resetPreflight") end
    self.phase = "SETUP"
    self.resumePhase = nil
    self.currentRecord = nil
    return true
end

function Model:snapshot()
    return clone({
        model_version = 1,
        phase = self.phase,
        blockIndex = self.blockIndex,
        trialIndex = self.trialIndex,
        exposed = self.exposed,
        currentRecord = self.currentRecord,
        outcomes = self.outcomes,
        finishedKeys = self.finishedKeys,
        resumePhase = self.resumePhase,
        lastInterruption = self.lastInterruption,
        lastOutcome = self.lastOutcome,
    })
end

return Model
