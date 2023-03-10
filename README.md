# mic1

A tiny (400 SLOC), optimizing, metaprogrammable, statement-based language that compiles to SIC-1 code for https://github.com/jaredkrinke/sic1

`Source`:
```rust
static a = 0
static msg = -"Hello, world!" // String literals
static zero = 0

loop { // Infinite loop syntax sugar
	a -= $in // Inputs
	echo a + 2 // Address offsets + Printing syntax sugar

	if a < 0 {
		echo msg // Can print strings too
	} else {
		echo a
	}

	zero = 0 // This is zero cost, since the loop will hijack this and use it to reset (jmp) to the beginning of the loop!
}

for 4 { // Compile time unfolded loop
	asm {
		; Write raw sic-1 code if needed.
	}
}

// Metaprogramming, recreating built-in operations using asm blocks.
macro lua(print $s:string) { // Can input addresses, numbers, strings, blocks and any other syntax.
	static internal_print = -$s
	$out -= internal_print
}

macro lua(while true do $block: block) { // Note there's also overloads.
	static jmphack = 0
	asm {@FOREVER:}
	$block
	asm {subleq @JMPHACK, @JMPHACK, @FOREVER}
}

lua! ( // Equivalent to static msg = -"Hello, world!" loop { echo msg }
	while true do {
		lua! (
			print "Hello, world!"
		)
	}
)
```

`Compiled`:
```haskell
@LOOP1:
subleq @A, @IN
subleq @OUT, @A+2
subleq @ZERO, @A, @ELSE1
subleq @ZERO, @ZERO, @IF1
@IF1:
@LOOP2:
subleq @OUT, @MSG
subleq @LOOP2+1, @NEGATIVE_ONE
subleq @ZERO, @ZERO, @LOOP2
@ELSE1:
subleq @OUT, @A
subleq @ZERO, @ZERO, @LOOP1
; Write raw sic-1 code if needed.
; Write raw sic-1 code if needed.
; Write raw sic-1 code if needed.
; Write raw sic-1 code if needed.
@FOREVER:
subleq @OUT, @INTERNAL_PRINT
subleq @JMPHACK, @JMPHACK, @FOREVER
@A: .data 0
@MSG: .data -"Hello, world!"
@ZERO: .data 0
@NEGATIVE_ONE: .data -1
@JMPHACK: .data 0
@INTERNAL_PRINT: .data -"Hello, world!"
```
