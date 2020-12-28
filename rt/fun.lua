local M = {}

function M.foldl(iter, init, func)
    local accm = init
    while true do
        local values = { iter() }
        if #values == 0 then break end
        accm = func(accm, table.unpack(values))
    end
    return accm
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

function M.map(iter, fun)
    local values = { iter() }
    if #values == 0 then return end
    fun(table.unpack(values))
    M.map(iter, fun)
end

return M
