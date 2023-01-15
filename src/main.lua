package.path = package.path .. ";src/?.lua"

local Mic = require("mic1")

if arg[1] == "compile" then
	local path = assert(arg[2], "Expected path to compile")

	local fd = assert(io.open(path, "rb"), "Couldn't open file (" .. path .. ")")
		local code = fd:read("*a")
	fd:close()

	local ast = Mic.parse(code)
	local optimized = Mic.optimize(ast)
	io.write(Mic.compile(optimized))
elseif arg[1] == "parse" then
	local path = assert(arg[2], "Expected path to parse")

	local fd = assert(io.open(path, "rb"), "Couldn't open file (" .. path .. ")")
		local code = fd:read("*a")
	fd:close()

	local function dbg(t)
		local buf = {"{\n"}
		for k, v in pairs(t) do
			buf[#buf + 1] = string.format("\t[%s] = %s,", k, v)
		end
		return table.concat(buf, "\n") .. "}"
	end

	local ast = Mic.parse(code)
	local optimized = Mic.optimize(ast)
	io.write(dbg(optimized))
else
	io.write([[
		Mic1 Compiler:
			compile <path>
			parse <path>
	]])
end