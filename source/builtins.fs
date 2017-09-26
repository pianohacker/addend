\ Built in functions; inserted into compiled kernel.

\ # Constants and shortcuts
: literal immediate
	' lit ,
	,
;

\ ## Character constants
: '\n' 10 ;
: sp 32 ;
: '0' [ char 0 ] literal ;
: 'A' [ char A ] literal ;

\ # Control structures
: if immediate
	record
	' 0branch ,
	\ Save location of offset on stack
	here @ >h
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
	h@
	here @ h> -
	!

	play
;

\ # I/O
0 if 33 emit else 65 emit endif
1 if 66 emit else 34 emit endif
