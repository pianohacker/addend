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
	hold
	' 0branch ,
	0 ,
;

: endif immediate
	h@
	here @ h@ - 
	!
	play
;

\ # I/O

