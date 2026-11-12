-- Base64 decode and encode (standard alphabet).

local base64 = {}

local ABC = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local value = {}
for i = 1, #ABC do value[ABC:byte(i)] = i - 1 end

function base64.decode(s)
	local out, n, acc, bits = {}, 0, 0, 0
	for i = 1, #s do
		local v = value[s:byte(i)]
		if v then
			acc = acc * 64 + v
			bits = bits + 6
			if bits >= 8 then
				bits = bits - 8
				local p = 2 ^ bits
				local byte = math.floor(acc / p)
				acc = acc - byte * p
				n = n + 1
				out[n] = string.char(byte)
			end
		end
	end
	return table.concat(out)
end

function base64.encode(s)
	local out = {}
	for i = 1, #s, 3 do
		local a, b, c = s:byte(i, i + 2)
		local n = a * 65536 + (b or 0) * 256 + (c or 0)
		local c1 = math.floor(n / 262144) % 64
		local c2 = math.floor(n / 4096) % 64
		local c3 = math.floor(n / 64) % 64
		local c4 = n % 64
		out[#out + 1] = ABC:sub(c1 + 1, c1 + 1) .. ABC:sub(c2 + 1, c2 + 1)
			.. (b and ABC:sub(c3 + 1, c3 + 1) or "=")
			.. (c and ABC:sub(c4 + 1, c4 + 1) or "=")
	end
	return table.concat(out)
end

return base64
