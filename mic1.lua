--[[
	Optimizing Compiler for a Statement-Only Language into SIC-1
		by Vurv
]]

---@enum StmtKind
local StmtKind = {
	Block = 1,
	Static = 2, -- static var = 5
	Loop = 3, -- loop {}
	For = 4, -- for 4 {}
	Echo = 5, -- echo xyz
	Asm = 6, -- asm {}
	Zero = 7, -- xyz = 0
	Sub = 8, -- xyz -= zyx
	Add = 9 -- xyz += zyx
}

---@class Stmt
---@field kind StmtKind
---@field data table
local Stmt = {}
Stmt.__index = Stmt

function Stmt:__tostring()
	return string.format("Stmt { kind: %u, data: %s }", self.kind, self.data)
end

---@param kind StmtKind
---@param data string|table|nil
function Stmt.new(kind, data)
	return setmetatable({ kind = kind, data = data }, Stmt)
end

---@param code string
---@return Stmt
local function parse(code)
	local ptr, code_len = 1, #code

	local function skipWhitespace()
		local _, ws = code:find("^(%s+)", ptr)
		if ws then
			ptr = ws + 1
		end
	end

	local function skipComments()
		while true do
			local _, comment = code:find("^(//[^\n]*)", ptr)
			if not comment then break end
			ptr = comment + 1
		end
	end

	---@param pattern string
	---@return string?
	local function consume(pattern)
		-- Allow whitespace & comments between tokens
		skipWhitespace()
		skipComments()
		skipWhitespace()

		local _, ed, match = code:find(pattern, ptr)
		if ed then
			ptr = ed + 1
			return match or true
		end
		return nil
	end


	local function consumeAddress()
		return consume("^($?[%w_]+)") or error("Invalid address: " .. (consume("^(%S+)") or "EOF"))
	end

	local consumeBlock

	---@return Stmt?
	local function next()
		local op = consume("^($?[%w_]+)")
		if op == "loop" then
			return Stmt.new(StmtKind.Loop, {consumeBlock(), true})
		elseif op == "for" then
			local num = assert( consume("^(%d+)"), "Expected number after for keyword" )
			return Stmt.new(StmtKind.For, {tonumber(num), consumeBlock()})
		elseif op == "goto" then
			return Stmt.new(StmtKind.Goto, consumeAddress())
		elseif op == "echo" then
			return Stmt.new(StmtKind.Echo, consumeAddress())
		elseif op == "static" then
			local name = assert(consume("^([%w_]+)"), "Expected name for static variable")
			assert(consume("^="), "Expected '=' to follow static declaration")

			local value = consume("^(%d+)")
			if value then
				return Stmt.new(StmtKind.Static, { name, tonumber(value) })
			end

			value = consume("^(-?\"[^\"]+\")")
			if value then
				return Stmt.new(StmtKind.Static, { name, value })
			end

			error("Unimplemented static value type: " .. (consume("^(%S+)") or "EOF"))
		elseif op == "asm" then
			local block = assert( consume("^(%b{})"), "Expected block after asm keyword" )
			return Stmt.new(StmtKind.Asm, block:sub(2, -2))
		elseif op then
			if consume("^+=") then
				return Stmt.new(StmtKind.Add, {op, consumeAddress()})
			elseif consume("^-=") then
				return Stmt.new(StmtKind.Sub, {op, consumeAddress()})
			elseif consume("=") then
				assert(consume("0"), "Can only assign to 0.")
				return Stmt.new(StmtKind.Zero, op)
			elseif consume("^:") then
				return Stmt.new(StmtKind.Label, op)
			else
				error("Invalid operation w/ identifier: " .. op)
			end
		end
	end

	---@return Stmt
	function consumeBlock()
		assert(consume("^{"), "Expected curly bracket to begin block")

		local block = {}
		while ptr < code_len do
			if consume("^}") then return Stmt.new(StmtKind.Block, block) end

			local stmt = next()
			if not stmt then
				error("Parsing error: What is (" .. tostring(consume("^(%S+)")) .. ") ?")
			end
			block[#block + 1] = stmt
		end

		error("Expected } to end block, got EOF")
	end

	local ast = {}
	while ptr < code_len do
		local stmt = next()
		if not stmt then
			error("Parsing error: What is (" .. tostring(consume("^(%S+)")) .. ") ?")
		end
		ast[#ast + 1] = stmt
	end

	return Stmt.new(StmtKind.Block, ast)
end

---@param ast Stmt
local function optimize(ast)
	local addresses = {
		["$out"] = "@OUT",
		["$in"] = "@IN",
		["$max"] = "@MAX",
		["$halt"] = "@HALT"
	}

	local function makeAddress(addr) -- Assumes that the address is valid. Might need a validation step.
		return addresses[addr] or ("@" .. string.upper(addr))
	end

	local function optimizeStmt(stmt)
		if stmt.kind == StmtKind.Block then
			local stmts = stmt.data
			for k, stmt in ipairs(stmts) do
				stmts[k] = optimizeStmt(stmt)
			end
		elseif stmt.kind == StmtKind.Loop then
			local stmts = stmt.data[1].data
			for k, stmt in ipairs(stmts) do
				stmts[k] = optimizeStmt(stmt)
			end

			local last_stmt = stmts[#stmts]
			if last_stmt and last_stmt.kind == StmtKind.Zero then
				-- Optimize this last node into one that also jmps to beginning of loop.
				local addr = makeAddress(last_stmt.data)
				stmts[#stmts] = Stmt.new(StmtKind.Asm, string.format("subleq %s, %s, @LOOP", addr, addr))
				stmt.data[2] = false
			end
		end

		return stmt -- No optimization found
	end

	return optimizeStmt(ast)
end

---@param ast Stmt
local function compile(ast)
	local footer = {}
	local addresses = {
		["$out"] = "@OUT",
		["$in"] = "@IN",
		["$max"] = "@MAX",
		["$halt"] = "@HALT"
	}

	local function verifyAddress(addr)
		return assert(addresses[addr], "Undefined address " .. addr .. ", did you forget to declare it?")
	end

	local function declareAddress(addr)
		local v = "@" .. string.upper(addr)
		addresses[addr] = v
		return v
	end

	---@param value integer
	local function defineAddress(addr, value)
		if addresses[addr] then
			return true
		else
			local fmt = "@" .. string.upper(addr)
			addresses[addr] = fmt
			footer[#footer + 1] = string.format("%s: .data %u", fmt, value)
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
			footer[#footer + 1] = string.format("%s: .data %s", declareAddress(stmt.data[1]), stmt.data[2])
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
			body[#body + 1] = string.format("subleq @OUT %s", verifyAddress(stmt.data))
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
