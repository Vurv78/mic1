# mic1

A tiny (<300 SLOC), optimizing, statement-based language that compiles to SIC-1 code for https://github.com/jaredkrinke/sic1

```lua
local ast = parse [[
	// Comment

	static a = 0
	static b = 0
	static zero = 0

	loop {
		a -= b
		b += a

		echo b

		zero = 0
	}

	for 4 {
		asm {
			; hello
		}
	}
]]

print( compile( optimize(ast) ) )
--[[
@LOOP:
subleq @A, @B
subleq @B, @ZERO
subleq @ZERO, @A
subleq @B, @A
subleq @OUT @B
subleq @ZERO, @ZERO, @LOOP
; hello
; hello
; hello
; hello
@A: .data 0
@B: .data 0
@ZERO: .data 0
```
