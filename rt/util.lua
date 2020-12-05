local util = {}

function util.last_gmatch(s, pat)
	last = ""
	for i in s:gmatch(pat) do
		last = i
	end
	return last
end

function util.printf(fmt, ...)
	io.write(string.format(fmt, ...))
end

function util.eprintf(fmt, ...)
	io.stderr:write(string.format(fmt, ...))
end

function util.read(file)
	local f = assert(io.open(file, 'rb'))
	local out = assert(f:read('*all'))
	f:close()
	return out
end

function util.write(file, stuff)
	local f = assert(io.open(file, 'w'))
	assert(f:write(stuff))
	f:close()
end

function util.append(file, stuff)
	local f = assert(io.open(file, 'a'))
	assert(f:write(stuff))
	f:close()
end

function util.create(file)
	util.write(file, "")
end

function util.exists(file)
	local f = io.open(file, "rb")
	if f ~= nil then f:close() end
	return f ~= nil
end

-- Fold text to width, adding newlines between words. This is basically a /bin/fold
-- implementation in Lua.
function util.fold(text, width)
	local _raw_len = function(text)
		text = text:gsub("\x1b%[.-m", "")
		text = text:gsub("\x1b%[m", "")
		return #text
	end

	local res = ""
	for w in string.gmatch(text, "([^ ]+%s?)") do -- iterate over each word
		-- get the last line of the message.
		local last_line = util.last_gmatch(res..w.."\n", "(.-)\n")

		-- only append a newline if the line's width is greater than
		-- zero. This is to prevent situations where a long word (say,
		-- a URL) is put on its own line with nothing on the line
		-- above.
		if _raw_len(last_line or res..w) >= width then
			if _raw_len(res) > 0 then
				res = res .. "\n"
			end
		end
		res = res .. w
	end
	return res
end

function util.contains(src, value)
	local has = false
	for i = 1, #src do
		if src[i] == value then
			has = true
			break
		end
	end
	return has
end

function util.indexof(src, value)
	local idx = nil
	for i = 1, #src do
		if src[i] == value then
			idx = i
			break
		end
	end
	return idx
end

-- This hash function was stolen from the QBE project.
-- git://c9x.me/qbe.git, ./minic/minic.y:104
HASH_BEG = 42
HASH_MOD = 512
function util.hash(value, max)
	local h = 0

	h = HASH_BEG
	for char in value:gmatch(".") do
		h = h + (11 * h + utf8.codepoint(char))
	end
	return h % (max or HASH_MOD)
end

return util
