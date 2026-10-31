-- Study records: append-only auxiliary observations and a separate coding sheet.
-- No Hammerspoon globals are required: pass hs to create/inspectParticipant.
-- A surviving ACTIVE.json / .session-lock is deliberately NOT auto-resumed.
local M = { SCHEMA_VERSION = "2.0" }
local Store = {}
Store.__index = Store

local COMMON = {
    "session_id", "mode", "participant", "group", "block", "condition",
    "orientation", "tab_load", "content_set", "trial", "target_id", "target_title",
    "is_repeat", "target_task_position", "task_tab_count", "visible_tab_count",
}
local function columns(extra)
    local out = {}
    for _, value in ipairs(COMMON) do out[#out + 1] = value end
    for _, value in ipairs(extra) do out[#out + 1] = value end
    return out
end
M.EVENT_COLUMNS = columns({
    "phase", "event", "wall_epoch", "monotonic_s", "elapsed_s", "observed_title",
    "aux_selection_count", "aux_incorrect_count", "aux_first_correct", "observation_source", "detail",
})
M.TRIAL_COLUMNS = columns({
    "status", "prompt_exposed", "timed_started", "reveal_command_monotonic_s",
    "auto_detection_elapsed_s", "manual_ack_elapsed_s", "aux_selection_count",
    "aux_incorrect_count", "aux_first_correct", "aux_incorrect_pages", "detection_mode",
    "mask_hide_returned_monotonic_s", "endpoint_monotonic_s", "observed_duration_s",
    "max_poll_gap_s", "verification_required", "reason",
})
M.VIDEO_COLUMNS = columns({
    "controller_status", "video_status", "video_file", "video_start_frame",
    "video_target_frame", "frame_rate", "retrieval_time_s", "total_tab_switches",
    "incorrect_selections", "first_selection_correct", "no_selection",
    "technical_loss", "coder", "notes",
})
M.MAIN_COLUMNS = columns({
    "controller_status", "measurement_source", "retrieval_time_s",
    "total_tab_switches", "incorrect_selections", "first_selection_correct",
    "no_selection", "technical_loss", "video_verified", "coder", "notes",
})

local function err(message) return nil, message end
local function present(value) return value ~= nil and tostring(value) ~= "" end
local function pick(...)
    for i = 1, select("#", ...) do
        local value = select(i, ...)
        if value ~= nil then return value end
    end
end
local function join(a, b) return a:gsub("[\\/]+$", "") .. "/" .. b end
local function safePart(value, limit)
    return type(value) == "string" and #value > 0 and #value <= limit
        and value:match("^[A-Za-z0-9][A-Za-z0-9_-]*$") ~= nil
end
local function attrs(hs, path)
    local ok, value = pcall(hs.fs.attributes, path)
    if not ok then return nil end
    return value
end
local function ensureDirectory(hs, path)
    local existing = attrs(hs, path)
    if existing then
        if existing.mode == "directory" then return true end
        return err("Expected a directory, found a file: " .. path)
    end
    local normalized = path:gsub("\\", "/"):gsub("/+$", "")
    local parent = normalized:match("^(.*)/[^/]+$")
    if parent and parent ~= "" and parent ~= normalized then
        -- Preserve a Windows drive root when running local tests.
        if parent:match("^[A-Za-z]:$") then parent = parent .. "/" end
        local ok, message = ensureDirectory(hs, parent)
        if not ok then return nil, message end
    end
    local ok, message = hs.fs.mkdir(path)
    if ok or (attrs(hs, path) or {}).mode == "directory" then return true end
    return err("Cannot create directory " .. path .. ": " .. tostring(message))
end

local function readFile(path)
    local file, message = io.open(path, "rb")
    if not file then return err("Cannot read " .. path .. ": " .. tostring(message)) end
    local text, readError = file:read("*a")
    local closed, closeError = file:close()
    if text == nil then return err("Cannot read " .. path .. ": " .. tostring(readError)) end
    if closed == nil then return err("Cannot close " .. path .. ": " .. tostring(closeError)) end
    return text
end
local function readJSON(hs, path)
    if not attrs(hs, path) then return nil end
    local text, message = readFile(path)
    if not text then return nil, message end
    local ok, value = pcall(hs.json.decode, text)
    if not ok or type(value) ~= "table" then
        return err("Malformed JSON record; review it manually before restarting: " .. path)
    end
    return value
end

local tempSerial = 0
local function writeText(path, text)
    local file, message = io.open(path, "wb")
    if not file then return err("Cannot write " .. path .. ": " .. tostring(message)) end
    local written, writeError = file:write(text)
    if not written then file:close(); return err("Write failed for " .. path .. ": " .. tostring(writeError)) end
    local flushed, flushError = file:flush()
    local closed, closeError = file:close()
    if not flushed or not closed then
        return err("Flush/close failed for " .. path .. ": " .. tostring(flushError or closeError))
    end
    return true
end
local function atomicJSON(hs, path, value)
    local parent = path:match("^(.*)/[^/]+$")
    if parent and not attrs(hs, parent) then
        return err("Record directory is missing; the active run may have been deleted: " .. parent)
    end
    local ok, encoded, encodeError = pcall(hs.json.encode, value, true)
    if not ok then return err("Cannot encode record: " .. path .. ": " .. tostring(encoded)) end
    if type(encoded) ~= "string" then
        return err("Cannot encode record: " .. path .. ": " .. tostring(encodeError or "encoder returned no data"))
    end
    tempSerial = tempSerial + 1
    local suffix = ".tmp-" .. tostring(os.time()) .. "-" .. tostring(tempSerial)
    local temporary = path .. suffix
    if attrs(hs, temporary) then return err("Unexpected existing temporary record: " .. temporary) end
    local written, message = writeText(temporary, encoded .. "\n")
    if not written then return nil, message end
    -- POSIX rename replaces atomically. Windows' C runtime may refuse an
    -- existing destination: retain the old file as a unique backup, then rename.
    local renamed, renameError = os.rename(temporary, path)
    if renamed then return true end
    if not attrs(hs, path) then return err("Cannot commit record " .. path .. ": " .. tostring(renameError)) end
    local backup = path .. ".previous-" .. tostring(os.time()) .. "-" .. tostring(tempSerial)
    if attrs(hs, backup) then return err("Unexpected existing backup record: " .. backup) end
    local saved, saveError = os.rename(path, backup)
    if not saved then return err("Cannot preserve prior record " .. path .. ": " .. tostring(saveError)) end
    local committed, commitError = os.rename(temporary, path)
    if not committed then
        local restored = os.rename(backup, path)
        return err("Cannot commit " .. path .. ": " .. tostring(commitError)
            .. (restored and "; previous record restored" or "; prior record remains at " .. backup))
    end
    return true
end

local function cell(value, hs)
    if value == nil then return "" end
    if type(value) == "number" and (value ~= value or value == math.huge or value == -math.huge) then
        error("Non-finite numbers cannot be written to study records")
    end
    local text
    if type(value) == "table" then
        text = assert(hs.json.encode(value), "Cannot encode structured CSV value")
    else text = tostring(value) end
    if text:find('[,"\r\n]') then text = '"' .. text:gsub('"', '""') .. '"' end
    return text
end
local function appendCSV(hs, path, names, row)
    local header = table.concat(names, ",")
    local file, openError = io.open(path, "rb")
    if not file then return err("Missing/unreadable log " .. path .. ": " .. tostring(openError)) end
    local existing = file:read("*l")
    file:close()
    if existing and existing:sub(-1) == "\r" then existing = existing:sub(1, -2) end
    if existing ~= header then return err("Log header/schema mismatch; refusing to append: " .. path) end
    local out, any = {}, false
    local ok, message = pcall(function()
        for i, name in ipairs(names) do
            out[i] = cell(row[name], hs)
            if row[name] ~= nil and tostring(row[name]) ~= "" then any = true end
        end
    end)
    if not ok then return err("Cannot encode log row: " .. tostring(message)) end
    if not any then return err("Refusing a completely empty log row: " .. path) end
    local writer, writerError = io.open(path, "ab")
    if not writer then return err("Cannot append " .. path .. ": " .. tostring(writerError)) end
    local wrote, writeError = writer:write(table.concat(out, ",") .. "\n")
    local flushed, flushError = writer:flush()
    local closed, closeError = writer:close()
    if not wrote or not flushed or not closed then
        return err("Log append failed for " .. path .. ": " .. tostring(writeError or flushError or closeError))
    end
    return true
end

local function validateInput(baseDir, mode, participant, hs)
    if type(baseDir) ~= "string" or baseDir == "" then return err("A record directory is required") end
    if mode ~= "main" and mode ~= "pilot" and mode ~= "test" then return err("Mode must be main, pilot or test") end
    if not safePart(participant, 64) then return err("Participant code must contain only letters, digits, hyphens or underscores") end
    if not hs or not hs.fs or not hs.fs.attributes or not hs.fs.mkdir or not hs.json then
        return err("Storage requires hs.fs attributes/mkdir and hs.json encode/decode")
    end
    return true
end

function M.inspectParticipant(baseDir, mode, participant, hs)
    local valid, message = validateInput(baseDir, mode, participant, hs)
    if not valid then return nil, message end
    local participantPath = join(join(baseDir, mode), participant)
    local existing = attrs(hs, participantPath)
    if existing and existing.mode ~= "directory" then return err("Participant path is not a directory") end
    local info = { exists = existing ~= nil, participantPath = participantPath, blocked = false }
    local active, activeError = readJSON(hs, join(participantPath, "ACTIVE.json"))
    if activeError then return nil, activeError end
    local completed, completedError = readJSON(hs, join(participantPath, "COMPLETED.json"))
    if completedError then return nil, completedError end
    info.active, info.completed = active, completed
    info.locked = attrs(hs, join(participantPath, ".session-lock")) ~= nil
    if active or info.locked then
        info.blocked = true
        info.block_reason = "Prior active/interrupted session requires manual review; no automatic replay or resume"
    elseif mode == "main" and completed then
        info.blocked = true
        info.block_reason = "This main-study participant already has a finalized session"
    end
    return info
end

local function fail(store, message)
    store.failure = tostring(message)
    return nil, store.failure
end
function Store:_guard()
    if self.failure then return err("Record storage is stopped: " .. self.failure) end
    if self.closed then return err("Session records are already closed") end
    return true
end
local function identity(store, ctx)
    ctx = ctx or {}
    local result = {
        session_id = store.meta.session_id, mode = store.meta.mode,
        participant = store.meta.participant, group = store.meta.group,
        block = pick(ctx.block, ctx.block_index, ctx.blockIndex),
        condition = pick(ctx.condition, ctx.condition_name),
        orientation = ctx.orientation, tab_load = pick(ctx.tab_load, ctx.load),
        content_set = pick(ctx.content_set, ctx.contentSet, ctx.set),
        trial = pick(ctx.trial, ctx.trial_id, ctx.trialIndex),
        target_id = pick(ctx.target_id, ctx.targetID),
        target_title = pick(ctx.target_title, ctx.targetTitle),
    }
    local block = store.meta.plan and store.meta.plan[tonumber(result.block)]
    if block then
        result.condition = result.condition or block.name
        result.orientation = result.orientation or block.orientation
        result.tab_load = result.tab_load or block.tabLoad
        result.content_set = result.content_set or block.contentSet
        result.visible_tab_count = block.expectedTabCount
        result.task_tab_count = block.expectedTabCount and block.expectedTabCount - 1
        local index = tonumber(tostring(result.trial or ""):match("(%d+)$"))
        local trial = index and block.trials and block.trials[index]
        if trial then
            result.is_repeat = 0
            for i = 1, index - 1 do
                if block.trials[i].targetID == trial.targetID then result.is_repeat = 1 end
            end
            for pos, path in ipairs(block.taskOrder or {}) do
                if path == trial.path then result.target_task_position = pos end
            end
        end
    end
    return result
end

function M.create(baseDir, meta, hs)
    if type(meta) ~= "table" then return err("Session metadata is required") end
    local valid, message = validateInput(baseDir, meta.mode, meta.participant, hs)
    if not valid then return nil, message end
    local group = tonumber(meta.group)
    if not group or group % 1 ~= 0 or group < 1 or group > 4 then return err("Allocated group must be 1, 2, 3 or 4") end
    if not safePart(meta.session_id, 96) then return err("A unique safe session_id is required") end
    local info, inspectError = M.inspectParticipant(baseDir, meta.mode, meta.participant, hs)
    if not info then return nil, inspectError end
    if info.blocked then return err(info.block_reason) end
    local made, mkdirError = ensureDirectory(hs, info.participantPath)
    if not made then return nil, mkdirError end
    local path = join(info.participantPath, meta.session_id)
    if attrs(hs, path) then return err("Session ID already exists; refusing to append: " .. path) end
    local lockPath = join(info.participantPath, ".session-lock")
    local reserved, reserveError = hs.fs.mkdir(lockPath)
    if not reserved then return err("Participant already reserved or cannot be locked: " .. tostring(reserveError)) end
    -- Once reserved, any setup/write failure leaves the guard for explicit
    -- inspection instead of silently starting another potentially exposed run.
    local newRun, runError = hs.fs.mkdir(path)
    if not newRun then return err("Cannot create fresh run: " .. tostring(runError)) end
    local copy = {}
    for key, value in pairs(meta) do copy[key] = value end
    copy.group, copy.schema_version, copy.status = group, M.SCHEMA_VERSION, "active"
    copy.created_wall_epoch = copy.created_wall_epoch or os.time()
    local store = setmetatable({
        path = path, participantPath = info.participantPath, lockPath = lockPath,
        meta = copy, hs = hs, seenTrials = {}, trialCount = 0, exposureSeen = false,
        closed = false, failure = nil,
    }, Store)
    for _, entry in ipairs({
        {"events.csv", M.EVENT_COLUMNS}, {"trials_aux.csv", M.TRIAL_COLUMNS},
        {"video_coding.csv", M.VIDEO_COLUMNS}, {"main_data.csv", M.MAIN_COLUMNS},
    }) do
        local ok, createError = writeText(join(path, entry[1]), table.concat(entry[2], ",") .. "\n")
        if not ok then return fail(store, createError) end
    end
    local marker = {
        session_id = copy.session_id, participant = copy.participant, mode = copy.mode,
        group = copy.group, status = "active", path = path,
        created_wall_epoch = copy.created_wall_epoch, schema_version = M.SCHEMA_VERSION,
    }
    local wroteMarker, markerError = atomicJSON(hs, join(info.participantPath, "ACTIVE.json"), marker)
    if not wroteMarker then return fail(store, markerError) end
    local wroteMeta, metaError = atomicJSON(hs, join(path, "session.json"), copy)
    if not wroteMeta then return fail(store, metaError) end
    local initial, initialError = atomicJSON(hs, join(path, "checkpoint.json"), { phase = "SETUP", session_id = copy.session_id })
    if not initial then return fail(store, initialError) end
    return store
end

function Store:event(name, ctx)
    local ready, message = self:_guard(); if not ready then return nil, message end
    if not present(name) then return fail(self, "An event name is required") end
    ctx = ctx or {}
    local row = identity(self, ctx)
    row.phase, row.event = ctx.phase, name
    row.wall_epoch = pick(ctx.wall_epoch, os.time())
    row.monotonic_s, row.elapsed_s = ctx.monotonic_s, ctx.elapsed_s
    row.observed_title, row.detail = ctx.observed_title, ctx.detail
    row.observation_source = ctx.observation_source
    row.aux_selection_count = pick(ctx.aux_selection_count, ctx.nSelections)
    row.aux_incorrect_count = pick(ctx.aux_incorrect_count, ctx.nIncorrect)
    row.aux_first_correct = pick(ctx.aux_first_correct, ctx.firstCorrect)
    if name == "PROMPT_STARTED" or ctx.prompt_exposed == true then self.exposureSeen = true end
    local ok, appendError = appendCSV(self.hs, join(self.path, "events.csv"), M.EVENT_COLUMNS, row)
    if not ok then return fail(self, appendError) end
    return true
end

function Store:trial(record)
    local ready, message = self:_guard(); if not ready then return nil, message end
    if type(record) ~= "table" then return fail(self, "Trial record is required") end
    local row = identity(self, record)
    for _, key in ipairs({"block", "condition", "content_set", "trial", "target_id", "target_title"}) do
        if not present(row[key]) then return fail(self, "Trial record missing " .. key) end
    end
    if not present(record.status) then return fail(self, "Trial record missing status") end
    local key = tostring(row.block) .. ":" .. tostring(row.trial)
    if self.seenTrials[key] then return fail(self, "Duplicate terminal trial outcome: " .. key) end
    row.status = record.status
    row.prompt_exposed = pick(record.prompt_exposed, record.exposed)
    row.timed_started = pick(record.timed_started, record.timed_interval_started, record.timedStarted)
    row.reveal_command_monotonic_s = pick(record.reveal_command_monotonic_s, record.revealMonotonic)
    row.auto_detection_elapsed_s = record.auto_detection_elapsed_s
    row.manual_ack_elapsed_s = record.manual_ack_elapsed_s
    row.aux_selection_count = pick(record.aux_selection_count, record.nSelections)
    row.aux_incorrect_count = pick(record.aux_incorrect_count, record.nIncorrect)
    row.aux_first_correct = pick(record.aux_first_correct, record.firstCorrect)
    for _, name in ipairs({"aux_incorrect_pages", "detection_mode", "mask_hide_returned_monotonic_s",
        "endpoint_monotonic_s", "observed_duration_s", "max_poll_gap_s"}) do row[name] = record[name] end
    row.verification_required = true
    row.reason = pick(record.reason, record.detail)
    if row.prompt_exposed == true then self.exposureSeen = true end
    local ok, appendError = appendCSV(self.hs, join(self.path, "trials_aux.csv"), M.TRIAL_COLUMNS, row)
    if not ok then return fail(self, appendError) end
    local coding = identity(self, record)
    coding.controller_status = record.status
    -- Every final measurement remains nil/blank. Never copy polling observations
    -- into the authoritative coding sheet, even when the observer saw no error.
    local coded, codingError = appendCSV(self.hs, join(self.path, "video_coding.csv"), M.VIDEO_COLUMNS, coding)
    if not coded then return fail(self, codingError) end
    local main = identity(self, record)
    main.controller_status = record.status
    main.measurement_source = record.measurement_source or "controller_title_detection"
    main.retrieval_time_s = record.retrieval_time_s
    main.total_tab_switches = record.total_tab_switches
    main.incorrect_selections = record.incorrect_selections
    main.first_selection_correct = record.first_selection_correct
    main.no_selection = record.no_selection
    main.technical_loss = record.technical_loss
    main.video_verified = false
    main.coder, main.notes = record.coder, record.notes
    local written, mainError = appendCSV(self.hs, join(self.path, "main_data.csv"), M.MAIN_COLUMNS, main)
    if not written then return fail(self, mainError) end
    self.seenTrials[key], self.trialCount = true, self.trialCount + 1
    return true
end

function Store:checkpoint(snapshot)
    local ready, message = self:_guard(); if not ready then return nil, message end
    if type(snapshot) ~= "table" then return fail(self, "Checkpoint must be a table") end
    local saved = {}
    for key, value in pairs(snapshot) do saved[key] = value end
    saved.session_id, saved.schema_version = self.meta.session_id, M.SCHEMA_VERSION
    if snapshot.exposed == true or snapshot.prompt_exposed == true then self.exposureSeen = true end
    local ok, writeError = atomicJSON(self.hs, join(self.path, "checkpoint.json"), saved)
    if not ok then return fail(self, writeError) end
    return true
end

function Store:markInterrupted(reason)
    local ready, message = self:_guard(); if not ready then return nil, message end
    self.meta.status, self.meta.interruption_reason = "interrupted", tostring(reason or "Unspecified interruption")
    self.meta.closed_wall_epoch = os.time()
    local ok, writeError = atomicJSON(self.hs, join(self.path, "session.json"), self.meta)
    if not ok then return fail(self, writeError) end
    local marker = {
        session_id = self.meta.session_id, participant = self.meta.participant,
        mode = self.meta.mode, group = self.meta.group, path = self.path,
        status = "interrupted", reason = self.meta.interruption_reason,
        schema_version = M.SCHEMA_VERSION,
    }
    local marked, markerError = atomicJSON(self.hs, join(self.participantPath, "ACTIVE.json"), marker)
    if not marked then return fail(self, markerError) end
    self.closed = true -- guard intentionally survives until documented manual review
    return true
end

function Store:close(status)
    local ready, message = self:_guard(); if not ready then return nil, message end
    status = status or "completed"
    if status ~= "completed" and status ~= "cancelled_unexposed" then
        return self:markInterrupted("Session closed with status " .. tostring(status))
    end
    if status == "cancelled_unexposed" and (self.exposureSeen or self.trialCount > 0) then
        return fail(self, "Cannot label an exposed session cancelled_unexposed")
    end
    if status == "completed" and self.meta.mode == "main" and type(self.meta.plan) == "table" then
        local expected = 0
        for _, block in ipairs(self.meta.plan) do
            if type(block) == "table" and type(block.trials) == "table" then expected = expected + #block.trials end
        end
        if expected > 0 and self.trialCount ~= expected then
            return fail(self, "Cannot finalize main session: recorded " .. self.trialCount
                .. " terminal outcomes for " .. expected .. " scheduled trials")
        end
    end
    -- Read back ownership before modifying the participant-level guard.
    local active, activeError = readJSON(self.hs, join(self.participantPath, "ACTIVE.json"))
    if activeError then return fail(self, activeError) end
    if not active or active.session_id ~= self.meta.session_id then
        return fail(self, "Session guard ownership changed; refusing to release it")
    end
    self.meta.status, self.meta.closed_wall_epoch = status, os.time()
    local ok, writeError = atomicJSON(self.hs, join(self.path, "session.json"), self.meta)
    if not ok then return fail(self, writeError) end
    if status == "completed" then
        local marked, markerError = atomicJSON(self.hs, join(self.participantPath, "COMPLETED.json"), {
            session_id = self.meta.session_id, participant = self.meta.participant,
            mode = self.meta.mode, group = self.meta.group, status = "completed",
            path = self.path, schema_version = M.SCHEMA_VERSION,
        })
        if not marked then return fail(self, markerError) end
    end
    local removed, removeError = os.remove(join(self.participantPath, "ACTIVE.json"))
    if not removed then return fail(self, "Cannot release own ACTIVE guard: " .. tostring(removeError)) end
    local removeDirectory = self.hs.fs.rmdir or os.remove
    local unlocked, unlockError = removeDirectory(self.lockPath) -- only our empty reservation directory
    if not unlocked then return fail(self, "Cannot release empty session lock: " .. tostring(unlockError)) end
    self.closed = true
    return true
end

return M
