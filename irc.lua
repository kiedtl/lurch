local irc = {}

-- ported from the parse() function in:
-- https://github.com/dylanaraps/birch
--
-- example IRC message:
-- @time=2020-09-07T01:14:11Z :onisamot!~onisamot@reghog.pink PRIVMSG #meat :ahah
function irc.parse(rawmsg)
	local fields = {}
	local whom = ""
	local dest = ""
	local msg  = ""

	-- Remove the trailing \r\n from the raw message.
	rawmsg = rawmsg:gsub("\r\n$", "")

	-- grab the first "word" of the IRC message, as we know that
	-- will be the timestamp of the message
	--
	-- TODO: full tag-parsing capability
	--date, time = string.gmatch(rawmsg, "@time=([%d-]+)T([%d:]+)Z")()
	--rawmsg = rawmsg:gsub(".-%s", "", 1)

	-- if the next word in the raw IRC message contains ':', '@',
	-- or '!', split it and grab the sending user nick.
	if string.gmatch(rawmsg, "(.-)%s")():find("[:@!]") then
	        whom = string.gmatch(rawmsg, ":?([%w%-_%[%]{}%^`%|]+)!?.-%s")()
	        rawmsg = rawmsg:gsub("^.-%s", "", 1)
	end

	-- Grab all the stuff before the next ':' and stuff it into
	-- a table for later. Anything after the ':' is the message.
	local data, msg = string.gmatch(rawmsg, "(.-):(.*)")()
	if not data then
	        msg = ""
	        data = string.gmatch(rawmsg, "(.*)")()
	end

	local ctr = 1
	for w in string.gmatch(data, "([^%s]+)%s?") do
	        fields[ctr] = w
	        ctr = ctr + 1
	end

	-- If the field after the typical dest is a channel, use
	-- it in place of the regular field. This correctly catches
	-- MOTD and join messages.
	if fields[3] and string.gmatch(fields[3], "^[\\*#]") then
		fields[2] = fields[3]
	elseif fields[3] and string.gmatch(fields[3], "^=") then
		fields[2] = fields[4]
	end

	dest = fields[2]

	-- If the message itself contains ACTION with surrounding '\001',
	-- we're dealing with CTCP /me. Simply set the type to 'ACTION' so
	-- we may specially deal with it below.
	if msg:find("\001ACTION\001") then
		fields[1] = "ACTION"
		msg = msg:gsub("\001ACTION\001 ", "", 1)
	end

	return fields, whom, dest, msg
end

-- unit tests.
local failed = 0
local passed = 0

local function assert_eq(left, right)
	if left == right then
		passed = passed + 1
		print(string.format("\x1b[32m✔\x1b[0m | '%s' == '%s'",
			left, right))
	else
		failed = failed + 1
		print(string.format("\x1b[31m✖\x1b[0m | '%s' != '%s'",
			left, right))
	end
end

local function test_parse_irc()
	local cases = {
		{
			"@time=2020-11-05T22:26:13Z :team.tilde.chat NOTICE * :*** Looking up your ident...",
			{
				{ "NOTICE", "*" }, "team", "*",
				"*** Looking up your ident...", "2020-11-05", "22:26:13"
			},
		},
		{
			"@time=2020-11-05T22:26:14Z :VI-A!test@tilde.team JOIN #gemini",
			{
				{ "JOIN", "#gemini" }, "VI-A", "#gemini",
				"", "2020-11-05", "22:26:14"
			},
		},
		{
			"@time=2020-11-05T22:33:33Z :__restrict!spacehare@tilde.town PRIVMSG #gemini :hm",
			{
				{ "PRIVMSG", "#gemini" }, "__restrict", "#gemini",
				"hm", "2020-11-05", "22:33:33",
			},
		},
	}

	for c = 1, #cases do
		local fields, whom, dest, msg, date, time = irc.parse(cases[c][1])
		assert_eq(table.concat(fields), table.concat(cases[c][2][1]))
		assert_eq(whom, cases[c][2][2])
		assert_eq(dest, cases[c][2][3])
		assert_eq(msg, cases[c][2][4])
		assert_eq(date, cases[c][2][5])
		assert_eq(time, cases[c][2][6])
	end
end

function irc.tests()
	local tests = {
		[test_parse_irc] = "test_parse_irc",
	}

	for testf, testname in pairs(tests) do
		print("\x1b[33m->\x1b[0m testing " .. testname)
		testf()
		print()
	end

	print()
	print(string.format("%d tests completed. %d passed, %d failed.",
		passed + failed, passed, failed))
end

return irc
