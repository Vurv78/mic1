local Mic = require "src.mic1"

local ast = Mic.parse([[
	static a = 0
	loop {
		a = 0
	}
]])

print( Mic.compile(Mic.optimize(ast)) )

Assert.equal(
	Mic.compile(Mic.optimize(ast)),
	Sic(
		"", -- static a = 0
		"@LOOP1:", -- loop {
		"", -- I don't know why this exists but I'm not going to question it for now.
		"subleq @A, @A, @LOOP1", -- a = 0 and loop repeat optimization
		"@A: .data 0" -- set a to 0
	)
)