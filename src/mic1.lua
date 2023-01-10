--[[
	Optimizing Compiler for a Statement-Only Language into SIC-1
		by Vurv
]]

local parser = require("compiler.parser")
local optimizer = require("compiler.optimizer")
local codegen = require("compiler.codegen")

return {
	parse = parser.parse,
	optimize = optimizer.optimize,
	compile = codegen.compile
}