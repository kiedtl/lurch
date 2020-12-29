local M = {}

function M.iter(val)
    if type(val) == "string" then
        return function(v, i)
            i = i + 1
            if i <= v:len() then
                return i, val:sub(i, i)
            end
        end, val, 0
    elseif type(val) == "table" and #val == 0 then
        return pairs(val)
    elseif type(val) == "table" and #val  > 0 then
        return ipairs(val)
    end
end

function M.range(from, to, step)
    local function _continue(to, i)
        return (from <= to and i <= to)
            or (from >= to and i >= to)
    end

    local step = step or 1
    return function(v, i)
        i = i + step
        if _continue(v, i) then return i end
    end, to, from - step
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

-- Create t_ variants of functions that return iterators.
M.map(function(_, v)
    M["t_" .. v] = function(...) return { (M[v])(...) } end
end, {M.iter({ "iter", "range", "map" })})

return M
