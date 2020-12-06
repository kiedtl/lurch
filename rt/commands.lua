local conf   = require('config')
local fold   = require('util').fold
local send   = require('irc').send
local format = string.format
local M = {}

local function send_both(fmt, ...)
	-- this is a simple function to send the input to the
	-- terminal and to the server at the same time.
	send(fmt, ...)
	parseirc(format(fmt, ...))
end

M.handlers = {
	["/redraw"] = {
		help = { "Redraw the screen.", "Ctrl+L may also be used." },
		fn = function(_, _, _) redraw() end,
	},
	["/next"] = {
		help = { "Switch to the next buffer.", "Ctrl+N may also be used." },
		fn = function(_, _, _) buf_switch(cur_buf + 1) end
	},
	["/prev"] = {
		help = { "Switch to the previous buffer.", "Ctrl+P may also be used." },
		fn = function(_, _, _) buf_switch(cur_buf - 1) end
	},
	["/invite"] = {
		REQUIRE_CHANBUF = true,
		REQUIRE_ARG = true,
		help = { "Invite a user to the current channel." },
		usage = "<user>",
		fn = function(a, _, _)
			send(":%s INVITE %s :%s", nick, a, buffers[cur_buf].name)
		end
	},
	["/names"] = {
		REQUIRE_CHANBUF_OR_ARG = true,
		help = { "See the users for a channel (the current one by default)." },
		usage = "[channel]",
		fn = function(a, _, _) send("NAMES %s", a or buffers[cur_buf].name) end
	},
	["/topic"] = {
		-- TODO: separate settopic command
		REQUIRE_CHANBUF_OR_ARG = true,
		help = { "See the current topic for a channel (the current one by default)." },
		usage = "[channel]",
		fn = function(a, _, _) send("TOPIC %s", a or buffers[cur_buf].name) end
	},
	["/whois"] = {
		REQUIRE_ARG = true,
		help = { "See WHOIS information for a user." },
		usage = "<user>",
		fn = function(a, _, _) send("WHOIS %s", a) end
	},
	["/join"] = {
		REQUIRE_ARG = true,
		help = { "Join a channel; if already joined, focus that buffer." },
		usage = "[channel]",
		fn = function(a, args, inp)
			send(":%s JOIN %s", nick, a)
			statusbar()

			local bufidx = buf_idx(a)
			if not bufidx then
				buf_add(a)
				bufidx = buf_idx(a)
				statusbar()
			end

			buf_switch(bufidx)
		end
	},
	["/part"] = {
		REQUIRE_CHANBUF_OR_ARG = true,
		help = { "Part the current channel." },
		usage = "[part_message]",
		fn = function(a, args, _)
			local msg = conf.part_msg
			if a and a ~= "" then msg = format("%s %s", a, args) end
			send(":%s PART %s :%s", nick, buffers[cur_buf].name, msg)
		end
	},
	["/quit"] = {
		help = { "Exit lurch." },
		usage = "[quit_message]",
		fn = function(a, args, _)
			local msg
			if not a or a == "" then
				msg = conf.quit_msg
			else
				msg = format("%s %s", a, args)
			end

			send("QUIT :%s", msg)
			eprintf("[lurch exited]\n")
			tui.clean()
			os.exit(0)
		end
	},
	["/nick"] = {
		REQUIRE_ARG = true,
		help = { "Change nickname." },
		usage = "<nickname>",
		fn = function(a, _, _) send("NICK %s", a); nick = a; end
	},
	["/msg"] = {
		REQUIRE_ARG = true,
		help = { "Privately message a user. Opens a new buffer." },
		usage = "<user> <message...>",
		fn = function(a, args, _)
			send_both(":%s PRIVMSG %s :%s", nick, a, args)
		end
	},
	["/raw"] = {
		REQUIRE_ARG = true,
		help = { "Send a raw IRC command to the server." },
		usage = "<command> <args>",
		fn = function(a, args, _) send("%s %s", a, args) end
	},
	["/me"] = {
		REQUIRE_ARG = true,
		REQUIRE_CHANBUF = true,
		help = { "Send a CTCP action to the current channel." },
		usage = "<text>",
		fn = function(a, args, _)
			send_both(":%s PRIVMSG %s :\1ACTION %s %s\1", nick,
				buffers[cur_buf].name, a, args)
		end,
	},
	["/help"] = {
		help = { "You know what this command is for." },
		usage = "[command]",
		fn = function(a, args, _)
			local curbuf = buffers[cur_buf].name

			if not a or a == "" then
				prin(curbuf, "--", "welcome to lurch , bastard !!!")
				return
			end

			local cmd = a
			if not (cmd:find("/") == 1) then cmd = "/" .. cmd end

			if not M.handlers[cmd] then
				prin(curbuf, "-!-", "No such command '%s'", a)
				return
			end

			local cmdinfo = M.handlers[cmd]
			prin(curbuf, "--", "")
			prin(curbuf, "--", "Help for %s", cmd)

			if cmdinfo.usage then
				prin(curbuf, "--", "usage: %s %s", cmd, cmdinfo.usage)
			end

			prin(curbuf, "--", "")
			
			for i = 1, #cmdinfo.help do
				prin(curbuf, "--", "%s", cmdinfo.help[i])
				prin(curbuf, "--", "")
			end

			if cmdinfo.REQUIRE_CHANBUF then
				prin(curbuf, "--", "This command must be run in a channel buffer.")
				prin(curbuf, "--", "")
			end
		end,
	},
	["/list"] = {
		-- TODO: list user-defined commands.
		help = { "List builtin and user-defined lurch commands." },
		fn = function(_, _, _)
			local curbuf = buffers[cur_buf].name
			prin(curbuf, "--", "")
			prin(curbuf, "--", "[builtin]")

			local cmdlist = ""
			for k, _ in pairs(M.handlers) do
				cmdlist = cmdlist .. k .. " "
			end

			prin(curbuf, "--", "%s", cmdlist)
		end,
	},
}

return M
