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
	' 0branch ,
	here @
	0 ,
;

: endif immediate
	dup
	here @
	swap -
	!
;

\ # I/O

