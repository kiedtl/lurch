local lunatest  = package.loaded.lunatest
local assert_eq = lunatest.assert_equal
local assert_ye = lunatest.assert_true
local assert_no = lunatest.assert_false

local util = require('util')
local M = {}

local function _assert_table_eq(a, b)  assert_ye(util.table_eq(a, b))  end
local function _assert_table_neq(a, b) assert_no(util.table_eq(a, b)) end

function M.test_last_gmatch()
    assert_eq(util.last_gmatch("Lorem ipsum", "."), "m")
    assert_eq(util.last_gmatch("Lorem ipsum", "([^%s]+)%s?"), "ipsum")
    assert_eq(util.last_gmatch("God Save the King", "([Gg])"), "g")
end

function M.test_parse_offset()
    assert_eq(util.parse_offset("UTC+7:30"),    7.5)
    assert_eq(util.parse_offset("UTC+3:00"),    3.0)
    assert_eq(util.parse_offset("UTC+14:30"),  14.5)
    assert_eq(util.parse_offset("UTC+0:00"),    0.0)
    assert_eq(util.parse_offset("UTC+0:30"),    0.5)

    assert_eq(util.parse_offset("UTC-7:00"),   -7.0)
    assert_eq(util.parse_offset("UTC-9:30"),   -9.5)
    assert_eq(util.parse_offset("UTC-18:00"), -18.0)
    assert_eq(util.parse_offset("UTC-0:30"),   -0.5)
end

function M.test_time_from_iso8601()
    local cases = {
        { "1975-01-11T15:45:34.285Z",  158687134 },
        { "1975-01-11T15:45:34Z",      158687134 },
        { "2020-12-13T15:47:28Z",     1607874448 },
    }

    for _, case in ipairs(cases) do
        assert_eq(util.time_from_iso8601(case[1]), case[2])
    end
end

function M.test_fmt_duration()
    local cases = {
        {      75,        "1m" },
        { 3290505, "38d 2h 1m" },
    }

    for _, case in ipairs(cases) do
        assert_eq(util.fmt_duration(case[1]), case[2])
    end
end

function M.test_table_eq()
    _assert_table_eq({1}, {1})
    _assert_table_eq({1, 2, 3, 4, 5}, {1, 2, 3, 4, 5})
    _assert_table_neq({1, 2, 3, 4, 5}, {1, 2, 3, 4})

    _assert_table_eq({{1, 2}, "test", {56}}, {{1, 2}, "test", {56}})
    _assert_table_neq({{1, 2}, {"test"}, {56}}, {{1, 2}, "test", {56}})
end

function M.test_remove()
    local r
    r = util.remove({"test", 2, 2, 5, {"table2", 4}, 3}, 5)
    _assert_table_eq(r, {"test", 2, 2, 5, 3})
end

return M
