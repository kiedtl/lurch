local format = string.format
local irc = require("irc")
local mirc = require("mirc")
local util = require("util")

local M = { }
M.logdir = nil

function M.setup(server)
    if os.getenv("LURCH_LOGDIR") then
        M.logdir = os.getenv("LURCH_LOGDIR")
    elseif os.getenv("XDG_DATA_HOME") then
        M.logdir = format("%s/lurch/", os.getenv("XDG_DATA_HOME"))
    else
        M.logdir = format("/home/%s/.local/share/lurch/",
            os.getenv("USER"))
    end
    M.logdir = M.logdir .. server

    -- XXX: Please don't beat me up
    os.execute("mkdir -p " .. M.logdir)
end

function M.append(dest, event)
    assert(M.logdir)
    local logfile = format("%s/%s.txt", M.logdir, dest)

    if not event.tags.time then
        event.tags.time = os.date("!%Y-%m-%dT%H:%M:%S.000Z")
    end

    event.msg = mirc.remove_nonstandard(event.msg)
    util.append(logfile, irc.construct(event) .. "\n")
end

return M
