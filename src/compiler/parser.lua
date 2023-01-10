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
		elseif op == "echo" then
			return Stmt.new(StmtKind.Echo, consumeAddress())
		elseif op == "static" then
			local name = assert(consume("^([%w_]+)"), "Expected name for static variable")
			assert(consume("^="), "Expected '=' to follow static declaration")

			local value = consume("^(%d+)")
			if value then
				return Stmt.new(StmtKind.Static, { name, tonumber(value), "int" })
			end

			value = consume("^(-?\"[^\"]+\")")
			if value then
				return Stmt.new(StmtKind.Static, { name, value, "str" })
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
			elseif consume("^=") then
				assert(consume("^0"), "Can only assign to 0.")
				return Stmt.new(StmtKind.Zero, op)
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

return {
	parse = parse,

	Stmt = Stmt,
	Kind = StmtKind
}