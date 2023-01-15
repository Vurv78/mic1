---@enum StmtKind
local StmtKind = {
	Block = 1,
	Static = 2, -- static var = 5
	If = 3,
	Loop = 4, -- loop {}
	For = 5, -- for 4 {}
	Echo = 6, -- echo xyz
	Asm = 7, -- asm {}
	Zero = 8, -- xyz = 0
	Sub = 9, -- xyz -= zyx
	Add = 10 -- xyz += zyx
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


	local macros = {}

	local function consumeAddress()
		local offset, addr = consume("^-") and "-1", consume("^($?[%w_]+)") or error("Invalid address: " .. (consume("^(%S+)") or "EOF"))
		if not offset and consume("^+") then
			offset = "+" .. assert(consume("^(%d+)"), "Expected number for address offset")
		end

		return {addr, offset}
	end

	local consumeBlock

	---@return Stmt|true|nil
	local function next()
		local op = consume("^($?[%w_]+)")
		if op == "loop" then
			return Stmt.new(StmtKind.Loop, {consumeBlock()})
		elseif op == "if" then
			return Stmt.new(StmtKind.If, { consumeAddress(), assert(consume("^[<>]"), "Expected < or > for if statement"), assert(consume("^0") and 0, "Expected 0 for gt/lt operand"), consumeBlock(), consume("^else") and consumeBlock() })
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
		elseif op == "macro" then
			local name, params = assert(consume("^(%l[%w_]+)"), "Expected macro name after macro keyword"), {}
			assert(consume("^%("), "Expected left paren to start macro parameters")
			if consume("^%)") then macros[name] = {{}, consumeBlock()} return true end
			while true do
				local pname = assert(consume("^(%w+)"), "Expected parameter name")
				assert(consume("^:"), "Expected colon for macro parameter type")

				local ty = assert(consume("^(%w+)"), "Expected macro parameter type after colon")
				assert(ty == "block" or ty == "address", "Invalid macro parameter type (" .. ty .. "), expected block or address")
				params[#params + 1] = { pname, ty }

				if not consume("^,") then
					break
				end
			end
			assert(consume("^%)"), "Expected right paren to end macro parameters")
			macros[name] = {params, consumeBlock()}
			return true
		elseif op then
			if consume("^+=") then
				return Stmt.new(StmtKind.Add, {{op}, consumeAddress()})
			elseif consume("^-=") then
				return Stmt.new(StmtKind.Sub, {{op}, consumeAddress()})
			elseif consume("^=") then
				assert(consume("^0"), "Can only assign to 0.")
				return Stmt.new(StmtKind.Zero, {op})
			elseif consume("^!") then
				assert(macros[op], "Macro does not exist: " .. op)
				if consume("^%(") then
					local args, last = {}, #macros[op][1]
					for i, data in ipairs(macros[op][1]) do
						if data[2] == "block" then
							args[data[1]] = consumeBlock()
						elseif data[2] == "address" then
							args[data[1]] = consumeAddress()
						end

						if i ~= last then
							assert(consume("^,"), "Expected comma between macro arguments")
						end
					end
					assert(consume("^%)"), "Expected right paren to end macro arguments")
					return macros[op][2]
				end

				assert(#macros[op][1] == 0, "Cannot invoke this macro without any arguments")
				return macros[op][2]
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
			elseif stmt ~= true then
				block[#block + 1] = stmt
			end
		end

		error("Expected } to end block, got EOF")
	end

	local ast = {}
	while ptr < code_len do
		local stmt = next()
		if not stmt then
			error("Parsing error: What is (" .. tostring(consume("^(%S+)")) .. ") ?")
		elseif stmt ~= true then
			ast[#ast + 1] = stmt
		end
	end

	return Stmt.new(StmtKind.Block, ast)
end

return {
	parse = parse,

	Stmt = Stmt,
	Kind = StmtKind
}