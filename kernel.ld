/******************************************************************************
*	kernel.ld
*	 by Alex Chadwick
*
*	A linker script for generation of raspberry pi kernel images.
******************************************************************************/

ENTRY(_start)

SECTIONS {
	/*
	* First and formost we need the .init section, containing the code to 
        * be run first. We allow room for the ATAGs and stack and conform to 
        * the bootloader's expectation by putting this code at 0x8000.
	*/
	.init 0x41000000 : {
		*(.init)
	}
	
	/* 
	* Next we put the rest of the code.
	*/
	.text : {
		*(.text)
	}

	/* 
	* Next we put the data.
	*/
	. = ALIGN(4096);
	.data : {
		*(.data)
		__data_seg_end = .;
	}
}
