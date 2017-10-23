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
: '"' [ char " ] literal ; \ to fix Vim's syntax highlighting: "
: '(' [ char ( ] literal ;
: ')' [ char ) ] literal ;

\ ## Shortcut syntax
: not 0= ;
: hex immediate base 16 ! ;
: dec immediate base 10 ! ;

\ # Core syntax
: mark-here here @ >h ;
: update-mark-offset
	h@
	here @ h> -
	!
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
	' exit ,
	save

	update-mark-offset

	record
	' lit ,
	,
	play
;

: {}
	' branch ,
	8 ,

	record
	next ,
	save

	record
	' lit ,
	,
	play
;

\ ## Control structures
: if
	choose
	execute
;

: when
	{} if
;

: until
	>h

	h@ execute -40 s0branch

	hdrop
;

: cond-while
	>h >h
	{
		hover@ execute
		dup >h hover@ swap when
		h>
	} until
	hdrop hdrop
;

\ ## ( ... ) comments

: ( immediate
	{ key ')' = } until
;

\ ## Constants
: constant
	word create
	enter ,
	' lit ,
	,
	' exit ,
;

\ ## Strings

: " immediate
	record

	' litstring ,
	mark-here
	0 ,

	{
		key

		dup '"' = {
			drop
			1
		} {
			,c
			0
		} if
	} until

	\ Similar to `update-mark-offset`, but `litstring` does not include the 8 bytes of the length in the string length (unlike a `branch` offset).
	h@
	here @ h> - 8 -
	!

	here
	here @ align
	!

	play
;

\ ## Combinators
: keep ( ..a x q -- ..b x ) \ Restores x after execution
	swap
	dup
	>h

	swap
	execute

	h>
;

: dip ( ..a x q -- ..b x ) \ Hides x during execution
	swap
	>h
	execute
	h>
;


: bi ( x q1 q2 -- ..a ..b )
	>h \ x q1
	keep \ ...a x
	h> \ ...a x q2
	execute
;

: tri
	>h \ x q1 q2
	>h \ x q1
	keep \ ...a x
	h> \ ...a x q2
	keep \ ...a ...b x
	h> \ ...a ...b x q3
	execute
;

\ # I/O

\ # Hardware

hex 84000000 dec constant PSCI_BASE
hex PSCI_BASE 8 + dec constant PSCI_0_2_FN_SYSTEM_OFF

: halt ( -- ) \ Shuts down the system immediately.
	PSCI_0_2_FN_SYSTEM_OFF
	1 hvc
;

\ ## Interrupt configuration

hex 08000000 dec constant GIC_DISTBASE
hex GIC_DISTBASE dec constant GICD_CTLR
hex GIC_DISTBASE 100 + dec constant GICD_ISENABLERs
hex GIC_DISTBASE 800 + dec constant GICD_ITARGETSRs
hex GIC_DISTBASE C00 + dec constant GICD_ICFGRs

hex 08010000 dec constant GIC_CPUBASE
hex GIC_CPUBASE dec constant GICC_CTLR
hex GIC_CPUBASE 4 + dec constant GICC_PMR

: !gic-int-b ( interrupt reg-base bit-val -- )
	{
		swap
		{ 32 / 4 * + } { 32 mod } bi
	} dip
	!b
;

: !gic-int-sb ( interrupt reg-base bit-val -- )
	{
		swap
		{ 16 / 4 * + } { 16 mod 2 * 1 + } bi
	} dip
	!b
;

: !gic-int-c ( interrupt reg-base val -- )
	{ + } dip
	!c
;

: gic-disable-interrupt ( interrupt -- )
	GICD_ISENABLERs 0 !gic-int-b
;

: gic-enable-interrupt ( interrupt -- )
	\ Enable this interrupt.
	{ GICD_ISENABLERs 1 !gic-int-b }
	\ Target it to CPU interface 0.
	{ GICD_ITARGETSRs 1 !gic-int-c }
	\ Set this register to edge-sensitive.
	{ GICD_ICFGRs 1 !gic-int-sb }
	tri
;

: gic-enable-interrupts
	\ Allow interrupts of all priorities to come through.
	GICC_PMR hex FF dec !w
	\ Enable interrupts on this CPU interface.
	GICC_CTLR 3 !w
	\ Enable interrupts.
	GICD_CTLR 3 !w
;

\ Enable UART interrupts.
5 gic-enable-interrupt
33 gic-enable-interrupt
gic-enable-interrupts
key-wfi 1 !

\ # Done

" done.

" tell

\ vim: set commentstring=\\\ %s foldmethod=expr foldexpr=SourceMarkdownFolds() :
