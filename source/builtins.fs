\ Built in functions; inserted into compiled kernel.

\ # Constants and shortcuts
: LITERAL IMMEDIATE
	' LIT ,
	,
	;

\ ## Character constants
: '\n' 10 ;
: SP 32 ;
: '0' [ CHAR 0 ] LITERAL ;
: 'A' [ CHAR A ] LITERAL ;

\ # I/O

