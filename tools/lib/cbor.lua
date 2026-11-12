-- CBOR decoder (RFC 8949), the subset QuestieDB's baked data uses.
-- Also a small encoder, used by the tests to build fixtures.

local bit = require("bit")
local ffi = require("ffi")

local cbor = {}

local float32 = ffi.typeof("union { uint8_t b[4]; float f; }")
local float64 = ffi.typeof("union { uint8_t b[8]; double d; }")

local SIZE = { [24] = 1, [25] = 2, [26] = 4, [27] = 8 }

function cbor.decode(s)
	local pos = 1
	local item

	local function uint(info)
		if info < 24 then return info end
		local len = SIZE[info]
		if not len then error("cbor: bad length info " .. info) end
		local v = 0
		for i = 0, len - 1 do v = v * 256 + s:byte(pos + i) end
		pos = pos + len
		return v
	end

	function item()
		local b = s:byte(pos)
		if not b then error("cbor: unexpected end") end
		pos = pos + 1
		local major, info = bit.rshift(b, 5), bit.band(b, 31)
		if major == 0 then
			return uint(info)
		elseif major == 1 then
			return -1 - uint(info)
		elseif major == 2 or major == 3 then
			local len = uint(info)
			local v = s:sub(pos, pos + len - 1)
			pos = pos + len
			return v
		elseif major == 4 then
			local len, t = uint(info), {}
			for i = 1, len do
				local v = item()
				if v ~= nil then t[i] = v end
			end
			return t
		elseif major == 5 then
			local len, t = uint(info), {}
			for _ = 1, len do
				local k = item()
				local v = item()
				if k ~= nil then t[k] = v end
			end
			return t
		elseif major == 7 then
			if info == 20 then return false end
			if info == 21 then return true end
			if info == 22 or info == 23 then return nil end
			if info == 25 then
				local h = s:byte(pos) * 256 + s:byte(pos + 1)
				pos = pos + 2
				local sign = h >= 32768 and -1 or 1
				local exp, frac = math.floor(h / 1024) % 32, h % 1024
				if exp == 0 then return sign * frac * 2 ^ -24 end
				if exp == 31 then return frac == 0 and sign * math.huge or 0 / 0 end
				return sign * (1 + frac / 1024) * 2 ^ (exp - 15)
			end
			if info == 26 then
				local u = float32()
				for i = 0, 3 do u.b[3 - i] = s:byte(pos + i) end
				pos = pos + 4
				return tonumber(u.f)
			end
			if info == 27 then
				local u = float64()
				for i = 0, 7 do u.b[7 - i] = s:byte(pos + i) end
				pos = pos + 8
				return u.d
			end
		end
		error(("cbor: unsupported major %d info %d"):format(major, info))
	end

	local v = item()
	if pos ~= #s + 1 then error("cbor: trailing bytes") end
	return v
end

-- Encoder: integers, strings, arrays, maps, booleans. Enough for test fixtures.

local function head(major, n)
	local m = major * 32
	if n < 24 then return string.char(m + n) end
	if n < 256 then return string.char(m + 24, n) end
	if n < 65536 then return string.char(m + 25, math.floor(n / 256), n % 256) end
	return string.char(m + 26, math.floor(n / 16777216) % 256, math.floor(n / 65536) % 256,
		math.floor(n / 256) % 256, n % 256)
end

function cbor.encode(v)
	local tv = type(v)
	if tv == "number" then
		if v ~= math.floor(v) then error("cbor: encoder only takes integers") end
		if v >= 0 then return head(0, v) end
		return head(1, -1 - v)
	elseif tv == "string" then
		return head(3, #v) .. v
	elseif tv == "boolean" then
		return string.char(v and 0xF5 or 0xF4)
	elseif tv == "table" then
		local keys = 0
		for _ in pairs(v) do keys = keys + 1 end
		local n, array = keys, true
		for i = 1, keys do
			if v[i] == nil then array = false break end
		end
		local out = {}
		if array then
			out[1] = head(4, n)
			for i = 1, n do out[#out + 1] = cbor.encode(v[i]) end
		else
			local sorted = {}
			for k in pairs(v) do sorted[#sorted + 1] = k end
			table.sort(sorted, function(a, b) return tostring(a) < tostring(b) end)
			out[1] = head(5, keys)
			for _, k in ipairs(sorted) do
				out[#out + 1] = cbor.encode(k)
				out[#out + 1] = cbor.encode(v[k])
			end
		end
		return table.concat(out)
	end
	error("cbor: cannot encode " .. tv)
end

return cbor
