local parser = require "compiler.parser"
local Stmt, StmtKind = parser.Stmt, parser.Kind

---@param ast Stmt
local function compile(ast)
	local footer = {}
	local addresses = {
		["$out"] = { "@OUT", "int" },
		["$in"] =  { "@IN", "int" },
		["$max"] = { "@MAX", "int" },
		["$halt"] = { "@HALT", "int" }
	}

	---@return string raw, "int"|"str" type
	local function verifyAddress(addr)
		local data = assert(addresses[addr], "Undefined address " .. addr .. ", did you forget to declare it?")
		return data[1], data[2]
	end

	local function declareAddress(addr, type)
		local v = "@" .. string.upper(addr)
		addresses[addr] = { v, type or "int" }
		return v
	end

	---@type fun(addr: string, value: integer|string, type?: "int"|"str"): string
	local function defineAddress(addr, value, type)
		if addresses[addr] then
			return addresses[addr][1]
		else
			local fmt = "@" .. string.upper(addr)
			addresses[addr] = { fmt, type or "int" }
			footer[#footer + 1] = string.format("%s: .data %s", fmt, value)
			return fmt
		end
	end

	---@param stmt Stmt
	local function compileStmt(stmt)
		local body = {}

		if stmt.kind == StmtKind.Block then
			for _, stmt in ipairs(stmt.data) do
				body[#body + 1] = compileStmt(stmt)
			end
		elseif stmt.kind == StmtKind.Static then
			footer[#footer + 1] = string.format("%s: .data %s", declareAddress(stmt.data[1], stmt.data[3]), stmt.data[2])
		elseif stmt.kind == StmtKind.Loop then
			body[#body + 1] = "@LOOP:"
			body[#body + 1] = compileStmt(stmt.data[1])

			if stmt.data[2] then -- Only do this if not already done
				defineAddress("zero", 0)
				body[#body + 1] = "subleq @ZERO, @ZERO, @LOOP"
			end
		elseif stmt.kind == StmtKind.For then
			local num, compiled = stmt.data[1], compileStmt(stmt.data[2])
			for _ = 1, num do
				body[#body + 1] = compiled
			end
		elseif stmt.kind == StmtKind.Echo then
			local addr, type = verifyAddress(stmt.data)
			if type == "str" then
				defineAddress("negative_one", -1)
				defineAddress("zero", 0)

				body[#body + 1] = "@LOOP:"
				body[#body + 1] = "subleq @OUT, " .. addr
				body[#body + 1] = "subleq @LOOP+1, @NEGATIVE_ONE"
				body[#body + 1] = "subleq @ZERO, @ZERO, @LOOP"
			else
				body[#body + 1] = string.format("subleq @OUT, %s", addr)
			end
		elseif stmt.kind == StmtKind.Asm then
			body[#body + 1] = stmt.data
		elseif stmt.kind == StmtKind.Zero then
			local addr = verifyAddress(stmt.data)
			body[#body + 1] = string.format("subleq %s, %s", addr, addr)
		elseif stmt.kind == StmtKind.Sub then
			local lhs, rhs = verifyAddress(stmt.data[1]), verifyAddress(stmt.data[2])
			body[#body + 1] = string.format("subleq %s, %s", lhs, rhs)
		elseif stmt.kind == StmtKind.Add then
			local lhs, rhs = verifyAddress(stmt.data[1]), verifyAddress(stmt.data[2])
			body[#body + 1] = string.format("subleq %s, @ZERO", lhs)
			body[#body + 1] = string.format("subleq @ZERO, %s", rhs)
			body[#body + 1] = string.format("subleq %s, %s", lhs, rhs)
		end

		return table.concat(body, "\n")
	end

	local body = compileStmt(ast)
	return body .. (#footer == 0 and "" or "\n" .. table.concat(footer, "\n"))
end

return {
	compile = compile
}