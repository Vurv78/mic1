local Mic = require "src.mic1"

local ast = Mic.parse([[
	static a = 0
	loop {
		a = 0
	}
]])

Assert.equal(
	Mic.compile(Mic.optimize(ast)),
	table.concat({
		"", -- static a = 0
		"@LOOP:", -- loop {
		"subleq @A, @A, @LOOP", -- a = 0 and loop repeat optimization
		"@A: .data 0" -- set a to 0
	}, "\n")
)