-- Main-study allocation. Codes are recruitment slots, not participant names.
--
-- P001-P016: the original frozen 16-slot template (seed 20261028; four permuted
-- blocks; practice order balanced within group). Never edit these rows.
--
-- P017 onward: continued by a fixed rule with no upper limit, so every slot is
-- decided before recruitment and nothing depends on who arrives:
--   * groups: each run of four codes (P017-P020, P021-P024, ...) is one
--     allocation block holding groups 1-4 once each, in a seeded order;
--   * practice order: blocks are paired (5+6, 7+8, ...). Within a pair each
--     group practises H first in one block and V first in the other, and every
--     block has two H-first and two V-first slots.
-- Enrol codes in order without gaps. Groups are then equal after every 4 codes,
-- practice order is balanced within each group after every 8 codes past P016,
-- and every complete 16 keeps the original template's balance.
-- The rule uses its own integer hash, not math.random, so the result does not
-- depend on the Lua build. tests/integration_spec.lua pins P017-P032.
local M = {
    version = "hci2000-allocation-2026-11-26",
    frozenSlots = 16,
    frozenSeed = 20261028,
    extensionSeed = 20261126,
    groups = 4, -- condition orders in study/materials.lua
}

local FROZEN = {
    P001 = {group = 2, practiceFirst = "H", allocationBlock = 1},
    P002 = {group = 4, practiceFirst = "H", allocationBlock = 1},
    P003 = {group = 3, practiceFirst = "V", allocationBlock = 1},
    P004 = {group = 1, practiceFirst = "H", allocationBlock = 1},
    P005 = {group = 3, practiceFirst = "V", allocationBlock = 2},
    P006 = {group = 4, practiceFirst = "V", allocationBlock = 2},
    P007 = {group = 2, practiceFirst = "V", allocationBlock = 2},
    P008 = {group = 1, practiceFirst = "V", allocationBlock = 2},
    P009 = {group = 4, practiceFirst = "H", allocationBlock = 3},
    P010 = {group = 2, practiceFirst = "V", allocationBlock = 3},
    P011 = {group = 1, practiceFirst = "V", allocationBlock = 3},
    P012 = {group = 3, practiceFirst = "H", allocationBlock = 3},
    P013 = {group = 4, practiceFirst = "V", allocationBlock = 4},
    P014 = {group = 1, practiceFirst = "H", allocationBlock = 4},
    P015 = {group = 3, practiceFirst = "H", allocationBlock = 4},
    P016 = {group = 2, practiceFirst = "H", allocationBlock = 4},
}

-- The 24 orders of groups 1-4 and the 6 ways to choose two of them.
local ORDERS, HALVES = {}, {}
for a = 1, 4 do for b = 1, 4 do for c = 1, 4 do for d = 1, 4 do
    if a ~= b and a ~= c and a ~= d and b ~= c and b ~= d and c ~= d then
        ORDERS[#ORDERS + 1] = {a, b, c, d}
    end
end end end end
for a = 1, 3 do for b = a + 1, 4 do HALVES[#HALVES + 1] = {a, b} end end

local MASK = 0xffffffff
local function hash32(x)
    x = x & MASK
    x = x ~ (x >> 16)
    x = (x * 0x7feb352d) & MASK
    x = x ~ (x >> 15)
    x = (x * 0x846ca68b) & MASK
    return x ~ (x >> 16)
end
-- Deterministic choice in 1..count for one (stream, index) pair.
local function draw(stream, index, count)
    local h = hash32(M.extensionSeed)
    h = hash32(h ~ stream)
    h = hash32(h ~ index)
    return h % count + 1
end

local FIRST_EXTENSION_BLOCK = M.frozenSlots // 4 + 1
local function extensionEntry(number)
    local block = (number - 1) // 4 + 1
    local group = ORDERS[draw(1, block, #ORDERS)][(number - 1) % 4 + 1]
    local offset = block - FIRST_EXTENSION_BLOCK
    local half = HALVES[draw(2, offset // 2 + 1, #HALVES)]
    local inHalf = half[1] == group or half[2] == group
    local firstOfPair = offset % 2 == 0
    return {group = group, practiceFirst = inHalf == firstOfPair and "H" or "V",
        allocationBlock = block}
end

-- Slot number for a canonical main code (P001, P017, P120, P1000), else nil.
-- Non-canonical spellings (P17, P0017) are refused so one slot has one code.
function M.number(code)
    if type(code) ~= "string" then return nil end
    local digits = code:match("^P(%d+)$")
    if not digits or #digits < 3 or #digits > 9 then return nil end
    local number = tonumber(digits)
    if number < 1 or string.format("P%03d", number) ~= code then return nil end
    return number
end

function M.code(number)
    return string.format("P%03d", number)
end

-- {group, practiceFirst, allocationBlock} for a main code, or nil. Returns a copy.
function M.lookup(code)
    local number = M.number(code)
    if not number then return nil end
    local entry = number <= M.frozenSlots and FROZEN[code] or extensionEntry(number)
    return {group = entry.group, practiceFirst = entry.practiceFirst,
        allocationBlock = entry.allocationBlock}
end

-- Allocation["P017"] keeps working for code written against the old table.
return setmetatable(M, {__index = function(_, code) return M.lookup(code) end})
