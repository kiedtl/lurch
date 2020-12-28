-- TODO: Get some unit tests for heaven's sake

local M = {}

function M.range(start, _end, step)
    local step = step or 1
    local i = start
    local function continue()
        return (start >= 0 and start <= _end and i <= _end)
            or (start >= 0 and start >= _end and i >= _end)
            or (start <  0 and start <= _end and i >= _end)
            or (start <  0 and start >= _end and i <= _end)
    end

    return function()
        if continue() then
            local oldi = i
            i = i + step
            return oldi
        end
    end
end

function _foldl_helper(accm, func, i_f, i_s, i_v)
    local values = { i_f(i_s, i_v) }
    i_v = values[1]
    if not i_v then return accm end
    accm = func(accm, table.unpack(values))
    return _foldl_helper(accm, func, i_f, i_s, i_v)
end

function M.foldl(init, func, iter)
    return _foldl_helper(init, func, table.unpack(iter))
end

function M.iter(val)
    local n = 0
    local i = 0

    if type(val) == "string" then
        n = val:len()
        return function()
            i = i + 1
            if i <= n then
                return i, val:sub(i, i)
            end
        end
    elseif type(val) == "table" and #val == 0 then
        return pairs(val)
    elseif type(val) == "table" and #val  > 0 then
        return ipairs(val)
    end
end

function _map_helper(vals, fun, i_f, i_s, i_v)
    local values = { i_f(i_s, i_v) }
    i_v = values[1]
    if not i_v then return vals end

    vals[#vals + 1] = fun(table.unpack(values))
    return _map_helper(vals, fun, i_f, i_s, i_v)
end

function M.map(fun, iter)
    local r = _map_helper({}, fun, table.unpack(iter))
    if r and #r > 0 then return M.iter(r) end
end

function _collect_helper(vals, fun, i_f, i_s, i_v)
    local values = { i_f(i_s, i_v) }
    i_v = values[1]
    if not i_v then return vals end

    vals[#vals + 1] = fun(table.unpack(values))
    return _collect_helper(vals, fun, i_f, i_s, i_v)
end

function M.collect(fun, iter)
    return _collect_helper({}, fun, table.unpack(iter))
end

return M
