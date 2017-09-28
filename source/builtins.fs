\ Built in functions; inserted into compiled kernel.

\ # Constants and shortcuts
: literal immediate
	record
	' lit ,
	,
	play
;

\ ## Character constants
: '\n' 10 ;
: sp 32 ;
: '0' [ char 0 ] literal ;
: 'A' [ char A ] literal ;

\ # Control structures
: mark-here here @ >h ;
: update-mark-offset
	h@
	here @ h> -
	!
	;

: if immediate
	record
	' 0branch ,
	\ Save location of offset on stack
	mark-here
	0 ,
;

: else immediate
	\ Fetch offset address
	h>

	\ Shove `branch` to the end of the `else` block on the hold stack.
	' branch ,
	here @ >h
	0 ,

	\ Now, fill in the position just past that branch in the original zbranch offset.
	dup
	here @ swap -
	!
;

: endif immediate
	update-mark-offset
	play
;

\ ## Quotations

: { immediate
	\ Put a branch over the following quotation in the compiled code.
	\ This will be harmlessly ignored in interpreted mode.
	' branch ,
	mark-here
	0 ,

	record
	enter ,
;

: } immediate
	save

	update-mark-offset

	record
	' lit ,
	,
	play
;

\ ## Combinators
: keep
	swap
	dup
	>h

	swap
	execute 

	h>
;

: bi
	-rot \ q2 x q1
	keep \ q2 a x
	rot \ a x q2
	execute
;

\ # I/O

