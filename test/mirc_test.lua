local lunatest  = package.loaded.lunatest
local assert_eq = lunatest.assert_equal
local assert_ye = lunatest.assert_true
local assert_no = lunatest.assert_false

local mirc = require('mirc')
local M = {}

function M.test_remove()
    local cases = {
        { "[\x0302Ping\x03] kiedtl: pong!", "[Ping] kiedtl: pong!" },
        { "Don't be so \x02dense\x0f.", "Don't be so dense." },
        { "[\x03isup\x03] 2uo.de looks down", "[isup] 2uo.de looks down" },
        { "\x02\x1fF U N C T I O N A L\x0f", "F U N C T I O N A L" },
        { "\x02\x1dI M P E R A T I V E\x0f", "I M P E R A T I V E" },
    }

    for _, case in ipairs(cases) do
        assert_eq(case[2], mirc.remove(case[1]))
    end
end

function M.test_remove_nonstandard()
    local cases = {
        { "* \x04226kiedtl\x0f slaps tildebot", "* kiedtl\x0f slaps tildebot" },
        { "\x04216Nedjay\x0f | \x02STAHP\x0f", "Nedjay\x0f | \x02STAHP\x0f" }
    }

    for _, case in ipairs(cases) do
        assert_eq(case[2], mirc.remove_nonstandard(case[1]))
    end
end

return M
