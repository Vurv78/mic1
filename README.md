# mic1

A tiny (<300 SLOC), optimizing, statement-based language that compiles to SIC-1 code for https://github.com/jaredkrinke/sic1

```lua
local ast = parse [[
	static a = 0
	static b = 0
	static zero = 0

	loop {
		a -= b
		b += a

		zero = 0
	}

	for 4 {
		asm {
			; hello
		}
	}
]]

local compiled = compile(optimize(ast))

print("Optimized: ", compiled)
--[[
@LOOP:
subleq @A, @B
subleq @B, @ZERO
subleq @ZERO, @A
subleq @B, @A
subleq @ZERO, @ZERO, @LOOP ; <-- Optimized two instructions into a single subleq
; hello
; hello
; hello
; hello
@A: .data 0
@B: .data 0
@ZERO: .data 0
]]
```
