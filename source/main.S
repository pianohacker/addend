.title "ARMForth"
// vim: set ft=asm :

.set UART_START, 0x09000000
.set PSCI_0_2_FN_SYSTEM_OFF, 0x84000000 + 8

// # Defined registers
// This code uses the available registers according to the [AArch64 Procedure Call
// Standard](http://infocenter.arm.com/help/topic/com.arm.doc.ihi0055b/IHI0055B_aapcs64.pdf) to the
// best of its ability, i.e.:
//
//  * x0-x7 are used to pass parameters/results between functions.
//  * x8 is used as a temporary address register for indirect loads.
//  * x9-x15 are used as temporary registers, and must be saved by the caller before any call.
//  * x16 and x17 are off limits, as the assembler may use them in stubs to call faraway functions.
//  * x20-x26 are callee-saved temporary registers.
//  * x29 (the Frame Pointer) is used to hold the current top of the return stack.
#define fp x29
//  * x30 (the Link Register) holds the location of the next instruction after the last `bl`.
#define lr x30
//
// However, we have three more special registers of our own:
//  * x18 holds the Word Address, or the address of the next word to be executed.
#define wa x18
//  * x19 holds the Current Word, or the contents of the currently running word. This is mainly
//    used by `enter`, which needs a argument location for _next and repl.
#define cw x19
//  * x27 holds the Hold Pointer, or the top of the hold stack. This stack holds some temporary data
//    for combinators and the base address of held code segments and data.
#define hp x27
//  * x28 holds the Stack Pointer, or the top of the data stack. We ignore the standard stack
//    pointer because of the strict 16-byte alignment requirement.
#define sp x28

// # Useful macros
// ## Constants
.set F_IMMEDIATE,0x80
.set F_HIDDEN,0x20
.set F_LENMASK,0x1f	// length mask

// Store the chain of links.
.set link,0

// Lifted almost directly from jonesforth.
// ## `defword` - define a forth primitive
.macro defword name, namelen, flags=0, label
	.section .data
	.balign 8
	.global name_\label
	name_\label:
		.dword link		// link
		.set link,name_\label
		.byte \flags+\namelen	// flags + length byte
		.ascii "\name"		// the name

	.balign 8		// padding to next 8 byte boundary
	.global \label
	\label:
		.dword enter		// codeword - the interpreter
		// list of word pointers follow
.endm

// ## `defcode` - define an assembler primitive
.macro defcode name, namelen, flags=0, label
	.section .data
	.balign 8
	.global name_\label
	name_\label:
		.dword link		// link
		.set link,name_\label
		.byte \flags+\namelen	// flags + length byte
		.ascii "\name"		// the name

	.balign 8	// padding to next 8 byte boundary
	.globl \label
	\label:
		.dword code_\label	// codeword

	.section .text
	.globl code_\label
	code_\label :			// assembler code follows
.endm

// ## `defvar` - define a variable
.macro defvar name, namelen, flags=0, label, initial=0
	defcode \name,\namelen,\flags,\label
		ldr x0, =var_\label
		_push x0
	_next

	.section .data
	.balign 8
	var_\label:
		.dword \initial
.endm

.macro _setvar variable, source
	ldr x8, =var_\variable
	str \source, [x8]
.endm

.macro _getvar variable, dest
	ldr x8, =var_\variable
	ldr \dest, [x8]
.endm

// ## `defconst` - define a const.
.macro defconst name, namelen, flags=0, label, initial=0
	defcode \name,\namelen,\flags,\label
		ldr x8, =const_\label
		ldr x9, [x8]
		_push x9
	_next

	.section .data
	.balign 8
	const_\label:
		.dword \initial
.endm

// # Startup
// ## Alternate stack macros
.macro _push_alt stackreg:req, reg:req
	str \reg, [\stackreg, -8]!
.endm

.macro _pop_alt stackreg:req, reg
	ldr \reg, [\stackreg], 8
.endm

// ## Data stack macros
// The argument order of these macros matches the order of the values on the stack (top to the
// right); i.e.,
//
//     _push x1, x2, x3
//
// matches:
//
//     _pop x1, x2, x3
//
// This makes the memory math and recursion below a bit odd.
.macro _push reg1:req, reg2, rest:vararg
	.ifnb \reg2
	stp \reg2, \reg1, [sp, -16]!
	.else
	str \reg1, [sp, -8]!
	.endif

	.ifnb \rest
		_push \rest
	.endif
.endm

.macro _pop reg1:req, reg2, rest:vararg
	.ifnb \rest
		_pop \rest
	.endif

	.ifnb \reg2
	ldp \reg2, \reg1, [sp], 16
	.else
	ldr \reg1, [sp], 8
	.endif
.endm

.macro _save num
	_push x9, x10
	.ifgt \num - 2
	_push x11, x12
	.endif
	.ifgt \num - 4
	_push x13, x14
	.endif
	.ifgt \num - 6
	_push x15, x16
	.endif
.endm

.macro _load num
	.ifgt \num - 6
	_pop x15, x16
	.endif
	.ifgt \num - 4
	_pop x13, x14
	.endif
	.ifgt \num - 2
	_pop x11, x12
	.endif
	_pop x9, x10
.endm

// ## Control flow macros

.macro _next
	ldr cw, [wa], 8
	ldr x8, [cw]
	br x8
.endm

.macro _call func, saved_vars = 0
	.ifgt \saved_vars
		_save \saved_vars
	.endif
	bl \func
	.ifgt \saved_vars
		_load \saved_vars
	.endif
.endm

.macro _func func
	\func:
	_push_alt fp, lr
.endm

.macro _return
	_pop_alt fp, lr
	ret lr
.endm

// ## `enter` - main interpreter
.section .init
.align 3
enter:
	_push_alt fp, wa
	add wa, cw, 8
	_next

// ## Entry point
.global _start
_start:
	//### Interpreter initialization
	// Set up the stack starting locations.
	ldr hp, =__hold_stack_end
	_setvar hz, hp
	ldr fp, =__return_stack_end
	_setvar rz, fp
	ldr sp, =__data_stack_end
	_setvar sz, sp

	// Set the next word as "quit."
	ldr wa, =_interpret_start
	_next

.data
_interpret_start:
	.dword quit

// # Builtins
// ## Arithmetic
// `( a b -- sum )`, adds two integers.
defcode "+", 1, , add
	_pop x9, x10
	add x9, x9, x10
	_push x9
_next

// `( a b -- difference )`, subtracts two integers (a - b).
defcode "-", 1, , sub
	_pop x9, x10
	sub x9, x9, x10
	_push x9
_next

// `( a b -- product )`, multiplies two integers.
defcode "*", 1, , mult
	_pop x9, x10
	smull x9, w9, w10
	_push x9
_next

// `( a b -- quotient )`, divides two integers (a / b).
defcode "/", 1, , div
	_pop x9, x10
	sdiv x9, x9, x10
	_push x9
_next

// `( a b -- modulus )`, pushes a % b.
defcode "mod", 3, , mod
	_pop x9, x10
	// This approach is taken from GCC:
	//
	//     a % b = a - (a // b) * b
	//
	// First, `x11 = x9(a) // x10`.
	sdiv x11, x9, x10
	// Then, `x9(a) - x11(a // b) * x10`. (The ARM operand ordering is screwy.)
	msub x9, x11, x10, x9
	_push x9
_next

// ## Comparison
.macro _2cmp
	_pop x9, x10
	cmp x9, x10
.endm

defcode "=", 1, , equal
	_2cmp
	mov x11, 1
	csel x11, x11, xzr, eq
	_push x11
_next

// ## Syntax
defcode "lit", 3, , lit
	ldr cw, [wa], 8
	_push cw
_next

// `( -- ) name`, pushes the address of the next word on the stack.
defcode "'", 1, , tick
	ldr x9, [wa], 8
	_push x9
_next

defcode "branch", 6, , branch
	ldr x9, [wa]
	add wa, wa, x9
_next

defcode "0branch", 7, , zbranch
	_pop x9
	cmp x9, 0
	b.eq code_branch

	add wa, wa, 8
_next

defcode "char", 4, , char
	_call _word
	cmp x1, 0
	b.eq char_done

	ldrb w9, [x0]
	_push x9

	char_done:
_next

// ## Stack manipulation
// `( value -- )`, drops a value from the stack.
defcode "drop", 4, , drop
	_pop x0
_next

// `( a b -- b a )`, swaps the top two values on the stack.
defcode "swap", 4, , swap
	_pop x9, x10
	_push x10, x9
_next

// `( value -- value value )`, duplicates the top of the stack.
defcode "dup", 3, , dup
	ldr x9, [sp]
	_push x9
_next

// ## Alternate stack manipulation
// `( new-return-stack -- )`, changes the return stack pointer.
defcode "rsp!", 4, , rspstore
	_pop fp
_next

// `( val -- )`, pushes the given value to the return stack.
defcode "r>", 2, , tors
	_pop x0
	_push_alt fp, x0
_next

// `( -- val )`, pops a value from the return stack.
defcode "r>", 2, , fromrs
	_pop_alt fp, x0
	_push x0
_next

// `( val -- )`, pushes the given value to the hold stack.
defcode ">h", 2, , tohs
	_pop x0
	_push_alt hp, x0
_next

// `( -- val )`, pops a value from the hold stack.
defcode "h>", 2, , fromhs
	_pop_alt hp, x0
	_push x0
_next

// `( -- val )`, fetches a value from the hold stack without changing it.
defcode "h@", 2, , fetchhs
	ldr x0, [hp]
	_push x0
_next

// ## Memory
// `( address -- value )`, fetches a word from memory.
defcode "@", 1, , fetch
	_pop x1
	ldr x0, [x1]
	_push x0
_next

// `( address value -- )`, stores a word in memory.
defcode "!", 1, , store
	_pop x0, x1
	str x1, [x0]
_next

// ## Control structures
defcode "exit", 4, , exit
	_pop_alt fp, wa
_next

// ## Dictionary manipulation
// `( word-addr word-len -- )`, creates a new word.
defcode "create", 6, , create
	// Get length of name.
	_pop x1
	// Get address of name.
	_pop x0

	_getvar here, x9
	_getvar latest, x10

	str x10, [x9]
	mov x10, x9
	add x9, x9, 8
	strb w1, [x9], 1

	mov x11, 0
	_create_copy_name:
	ldrb w12, [x0,x11]
	strb w12, [x9,x11]
	add x11, x11, 1
	cmp x11, x1
	b.ne _create_copy_name
	add x9, x9, x1

	// Align to next 8-byte boundary.
	add x9, x9, 7
	and x9, x9, ~7

	_setvar here, x9
	_setvar latest, x10
_next

_func _find
	_getvar latest, x2

	_find_loop:
	cmp x2, 0
	// We've looked through every entry, and have reached the end; return 0.
	b.eq _find_done

	// Skip the link.
	add x9, x2, 8

	// Read and check the length byte; we don't mask out F_HIDDEN to make sure hidden words never
	// match.
	ldrb w10, [x9], 1
	and w10, w10, (F_HIDDEN | F_LENMASK)
	cmp w10, w1
	b.ne _find_next

	mov x10, 0
	_find_char:
	ldrb w11, [x9,x10]
	ldrb w12, [x0,x10]
	cmp w11, w12
	b.ne _find_next

	add x10, x10, 1
	cmp x10, x1
	// We made it all the way to the end of the word without a mismatch; we're good!
	b.eq _find_done
	b _find_char

	_find_next:
	ldr x2, [x2]
	b _find_loop

	_find_done:
	_return

// ## Codeword manipulation
_func _comma
	_getvar here, x9
	str x0, [x9], 8
	_setvar here, x9
	_return

// `(value -- )`, appends the value to user memory.
defcode ",", 1, , comma
	_pop x0
	_call _comma
_next

// `(word-entry -- )`, toggles the hidden state of the given word.
defcode "hidden", 6, , hidden
	_pop x0
	// Skip the link.
	ldrb w9, [x0, 8]!
	eor w9, w9, F_HIDDEN
	strb w9, [x0]
_next

// `( -- )`, toggles the immediate state of the most recent word.
defcode "immediate", 9, F_IMMEDIATE, immediate
	_getvar latest, x9
	// Skip the link.
	ldrb w10, [x9, 8]!
	eor w10, w10, F_IMMEDIATE
	strb w10, [x9]
_next

// `( -- ) word-name`, starts defining a new word.
defword ":", 1, , colon
	.dword word
	.dword create
	.dword lit, enter, comma
	.dword latest, fetch, hidden
	.dword hlplus
	.dword exit
_next

// `( -- )`, finishes defining a new word.
defword ";", 1, F_IMMEDIATE, semicolon
	.dword lit, exit, comma
	.dword latest, fetch, hidden
	.dword hlminus
	.dword exit
_next

_func _tcfa
	// Skip the link.
	add x0, x0, 8

	// Skip the name.
	ldrb w9, [x0]
	add x0, x0, 1

	and w9, w9, F_LENMASK
	add x0, x0, x9

	// ... and align.
	add x0, x0, 7
	and x0, x0, ~7
	_return

// `(word-entry -- codeword-ptr)`, converts a word address to a codeword address.
defcode ">cfa", 4, , tcfa
	_pop x0
	_call tcfa
	_push x0
_next

// ## I/O

// `( -- char)`, reads a single character.
defcode "key", 3, , key
	_call _key
	_push x0
_next

_func _key
	_GETVAR key_buffer, x9
	cmp x9, 0
	b.eq _key_serial

	_GETVAR key_buffer_end, x10
	ldrb w0, [x9], 1
	cmp x9, x10
	b.ne _key_bufread_done
	mov x9, 0

	_key_bufread_done:
	_setvar key_buffer, x9
	_return

	_key_serial:
	ldr x10, =UART_START
	_key_wait_for_input:
	// Load RXFF (receive fifo full) from UARTFR (flags register)
	ldrb w9, [x10,0x18]
	ubfx w9, w9, 6, 1
	cmp w9, 1
	b.eq _key_read
	wfe
	b _key_wait_for_input

	_key_read:
	ldrb w0, [x10]

	cmp w0, '\r'
	b.ne _key_read_done
	mov w0, '\n'
	_key_read_done:

	// Echo typed character if desired
	_getvar echo, x11
	cmp x11, 0
	b.eq _key_done
	strb w0, [x10]

	_key_done:
	_return

defcode "word", 4, , word
	_call _word
	_push x0, x1
_next

_func _word
	ldr x9, =__word_read_buffer
	mov x1, 0

	_call _key, 2
	cmp w0, '\\'
	b.eq _word_skip_comment

	_word_key:
	cmp w0, ' '
	b.eq _word_done
	cmp w0, '\t'
	b.eq _word_done
	cmp w0, '\r'
	b.eq _word_done
	cmp w0, '\n'
	b.eq _word_done

	strb w0, [x9,x1]
	add x1, x1, 1

	_call _key, 2
	b _word_key

	_word_done:
	mov x0, x9
	_return

	_word_skip_comment:
	_call _key, 2
	cmp w0, '\n'
	b.ne _word_skip_comment
	b _word_key
	_return

_func _emit
	ldr x8, =UART_START
	strb w0, [x8]
	_return

// `( character -- )`, emits a single character.
defcode "emit", 4, , emit
	_pop x0
	_call _emit
_next

_func _tell
	cmp x1, 0
	b.eq _tell_done

	ldr x9, =UART_START

	_tell_char:
	ldrb w10, [x0], 1
	strb w10, [x9]
	sub x1, x1, 1
	cmp x1, 0
	b.ne _tell_char

	_tell_done:
	_return

defcode "tell", 4, , tell
	_pop x0, x1

	_call _tell
_next

defcode "litstring", 9, , litstring
	ldr x9, [wa], 8
	_push wa, x9
	// Skip past the string, then align.
	add wa, wa, x9
	add wa, wa, 7
	and wa, wa, ~7
_next

// ## Interpreter
// Temporarily switch to immediate (interpreting) mode.
defcode "[", 1, F_IMMEDIATE, lbrac
	_getvar level, x0
	_push_alt hp, x0
	mov x0, 0
	_setvar level, x0
_next

// Return to the previous mode.
defcode "]", 1, , rbrac
	_pop_alt hp, x0
	_setvar level, x0
_next

// Interpret the given word as a number.
_func _number
	// Successful parse?
	mov x2, 1
	// Resulting number.
	mov x3, 0
	// Position in the word.
	mov x9, 0
	// Sign of the word.
	mov x10, 1
	// Current character.
	mov w11, 0
	// Current base.
	_getvar base, x12

	ldrb w11, [x0]
	cmp w11, '-'
	b.eq _number_neg
	b _number_char

	_number_neg:
	mov x10, -1
	add x9, x9, 1

	_number_char:
	mul x3, x3, x12
	ldrb w11, [x0,x9]

	subs w11, w11, '0'
	b.lt _number_fail
	cmp w11, 9
	b.le _number_digit
	subs w11, w11, 'A' - '0'
	b.lt _number_fail
	cmp w11, 25
	b.gt _number_fail
	add w11, w11, 10

	_number_digit:
	cmp w11, w12
	b.ge _number_fail
	add x3, x3, x11

	_number_next_char:
	add x9, x9, 1
	cmp x9, x1
	b.eq _number_done
	b _number_char

	_number_fail:
	mov x2, 0

	_number_done:
	// Multiply in the sign.
	mul x3, x3, x10
	_return

// `( -- )`, powers off the machine.
defcode "halt", 4, , halt
	ldr x0, =PSCI_0_2_FN_SYSTEM_OFF
	hvc 0
	_next

// `( -- )`, starts a new hold level.
_func _hlplus
	_getvar level, x0
	add x0, x0, 1
	_setvar level, x0
	_return

defcode "hl+", 4, , hlplus
	_call _hlplus
	_next

// `( -- )`, finishes a hold level.
_func _hlminus
	_getvar level, x9
	subs x0, x9, 1
	// If x0 is >= 0, use it, otherwise fall back to the original x9 (which must be 0).
	csel x0, x0, x9, ge
	_setvar level, x0
	_return

defcode "hl-", 4, , hlminus
	_call _hlminus
	_next

// `( -- )`, starts a hold level and saves the current `here`.
defcode "record", 6, , record
	_call _hlplus

	_getvar here, x10
	_push_alt hp, x10
	_next

// `( -- )`, finishes a hold level and plays it.
//
// This has two different possible effects, depending on the new hold level:
//   * >= 1: just leaves the complied code since the last `record` in the definition segment.
//   * 0: after gluing on an `exit`, the code since the last `record` is immediately run.
//
// This means that words that manipulate the definition segment can behave identically when used in
// compiled and interpreted mode.
defcode "play", 4, , play
	_call _hlminus

	_pop_alt hp, x9

	cmp x0, 0
	b.gt play_done

	ldr x0, =exit	
	_call _comma, 2

	// We are playing tricky games with `enter` here; we're loading up the cw for it, but because
	// there isn't actually a `enter` on the front of our "word", we have to undo `enter`'s skip of
	// itself.
	sub cw, x9, 8
	b enter

	play_done:
	_next

// `( -- addr )`, packages the code since the last `record` and gives back the address.
defcode "save", 4, , save
	_call _hlminus

	_pop_alt hp, x9
	ldr x0, =exit	
	_call _comma, 2

	_push x9
	_next

// `( codeword-addr -- )`, runs the code at the given address.
defcode "execute", 7, , execute
	_pop x9
	mov cw, x9
	ldr x8, [cw]
	br x8

defcode "repl", 4, , repl
	_call _word
	cmp x1, 0
	// Empty, don't bother.
	b.eq repl_done

	_call _find
	cmp x2, 0
	b.ne repl_interpret

	// If it wasn't a valid word, maybe it's a number.
	repl_maybe_number:
	_call _number
	cmp x2, 0
	b.eq repl_invalid

	// If it is a number, then we need to either:
	_getvar level, x9
	cmp x9, 0
	b.eq repl_interpret_number
	//   a) if compiling, push the number (with a preceding lit) onto the current definition
	ldr x0, =lit
	_call _comma
	mov x0, x3
	_call _comma
	b repl_done

	repl_interpret_number:
	//   b) or, if interpreting, just push it on the stack.
	_push x3
	b repl_done

	repl_invalid:
	_push x0, x1
	ldr x0, =error_message
	ldr x1, =error_message_len
	_call _tell
	_pop x0, x1
	_call _tell
	mov w0, '\n'
	_call _emit
	b repl_done

	repl_interpret:
	mov x0, x2
	_call _tcfa

	// We should run the word if either:
	//   a) We're in interpreting mode
	_getvar level, x9
	cmp x9, 0
	b.eq repl_run

	//   or b) the word is immediate.
	ldrb w10, [x2, 8]
	and w10, w10, F_IMMEDIATE
	cmp x10, 0
	b.ne repl_run

	// Otherwise, we need to compile it.
	_call _comma
	b repl_done

	repl_run:
	mov cw, x0
	ldr x8, [cw]
	br x8

	repl_done:
	_next


defword "quit", 4, , quit
	.dword rz, fetch, rspstore
	.dword lit, welcome_message
	.dword lit, welcome_message_len
	.dword tell
	.dword repl
	.dword branch, -16

// # Builtin variables
// Start of stacks.
defvar "h0", 2, , hz
defvar "s0", 2, , sz
defvar "r0", 2, , rz
// Whether `key` echos while it reads.
defvar "echo", 4, , echo, 1
// Most recently defined word; initial value must be the last builtin word in this file.
defvar "latest", 6, , latest, name_enter_
// Position of next allocated byte.
defvar "here", 4, , here, __data_seg_end
// How many levels are held? (0 = interpreting)
defvar "level", 5, , level, 0
// Base we are currently interpreting numbers in.
defvar "base", 4, , base, 10
// Start and end of current `key` input buffer. `key` will _immediately_ start reading from
// `key-buffer` if it is nonzero.
defvar "key-buffer", 10, , key_buffer, __builtins_def_start
defvar "key-buffer-end", 14, , key_buffer_end, __builtins_def_end

// # Builtin constants
defconst "enter", 5, , enter_, enter

.section .data
welcome_message:
	.ascii "Welcome to ARMForth!\n"
.set welcome_message_len, . - welcome_message

error_message:
	.ascii "\nNot a number or known word: "
.set error_message_len, . - error_message

__word_read_buffer:
	.skip 32

.align 3
.skip 0x1000
__hold_stack_end:

.align 3
.skip 0x1000
__return_stack_end:

.align 3
.skip 0x10000
__data_stack_end:

__builtins_def_start:
.incbin "builtins.fs"
__builtins_def_end:

.align 3
