local parser = require "compiler.parser"
local Stmt, StmtKind = parser.Stmt, parser.Kind

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

return {
	optimize = optimize,
}