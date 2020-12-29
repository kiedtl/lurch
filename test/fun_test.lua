local inspect = require("inspect")
local F = require("fun")
local util = require("util")
local lunatest = package.loaded.lunatest
local assert_eq = lunatest.assert_equal
local assert_ye = lunatest.assert_true
local assert_no = lunatest.assert_false
local M = {}
local _assert_table_eq = nil
local function _0_(a, b)
    assert((nil ~= b), string.format("Missing argument %s on %s:%s", "b", "test/fun_test.fnl", 13))
    assert((nil ~= a), string.format("Missing argument %s on %s:%s", "a", "test/fun_test.fnl", 13))
    return assert_ye(util.table_eq(a, b))
end
_assert_table_eq = _0_
local _assert_table_neq = nil
local function _1_(a, b)
    assert((nil ~= b), string.format("Missing argument %s on %s:%s", "b", "test/fun_test.fnl", 15))
    assert((nil ~= a), string.format("Missing argument %s on %s:%s", "a", "test/fun_test.fnl", 15))
    return assert_no(util.table_eq(a, b))
end
_assert_table_neq = _1_
M.test_iter = function()
    local tbl1 = {"H", "a", "l", "p", "m", "e"}
    local tbl2 = {L = "o", m = "I", r = "e"}
    local _3_
    do
        local _2_0 = {F.iter("HelloWorld")}
        if _2_0 then
            local function _4_(_241, _242)
                return _242
            end
            _3_ = F.collect(_4_, _2_0)
        else
            _3_ = _2_0
        end
    end
    _assert_table_eq(_3_, {"H", "e", "l", "l", "o", "W", "o", "r", "l", "d"})
    local _5_
    do
        local _4_0 = {F.iter(tbl1)}
        if _4_0 then
            local function _6_(_241, _242)
                return _242
            end
            _5_ = F.collect(_6_, _4_0)
        else
            _5_ = _4_0
        end
    end
    _assert_table_eq(_5_, tbl1)
    local _7_
    do
        local _6_0 = {F.iter(tbl2)}
        if _6_0 then
            local function _8_(_241, _242, _243)
                _241[_242] = _243
                return _241
            end
            _7_ = F.foldl({}, _8_, _6_0)
        else
            _7_ = _6_0
        end
    end
    return _assert_table_eq(_7_, tbl2)
end
M.test_range = function()
    local _3_
    do
        local _2_0 = {F.range(0, 7)}
        if _2_0 then
            local function _4_(_241)
                return _241
            end
            _3_ = F.collect(_4_, _2_0)
        else
            _3_ = _2_0
        end
    end
    _assert_table_eq(_3_, {0, 1, 2, 3, 4, 5, 6, 7})
    local _5_
    do
        local _4_0 = {F.range(7, 0, -1)}
        if _4_0 then
            local function _6_(_241)
                return _241
            end
            _5_ = F.collect(_6_, _4_0)
        else
            _5_ = _4_0
        end
    end
    _assert_table_eq(_5_, {7, 6, 5, 4, 3, 2, 1, 0})
    local _7_
    do
        local _6_0 = {F.range(-7, 0)}
        if _6_0 then
            local function _8_(_241)
                return _241
            end
            _7_ = F.collect(_8_, _6_0)
        else
            _7_ = _6_0
        end
    end
    _assert_table_eq(_7_, {-7, -6, -5, -4, -3, -2, -1, 0})
    local _9_
    do
        local _8_0 = {F.range(-7, -14, -1)}
        if _8_0 then
            local function _10_(_241)
                return _241
            end
            _9_ = F.collect(_10_, _8_0)
        else
            _9_ = _8_0
        end
    end
    _assert_table_eq(_9_, {-7, -8, -9, -10, -11, -12, -13, -14})
    local _11_
    do
        local _10_0 = {F.range(0, 7, 3)}
        if _10_0 then
            local function _12_(_241)
                return _241
            end
            _11_ = F.collect(_12_, _10_0)
        else
            _11_ = _10_0
        end
    end
    return _assert_table_eq(_11_, {0, 3, 6})
end
M.test_foldl = function()
    local _3_
    do
        local _2_0 = {F.range(0, 7)}
        if _2_0 then
            local function _4_(_241, _242)
                return (_241 + _242)
            end
            _3_ = F.foldl(0, _4_, _2_0)
        else
            _3_ = _2_0
        end
    end
    assert_eq(_3_, 28)
    local _5_
    do
        local _4_0 = {F.range(1, 7)}
        if _4_0 then
            local function _6_(_241, _242)
                return (_241 * _242)
            end
            _5_ = F.foldl(1, _6_, _4_0)
        else
            _5_ = _4_0
        end
    end
    return assert_eq(_5_, 5040)
end
M.test_map = function()
    local _3_
    do
        local _2_0 = F.t_range(0, 7)
        if _2_0 then
            local _4_0 = nil
            local function _6_(_241)
                return (_241 + 1)
            end
            _4_0 = F.t_map(_6_, _2_0)
            if _4_0 then
                local function _7_(_241)
                    return _241
                end
                _3_ = F.collect(_7_, _4_0)
            else
                _3_ = _4_0
            end
        else
            _3_ = _2_0
        end
    end
    return _assert_table_eq(_3_, {1, 2, 3, 4, 5, 6, 7, 8})
end
return M
