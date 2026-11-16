-- Reads JSON text into Lua values. null becomes nil, so a null in a list leaves a hole.

local json = {}

local ESCAPES = { b = "\b", f = "\f", n = "\n", r = "\r", t = "\t" }

local function utf8(code)
	if code < 0x80 then return string.char(code) end
	if code < 0x800 then return string.char(0xC0 + math.floor(code / 64), 0x80 + code % 64) end
	return string.char(0xE0 + math.floor(code / 4096), 0x80 + math.floor(code / 64) % 64, 0x80 + code % 64)
end

function json.decode(text)
	local pos = 1
	local value

	local function fail(what)
		error(("json: %s at byte %d"):format(what, pos), 0)
	end
	local function space()
		pos = text:find("[^ \t\r\n]", pos) or #text + 1
	end

	local function str()
		local buf = {}
		pos = pos + 1
		while true do
			local stop = text:find('["\\]', pos) or fail("string without an end")
			buf[#buf + 1] = text:sub(pos, stop - 1)
			if text:sub(stop, stop) == '"' then
				pos = stop + 1
				return table.concat(buf)
			end
			local c = text:sub(stop + 1, stop + 1)
			if c == "u" then
				local hex = text:match("^%x%x%x%x", stop + 2) or fail("bad \\u escape")
				buf[#buf + 1] = utf8(tonumber(hex, 16))
				pos = stop + 6
			else
				buf[#buf + 1] = ESCAPES[c] or c
				pos = stop + 2
			end
		end
	end

	function value()
		space()
		local c = text:sub(pos, pos)
		if c == "{" then
			local out = {}
			pos = pos + 1
			space()
			if text:sub(pos, pos) == "}" then pos = pos + 1 return out end
			while true do
				space()
				if text:sub(pos, pos) ~= '"' then fail("expected a key") end
				local key = str()
				space()
				if text:sub(pos, pos) ~= ":" then fail("expected ':'") end
				pos = pos + 1
				out[key] = value()
				space()
				c = text:sub(pos, pos)
				pos = pos + 1
				if c == "}" then return out end
				if c ~= "," then fail("expected ',' or '}'") end
			end
		elseif c == "[" then
			local out, n = {}, 0
			pos = pos + 1
			space()
			if text:sub(pos, pos) == "]" then pos = pos + 1 return out end
			while true do
				n = n + 1
				out[n] = value()
				space()
				c = text:sub(pos, pos)
				pos = pos + 1
				if c == "]" then return out end
				if c ~= "," then fail("expected ',' or ']'") end
			end
		elseif c == '"' then
			return str()
		end
		for word, result in pairs({ ["true"] = true, ["false"] = false }) do
			if text:sub(pos, pos + #word - 1) == word then pos = pos + #word return result end
		end
		if text:sub(pos, pos + 3) == "null" then pos = pos + 4 return nil end
		local number = text:match("^-?%d+%.?%d*[eE]?[+-]?%d*", pos)
		if not number or not tonumber(number) then fail("unexpected text") end
		pos = pos + #number
		return tonumber(number)
	end

	local result = value()
	space()
	if pos <= #text then fail("text after the value") end
	return result
end

return json
