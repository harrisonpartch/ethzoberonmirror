(* ETH Oberon, Copyright 2000 ETH Zuerich Institut fuer Computersysteme, ETH Zentrum, CH-8092 Zuerich.
Refer to the "General ETH Oberon System Source License" contract available at: http://www.oberon.ethz.ch/ *)

MODULE BootLinkerHeaps;   (** AUTHOR "G.F." ; PURPOSE "UnixAos bootlinker"; *)

(* based on Oberon for Windows bootlinker (MH) and  MIPS bootlinker (RC) *)


IMPORT S := SYSTEM, Streams;

CONST	
	AddrSize = SIZEOF( ADDRESS );
	SizeSize = SIZEOF( SIZE );

	BootHeapSize = 2*1024*1024;  MaxReloc = 10000;  

	NilVal* = 0;
	BlockSize* = 32;	(* must be a mutiple of 32 *)
	ProtOfs = 2*BlockSize + 16;
	ArrayAlignment = 8;
	HeapBlockOffset = - 2*AddrSize;
	TypeDescOffset = -AddrSize;
	
	ArrayMask* = {1};
	ProtTypeBit* = 31;   (* flags in TypeDesc, low bits reserved for extLevel *)
	
	FlagsOfs = AddrSize * 3;			(* flags offset in TypeDesc *)
	
TYPE	
	RootObject* = OBJECT 
		PROCEDURE FindRoots*;	(** abstract *)
		BEGIN HALT( 301 ) END FindRoots;
	END RootObject;
	
	StaticTypeBlock*= POINTER TO StaticTypeDesc;
	StaticTypeDesc = RECORD
		recSize: SIZE;
		pointerOffsets* {UNTRACED}: PointerOffsets;
	END;

	PointerOffsets = POINTER TO ARRAY OF SIZE;
		
	
VAR
	error: Streams.Writer;
	
	AN-:  ADDRESS;

	heapAdr-: ADDRESS;

	relocAddr-: ARRAY MaxReloc OF ADDRESS;
	numRelocations-: LONGINT;





	PROCEDURE Error( CONST str1, str2: ARRAY OF CHAR );
	BEGIN
		error.Ln;
		error.String( "Error: " );  error.String( str1 );  error.String( str2 );  
		error.Ln; 
	END Error;
	
	
	PROCEDURE FatalError( CONST str1, str2: ARRAY OF CHAR );
	BEGIN
		error.Ln;
		error.String( "Error: " );  error.String( str1 );  error.String( str2 );  
		error.Ln; 
		error.Update;
		HALT( 99 )
	END FatalError;
	

	PROCEDURE Relocate*( adr: ADDRESS );
	VAR i: LONGINT;
	BEGIN
		FOR i := 0 TO numRelocations - 1 DO
			IF relocAddr[i] = adr THEN
			(*	Error( "", "same ptr location marked twice for fixing, ignored" );	*)
				RETURN
			END
		END;
		IF numRelocations # -1 THEN
			IF numRelocations < MaxReloc THEN  relocAddr[numRelocations] := adr;  INC( numRelocations )
			ELSE  Error( "Too many relocations", "" );  numRelocations := -1
			END
		END
	END Relocate;
	
	
	PROCEDURE ClearMem( a, len: LONGINT );
	VAR  top: LONGINT;
	BEGIN
		top := a + len;
		WHILE (a MOD 4 # 0) & (a < top) DO  S.PUT( a, S.VAL( SHORTINT, 0 ) );  INC( a )  END;
		WHILE a <= top - 4 DO  S.PUT( a, S.VAL( LONGINT, 0 ) );  INC( a, 4 )  END;
		WHILE a < top DO  S.PUT( a, S.VAL( SHORTINT, 0 ) );  INC( a )  END;
	END ClearMem;


	PROCEDURE NewBlock( size: LONGINT ): ADDRESS;   (* size MOD B = 0 *)
	VAR rsize, rest: LONGINT;  ptr, restptr: ADDRESS;
	BEGIN
		ptr := AN;
		ASSERT( ptr MOD BlockSize = BlockSize - AddrSize );
		S.GET( ptr + AddrSize, rsize );
		IF rsize + AddrSize < size  THEN  FatalError( "Pseudo-heap too small", "" )  END;
		rest := rsize + AddrSize - size;
		IF rest > 0 THEN  (* >= B >= 16 *)
			restptr := ptr + size;
			S.PUT( restptr, restptr + AddrSize );
			S.PUT( restptr + AddrSize, rest - AddrSize );
			S.PUT( restptr + 2*AddrSize, 0 );
			AN := restptr
		ELSE
			AN := 0
		END;
		RETURN ptr
	END NewBlock;


	PROCEDURE NewSys*( size: LONGINT ): ADDRESS;   (* implementation of S.NEW(ptr, size) *)
	VAR ptr: ADDRESS;
	BEGIN
		INC( size, AddrSize + 24 );  INC( size, (-size) MOD BlockSize );
		ptr := NewBlock( size ) + AddrSize;
		ClearMem( ptr, size - AddrSize );
		S.PUT( ptr - AddrSize, ptr );	Relocate( ptr - AddrSize );
		S.PUT( ptr, size - AddrSize );
		S.PUT( ptr + SizeSize, S.VAL( LONGINT, -AddrSize ) );
		S.PUT( ptr + 24 - AddrSize, ptr );	Relocate( ptr + 24 - AddrSize );
		RETURN ptr + 24;
	END NewSys;


	PROCEDURE NewRec*( VAR ptr: ANY; tag: ADDRESS;  size: LONGINT );   (* implementation of NEW( ptr ) *)
	VAR p: ADDRESS;  typ: ADDRESS;  flags: SET
	BEGIN
		S.GET( tag - AddrSize, typ );   (* will be replaced by direct compiler call of NewProtObj *)
		S.GET( typ + FlagsOfs, flags );
		IF ProtTypeBit IN flags THEN  (* protected record *)
			NewProtRec( S.VAL( ANY, ptr  ), tag );
		ELSE
			INC( size, AddrSize ); INC( size, (-size) MOD BlockSize );
			p := NewBlock( size ) + AddrSize;
			S.PUT( p - AddrSize, tag );  Relocate( p - AddrSize );
			ClearMem( p, size - AddrSize );
			ptr := S.VAL( ANY, p )
		END
	END NewRec;


	PROCEDURE NewProtRec*( VAR p: ANY;  tag: ADDRESS );
	VAR recSize, size: LONGINT;  ptr0, ptr: ADDRESS;
	BEGIN
		S.GET( tag, recSize );
		(* add space for tag and header and round up to BlockSize *)
		size := recSize + ProtOfs + AddrSize;  INC( size, (-size) MOD BlockSize );
		ptr0 := NewBlock( size ) + AddrSize;
		ClearMem( ptr0, size - AddrSize );   (* clear everything *)
		S.PUT( ptr0 - AddrSize, ptr0 );   (* set the main tag *)	Relocate( ptr0 - AddrSize );
		S.PUT( ptr0, size - AddrSize );   (* size *)
		
		ptr := ptr0 + ProtOfs;
		S.PUT( ptr + HeapBlockOffset, ptr0 );	Relocate( ptr + HeapBlockOffset );
		S.PUT( ptr + TypeDescOffset, tag );	Relocate( ptr + TypeDescOffset );
		
		p := S.VAL( ANY, ptr );
	END NewProtRec;


	PROCEDURE NewArr*( VAR ptr: ANY; eltag: ADDRESS;  nofelem, nofdim: LONGINT );
	(* implementation of NEW(ptr, dim0,  ...) *)
	VAR size, elSize, arrSize, ptrOffset, dataOffset: SIZE;  firstElem, p: ADDRESS;
	BEGIN
		ASSERT( nofdim = 1 );   (* bootloader limit *)
		IF eltag = 0 THEN  elSize := AddrSize  ELSE  S.GET( eltag, elSize )  END;
		arrSize := nofelem*elSize;
		dataOffset := 3*AddrSize + nofdim*AddrSize;
		INC( dataOffset, (-dataOffset) MOD ArrayAlignment );  (* -> ADR(firstElem) MOD 8 = 0 *)
		IF arrSize = 0 THEN
			p := NewSys( nofdim*4 + 3*AddrSize );
		ELSE
			S.GET( eltag + AddrSize, ptrOffset );
			IF ptrOffset = -AddrSize THEN  (* no pointers in element type *)
				p := NewSys( dataOffset + arrSize );
				S.PUT( p + 3*AddrSize, nofelem )
			ELSE
				size := AddrSize + dataOffset + arrSize;  INC( size, (-size) MOD BlockSize );
				p := NewBlock( size ) + AddrSize;
				S.PUT( p - AddrSize, S.VAL( SET, eltag ) + {1} );  Relocate( p - AddrSize );
				ClearMem( p, size - AddrSize );
				firstElem := p + dataOffset;
				S.PUT( p, firstElem + arrSize - elSize );  Relocate( p );
				(* p + 4 is reserved for mark phase *)
				S.PUT( p + 2*AddrSize, firstElem );  Relocate( p + 2*AddrSize );
				S.PUT( p + 3*AddrSize, nofelem );
			END
		END;
		ptr := S.VAL( ANY, p )
	END NewArr;
	

	PROCEDURE FillStaticType*( VAR staticTypeAddr: ADDRESS;
								startAddr, typeInfoAdr: ADDRESS;
								size, recSize: SIZE;
								numPtrs, numSlots: LONGINT );
	VAR 
		p, offset: ADDRESS;  sTB {UNTRACED}: StaticTypeBlock;
	BEGIN
		ClearMem( startAddr, size );	(* clear whole static type, size MOD AddressSize = 0 implicitly, see WriteType in PCOF.Mod *)
		S.PUT( startAddr, S.VAL( ADDRESS, -AddrSize ) );	(* sentinel *)

		(* methods and tags filled in later *)
		
		offset := AddrSize*(numSlots + 1 + 1);  (* #methods, max. no. of tags, method end marker (sentinel), pointer to type information*)
		p := startAddr + offset;
		S.PUT( p - AddrSize, typeInfoAdr ); 	(* pointer to typeInfo *) Relocate( p - AddrSize );
		sTB := S.VAL( StaticTypeBlock, p );
		sTB.recSize := recSize;
		staticTypeAddr := p;
		
		(* create the pointer for the dynamic array of pointer offsets, the dynamic array of pointer offsets 
		    is stored in the static type descriptor, it has no header part *)
		INC( p, SIZEOF(StaticTypeDesc) );
		IF p MOD (2 * AddrSize) # 0 THEN  INC( p, AddrSize )  END;
		S.PUT( p + 3 * AddrSize, numPtrs ); (* internal structure of dynamic array without pointers: the first 3 fields are unused *)
		sTB.pointerOffsets := S.VAL( PointerOffsets, p ); (* the fourth field contains the dimension of the array *)
		Relocate( ADDRESSOF( sTB.pointerOffsets ) )

		(* ptrOfs filled in later *)

	END FillStaticType;
	
	



	PROCEDURE Initialize*( w: Streams.Writer );
	VAR firstBlock: ADDRESS;  i, size: LONGINT;  heap: ADDRESS;
	BEGIN
		error := w;
		
		S.NEW( S.VAL( ANY, heap ), BootHeapSize );
		
		FOR i := 0 TO MaxReloc -1 DO  relocAddr[i] := 0  END;
		numRelocations := 0;

		heapAdr := heap + (-heap) MOD BlockSize;
		firstBlock := heapAdr + BlockSize - AddrSize;
		size := heap + BootHeapSize - firstBlock;  DEC( size, size MOD BlockSize );
		S.PUT( firstBlock, firstBlock + AddrSize );
		S.PUT( firstBlock + AddrSize, size - AddrSize );
		S.PUT( firstBlock + 2*AddrSize, 0 );
		AN := firstBlock ;
	END Initialize;



END BootLinkerHeaps.




