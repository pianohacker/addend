.title "ARMForth"
// vim: set ft=asm :

#define UART_START 0x09000000

// # Defined registers
// This code uses the available registers according to the [AArch64 Procedure Call
// Standard](http://infocenter.arm.com/help/topic/com.arm.doc.ihi0055b/IHI0055B_aapcs64.pdf) to the
// best of its ability, i.e.:
//
//  * x0-x7 are used to pass parameters/results between functions.
//  * x8 is used as a temporary address register for indirect loads.
//  * x9-x15 are used as temporary registers, and must be saved by the caller before any call.
//  * x16 and x17 are off limits, as the assembler may use them in stubs to call faraway functions.
//  * x20-x27 are callee-saved temporary registers.
//  * x29 (the Frame Pointer) is used to hold the current top of the return stack.
#define fp x29
//  * x30 (the Link Register) holds the location of the next instruction after the last `bl`.
#define lr x30
//
// However, we have three more special registers of our own:
//  * x18 holds the Word Address, or the address of the next word to be executed.
#define wa x18
//  * x19 holds the Current Word, or the contents of the currently running word. This is mainly
//    used by DOCOL, which needs a argument location for _NEXT and REPL.
#define cw x19
//  * x28 holds the Stack Pointer, or the top of the data stack. We ignore the standard stack
//    pointer because of the strict 16-byte alignment requirement.
#define sp x28

/* # Useful macros */
/* ## Constants */
.set F_IMMEDIATE,0x80
.set F_HIDDEN,0x20
.set F_LENMASK,0x1f	// length mask

/*  Store the chain of links. */
.set link,0

/* Lifted almost directly from jonesforth. */
/* ## `defword` - define a forth primitive */
.macro defword name, namelen, flags=0, label
	.section .data
	.balign 8
	.globl name_\label
name_\label:
	.dword link		// link
	.set link,name_\label
	.byte \flags+\namelen	// flags + length byte
	.ascii "\name"		// the name
	.balign 8		// padding to next 8 byte boundary
	.globl \label
\label:
	.dword DOCOL		// codeword - the interpreter
	// list of word pointers follow
.endm

/* ## `defcode` - define an assembler primitive */
.macro defcode name, namelen, flags=0, label
	.section .data
	.balign 8
	.globl name_\label
name_\label:
	.dword link		// link
	.set link,name_\label
	.byte \flags+\namelen	// flags + length byte
	.ascii "\name"		// the name
	.balign 8	// padding to next 8 byte boundary
	.globl \label
\label:
	.dword code_\label	// codeword
.text
	//.align 4
	.globl code_\label
code_\label :			// assembler code follows
.endm

/* ## `defvar` - define a variable */

.macro defvar name, namelen, flags=0, label, initial=0
	defcode \name,\namelen,\flags,\label
		ldr x0, =var_\name
		_PUSH x0
	_NEXT

.section .data
	.align 3
var_\name:
	.dword \initial
.endm

.macro _SETVAR variable, value
	ldr x8, =var_\variable
	str \value, [x8]
.endm

.macro _GETVAR variable, dest
	ldr x8, =var_\variable
	ldr \dest, [x8]
.endm

/* # Startup */
/* ## Return stack macros */
.macro _PUSH_RS reg
	str \reg, [fp, -8]!
.endm

.macro _POP_RS reg
	ldr \reg, [fp], 8
.endm

/* ## Data stack macros */
// The argument order of these macros matches the order of the values on the stack (top to the
// right); i.e.,
//
//     _PUSH x1, x2, x3
//
// matches:
//
//     _POP x1, x2, x3
//
// This makes the memory math and recursion below a bit odd.
.macro _PUSH reg1:req, reg2, rest:vararg
	.ifnb \reg2
	stp \reg2, \reg1, [sp, -16]!
	.else
	str \reg1, [sp, -8]!
	.endif

	.ifnb \rest
		_PUSH \rest
	.endif
.endm

.macro _POP reg1:req, reg2, rest:vararg
	.ifnb \rest
		_POP \rest
	.endif

	.ifnb \reg2
	ldp \reg2, \reg1, [sp], 16
	.else
	ldr \reg1, [sp], 8
	.endif
.endm

.macro _SAVE num
	_PUSH x9, x10
	.ifgt \num - 2
	_PUSH x11, x12
	.endif
	.ifgt \num - 4
	_PUSH x13, x14
	.endif
	.ifgt \num - 6
	_PUSH x15, x16
	.endif
.endm

.macro _LOAD num
	.ifgt \num - 6
	_POP x15, x16
	.endif
	.ifgt \num - 4
	_POP x13, x14
	.endif
	.ifgt \num - 2
	_POP x11, x12
	.endif
	_POP x9, x10
.endm

/* ## Control flow macros */

.macro _NEXT
	ldr cw, [wa], 8
	ldr x8, [cw]
	br x8
.endm

.macro _CALL func, saved_vars = 0
	.ifgt \saved_vars
		_SAVE \saved_vars
	.endif
	bl \func
	.ifgt \saved_vars
		_LOAD \saved_vars
	.endif
.endm

.macro _FUNC func
	\func:
	_PUSH_RS lr
.endm

.macro _RETURN
	_POP_RS lr
	ret lr
.endm

/* ## `DOCOL` - main interpreter */
.section .init
.align 3
DOCOL:
	_PUSH_RS wa
	add wa, cw, 8
	_NEXT

/* ## Entry point */
.global _start
_start:
	//### Interpreter initialization
	// Set up the stack starting locations.
	ldr fp, =__return_stack_end
	ldr sp, =__data_stack_end
_SETVAR R0, fp
	_SETVAR S0, sp

	// Set the next word as "QUIT."
	ldr wa, =_interpret_start
	_NEXT

.data
_interpret_start:
	.dword QUIT

/* # Builtins */
/* ## Arithmetic */
// `( a b -- sum )`, adds two integers.
defcode "+", 1, , ADD
	_POP x9, x10
	add x9, x9, x10
	_PUSH x9
_NEXT

// `( a b -- difference )`, subtracts two integers (a - b).
defcode "-", 1, , SUB
	_POP x9, x10
	sub x9, x9, x10
	_PUSH x9
_NEXT

// `( a b -- product )`, multiplies two integers.
defcode "*", 1, , MULT
	_POP x9, x10
	smull x9, w9, w10
	_PUSH x9
_NEXT

// `( a b -- quotient )`, divides two integers (a / b).
defcode "/", 1, , DIV
	_POP x9, x10
	sdiv x9, x9, x10
	_PUSH x9
_NEXT

// `( a b -- modulus )`, pushes a % b.
defcode "MOD", 1, , MOD
	_POP x9, x10
	// This approach is taken from GCC:
	//
	//     a % b = a - (a // b) * b
	//
	// First, `x11 = x9(a) // x10`.
	sdiv x11, x9, x10
	// Then, `x9(a) - x11(a // b) * x10`. (The ARM operand ordering is screwy.)
	msub x9, x11, x10, x9
	_PUSH x9
_NEXT

/* ## Comparison */
.macro _2CMP
	_POP x9, x10
	cmp x9, x10
.endm

defcode "=", 1, , EQUAL
	_2CMP
	mov x11, 1
	csel x11, x11, xzr, eq
	_PUSH x11
_NEXT

/* ## Syntax */
defcode "LIT", 3, , LIT
	ldr cw, [wa], 8
	_PUSH cw
_NEXT

// `( -- ) name`, pushes the address of the next word on the stack.
defcode "'", 1, , TICK
	ldr x9, [wa], 8
	_PUSH x9
_NEXT

defcode "BRANCH", 6, , BRANCH
	ldr x0, [wa]
	add wa, wa, x0
_NEXT

defcode "0BRANCH", 7, , ZBRANCH
	_POP x0
	cmp x0, 0
	b.eq code_BRANCH

	add wa, wa, 8
_NEXT

defcode "CHAR", 4, , CHAR
	_CALL _WORD
	cmp x1, 0
	b.eq CHAR_done

	ldrb w9, [x0]
	_PUSH x9

	CHAR_done:
_NEXT

/* ## Stack manipulation */
// `( value -- )`, drops a value from the stack.
defcode "DROP", 4, , DROP
	_POP x0
_NEXT

// `( val1 val2 -- val2 val1 )`, swaps the top two values on the stack.
defcode "SWAP", 4, , SWAP
	_POP x9, x10
	_PUSH x10, x9
_NEXT

/* ## Return stack manipulation */
// `( new-return-stack -- )`, changes the return stack pointer.
defcode "RSP!", 4, , RSPSTORE
	_POP fp
_NEXT

/* ## Memory */
// `( address -- value )`, fetches a word from memory.
defcode "@", 1, , FETCH
	_POP x1
	ldr x0, [x1]
	_PUSH x0
_NEXT

// `( address value -- )`, stores a word in memory.
defcode "!", 1, , STORE
	_POP x1
	_POP x0
	str x1, [x0]
_NEXT

/* ## Control structures */
defcode "EXIT", 4, , EXIT
	_POP_RS wa
_NEXT

/* ## Dictionary manipulation */
// `( word-addr word-len -- )`, creates a new word.
defcode "CREATE", 6, , CREATE
	// Get length of name.
	_POP x1
	// Get address of name.
	_POP x0

	_GETVAR HERE, x9
	_GETVAR LATEST, x10

	str x10, [x9]
	mov x10, x9
	add x9, x9, 8
	strb w1, [x9], 1

	mov x11, 0
	_CREATE_copy_name:
	ldrb w12, [x0,x11]
	strb w12, [x9,x11]
	add x11, x11, 1
	cmp x11, x1
	b.ne _CREATE_copy_name
	add x9, x9, x1

	// Align to next 8-byte boundary.
	add x9, x9, 7
	and x9, x9, ~7

	_SETVAR HERE, x9
	_SETVAR LATEST, x10
_NEXT

_FUNC _FIND
	_GETVAR LATEST, x2

	_FIND_loop:
	cmp x2, 0
	// We've looked through every entry, and have reached the end; return 0.
	b.eq _FIND_done

	// Skip the link.
	add x9, x2, 8

	// Read and check the length byte; we don't mask out F_HIDDEN to make sure hidden words never
	// match.
	ldrb w10, [x9], 1
	and w10, w10, (F_HIDDEN | F_LENMASK)
	cmp w10, w1
	b.ne _FIND_next

	mov x10, 0
	_FIND_char:
	ldrb w11, [x9,x10]
	ldrb w12, [x0,x10]
	cmp w11, w12
	b.ne _FIND_next

	add x10, x10, 1
	cmp x10, x1
	// We made it all the way to the end of the word without a mismatch; we're good!
	b.eq _FIND_done
	b _FIND_char

	_FIND_next:
	ldr x2, [x2]
	b _FIND_loop

	_FIND_done:
	_RETURN

/* ## Codeword manipulation */
_FUNC _COMMA
	_GETVAR HERE, x9
	str x0, [x9], 8
	_SETVAR HERE, x9
	_RETURN

// `(value -- )`, appends the value to user memory.
defcode ",", 1, , COMMA
	_POP x0
	_CALL _COMMA
_NEXT

// `(word-entry -- )`, toggles the hidden state of the given word.
defcode "HIDDEN", 6, , HIDDEN
	_POP x0
	// Skip the link.
	ldrb w9, [x0, 8]!
	eor w9, w9, F_HIDDEN
	strb w9, [x0]
_NEXT

// `( -- )`, toggles the immediate state of the most recent word.
defcode "IMMEDIATE", 9, F_IMMEDIATE, IMMEDIATE
	_GETVAR LATEST, x9
	// Skip the link.
	ldrb w10, [x9, 8]!
	eor w10, w10, F_IMMEDIATE
	strb w10, [x9]
_NEXT

// `( -- ) word-name`, starts defining a new word.
defword ":", 1, , COLON
	.dword WORD
	.dword CREATE
	.dword LIT, DOCOL, COMMA
	.dword LATEST, FETCH, HIDDEN
	.dword RBRAC
	.dword EXIT
_NEXT

// `( -- )`, finishes defining a new word.
defword ";", 1, F_IMMEDIATE, SEMICOLON
	.dword LIT, EXIT, COMMA
	.dword LATEST, FETCH, HIDDEN
	.dword LBRAC
	.dword EXIT
_NEXT

_FUNC _TCFA
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
	_RETURN

// `(word-entry -- codeword-ptr)`, converts a word address to a codeword address.
defcode ">CFA", 4, , TCFA
	_POP x0
	_CALL TCFA
	_PUSH x0
_NEXT

/* ## I/O */

// `( -- char)`, reads a single character.
defcode "KEY", 3, , KEY
	_CALL _KEY
	_PUSH x0
_NEXT

_FUNC _KEY
	ldr x10, =__builtins_def_end
	ldr x8, =__loading_builtins
	ldr x9, [x8]
	cmp x9, 0
	b.eq _KEY_serial
	ldrb w0, [x9], 1
	cmp x9, x10
	b.ne _KEY_builtin_done
	mov x9, 0
	_KEY_builtin_done:
	str x9, [x8]
	b _KEY_done

	_KEY_serial:
	ldr x10, =UART_START
	_KEY_wait_for_input:
	// Load RXFF (receive fifo full) from UARTFR (flags register)
	ldrb w9, [x10,0x18]
	ubfx w9, w9, 6, 1
	cmp w9, 1
	b.eq _KEY_read
	wfe
	b _KEY_wait_for_input

	_KEY_read:
	ldrb w0, [x10]

	cmp w0, '\r'
	b.ne _KEY_read_done
	mov w0, '\n'
	_KEY_read_done:

	// Echo typed character if desired
	ldr x12, =var_ECHO
	ldr x11, [x12]
	cmp x11, 0
	b.eq _KEY_done
	strb w0, [x10]

	_KEY_done:
	_RETURN

defcode "WORD", 4, , WORD
	_CALL _WORD
	_PUSH x0, x1
_NEXT

_FUNC _WORD
	ldr x9, =__word_read_buffer
	mov x1, 0

	_WORD_key:
	_CALL _KEY, 2

	cmp w0, '\\'
	b.eq _WORD_skip_comment
	cmp w0, ' '
	b.eq _WORD_done
	cmp w0, '\t'
	b.eq _WORD_done
	cmp w0, '\r'
	b.eq _WORD_done
	cmp w0, '\n'
	b.eq _WORD_done

	strb w0, [x9,x1]
	add x1, x1, 1
	b _WORD_key

	_WORD_done:
	mov x0, x9
	_RETURN

	_WORD_skip_comment:
	_CALL _KEY, 2
	cmp w0, '\n'
	b.ne _WORD_skip_comment
	b _WORD_key
	_RETURN

_FUNC _EMIT
	ldr x8, =UART_START
	strb w0, [x8]
	_RETURN

// `( character -- )`, emits a single character.
defcode "EMIT", 4, , EMIT
	_POP x0
	_CALL _EMIT
_NEXT

_FUNC _TELL
	cmp x1, 0
	b.eq _TELL_done

	ldr x9, =UART_START

	_TELL_char:
	ldrb w10, [x0], 1
	strb w10, [x9]
	sub x1, x1, 1
	cmp x1, 0
	b.ne _TELL_char

	_TELL_done:
	_RETURN

defcode "TELL", 4, , TELL
	_POP x0, x1

	_CALL _TELL
_NEXT

defcode "LITSTRING", 9, , LITSTRING
	ldr x9, [wa], 8
	_PUSH wa, x9
	// Skip past the string, then align.
	add wa, wa, x9
	add wa, wa, 7
	and wa, wa, ~7
_NEXT

/* ## Interpreter */
// Switch to immediate (interpreting) mode.
defcode "[", 1, F_IMMEDIATE, LBRAC
	mov x0, 0
	_SETVAR STATE, x0
_NEXT

// Switch to compiling mode.
defcode "]", 1, , RBRAC
	mov x0, 1
	_SETVAR STATE, x0
_NEXT

// Interpret the given word as a number.
_FUNC _NUMBER
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
	_GETVAR BASE, x12

	ldrb w11, [x0]
	cmp w11, '-'
	b.eq _NUMBER_neg
	b _NUMBER_char

	_NUMBER_neg:
	mov x10, -1
	add x9, x9, 1

	_NUMBER_char:
	mul x3, x3, x12
	ldrb w11, [x0,x9]

	subs w11, w11, '0'
	b.lt _NUMBER_fail
	cmp w11, 9
	b.le _NUMBER_digit
	subs w11, w11, 'A' - '0'
	b.lt _NUMBER_fail
	cmp w11, 25
	b.gt _NUMBER_fail
	add w11, w11, 10

	_NUMBER_digit:
	cmp w11, w12
	b.ge _NUMBER_fail
	add x3, x3, x6

	_NUMBER_next_char:
	add x9, x9, 1
	cmp x9, x1
	b.eq _NUMBER_done
	b _NUMBER_char

	_NUMBER_fail:
	mov x2, 0

	_NUMBER_done:
	// Multiply in the sign.
	mul x3, x3, x10
	_RETURN

defcode "REPL", 4, , REPL
	_CALL _WORD
	cmp x1, 0
	// Empty, don't bother.
	b.eq REPL_done

	_CALL _FIND
	cmp x2, 0
	b.ne REPL_interpret

	// If it wasn't a valid word, maybe it's a number.
	REPL_maybe_number:
	_CALL _NUMBER
	cmp x2, 0
	b.eq REPL_invalid

	// If it is a number, then we need to either:
	_GETVAR STATE, x9
	cmp x9, 0
	b.eq REPL_interpret_number
	//   a) if compiling, push the number (with a preceding lit) onto the current definition
	ldr x10, =LIT
	_CALL _COMMA
	mov x10, x3
	_CALL _COMMA
	b REPL_done
	REPL_interpret_number:
	//   b) or, if interpreting, just push it on the stack.
	_PUSH x3
	b REPL_done

	REPL_invalid:
	_PUSH_RS x0
	_PUSH_RS x1
	ldr x0, =error_message
	ldr x1, =error_message_len
	_CALL _TELL
	_POP_RS x1
	_POP_RS x0
	_CALL _TELL
	mov w0, '\n'
	_CALL _EMIT
	b REPL_done

	REPL_interpret:
	mov x0, x2
	_CALL _TCFA

	// We should run the word if either:
	//   a) We're in immediate mode
	_GETVAR STATE, x9
	cmp x9, 0
	b.eq REPL_run

	//   or b) the word is immediate.
	ldrb w10, [x2, 8]
	and w10, w10, F_IMMEDIATE
	cmp x10, 0
	b.ne REPL_run

	// Otherwise, we need to compile it.
	_CALL _COMMA
	b REPL_done

	REPL_run:
	mov cw, x0
	ldr x8, [cw]
	br x8

	REPL_done:
_NEXT


defword "QUIT", 4, , QUIT
	.dword RZ, FETCH, RSPSTORE
	.dword LIT, welcome_message
	.dword LIT, welcome_message_len
	.dword TELL
	.dword REPL
	.dword BRANCH, -16

/* # Builtin variables */
/* Start of data and return stacks. */
defvar "S0", 2, , SZ
defvar "R0", 2, , RZ
/* Whether `KEY` echos while it reads. */
defvar "ECHO", 4, , ECHO, 1
/* Most recently defined word; initial value must be the last builtin word in this file. */
defvar "LATEST", 6, , LATEST, name_QUIT
/* Position of next allocated byte. */
defvar "HERE", 4, , HERE, __data_seg_end
/* Is REPL compiling? (0 = interpreting) */
defvar "STATE", 5, , STATE, 0
/* Base we are currently interpreting numbers in. */
defvar "BASE", 4, , BASE, 10

.section .data
__loading_builtins:
	.dword __builtins_def_start

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
__return_stack_end:

.align 3
.skip 0x10000
__data_stack_end:

__builtins_def_start:
.incbin "builtins.fs"
__builtins_def_end:

.align 3
__data_seg_end:
