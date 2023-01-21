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
local function parse(code, macros)
	local ptr, code_len = 1, #code
	macros = macros or {}

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
			if consume("^%)") then
				macros[name] = macros[name] or {}
				macros[name][#macros[name] + 1] = {{}, assert(consume("^(%b{})"), "Expected block for macro"):sub(2, -2)} return true end
			repeat
				if consume("^%$") then
					local param_name = assert(consume("^(%w+)"), "Expected parameter name after $")
					assert(consume("^:"), "Expected colon before macro parameter type")
					local param_type = assert(consume("^(%w+)"), "Expected parameter type")
					assert( ({block=1, address=1, string=1, number=1})[param_type], "Invalid macro parameter type (" .. param_type .. "), expected block, string or number")
					params[#params + 1] = { false, param_name, param_type }
				else
					-- Raw syntax in between. Usually a comma
					local token = assert(consume("^([^$)]+)"), "Expected token for macro parameter, got EOF")
					params[#params + 1] = { true, token }
				end
			until consume("^%)")

			local block = assert(consume("^(%b{})"), "Expected block for macro"):sub(2, -2)
			macros[name] = macros[name] or {}
			macros[name][#macros[name] + 1] = {params, block}

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
				local overloads = assert(macros[op], "Macro does not exist: " .. op)
				assert(consume("^%("), "Expected left paren to begin macro arguments")

				local expected = {}
				for k, macro in ipairs(overloads) do
					local args, last, old_ptr = {}, #macro[1], ptr
					for i, data in ipairs(macro[1]) do
						if data[1] then
							-- Raw syntax; Todo: Escape lua pattern syntax :p
							local token = consume("^" .. data[2])
							if not token then expected[#expected + 1] = "token " .. data[2] break end
						else
							if data[3] == "block" then
								local token = consume("^(%b{})")
								if not token then expected[#expected + 1] = "block" break end
								args[data[2]] = token:sub(2, -2)
							elseif data[3] == "address" then
								local token = consume("^($?[%w_]+)")
								if not token then expected[#expected + 1] = "address" break end
								args[data[2]] = assert(token, "Expected address for macro argument #" .. i)
							elseif data[3] == "string" then
								local token = consume("^(\"[^\"]+\")")
								if not token then expected[#expected + 1] = "string literal" break end
								args[data[2]] = token
							else -- number
								local token = consume("^(%d+)")
								if not token then expected[#expected + 1] = "number literal" break end
								args[data[2]] = token
							end
						end

						if i == last then
							assert(consume("^%)"), "Expected right paren to end macro arguments")
							return parse(macro[2]:gsub("$(%w+)", args), macros)
						end
					end

					ptr = old_ptr
				end

				error("Expected " .. table.concat(expected, " or ") .. " for macro argument")
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
				error("Parsing error: What is (" .. tostring(consume("^(%S+)") or "EOF") .. ")? @" .. ptr)
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
			error("Parsing error: What is (" .. tostring(consume("^(%S+)") or "EOF") .. ")? @" .. ptr)
		elseif stmt ~= true then
			ast[#ast + 1] = stmt
			skipWhitespace()
		end
	end

	return Stmt.new(StmtKind.Block, ast)
end

return {
	parse = parse,

	Stmt = Stmt,
	Kind = StmtKind
}