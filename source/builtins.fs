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

\ # Core syntax
\ ## Control structures
: mark-here here @ >h ;
: update-mark-offset
	h@
	here @ h> -
	!
;
: branch-to-mark
	' branch ,
	h> here @ - ,
;
: 0branch-to-mark
	' 0branch ,
	h> here @ - ,
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

: begin immediate
	record
	mark-here
;

: again immediate
	branch-to-mark
	play
;

: until immediate
	0branch-to-mark
	play
;

\ ## ( ... ) comments

: ( immediate
	begin key ')' = until
;

\ ## Strings

: " immediate
	record

	' litstring ,
	mark-here
	0 ,

	begin
		key
		dup '"' = if
			drop
			1
		else
			,c
			0
		endif
	until

	\ Similar to `update-mark-offset`, but `litstring` does not include the 8 bytes of the length in the string length (unlike a `branch` offset).
	h@
	here @ h> - 8 -
	!

	here
	here @ align
	!

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
	' exit ,
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

" done.

" tell

\ vim: set commentstring=\\\ %s foldmethod=expr foldexpr=SourceMarkdownFolds() :
