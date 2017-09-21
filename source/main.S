.title "ARMForth"

#define UART_START 0x09000000
/* Word Address - address of the next forth word to be executed */
#define wa x19
/* Current Word - contents of the currently executing forth word */
#define cw x20
/* Stack Pointer - current top of the data stack */
#define sp x21
/* Frame Pointer - current top of the return stack */
#define fp x29
/* Link Register (ARM ABI defined) - next instruction after `bl` */
#define lr x30

/* # Useful macros */
/* ## Constants */
.set F_IMMED,0x80
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
.macro _PUSH reg
	str \reg, [sp, -8]!
.endm

.macro _POP reg
	ldr \reg, [sp], 8
.endm

/* ## Control flow macros */

.macro _NEXT
	ldr cw, [wa], 8
	ldr x8, [cw]
	br x8
.endm

.macro _CALL func
	bl \func
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
/* ## Syntax */
defcode "LIT", 3, , LIT
	ldr cw, [wa], 8
	_PUSH cw
_NEXT

defcode "BRANCH", 6, , BRANCH
	ldr x0, [wa]
	add wa, wa, x0
_NEXT

defcode "0BRANCH", 7, , 0BRANCH
	_POP x0
	cmp x0, 0
	b.eq code_BRANCH

	add wa, wa, 8
_NEXT

/* ## Stack manipulation */
defcode "DROP", 4, , DROP
	_POP x0
_NEXT

/* ## Return stack manipulation */
defcode "RSP!", 4, , RSPSTORE
	_POP fp
_NEXT

/* ## Memory */
defcode "@", 1, , FETCH
	_POP x1
	ldr x0, [x1]
	_PUSH x0
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

	_GETVAR HERE, x2
	_GETVAR LATEST, x3

	str x3, [x2]
	mov x3, x2
	add x2, x2, 8
	strb w1, [x2], 1

	mov x4, 0
	_CREATE_copy_name:
	ldrb w5, [x0,x4]
	strb w5, [x2,x4]
	add x4, x4, 1
	cmp x4, x1
	b.ne _CREATE_copy_name
	add x2, x2, x1

	// Align to next 8-byte boundary.
	add x2, x2, 7
	and x2, x2, ~7

	_SETVAR HERE, x2
	_SETVAR LATEST, x3
_NEXT

_FUNC _FIND
	_GETVAR LATEST, x2

	_FIND_loop:
	cmp x2, 0
	// We've looked through every entry, and have reached the end; return 0.
	b.eq _FIND_done

	// Skip the link.
	add x3, x2, 8

	// Read and check the length byte; we don't mask out F_HIDDEN to make sure hidden words never
	// match.
	ldrb w4, [x3], 1
	and w4, w4, (F_HIDDEN | F_LENMASK)
	cmp w4, w1
	b.ne _FIND_next

	mov x4, 0
	_FIND_char:
	ldrb w5, [x3,x4]
	ldrb w6, [x0,x4]
	cmp w5, w6
	b.ne _FIND_next
	
	add x4, x4, 1
	cmp x4, x1
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
	_GETVAR HERE, x1
	str x0, [x1], 8
	_SETVAR HERE, x1
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
	ldrb w1, [x0, 8]!
	eor w1, w1, F_HIDDEN
	strb w1, [x0]
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
defword ";", 1, F_IMMED, SEMICOLON
	.dword LIT, EXIT, COMMA
	.dword LATEST, FETCH, HIDDEN
	.dword LBRAC
	.dword EXIT
_NEXT

_FUNC _TCFA
	// Skip the link.
	add x0, x0, 8
	
	// Skip the name.
	ldrb w1, [x0]
	add x0, x0, 1

	and w1, w1, F_LENMASK
	add x0, x0, x1

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
	_PUSH x4
_NEXT

_FUNC _KEY
	ldr x6, =UART_START
	_KEY_wait_for_input:
	// Load RXFF (receive fifo full) from UARTFR (flags register)
	ldrb w5, [x6,0x18]
	ubfx w5, w5, 6, 1
	cmp w5, 1
	b.ne _KEY_wait_for_input

	_KEY_read:
	ldrb w4, [x6]

	cmp w4, '\r'
	b.ne _KEY_read_done
	mov w4, '\n'
	_KEY_read_done:

	// Echo typed character if desired
	ldr x8, =var_ECHO
	ldr x7, [x8]
	cmp x7, 0
	b.eq _KEY_done
	strb w4, [x6]

	_KEY_done:
_RETURN

defcode "WORD", 4, , WORD
	_CALL _WORD
	_PUSH x0
	_PUSH x1
_NEXT

_FUNC _WORD
	ldr x0, =__word_read_buffer
	mov x1, 0

	_WORD_key:
	_CALL _KEY

	cmp w4, '\\'
	b.eq _WORD_skip_comment
	cmp w4, ' '
	b.eq _WORD_done
	cmp w4, '\t'
	b.eq _WORD_done
	cmp w4, '\r'
	b.eq _WORD_done
	cmp w4, '\n'
	b.eq _WORD_done

	strb w4, [x0,x1]
	add x1, x1, 1
	b _WORD_key

	_WORD_done:
	_RETURN

	_WORD_skip_comment:
	_CALL _KEY
	cmp w4, '\n'
	b.ne _WORD_skip_comment
	b _WORD_key
_RETURN

_FUNC _CTELL
	ldr x1, =UART_START
	strb w0, [x1]
_RETURN

_FUNC _TELL
	cmp x1, 0
	b.eq _TELL_done

	ldr x2, =UART_START
	
	_TELL_char:
	ldrb w3, [x0], 1
	strb w3, [x2]
	sub x1, x1, 1
	cmp x1, 0
	b.ne _TELL_char

	_TELL_done:
_RETURN

defcode "TELL", 4, , TELL
	_POP x1
	_POP x0

	_CALL _TELL
_NEXT

/* ## Interpreter */
// Switch to immediate (interpreting) mode.
defcode "[", 1, F_IMMED, LBRAC
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
	mov x4, 0
	// Sign of the word.
	mov x5, 1
	// Current character.
	mov w6, 0
	// Current base.
	_GETVAR BASE, x7

	ldrb w6, [x0]
	cmp w6, '-'
	b.eq _NUMBER_neg
	b _NUMBER_char
	
	_NUMBER_neg:
	mov x5, -1
	add x4, x4, 1

	_NUMBER_char:
	mul x3, x3, x7
	ldrb w6, [x0,x4]

	subs w6, w6, '0'
	b.lt _NUMBER_fail
	cmp w6, 9
	b.le _NUMBER_digit
	subs w6, w6, 'A' - '0'
	b.lt _NUMBER_fail
	cmp w6, 25
	b.gt _NUMBER_fail
	add w6, w6, 10
	
	_NUMBER_digit:
	cmp w6, w7
	b.ge _NUMBER_fail
	add x3, x3, x6

	_NUMBER_next_char:
	add x4, x4, 1
	cmp x4, x1
	b.eq _NUMBER_done
	b _NUMBER_char

	_NUMBER_fail:
	mov x2, 0

	_NUMBER_done:
	// Multiply in the sign.
	mul x3, x3, x5
_RETURN

defcode "REPL", 4, , REPL
	_CALL _WORD
	cmp x1, 0
	// Empty, don't bother.
	b.eq REPL_done

	_CALL _FIND
	cmp x2, 0
	b.ne REPL_interpret
	
	REPL_maybe_number:
	_CALL _NUMBER
	cmp x2, 0
	b.eq REPL_invalid

	_GETVAR STATE, x4
	cmp x4, 0
	b.eq REPL_interpret_number
	ldr x0, =LIT
	_CALL _COMMA
	mov x0, x3
	_CALL _COMMA
	b REPL_done
	REPL_interpret_number:
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
	_CALL _CTELL
	b REPL_done

	REPL_interpret:
	mov x0, x2
	_CALL _TCFA

	// We should run the word if either:
	//   a) We're in immediate mode
	_GETVAR STATE, x3
	cmp x3, 0
	b.eq REPL_run

	//   or b) the word is immediate.
	ldrb w3, [x2, 8]
	and w3, w3, F_IMMED
	cmp x3, 0
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
.pool

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

__data_seg_end:
