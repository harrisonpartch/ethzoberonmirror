(* ETH Oberon, Copyright 2000 ETH Zuerich Institut fuer Computersysteme, ETH Zentrum, CH-8092 Zuerich.
Refer to the "General ETH Oberon System Source License" contract available at: http://www.oberon.ethz.ch/ *)

MODULE BootLinker;   (** AUTHOR "G.F." ; PURPOSE "UnixAos bootlinker"; *)

(* based on Oberon for Windows bootlinker (MH) and  MIPS bootlinker (RC) *)


IMPORT S := SYSTEM, Commands, Streams, Files;

CONST
	StartModule = "BootConsole";
	
	ObjSuffix = ".Obj";

	AdrSize = S.SIZEOF( S.ADDRESS );
	SizeSize = S.SIZEOF( S.SIZE );

	BootHeapSize = 32*1024*1024;  NofPtrFix = 10000;  


TYPE
	Address = S.ADDRESS; Size = S.SIZE;


	(* ------------ Heaps -------------------------------------------- *)
	
CONST
	NilVal* = 0;
	BlockSize = 32;
	ProtOfs = 2*BlockSize + 16;
	ArrayAlignment = 8;
	HeapBlockOffset = - 2*AdrSize;
	TypeDescOffset = -AdrSize;
	
	ProtTypeBit* = 31;   (* flags in TypeDesc, low bits reserved for extLevel *)
	
TYPE	
	RootObject* = OBJECT 
		PROCEDURE FindRoots*;	(** abstract *)
		BEGIN HALT( 301 ) END FindRoots;
	END RootObject;
	
	StaticTypeBlock*= POINTER TO StaticTypeDesc;
	StaticTypeDesc = RECORD
		recSize: Size;
		pointerOffsets* {UNTRACED}: PointerOffsets;
	END;

	PointerOffsets = POINTER TO ARRAY OF Size;
		
	(* ------------ Modules ------------------------------------------ *)

CONST
	MaxTags* = 16;   (* in type descriptor *)
	
	(** type descriptor field offsets relative to root (middle) *)
	Tag0Ofs* = -8;   (** first tag *)
	Mth0Ofs* = Tag0Ofs - 4*MaxTags;   (** first method *)
	Ptr0Ofs* = 4;   (** first pointer offset *)
	
	InitTableLen = 1024;
	InitPtrTableLen = 2048;

TYPE
	Name* = ARRAY 32 OF CHAR;
	TermHandler* = PROCEDURE;

	Command* = RECORD
				name*		: Name;		(* Name of the command *)
				argTdAdr*	: Address;	(* address of type descriptor of argument *)
				retTdAdr*	: Address;	(* address of type descriptor of return type, 0 if no type *)
				entryAdr*	: Address;	(* entry address of procedure *)
			END;


	ExportDesc* = RECORD
				fp*			: Address;
				adr*		: Address;
				exports*	: LONGINT;
				dsc*		: ExportArray
			END;

	ExportPtr* 		= POINTER TO ExportDesc;
	ExportArray*	= POINTER TO ARRAY OF ExportDesc;


	TypeDesc* = POINTER TO TypeDescRec;
	TypeDescRec* = RECORD
				tdSize*		: LONGINT;
				sentinel*	: LONGINT;	(*  = -4 *)
				tag*		: Address; 	(* pointer to static type descriptor, only used by linker and loader *)
				flags*		: SET;
				mod*		: Module;   	(** hint only, because module may have been freed *)
				name*		: Name;
			END;

	ExceptionTableEntry* = RECORD
				pcFrom*	: Address;
				pcTo*		: Address;
				pcHandler*	: Address;
			END;

	
	
	ExceptionTable* = POINTER TO ARRAY OF ExceptionTableEntry;

	ProcTableEntry* = RECORD
				pcFrom*			: Address;
				pcLimit*			: Address;
				pcStatementBegin*	: Address;
				pcStatementEnd*	: Address;
				noPtr*				: LONGINT
			END;
	
	ProcOffsetEntry* = RECORD
		data*: ProcTableEntry;	(* code offsets of procedures *)
		startIndex*: LONGINT;	(* index into global ptrOffsets table *)
	END;

	ProcOffsetTable* = POINTER TO ARRAY OF ProcOffsetEntry;
	
	ProcTable* = POINTER TO ARRAY OF ProcTableEntry;
	PtrTable* = POINTER TO ARRAY OF Address;

	Bytes* = POINTER TO ARRAY OF CHAR;
	

	Module = OBJECT(RootObject)
			VAR
				next		: Module;
				name		: Name;
				init			: BOOLEAN;
				published	: BOOLEAN;
				refcnt		: LONGINT;
				sb	 		: Address;
			
				entry		: POINTER TO ARRAY OF Address;
				command	: POINTER TO ARRAY OF Command;
				ptrAdr		: POINTER TO ARRAY OF Address;
				typeInfo		: POINTER TO ARRAY OF TypeDesc;
				module		: POINTER TO ARRAY OF Module;

				procTable	: ProcTable; (* information inserted by loader, removed after use in Publish *)
				ptrTable	: PtrTable;  (* information inserted by loader, removed after use in Publish *)

				data, code, staticTypeDescs, refs	: Bytes;

				export		: ExportDesc;
				term		: TermHandler;
				exTable		: ExceptionTable;
				noProcs		: LONGINT;
				firstProc		: Address;   (* procedure with lowest PC in module *)
				maxPtrs		: LONGINT;
				crc			: LONGINT
			END Module;

	
	
VAR
	procOffsets{UNTRACED}: ProcOffsetTable;	(* global table containing procedure code offsets and pointer offsets, sorted in ascending order of procedure code offsets *)
	numProcs: LONGINT;			(* number of entries in procOffsets *)
	ptrOffsets{UNTRACED}: PtrTable;
	numPtrs: LONGINT;



	(* ------------------- Boot Heap ---------------------------------- *)

CONST
	B = 32;   (* must be a mutiple of 32 *)
	arrayMask = {1};

VAR
	out: Streams.Writer;
	error: Streams.Writer;
	
	AN:  Address;

	heapAdr, dlsymAdr, startModuleBody: Address;

	modTag, expTag, ptrElemTag, procTableEntryTag, procOffsetEntryTag, ptrTableTag, tdTag: Address;

	ptrFix: ARRAY NofPtrFix OF LONGINT;
	ptrFixx: LONGINT;

	(* ------------------- Loader ---------------------------------- *)


CONST
	Ok = 0;
	FileNotFound = 3401;
	TagInvalid = 3402;
	FileCorrupt = 3403;
	(*FileTooShort = 3404;*)
	IncompatibleImport = 3405;
	IncompatibleModuleName = 3406;

	MaxStructs = 1024;	(* maximum number of structures in export block *)

	FileTag = 0BBX;				(* cf. PCM.Mod *)
	NoZeroCompress = 0ADX;	(* cf. PCM.Mod *)
	FileVersion* = 0B1X;			(* cf. PCM.Mod *)
	FileVersionOC=0B2X; (* preparation for object and symbol file for new Oberon Compiler *)
	CurrentFileVersion=0B4X;
	
		(* object model exports *)
	EUEnd = 0;  EURecord = 1;  EUobjScope = 0;  EUrecScope = 1;  EUerrScope = -1;
	EUProcFlagBit = 31;

	Sentinel = SHORT(0FFFFFFFFH);


TYPE

	ObjHeader = RECORD  (* data in object file header *)
				entries			: LONGINT;
				commands		: LONGINT;
				pointers			: LONGINT;
				types			: LONGINT;
				modules		: LONGINT;
				links			: LONGINT;
				dataLinks		: LONGINT;
				refSize, codeSize, dataSize, constSize	: LONGINT;
				exTableLen		: LONGINT;
				procs			: LONGINT;
				maxPtrs			: LONGINT;
				staticTdSize		: LONGINT;
				crc				: LONGINT;
				name			: Name;
			END;

	LinkRec = RECORD
				mod	: LONGINT;
				entry	: LONGINT;
				link		: S.SIZE;
			END;

	DataLinkRec = RECORD
				mod	: LONGINT;
				entry	: LONGINT;
				fixups	: LONGINT;
				ofs		: POINTER TO ARRAY OF S.SIZE;
			END;

	TypeRec = RECORD
				init: BOOLEAN;
				entry, methods, inhMethods, baseMod: LONGINT;
				baseEntry: Address
			END;

VAR
	modules{UNTRACED}, lastMod{UNTRACED}: Module;

	KernelRoutines: ARRAY 11 OF RECORD
				name: Name;
				adr: Address
			END;


	(* ------------------- General procedures -------------------- *)



	PROCEDURE Error( CONST str1, str2: ARRAY OF CHAR );
	BEGIN
		error.String( "Error: " );  error.String( str1 );  error.String( str2 );  
		error.Ln;
	END Error;


	(* ------------------- Boot Heap ---------------------------------- *)


	PROCEDURE ClearMem( a, len: LONGINT );
	VAR  top: LONGINT;
	BEGIN
		top := a + len;
		WHILE (a MOD 4 # 0) & (a < top) DO  S.PUT( a, S.VAL( SHORTINT, 0 ) );  INC( a )  END;
		WHILE a <= top - 4 DO  S.PUT( a, S.VAL( LONGINT, 0 ) );  INC( a, 4 )  END;
		WHILE a < top DO  S.PUT( a, S.VAL( SHORTINT, 0 ) );  INC( a )  END;
	END ClearMem;



	PROCEDURE NewBlock( size: LONGINT ): Address;   (* size MOD B = 0 *)
	VAR rsize, rest: LONGINT;  ptr, restptr: Address;
	BEGIN
		ptr := AN;
		ASSERT( ptr MOD B = B - AdrSize );
		S.GET( ptr + AdrSize, rsize );
		IF rsize + AdrSize < size  THEN
			error.Ln; error.String( "Pseudo-heap too small" );  error.Ln;  RETURN 0
		END;
		rest := rsize + AdrSize - size;
		IF rest > 0 THEN  (* >= B >= 16 *)
			restptr := ptr + size;
			S.PUT( restptr, restptr + AdrSize );
			S.PUT( restptr + AdrSize, rest - AdrSize );
			S.PUT( restptr + 2*AdrSize, 0 );
			AN := restptr
		ELSE
			AN := 0
		END;
		RETURN ptr
	END NewBlock;


	PROCEDURE NewSys( size: LONGINT ): Address;   (* implementation of S.NEW(ptr, size) *)
	VAR ptr: Address;
	BEGIN
		INC( size, AdrSize + 24 );  INC( size, (-size) MOD B );
		ptr := NewBlock( size ) + AdrSize;
		ClearMem( ptr, size - AdrSize );
		S.PUT( ptr - AdrSize, ptr );	Relocate( ptr - AdrSize );
		S.PUT( ptr, size - AdrSize );
		S.PUT( ptr + SizeSize, S.VAL( LONGINT, -AdrSize ) );
		S.PUT( ptr + 24 - AdrSize, ptr );	Relocate( ptr + 24 - AdrSize );
		RETURN ptr + 24;
	END NewSys;


	PROCEDURE NewRec( VAR ptr: ANY; tag: Address;  size: LONGINT );   (* implementation of NEW( ptr ) *)
	VAR p: Address;  typ: TypeDesc;
	BEGIN
		IF tag # 0 THEN
			S.GET( tag - AdrSize, typ );   (* will be replaced by direct compiler call of NewProtObj *)
			IF ProtTypeBit IN typ.flags THEN  (* protected record *)
				NewProtRec( S.VAL( ANY, ptr  ), tag );
				RETURN
			END
		END;
		INC( size, AdrSize ); INC( size, (-size) MOD B );
		p := NewBlock( size ) + AdrSize;
		S.PUT( p - AdrSize, tag );  Relocate( p - AdrSize );
		ClearMem( p, size - AdrSize );
		ptr := S.VAL( ANY, p )
	END NewRec;


	PROCEDURE NewProtRec( VAR p: ANY;  tag: Address );
	VAR recSize, size: LONGINT;  ptr0, ptr: Address;
	BEGIN
		S.GET( tag, recSize );
		(* add space for tag and header and round up to BlockSize *)
		size := recSize + ProtOfs + AdrSize;  INC( size, (-size) MOD BlockSize );
		ptr0 := NewBlock( size ) + AdrSize;
		ClearMem( ptr0, size - AdrSize );   (* clear everything *)
		S.PUT( ptr0 - AdrSize, ptr0 );   (* set the main tag *)	Relocate( ptr0 - AdrSize );
		S.PUT( ptr0, size - AdrSize );   (* size *)
		
		ptr := ptr0 + ProtOfs;
		S.PUT( ptr + HeapBlockOffset, ptr0 );	Relocate( ptr + HeapBlockOffset );
		S.PUT( ptr + TypeDescOffset, tag );	Relocate( ptr + TypeDescOffset );
		
		p := S.VAL( ANY, ptr );
	END NewProtRec;


	PROCEDURE NewArr( VAR ptr: ANY; eltag: Address;  nofelem, nofdim: LONGINT );
	(* implementation of NEW(ptr, dim0,  ...) *)
	VAR size, elSize, arrSize, ptrOffset, dataOffset: Size;  firstElem, p: Address;
	BEGIN
		ASSERT( nofdim = 1 );   (* bootloader limit *)
		IF eltag = 0 THEN  elSize := AdrSize  ELSE  S.GET( eltag, elSize )  END;
		arrSize := nofelem*elSize;
		dataOffset := 3*AdrSize + nofdim*AdrSize;
		INC( dataOffset, (-dataOffset) MOD ArrayAlignment );  (* -> ADR(firstElem) MOD 8 = 0 *)
		IF arrSize = 0 THEN
			p := NewSys( nofdim*4 + 3*AdrSize );
		ELSE
			S.GET( eltag + AdrSize, ptrOffset );
			IF ptrOffset = -AdrSize THEN  (* no pointers in element type *)
				p := NewSys( dataOffset + arrSize );
				S.PUT( p + 3*AdrSize, nofelem )
			ELSE
				size := AdrSize + dataOffset + arrSize;  INC( size, (-size) MOD B );
				p := NewBlock( size ) + AdrSize;
				S.PUT( p - AdrSize, S.VAL( SET, eltag ) + {1} );  Relocate( p - AdrSize );
				ClearMem( p, size - AdrSize );
				firstElem := p + dataOffset;
				S.PUT( p, firstElem + arrSize - elSize );  Relocate( p );
				(* p + 4 is reserved for mark phase *)
				S.PUT( p + 2*AdrSize, firstElem );  Relocate( p + 2*AdrSize );
				S.PUT( p + 3*AdrSize, nofelem );
			END
		END;
		ptr := S.VAL( ANY, p )
	END NewArr;
	


	PROCEDURE FillStaticType( VAR staticTypeAddr: Address;
								startAddr, typeInfoAdr: Address;
								size, recSize: S.SIZE;
								numPtrs, numSlots: LONGINT );
	VAR 
		p, offset: Address;  sTB {UNTRACED}: StaticTypeBlock;
	BEGIN
		ClearMem( startAddr, size );	(* clear whole static type, size MOD AddressSize = 0 implicitly, see WriteType in PCOF.Mod *)
		S.PUT( startAddr, S.VAL( Address, -AdrSize ) );	(* sentinel *)

		(* methods and tags filled in later *)
		
		offset := AdrSize*(numSlots + 1 + 1);  (* #methods, max. no. of tags, method end marker (sentinel), pointer to type information*)
		p := startAddr + offset;
		S.PUT( p - AdrSize, typeInfoAdr ); 	(* pointer to typeInfo *) Relocate( p - AdrSize );
		sTB := S.VAL( StaticTypeBlock, p );
		sTB.recSize := recSize;
		staticTypeAddr := p;
		
		(* create the pointer for the dynamic array of pointer offsets, the dynamic array of pointer offsets 
		    is stored in the static type descriptor, it has no header part *)
		INC( p, S.SIZEOF(StaticTypeDesc) );
		IF p MOD (2 * AdrSize) # 0 THEN  INC( p, AdrSize )  END;
		S.PUT( p + 3 * AdrSize, numPtrs ); (* internal structure of dynamic array without pointers: the first 3 fields are unused *)
		sTB.pointerOffsets := S.VAL( PointerOffsets, p ); (* the fourth field contains the dimension of the array *)
		Relocate( S.ADR( sTB.pointerOffsets ) )

		(* ptrOfs filled in later *)

	END FillStaticType;



	(* ---------------------- from Modules  ---------------------- *)


	PROCEDURE RefReadNum( VAR pos: LONGINT;  VAR i: LONGINT );
	VAR n: LONGINT;  shift: SHORTINT;  x: CHAR;
	BEGIN
		shift := 0;  n := 0;  S.GET( pos, x );  INC( pos );
		WHILE ORD( x ) >= 128 DO
			INC( n, ASH( ORD( x ) MOD 128, shift ) );  INC( shift, 7 );  S.GET( pos, x );  INC( pos );
		END;
		i := n + ASH( ORD( x ) MOD 64 - ORD( x ) DIV 64*64, shift )
	END RefReadNum;

	PROCEDURE RefReadName( VAR pos: LONGINT;  VAR n: ARRAY OF CHAR );
	VAR i: INTEGER;  ch: CHAR;
	BEGIN
		i := 0;
		REPEAT  S.GET( pos, ch );  INC( pos );  n[i] := ch;  INC( i )  UNTIL ch = 0X;
	END RefReadName;

	PROCEDURE RefReadChar( VAR pos: LONGINT;  VAR ch: CHAR );
	BEGIN
		S.GET( pos, ch );  INC( pos );
	END RefReadChar;

	PROCEDURE ProcByName( CONST pname: ARRAY OF CHAR;  m: Module ): LONGINT;
	CONST mBodyTag = 0F8X;  ProcRefTag = 0F9X;  VarTag = 1X;  VarParTag = 3X;
	VAR 
		pos, refend, adr, t, size, tdAdr: LONGINT;  ch: CHAR;  name: ARRAY 128 OF CHAR; 
		newObjectFile: BOOLEAN;
	BEGIN
		IF pname = "" THEN  RETURN 0  END;
		pos := S.ADR( m.refs[0] );  refend := pos + LEN( m.refs^ );
		RefReadChar( pos, ch );
		newObjectFile := ch = 0FFX;  
		IF newObjectFile THEN  RefReadChar( pos, ch )  END;
		WHILE (pos <= refend) & ((ch = mBodyTag) OR (ch = ProcRefTag)) DO
			RefReadNum( pos, adr );
			IF newObjectFile THEN RefReadNum( pos, t )  END;
			IF ch = ProcRefTag THEN
				RefReadNum( pos, t );	(* nofPars *)
				INC( pos, 3 );		(* ret type, lev, slNeeded *)
				IF newObjectFile THEN  INC( pos, 6 )  END
			END;
			RefReadName( pos, name );
			IF name = pname THEN  RETURN S.ADR( m.code[adr] )  END;
			RefReadChar( pos, ch );
			WHILE (VarTag <= ch) & (ch <= VarParTag) DO
				RefReadChar( pos, ch );   (* form *)
				IF ORD( ch ) >= 80H THEN  RefReadNum( pos, size )
				ELSIF ORD( ch ) >= 14H THEN  RefReadNum( pos, tdAdr )
				END;
				RefReadNum( pos, adr );  RefReadName( pos, name );  RefReadChar( pos, ch );
			END;
		END;
		error.String( "Kernel routine '" );  error.String( pname );  
		error.String( "' not found" );  error.Ln;  RETURN 0
	END ProcByName;


	PROCEDURE FindInsertionPos(VAR entry: ProcTableEntry; VAR pos: LONGINT): BOOLEAN;
	VAR l, r, x: LONGINT; success, isHit: BOOLEAN;
	BEGIN
		pos := -1;
		success := FALSE;
		IF numProcs = 0 THEN (* empty table *)
			pos := 0; success := TRUE
		ELSE
			l := 0; r := numProcs - 1;
			REPEAT
				x := (l + r) DIV 2;
				IF entry.pcLimit < procOffsets[x].data.pcFrom THEN r := x - 1 ELSE l := x + 1 END;
				isHit := ((x = 0) OR (procOffsets[x - 1].data.pcLimit <= entry.pcFrom)) & 
								   (entry.pcLimit <= procOffsets[x].data.pcFrom);
			UNTIL isHit OR (l > r);
			IF isHit THEN
				pos := x; success := TRUE
			ELSE
				IF (x = numProcs - 1) & (procOffsets[x].data.pcLimit <= entry.pcFrom) THEN
					pos := x + 1; success := TRUE
				END
			END
		END;
		RETURN success
	END FindInsertionPos;
	
	(* insert the procedure code offsets and pointer offsets of a single module into the global table *)
	PROCEDURE InsertProcOffsets(procTable: ProcTable; ptrTable: PtrTable; maxPtr: LONGINT);
	VAR success: BOOLEAN; i, pos, poslast: LONGINT; 
	BEGIN
		(* this procedure is called by procedure Publish only and is protected by the Machine.Modules lock *)
		IF LEN(procTable) > 0 THEN
			ASSERT( numProcs + LEN(procTable) <= LEN(procOffsets) );
			
			(* ptrTabe ignored in UnixAos *)
			
			success := FindInsertionPos(procTable[0], pos); 
			success := success & FindInsertionPos(procTable[LEN(procTable) - 1], poslast);

			IF success THEN
				FOR i := numProcs - 1 TO pos BY -1 DO 
					procOffsets[i + LEN(procTable)] := procOffsets[i] 
				END;
				FOR i := 0 TO LEN(procTable) - 1 DO
					procTable[i].noPtr := 0;	(* ignore the pointers *)
					procOffsets[pos + i].data := procTable[i];
					procOffsets[pos + i].startIndex := 0; 
				END;
				numProcs := numProcs + LEN(procTable);
			END
		END
	END InsertProcOffsets;
	
	(* ----------------------------------------------------------*)


	PROCEDURE GetHeapRoutines( m: Module );
	VAR i: LONGINT;
	BEGIN
		FOR i := 0 TO 2 DO  KernelRoutines[i].adr := ProcByName( KernelRoutines[i].name, m )  END
	END GetHeapRoutines;

	PROCEDURE GetObjectRoutines( m: Module );
	VAR i: LONGINT;
	BEGIN
		FOR i := 3 TO 9 DO  KernelRoutines[i].adr := ProcByName( KernelRoutines[i].name, m )  END
	END GetObjectRoutines;

	PROCEDURE GetModuleRoutines( m: Module );
	BEGIN
		KernelRoutines[10].adr := ProcByName( KernelRoutines[10].name, m )
	END GetModuleRoutines;



	PROCEDURE PrepareGlue( m: Module );
	VAR i, n: LONGINT; name: Name; x: Module;
	BEGIN
		INC( m.refcnt );   (* gets never unloaded *)

		(* link to Unix (dlsym) *)
		dlsymAdr := m.sb - AdrSize;
		
		n := 0;
		FOR i := 0 TO LEN( m.typeInfo ) - 1 DO
			name := m.typeInfo[i].name;
			IF name = "PtrElemDesc" THEN  ptrElemTag := m.typeInfo[i].tag ;  INC( n )  END;
		END;
		IF n # 1 THEN
			error.Ln;
			error.String( "### 'PtrElemDesc' not found in module Glue" );  error.Ln;
		END;
		x := modules;
		WHILE x # NIL DO
			S.PUT( S.VAL( Address, x.typeInfo ) - AdrSize, S.VAL( SET, ptrElemTag ) + arrayMask );
			x := x.next
		END
	END PrepareGlue;
	
	PROCEDURE FixTypeDescs( m: Module );
	VAR i: LONGINT; 
		
		PROCEDURE PatchExport( VAR scope: ExportDesc;  tag: LONGINT );
		VAR i: LONGINT;  t: Address;
		BEGIN
			S.GET( S.VAL( Address, scope.dsc ) - AdrSize, t );
			IF t # tag THEN
				S.PUT( S.VAL( Address, scope.dsc ) - AdrSize, tag );  i := 0;
				WHILE i < scope.exports DO
					IF scope.dsc[i].exports > 0 THEN  PatchExport( scope.dsc[i], tag )  END;
					INC( i )
				END
			END
		END PatchExport;
	
	BEGIN
		FOR i := 0 TO LEN( m.typeInfo ) -1 DO
			S.PUT( S.VAL( Address, m.typeInfo[i] ) - AdrSize, tdTag );
		END;
		S.PUT( S.VAL( Address, m ) - AdrSize,  modTag );
		PatchExport( m.export, S.VAL( Address, S.VAL( SET, expTag ) + arrayMask ) );
	END FixTypeDescs;


	
	PROCEDURE FixupModuletypes( m: Module );
	VAR i, n: LONGINT;  name: Name;  x: Module;
	BEGIN
		n := 0;
		FOR i := 0 TO LEN( m.typeInfo ) - 1 DO
			name := m.typeInfo[i].name;
			IF name = "TypeDesc" THEN  tdTag := m.typeInfo[i].tag;  INC( n )  END;
			IF name = "Module" THEN  modTag := m.typeInfo[i].tag;  INC( n )  END;
			IF name = "ExportDesc" THEN  expTag := m.typeInfo[i].tag;  INC( n )  END;
			IF name = "ProcTableEntry" THEN  procTableEntryTag := m.typeInfo[i].tag;  INC( n )  END;
			IF name = "ProcOffsetEntry" THEN  procOffsetEntryTag := m.typeInfo[i].tag;  INC( n )  END;
		END;
		
		IF n # 5 THEN
			error.Ln;
			error.String( "### not all expected types found in module 'Modules'" ); 
			error.Ln;
		END;
		x := modules;
		WHILE x # NIL DO
			FixTypeDescs( x );
			x := x.next
		END
	END FixupModuletypes;

	PROCEDURE Relocate( adr: LONGINT );
	VAR i: LONGINT;
	BEGIN
		FOR i := 0 TO ptrFixx - 1 DO
			IF ptrFix[i] = adr THEN
			(*	Error( "", "same ptr location marked twice for fixing, ignored" );	*)
				RETURN
			END
		END;
		IF ptrFixx # -1 THEN
			IF ptrFixx < NofPtrFix THEN  ptrFix[ptrFixx] := adr;  INC( ptrFixx )
			ELSE  Error( "", "Too many ptr fixes" );  ptrFixx := -1
			END
		END
	END Relocate;


	(* GetNum - Get a compressed refblk number. *)

	PROCEDURE GetNum( refs: Bytes;  VAR i, num: LONGINT );
	VAR n, s: LONGINT;  x: CHAR;
	BEGIN
		s := 0;  n := 0;
		x := refs[i];  INC(i);
		WHILE ORD(x) >= 128 DO
			INC(n, ASH(ORD(x) - 128, s));
			INC(s, 7);
			x := refs[i];  INC(i)
		END;
		num := n + ASH(ORD(x) MOD 64 - ORD(x) DIV 64 * 64, s)
	END GetNum;

	(* VarByName - Find a global variable in the reference block. *)

	PROCEDURE VarByName( refs: Bytes;  CONST name: ARRAY OF CHAR ): S.SIZE;
	VAR mode: CHAR;  j, m, adr, type, t, i: LONGINT;  s: Name;  found: BOOLEAN;
	BEGIN
		ASSERT((refs[0] = 0F8X) & (refs[1] = 0X) & (refs[2] = "$") & (refs[3] = "$") & (refs[4] = 0X));
		m := LEN(refs^);  found := FALSE; i := 5;
		mode := refs[i];  INC(i);
		WHILE (i < m) & ((mode = 1X) OR (mode = 3X)) & ~found DO	(* var *)
			type := ORD(refs[i]);  INC(i);
			IF (type >= 81H) OR (type = 16H) OR (type = 1DH) THEN
				GetNum( refs, i, t )	(* dim/tdadr *)
			END;
			GetNum( refs, i, adr );
			j := 0;  REPEAT s[j] := refs[i];  INC(i);  INC(j) UNTIL s[j-1] = 0X;
			IF s = name THEN found := TRUE
			ELSIF i < m THEN mode := refs[i];  INC(i)
			END
		END;
		IF found THEN
			ASSERT((mode = 1X) & ((type = 0DH) OR (type = 1DH) OR (type = 06H)))	(* pointer or LInt VAR *)
		ELSE
			adr := 0
		END;
		RETURN S.VAL( S.SIZE, adr )
	END VarByName;
	
	
	PROCEDURE AssignValue( CONST module, variable: ARRAY OF CHAR; value: Address; reloc: BOOLEAN );
	VAR m: Module; ofs: S.SIZE;
	BEGIN
		m := modules;
		WHILE (m # NIL) & (m.name # module) DO m := m.next  END;
		IF m = NIL THEN
			error.String( "### AssignValue: module '" ); error.String( module ); 
			error.String( "' not found" ); error.Ln;
		ELSE
			ofs := VarByName( m.refs, variable );
			IF ofs = 0 THEN
				error.String( "### AssignValue: variable '" ); error.String( module ); 
				error.Char( '.' ); error.String( variable );
				error.String( "' not found" ); error.Ln
			ELSE
				S.PUT( m.sb + ofs, value );
				IF reloc THEN  Relocate( m.sb + ofs )  END
			END
		END
	END AssignValue;


	(* -------------------------  Loader  ------------------------- *)


	(* ReadHeader - Read object file header. *)

	PROCEDURE ReadHeader( r: Streams.Reader; VAR h: ObjHeader; VAR res: LONGINT; VAR msg: ARRAY OF CHAR );
	VAR symSize: LONGINT; flags: SET; tag: CHAR;
	BEGIN
		r.Char( tag );
		IF tag = FileTag THEN
			r.Char( tag );
			IF tag = NoZeroCompress THEN  r.Char( tag )  END;	(* no zero compression in symbol file *)
			IF (tag = FileVersion) OR (tag >= FileVersionOC) & (tag <= CurrentFileVersion) THEN
				IF tag = FileVersion THEN
					r.RawNum( symSize );
				ELSIF tag >= FileVersionOC THEN
					r.RawLInt( symSize )
				END;
				flags := {};
				r.SkipBytes( symSize );	(* skip symbols *)

				r.RawLInt( h.refSize );
				r.RawLInt( h.entries );
				r.RawLInt( h.commands );
				r.RawLInt( h.pointers );
				r.RawLInt( h.types );
				r.RawLInt( h.modules );
				r.RawLInt( h.dataLinks );
				r.RawLInt( h.links );
				r.RawLInt( h.dataSize );
				r.RawLInt( h.constSize );
				r.RawLInt( h.codeSize );
				r.RawLInt( h.exTableLen );
				r.RawLInt( h.procs );
				r.RawLInt( h.maxPtrs );
				r.RawLInt( h.staticTdSize ); (* ug *)
				IF ORD(tag) >= 0B4H THEN  r.RawLInt( h.crc )  END;
				r.RawString( h.name );
				IF r.res # Streams.Ok THEN  res := r.res  END
			ELSE
				res := TagInvalid;  COPY( "invalid tag", msg )
			END
		ELSE
			res := TagInvalid; COPY( "invalid tag", msg )
		END
	END ReadHeader;


	PROCEDURE ReadString8( r: Streams.Reader;  VAR string: ARRAY OF CHAR );
	VAR i: LONGINT;  ch: CHAR;
	BEGIN
		i := 0;  r.Char( ch );
		WHILE ch # 0X DO  string[i] := ch;  INC( i );  r.Char( ch )  END;
		string[i] := 0X;
	END ReadString8;


	PROCEDURE AllocateModule( m: Module; h: ObjHeader );
	CONST ArrHdrSize = 16;   (* {MOD 8 = 0} *)
		LenOfs = 12;   (* offset of dimension 0 in array header *)
		Align = ArrHdrSize + 4 + 15;   (* 4 for tag of next block, 15 for rounding up to 16 *)

	VAR adr, adr0, size, tag, dataSize: LONGINT;

		PROCEDURE ArrSize( elements, elemSize: LONGINT ): LONGINT;
		BEGIN
			RETURN (elements*elemSize + Align) DIV 16*16 (* size rounded up for header and alignment *)
		END ArrSize;

		PROCEDURE SubObjArray( VAR ptr: ANY;  elements, elemSize: LONGINT );
		VAR a: Address; s: Size;
		BEGIN
			ASSERT( adr MOD 16 = 8 );   (* => adr MOD 8 = 0 *)
			a := adr;  s := ArrSize( elements, elemSize );
			INC( adr, s );  DEC( size, s );   (* allocate *)
			(* array header *)
			S.PUT( a - AdrSize, tag );   (* indirect tag *) 
			IF a # adr0 THEN  Relocate( a - AdrSize )  END;
			S.PUT( a + LenOfs, elements );   (* dimension *)
			ptr := S.VAL( ANY, a );  Relocate( S.ADR( ptr ) );
		END SubObjArray;

	BEGIN
		dataSize := h.dataSize + (-h.dataSize) MOD 8;   (* round up to 8 to align constant block *)

		size :=	ArrSize( h.entries, AdrSize ) +
				ArrSize( h.commands, S.SIZEOF( Command ) ) +
				ArrSize( h.pointers, AdrSize ) +
				ArrSize( h.modules, S.SIZEOF( Module ) ) +
				ArrSize( dataSize + h.constSize, 1 ) +
				ArrSize( h.codeSize, 1 ) +
				ArrSize( h.staticTdSize, 1 ) +
				ArrSize( h.exTableLen, S.SIZEOF( ExceptionTableEntry ) ) +
				ArrSize( h.refSize, 1 );

		adr := NewSys( size );  S.GET( adr - AdrSize, tag );  adr0 := adr;

		SubObjArray( S.VAL( ANY, m.entry ), h.entries, AdrSize );
		SubObjArray( S.VAL( ANY, m.command ), h.commands, S.SIZEOF( Command ) );
		SubObjArray( S.VAL( ANY, m.ptrAdr ), h.pointers, AdrSize );
		NewArr( S.VAL( ANY, m.typeInfo ), ptrElemTag, h.types, 1 );  Relocate( S.ADR( m.typeInfo ) );
		SubObjArray( S.VAL( ANY, m.module ), h.modules, S.SIZEOF( Module ) );
		SubObjArray( S.VAL( ANY, m.data ), dataSize + h.constSize, 1 );
		SubObjArray( S.VAL( ANY, m.code ), h.codeSize, 1 );
		SubObjArray( S.VAL( ANY, m.staticTypeDescs ), h.staticTdSize, 1 );
		SubObjArray( S.VAL( ANY, m.exTable ), h.exTableLen, S.SIZEOF( ExceptionTableEntry ) );
		SubObjArray( S.VAL( ANY, m.refs ), h.refSize, 1 );

		m.sb := S.ADR( m.data[0] ) + dataSize;   (* constants positive, data negative *)
		Relocate( S.ADR( m.sb ) );
	END AllocateModule;


	(* ReadEntryBlock - Read the entry block. *)

	PROCEDURE ReadEntryBlock( r: Streams.Reader;  m: Module; h: ObjHeader ): BOOLEAN;
	VAR tag: CHAR;  i, num: LONGINT;
	BEGIN
		r.Char(tag);
		IF tag = 82X THEN	(* entry tag *)
			FOR i := 0 TO h.entries-1 DO
				r.RawNum(num);
				m.entry[i] := num + S.ADR( m.code[0] );
				Relocate( S.ADR( m.entry[i] ) );
			END;
			(*ASSERT((m.entries > 0) & (m.entry[0] = S.ADR(m.code[0])));*)	(* entry[0] is beginning of code (cf. OPL.Init) *)
			RETURN TRUE
		ELSE
			RETURN FALSE
		END
	END ReadEntryBlock;


	(* ReadPointerBlock - Read the pointer block. *)

	PROCEDURE ReadPointerBlock( r: Streams.Reader;  m: Module; h: ObjHeader ): BOOLEAN;
	VAR tag: CHAR;  i, num: LONGINT;
	BEGIN
		r.Char(tag);
		IF tag = 84X THEN	(* pointer tag *)
			FOR i := 0 TO h.pointers-1 DO
				r.RawNum(num);
				ASSERT(num MOD AdrSize = 0);	(* no deep copy flag *)
				m.ptrAdr[i] := m.sb + num;
				Relocate( S.ADR( m.ptrAdr[i] ) );
			END;
			RETURN TRUE
		ELSE
			RETURN FALSE
		END
	END ReadPointerBlock;


	(* ReadImportBlock - Read the import block. *)

	PROCEDURE ReadImportBlock(	r: Streams.Reader;  m: Module; h: ObjHeader;
								VAR res: LONGINT;  VAR msg: ARRAY OF CHAR ): BOOLEAN;
	VAR
		tag: CHAR;  i: LONGINT;  name: Name;
	BEGIN
		r.Char(tag);
		IF tag = 85X THEN	(* import tag *)
			i := 0;
			WHILE (i # h.modules) & (res = Ok) DO
				ReadString8( r, name );
				(* recursively load the imported module *)
				m.module[i] := Load( name, res, msg );
				Relocate( S.ADR( m.module[i] ) );
				INC( i )
			END
		ELSE
			res := FileCorrupt
		END;
		RETURN res = Ok
	END ReadImportBlock;


	(* ReadDataLinkBlock - Read the data links block. *)

	PROCEDURE ReadDataLinkBlock( r: Streams.Reader;  dataLinks: LONGINT;  VAR d: ARRAY OF DataLinkRec ): BOOLEAN;
	VAR tag: CHAR;  i, j, num: LONGINT;
	BEGIN
		r.Char(tag);
		IF tag = 8DX THEN	(* data links tag *)
			FOR i := 0 TO dataLinks-1 DO
				r.Char(tag);  d[i].mod := ORD(tag);
				r.RawNum(num);  d[i].entry := num;
				r.RawLInt(num);  d[i].fixups := num;  (* fixed size *)
				IF d[i].fixups > 0 THEN
					NEW(d[i].ofs, d[i].fixups);
					FOR j := 0 TO d[i].fixups-1 DO
						r.RawNum(num);  d[i].ofs[j] := num
					END
				ELSE
					d[i].ofs := NIL
				END
			END;
			RETURN TRUE
		ELSE
			RETURN FALSE
		END
	END ReadDataLinkBlock;


	(* ReadConstBlock - Read the constant block. *)

	PROCEDURE ReadConstBlock( r: Streams.Reader;  m: Module; h: ObjHeader ): BOOLEAN;
	VAR tag: CHAR;  i: LONGINT; t: S.ADDRESS;
	BEGIN
		r.Char(tag);
		IF tag = 87X THEN	(* constant tag *)
			t := m.sb;
			FOR i := 0 TO h.constSize-1 DO
				r.Char(tag);  S.PUT(t, tag);  INC(t)
			END;
			IF modTag # 0 THEN
				S.GET(m.sb, t);  ASSERT(t = 0);
				S.PUT(m.sb, m);	(* SELF *)
				Relocate( m.sb )
			END;
			RETURN TRUE
		ELSE
			RETURN FALSE
		END
	END ReadConstBlock;


	(* ReadCodeBlock - Read the code block. *)

	PROCEDURE ReadCodeBlock( r: Streams.Reader;  m: Module; h: ObjHeader ): BOOLEAN;
	VAR tag: CHAR; ignore: LONGINT;
	BEGIN
		r.Char(tag);
		IF tag = 89X THEN	(* code tag *)
			r.Bytes(m.code^, 0, h.codeSize, ignore);
			RETURN TRUE
		ELSE
			RETURN FALSE
		END
	END ReadCodeBlock;


	(* ReadRefBlock - Read the reference block. *)

	PROCEDURE ReadRefBlock( r: Streams.Reader;  m: Module; h: ObjHeader ): BOOLEAN;
	VAR tag: CHAR; ignore: LONGINT;
	BEGIN
		r.Char( tag );
		IF tag = 8CX THEN	(* ref tag *)
			r.Bytes( m.refs^, 0, h.refSize, ignore );
			RETURN TRUE
		ELSE
			RETURN FALSE
		END
	END ReadRefBlock;



	PROCEDURE ReadTypeBlock( r: Streams.Reader;  m: Module; h: ObjHeader; VAR type: ARRAY OF TypeRec ): BOOLEAN;
	VAR
		tag: CHAR;  i, j, num, newMethods, method, pointers, entry: LONGINT;
		tdSize: LONGINT; (* ug *)
		name: Name;  flags: SET;
		recSize, ofs, totTdSize: Size;
		startAddr, tdAdr, base: Address;
		sTB {UNTRACED}: StaticTypeBlock;
	BEGIN
		r.Char(tag);
		IF tag = 8BX THEN	(* type tag *)
			totTdSize := 0;
			IF h.staticTdSize > 0 THEN  startAddr := S.ADR(m.staticTypeDescs[0])  END;
			FOR i := 0 TO h.types - 1 DO
				flags := {};  type[i].init := FALSE;
				r.RawNum( recSize );
				r.RawNum( num );  type[i].entry := num;
				r.RawNum( num );  type[i].baseMod := num;
				r.RawNum( num );  type[i].baseEntry := num;
				r.RawNum( num );  type[i].methods := ABS( num );
				IF num # 0 THEN  flags := {ProtTypeBit}  END;
				r.RawNum( num );  type[i].inhMethods := num;
				r.RawNum( newMethods );
				r.RawLInt( pointers );
				r.RawString( name );
				r.RawLInt( tdSize);

				NewRec( S.VAL( ANY, m.typeInfo[i] ), tdTag, S.SIZEOF( TypeDescRec) );
				Relocate( S.ADR( m.typeInfo[i] ) );
				FillStaticType( tdAdr, startAddr, S.VAL( Address, m.typeInfo[i] ), tdSize, recSize, pointers,
							    MaxTags + type[i].methods);
				m.typeInfo[i].tag := tdAdr;	Relocate( S.ADR( m.typeInfo[i].tag ) );
				m.typeInfo[i].flags := flags;
				m.typeInfo[i].mod := m;		Relocate( S.ADR( m.typeInfo[i].mod ) );
				m.typeInfo[i].name := name;

				base := m.typeInfo[i].tag + Mth0Ofs;   (* read new methods *)
				FOR j := 0 TO newMethods - 1 DO
					r.RawNum( method );
					r.RawNum( entry );
					S.PUT( base - AdrSize*method, m.entry[entry] );
					Relocate( base - AdrSize*method );
				END;
				(* other methods are left NIL *)
				sTB := S.VAL( StaticTypeBlock, tdAdr );
				ASSERT( LEN( sTB.pointerOffsets ) = pointers );
				FOR j := 0 TO pointers - 1 DO
					r.RawNum( num );  ofs := num;
					ASSERT( ofs MOD 4 = 0 );   (* no deep copy flag *)
					sTB.pointerOffsets[j] := ofs;
					ASSERT( S.ADR( sTB.pointerOffsets[j] ) < startAddr + tdSize )
				END;
				
				ASSERT( m.typeInfo[i].tag # 0 );
				ASSERT( S.ADR( m.data[0] ) <=  m.sb + type[i].entry, 1001 );
				ASSERT( m.sb + type[i].entry+4  <= S.ADR( m.data[LEN(m.data)-1])+1, 1002 );
				
				S.PUT( m.sb + type[i].entry, m.typeInfo[i].tag );    (* patch in constant area *)
				Relocate( m.sb + type[i].entry );
				
				startAddr := startAddr + tdSize;
				totTdSize := totTdSize + tdSize;
			END;
			base := S.VAL( Address, m.typeInfo ) - AdrSize;
			S.PUT( base, S.VAL( SET, ptrElemTag ) + arrayMask );

			RETURN modTag # 0
		ELSE
			RETURN FALSE
		END
	END ReadTypeBlock;

	(* ReadCommandBlock - Read the command block. *)

	PROCEDURE ReadCommandBlock( r: Streams.Reader;  m: Module; h: ObjHeader ): BOOLEAN;
	VAR tag: CHAR;  i, adr: LONGINT;
	BEGIN
		r.Char( tag );
		IF tag = 83X THEN  (* command tag *)
			FOR i := 0 TO h.commands - 1 DO
				r.RawNum( adr );  m.command[i].argTdAdr := adr;
				r.RawNum( adr );  m.command[i].retTdAdr := adr;
				r.RawString( m.command[i].name );
				r.RawNum( adr );  m.command[i].entryAdr := adr;
				(* addresses will be fixed up later in FixupCommands *)
			END;
			RETURN TRUE
		ELSE
			RETURN FALSE
		END
	END ReadCommandBlock;

	(* ReadLinkBlock - Read the link block. *)

	PROCEDURE ReadLinkBlock( r: Streams.Reader;
							  links, entries: LONGINT;
							    VAR l: ARRAY OF LinkRec;
							    VAR f: ARRAY OF LONGINT;
							    VAR caseTableSize: LONGINT ): BOOLEAN;
	VAR tag: CHAR;  i, num: LONGINT;
	BEGIN
		r.Char( tag );
		IF tag = 86X THEN  (* links tag *)
			FOR i := 0 TO links - 1 DO
				r.Char( tag );  l[i].mod := ORD( tag );  r.Char( tag );  l[i].entry := ORD( tag );
				r.RawNum( num );  l[i].link := num
			END;
			FOR i := 0 TO entries - 1 DO  r.RawNum( num );  f[i] := num;   END;
			r.RawNum( caseTableSize );
			RETURN TRUE
		ELSE
			RETURN FALSE
		END
	END ReadLinkBlock;

	PROCEDURE ReadPtrsInProcBlock( r: Streams.Reader;  m: Module ): BOOLEAN;
	VAR
		tag: CHAR;  i, j, codeoffset, beginOffset, endOffset, nofptrs, p: LONGINT;
		procTable: ProcTable;  ptrTable: PtrTable;

		PROCEDURE Max( i, j: LONGINT ): LONGINT;
		BEGIN
			IF i > j THEN  RETURN i  ELSE  RETURN j  END
		END Max;

		PROCEDURE SwapProcTableEntries( p, q: LONGINT );
		VAR procentry: ProcTableEntry;  k, i, basep, baseq, ptr: LONGINT;
		BEGIN
			k := Max( procTable[p].noPtr, procTable[q].noPtr );
			IF k > 0 THEN  (* swap entries in ptrTable first *)
				basep := p*m.maxPtrs;  baseq := q*m.maxPtrs;
				FOR i := 0 TO k - 1 DO
					ptr := ptrTable[basep + i];  ptrTable[basep + i] := ptrTable[baseq + i];  ptrTable[baseq + i] := ptr
				END
			END;
			procentry := procTable[p];  procTable[p] := procTable[q];  procTable[q] := procentry
		END SwapProcTableEntries;

		PROCEDURE SortProcTable;
		VAR i, j, min: LONGINT;
		BEGIN
			FOR i := 0 TO m.noProcs - 2 DO
				min := i;
				FOR j := i + 1 TO m.noProcs - 1 DO
					IF procTable[j].pcFrom < procTable[min].pcFrom THEN  min := j  END
				END;
				IF min # i THEN  SwapProcTableEntries( i, min )  END
			END
		END SortProcTable;

	BEGIN
		r.Char( tag );
		IF tag = 8FX THEN
			NEW( procTable, m.noProcs );  NEW( ptrTable, m.noProcs*m.maxPtrs );
			(* m.noProcs > 0 since the empty module contains the module body procedure *)
			FOR i := 0 TO m.noProcs - 1 DO
				r.RawNum( codeoffset );
				r.RawNum( beginOffset );
				r.RawNum( endOffset );
				r.RawLInt( nofptrs );   (* fixed size *)

				procTable[i].pcFrom := codeoffset + S.ADR( m.code[0] );
				procTable[i].pcStatementBegin := beginOffset + S.ADR( m.code[0] );
				procTable[i].pcStatementEnd := endOffset + S.ADR( m.code[0] );
				procTable[i].noPtr := nofptrs;
				FOR j := 0 TO nofptrs - 1 DO  r.RawNum( p );  ptrTable[i*m.maxPtrs + j] := p;   END  ;
			END;
			SortProcTable();
			m.firstProc := procTable[0].pcFrom;  Relocate( S.ADR( m.firstProc ) );
			FOR i := 0 TO m.noProcs - 2 DO  procTable[i].pcLimit := procTable[i + 1].pcFrom  END;
			procTable[m.noProcs - 1].pcLimit := S.ADR( m.code[0] ) + LEN( m.code ) + 1;
					(* last element ùerved for end of code segment, allow 1 byte extra, cf. Modules.ThisModuleByAdr *)
			InsertProcOffsets(procTable, ptrTable, m.maxPtrs);
			procTable := NIL;  ptrTable := NIL;
			RETURN TRUE
		ELSE
			RETURN FALSE
		END;
	END ReadPtrsInProcBlock;

	PROCEDURE ReadExTableBlock( r: Streams.Reader;  m: Module ): BOOLEAN;
	VAR tag: CHAR;  pcFrom, pcTo, pcHandler, i: LONGINT;

		PROCEDURE SelectionSort( exTable: ExceptionTable );
		VAR p, q, min: LONGINT;  entry: ExceptionTableEntry;
		BEGIN
			FOR p := 0 TO LEN( exTable ) - 2 DO
				min := p;
				FOR q := p + 1 TO LEN( exTable ) - 1 DO
					IF exTable[min].pcFrom > exTable[q].pcFrom THEN  min := q  END;
					entry := exTable[min];  exTable[min] := exTable[p];  exTable[p] := entry;
				END
			END
		END SelectionSort;

	BEGIN
		r.Char( tag );
		IF tag = 8EX THEN
			FOR i := 0 TO LEN( m.exTable ) - 1 DO
				r.Char( tag );
				IF tag = 0FEX THEN
					r.RawNum( pcFrom );
					r.RawNum( pcTo );
					r.RawNum( pcHandler );
					m.exTable[i].pcFrom := pcFrom + S.ADR( m.code[0] );
					Relocate( S.ADR( m.exTable[i].pcFrom ) );
					m.exTable[i].pcTo := pcTo + S.ADR( m.code[0] );
					Relocate( S.ADR( m.exTable[i].pcTo ) );
					m.exTable[i].pcHandler := pcHandler + S.ADR( m.code[0] );
					Relocate( S.ADR( m.exTable[i].pcHandler ) )
				ELSE
					RETURN FALSE
				END;
			END;
			SelectionSort( m.exTable );
			RETURN TRUE
		ELSE
			RETURN FALSE
		END;
	END ReadExTableBlock;


	PROCEDURE ReadExportBlock( r: Streams.Reader;  m: Module ): BOOLEAN;
	VAR tag: CHAR;  struct: ARRAY MaxStructs OF Address;
		structs, i: LONGINT;
		p {UNTRACED}: ExportPtr; (* this variable must be untraced since it will be casted from a pure address field, it is not a valid heap block *)


		PROCEDURE LoadScope( VAR scope: ExportDesc;  level, adr: LONGINT );
		VAR no1, no2, fp, off, num: LONGINT;
		BEGIN
			r.RawLInt( num );  scope.exports := num; (* fixed size *)
			no1 := 0;  no2 := 0;

			IF scope.exports # 0 THEN
				NewArr( S.VAL( ANY, scope.dsc ), expTag, scope.exports, 1 );
				Relocate( S.ADR( scope.dsc ) );
				scope.dsc[0].adr := adr
			END;
			IF level = EUrecScope THEN
				INC( structs );  struct[structs] := S.VAL( Address, S.ADR( scope ) )
			END;
			r.RawNum( fp );
			WHILE fp # EUEnd DO
				IF fp = EURecord THEN
					r.RawNum( off );
					IF off < 0 THEN
						p := S.VAL( ExportPtr, struct[-off] );
						scope.dsc[no2].exports := p.exports;
						scope.dsc[no2].dsc := p.dsc;   (* old type *)
						Relocate( S.ADR( scope.dsc[no2].dsc ) )
					ELSE
						LoadScope( scope.dsc[no2], EUrecScope, off )
					END
				ELSE
					IF level = EUobjScope THEN  r.RawNum( adr ); scope.dsc[no1].adr := adr  END;
					scope.dsc[no1].fp := fp;  no2 := no1;  INC( no1 )
				END;
				r.RawNum( fp )
			END
		END LoadScope;

	BEGIN
		r.Char(tag);
		IF tag = 88X THEN	(* export tag *)
			structs := 0;
			FOR i := 0 TO MaxStructs - 1 DO  struct[i] := NilVal  END;
			LoadScope( m.export, EUobjScope, 0 );
			RETURN TRUE
		ELSE
			RETURN FALSE
		END
	END ReadExportBlock;


	PROCEDURE ReadUseBlock( r: Streams.Reader;  m: Module;  CONST dataLink: ARRAY OF DataLinkRec;
							   VAR res: LONGINT;  VAR msg: ARRAY OF CHAR
							   ): BOOLEAN;
	VAR tag: CHAR;  mod: Module;  prevname, name: ARRAY 256 OF CHAR;

		PROCEDURE Err;
		BEGIN
			IF res = Ok THEN
				res := IncompatibleImport;
				error.String( m.name );  error.String( " incompatible with " );  error.String( mod.name );  error.String( "  :  " )
			END
		END Err;

		PROCEDURE FixupVar( code, link, fixval: LONGINT );
		VAR i, val, adr: LONGINT;
		BEGIN
			ASSERT(dataLink[link].mod # 0);	(* this must be non-local module (?) *)
			FOR i := 0 TO dataLink[link].fixups - 1 DO
				adr := code + dataLink[link].ofs[i];
				S.GET( adr, val );
				S.PUT( adr, val + fixval );		Relocate( adr );
			END
		END FixupVar;

		PROCEDURE FixupCall( code, link, fixval: LONGINT );
		VAR nextlink: LONGINT;  opcode: CHAR;
		BEGIN
			REPEAT
				(*ASSERT( (link >= 0) & (link < m.codeSize) );  *)
				S.GET( code + link, nextlink );
				S.GET( code + link - 1, opcode );   (* backward disassembly safe? *)
				IF opcode = 0E8X THEN  (* call instruction relative *)
					S.PUT( code + link, fixval - (code + link + 4) ) (* + 4: to next instruction *)
					(* relative, no further fixup required *)
				ELSE  (* move instruction absolute *)
					S.PUT( code + link, fixval );  Relocate( code + link )
				END;
				link := nextlink
			UNTIL link = Sentinel
		END FixupCall;

		PROCEDURE CheckScope( scope: ExportDesc;  level: INTEGER );
		VAR fp, link, i: LONGINT;  adr, tdadr: Address;  tmpErr: BOOLEAN; 
		BEGIN
			tmpErr := (level = EUerrScope);  i := 0;  link := 0;  r.RawNum( fp ); 
			WHILE fp # EUEnd DO
				IF fp = EURecord THEN
					r.RawNum( link );
					IF tmpErr THEN  CheckScope( scope.dsc[i], EUerrScope )
					ELSE
						IF scope.dsc[i].dsc # NIL THEN
							IF link # 0 THEN
								adr := scope.dsc[i].dsc[0].adr;
								S.GET( mod.sb + adr, tdadr );
								S.PUT( m.sb - link, tdadr );  
								Relocate( m.sb - link )
							END
						END;
						CheckScope( scope.dsc[i], EUrecScope )
					END
				ELSE
					prevname := name;  ReadString8( r, name );  
					IF level >= EUobjScope THEN
						tmpErr := FALSE;
						IF level = EUobjScope THEN  r.RawNum( link )  END;
						i := 0;
						WHILE (i < scope.exports) & (scope.dsc[i].fp # fp) DO  INC( i )  END;
						IF i >= scope.exports THEN
							Err;  tmpErr := TRUE;  Append( "/", msg );
							IF name = "@" THEN  Append( "@/",msg );  Append( prevname, msg )
							ELSE  Append( name, msg )
							END;
						ELSIF (level = EUobjScope) & (link # 0) THEN
							IF ~(EUProcFlagBit IN S.VAL( SET, link )) THEN
								FixupVar( S.ADR( m.code[0] ), link, mod.sb + scope.dsc[i].adr )
							ELSE
								FixupCall( S.ADR( m.code[0] ),
										    S.VAL( S.SIZE, S.VAL( SET, link ) - {EUProcFlagBit} ),
										    scope.dsc[i].adr + S.ADR( mod.code[0] ) )
							END
						END
					END
				END;
				r.RawNum( fp )
			END
		END CheckScope;

	BEGIN
		r.Char(tag);
		IF tag = 8AX THEN	(* use tag *)
			ReadString8( r, name );
			WHILE (name # "") & (res = 0) DO
				mod := Load( name, res, msg );
				IF mod # NIL THEN  CheckScope( mod.export, EUobjScope )  END;
				ReadString8( r, name )
			END ;
		ELSE
			res := FileCorrupt
		END;
		RETURN res = Ok
	END ReadUseBlock;


	(* FixupGlobals - Fix up references to global variables. *)
	PROCEDURE FixupGlobals( m: Module;  CONST dataLink: ARRAY OF DataLinkRec );
	VAR i: LONGINT; t: S.SIZE;  adr: Address;
	BEGIN
		IF dataLink[0].mod = 0 THEN  (* local module has globals *)
			FOR i := 0 TO dataLink[0].fixups - 1 DO
				adr := S.ADR( m.code[0] ) + dataLink[0].ofs[i];
				S.GET( adr, t );  S.PUT( adr, t + m.sb );  Relocate( adr )
			END
		END
	END FixupGlobals;

	(* When loader parsed the command block, the type descriptors had not yet been allocated
		so we could not fixup the addresses -> do it now. *)
	PROCEDURE FixupCommands( m: Module; h: ObjHeader );
	VAR i: LONGINT;
	BEGIN
		FOR i := 0 TO h.commands - 1 DO
			m.command[i].entryAdr := m.command[i].entryAdr + S.ADR( m.code[0] );
			Relocate( S.ADR( m.command[i].entryAdr ) );
			IF m.command[i].argTdAdr > 1 THEN
				S.GET( m.sb + m.command[i].argTdAdr, m.command[i].argTdAdr );
				Relocate( S.ADR( m.command[i].argTdAdr ) )
			END;
			IF m.command[i].retTdAdr > 1 THEN
				S.GET( m.sb + m.command[i].retTdAdr, m.command[i].retTdAdr );
				Relocate( S.ADR( m.command[i].retTdAdr ) )
			END;
		END;
	END FixupCommands;


	(* InitType - Initialize a dynamic type. *)

	PROCEDURE InitType( m: Module;  VAR type: ARRAY OF TypeRec;  i: LONGINT );
	VAR j, t, root, baseMod, baseTag, baseMth, extLevel, baseRoot: LONGINT;  baseM: Module;
	BEGIN
		IF ~type[i].init THEN
			root := m.typeInfo[i].tag;
			baseTag := root + Tag0Ofs;
			baseMth := root + Mth0Ofs;
			baseMod := type[i].baseMod;  extLevel := 0;
			ASSERT( baseMod >= -1 );
			IF baseMod # -1 THEN  (* extended type *)
				IF baseMod = 0 THEN  (* base type local *)
					j := 0;
					WHILE type[j].entry # type[i].baseEntry DO  INC( j )  END;   (* find base type *)
					InitType( m, type, j );   (* and initialize it first *)
					baseM := m
				ELSE  (* base type imported *)
					baseM := m.module[baseMod - 1];
					t := type[i].baseEntry;   (* fingerprint *)
					j := 0;
					WHILE baseM.export.dsc[j].fp # t DO  INC( j )  END;   (* find base type *)
					type[i].baseEntry := baseM.export.dsc[j].dsc[0].adr
				END;
				(* copy base tags *)
				S.GET( baseM.sb + type[i].baseEntry, baseRoot );
				S.GET( baseRoot + Tag0Ofs, t );
				WHILE t # 0 DO
					S.PUT( baseTag - AdrSize*extLevel, t );  Relocate( baseTag - AdrSize*extLevel );
					INC( extLevel );
					S.GET( baseRoot + Tag0Ofs - AdrSize*extLevel, t )
				END;
				(* copy non-overwritten base methods *)
				FOR j := 0 TO type[i].inhMethods - 1 DO
					S.GET( baseMth - AdrSize*j, t );   (* existing method *)
					IF t = 0 THEN
						S.GET( baseRoot + Mth0Ofs - AdrSize*j, t );   (* base method *)
						S.PUT( baseMth - AdrSize*j, t );  Relocate( baseMth - AdrSize*j )
					END;
				END
			END;
			m.typeInfo[i].flags := m.typeInfo[i].flags + S.VAL( SET, extLevel );
			ASSERT( extLevel < MaxTags );

			S.PUT( baseTag - AdrSize*extLevel, m.typeInfo[i].tag );    (* self *)
			Relocate( baseTag - AdrSize*extLevel );

			(* init type for static type descriptors *)
			type[i].init := TRUE
		END
	END InitType;


	(* FixupLinks - Fix up other references. *)

	PROCEDURE FixupLinks( m: Module;  CONST link: ARRAY OF LinkRec;
						    VAR fixupCounts: ARRAY OF LONGINT;
						   caseTableSize: LONGINT;
						   VAR res: LONGINT );
	VAR codeadr, i, ii: LONGINT;

		PROCEDURE FixRelative( ofs, val: LONGINT );
		VAR t, adr: LONGINT;
		BEGIN
			ASSERT( val # 0 );
			WHILE ofs # Sentinel DO
				adr := codeadr + ofs;  S.GET( adr, t );
				S.PUT( adr, val - (adr + AdrSize) );   (* relative => no relocation required *)
				ofs := t
			END
		END FixRelative;

		PROCEDURE FixEntry( ofs: LONGINT;  VAR fixupCounts: ARRAY OF LONGINT );
		VAR t, adr, i: LONGINT;
		BEGIN
			i := 0;
			WHILE ofs # Sentinel  DO
				adr := codeadr + ofs;  S.GET( adr, t );
				WHILE fixupCounts[i] = 0 DO  INC( i )  END;
				S.PUT( adr, m.entry[i] );  Relocate( adr );
				DEC( fixupCounts[i] );  ofs := t
			END
		END FixEntry;

		PROCEDURE FixCase( ofs, caseTableSize: LONGINT );
		VAR t, adr, i: LONGINT;
		BEGIN
			i := caseTableSize;
			WHILE i > 0 DO
				adr := m.sb + ofs;  S.GET( adr, t );  S.PUT( adr, codeadr + t );  Relocate( adr );
				DEC( i );  ofs := ofs + 4
			END
		END FixCase;

	BEGIN
		codeadr := S.ADR( m.code[0] );
		FOR i := 0 TO LEN( link ) - 1 DO
			ASSERT( link[i].mod = 0 );   (* only fix local things *)
			CASE link[i].entry OF
			| 243..253:
					ii := 253 - link[i].entry;  FixRelative( link[i].link, KernelRoutines[ii].adr )
			| 254:   FixEntry( link[i].link, fixupCounts ) (* local procedure address *)
			| 255:   FixCase( link[i].link, caseTableSize ) (* case table *)
			ELSE
				error.String( "unsupported externel proc # " );  
				error.Int( link[i].entry, 0 );  error.Ln;
				res := 3406;  RETURN  (* unknown fixup type *)
			END
		END
	END FixupLinks;



	PROCEDURE LoadObj(	CONST name, fileName: ARRAY OF CHAR;  r: Streams.Reader;
						VAR res: LONGINT;  VAR msg: ARRAY OF CHAR
						): Module;
	VAR 	i, caseTableSize: LONGINT;   imp: Module;
		h: ObjHeader;
		links: POINTER TO ARRAY OF LinkRec;
		fixupCounts: POINTER TO ARRAY OF LONGINT;
		dataLink: POINTER TO ARRAY OF DataLinkRec;
		type: POINTER TO ARRAY OF TypeRec;
		m: Module;
	BEGIN
		res := Ok;
		ReadHeader( r, h, res, msg );
		IF res = Ok THEN
			IF h.name = name THEN

				NewProtRec( S.VAL( ANY, m ), modTag );  

				imp := lastMod;
				IF imp # NIL THEN  imp.next := m;  Relocate( S.ADR( imp.next ) )   END;
				lastMod := m;
				IF modules = NIL THEN  modules := lastMod  END;
				m.init := FALSE;  m.refcnt := 0;  m.next := NIL;  m.export.dsc := NIL;  m.term := NIL;
				
				i := 0;  WHILE h.name[i] # 0X DO m.name[i] := h.name[i];  INC(i) END;
				m.name[i] := 0X;
				
				m.noProcs := h.procs;
				m.maxPtrs := h.maxPtrs;
				m.crc := h.crc;

				AllocateModule( m, h );

				NEW( dataLink, h.dataLinks );  NEW( links, h.links );  NEW( fixupCounts, h.entries );
				NEW( type, h.types );

				IF ReadEntryBlock( r, m, h ) & ReadCommandBlock( r, m, h ) & ReadPointerBlock( r, m, h ) &
					ReadImportBlock( r, m, h, res, msg ) & ReadDataLinkBlock( r, h.dataLinks, dataLink^ ) &
					ReadLinkBlock( r, h.links, h.entries, links^, fixupCounts^, caseTableSize ) &
					ReadConstBlock(r, m, h) & ReadExportBlock(r, m) & ReadCodeBlock( r, m, h ) &
					ReadUseBlock( r, m, dataLink^, res, msg ) & ReadTypeBlock( r, m, h, type^ ) &
					ReadExTableBlock( r, m ) & ReadPtrsInProcBlock( r, m )  & ReadRefBlock( r, m, h )
				THEN
					IF m.name = "Glue" THEN  PrepareGlue( m )
					ELSIF m.name = "Heaps" THEN  GetHeapRoutines( m )
					ELSIF m.name = "Modules" THEN  
						FixupModuletypes( m );
						GetModuleRoutines( m )
					ELSIF m.name = "Objects" THEN  GetObjectRoutines( m )
					ELSIF m.name = StartModule THEN
						startModuleBody := S.ADR( m.code[0] )
					END;
					IF h.dataLinks # 0 THEN  FixupGlobals( m, dataLink^ )  END;
					IF h.links # 0 THEN  FixupLinks( m, links^, fixupCounts^, caseTableSize, res )  END;
					IF h.commands # 0 THEN  FixupCommands( m, h )  END;
					FOR i := 0 TO LEN(type^)-1  DO  InitType( m, type^, i )  END;
					m.init := TRUE;  m.published := TRUE;
					(*InsertProcOffsets(m.procTable, m.ptrTable, m.maxPtrs);*)
					m.procTable := NIL; m.ptrTable := NIL; (* not used any more as entered in global variable *)
				END
			END
		ELSE
			res := IncompatibleModuleName;  COPY(fileName, msg);  Append(" incompatible module name", msg)
		END;
		IF (res # Ok) & (msg[0] = 0X) THEN  COPY(fileName, msg);  Append(" corrupt", msg)  END;
		IF res # Ok THEN  m := NIL  END;
		RETURN m
	END LoadObj;


	PROCEDURE Load( CONST name: ARRAY OF CHAR; VAR res: LONGINT; VAR msg:  ARRAY OF CHAR  ): Module;
	VAR f: Files.File;  r: Files.Reader;
		fname: ARRAY 64 OF CHAR;
		m: Module;
	BEGIN
		m := modules;  res := Ok;
		WHILE (m # NIL ) & (name # m.name) DO  m := m.next  END;
		IF m = NIL THEN
			COPY( name, fname );  Append( ObjSuffix, fname );
			f := Files.Old( fname );
			IF f = NIL THEN
				Error( fname, " not found" );  res := FileNotFound;  RETURN  NIL
			END;
			Files.OpenReader( r, f, 0 );
			m := LoadObj( name, fname, r, res, msg )
		ELSIF ~m.init THEN
			Error( "", "cyclic import not allowed" );
			m := NIL
		END;
		RETURN m
	END Load;




	PROCEDURE Append( CONST src: ARRAY OF CHAR;  VAR dest: ARRAY OF CHAR );
	VAR i, j, m: LONGINT;
	BEGIN
		j := 0;
		WHILE dest[j] # 0X DO  INC( j )  END;
		m := LEN( dest ) - 1;  i := 0;
		WHILE (src[i] # 0X) & (j # m) DO  dest[j] := src[i];  INC( i );  INC( j )  END;
		dest[j] := 0X
	END Append;


(*	PROCEDURE ShowTD( tag: Address );
	VAR i, val: LONGINT;
	BEGIN
		S.GET( tag - 4, val );  out.Hex( val, -8 );  out.Ln;
		REPEAT
			S.GET( tag, val );
			out.Hex( tag, -8 ); out.Char( ' ' ); out.Hex( val, -8 );  out.Ln;
			INC( tag, 4 ); INC( i )
		UNTIL (val = -4) OR (i = 10);
		out.Ln;
		out.Update
	END ShowTD;	*)
	
	
	PROCEDURE MakeTD;
		(* create temp. type tags which are needed to load the *)
		(* first modules up to module 'Modules'  *)
	VAR 
		exp: ExportPtr;  mod: Module;
		ptr: POINTER TO RECORD a: ANY  END;
		proc: ProcTable;  procOfs: ProcOffsetTable;
		td: TypeDesc;  pTab: PtrTable;
	BEGIN
		NEW( exp );  S.GET( S.VAL( Address, exp ) - AdrSize, expTag );		
		NEW( td );  S.GET( S.VAL( Address, td ) - AdrSize, tdTag );			
		NEW( mod );  S.GET( S.VAL( Address, mod ) - AdrSize, modTag );		
		NEW( ptr );  S.GET( S.VAL( Address, ptr ) - AdrSize, ptrElemTag );		
		NEW( proc, 1 );  S.GET( S.VAL( Address, proc ) - AdrSize, procTableEntryTag );		
		NEW( procOfs, 1 );  S.GET( S.VAL( Address, procOfs ) - AdrSize, procOffsetEntryTag );		
		NEW( pTab, 1 );  S.GET( S.VAL( Address, pTab ) - AdrSize, ptrTableTag );			
	END MakeTD;


	PROCEDURE Init( heap: Address );
	VAR firstBlock: Address;  i, size: LONGINT;
	BEGIN
		FOR i := 0 TO 10 DO  KernelRoutines[0].name := "";  KernelRoutines[0].adr := 0  END;
		KernelRoutines[0].name := "NewRec";
		KernelRoutines[1].name := "NewSys";
		KernelRoutines[2].name := "NewArr";
		KernelRoutines[3].name := "CreateProcess";
		KernelRoutines[4].name := "Await";
		KernelRoutines[6].name := "Lock";
		KernelRoutines[7].name := "Unlock";
		KernelRoutines[10].name := "GetProcedure";
		modules := NIL;  lastMod := NIL;

		dlsymAdr := 0; startModuleBody := 0;

		FOR i := 0 TO NofPtrFix -1 DO  ptrFix[i] := 0  END;
		ptrFixx := 0;

		heapAdr := heap + (-heap) MOD B;
		firstBlock := heapAdr + B - AdrSize;
		size := heap + BootHeapSize - firstBlock;  DEC( size, size MOD B );
		S.PUT( firstBlock, firstBlock + AdrSize );
		S.PUT( firstBlock + AdrSize, size - AdrSize );
		S.PUT( firstBlock + 2*AdrSize, 0 );
		AN := firstBlock ;
		MakeTD
	END Init;


	PROCEDURE OutBootfile( CONST bootName: ARRAY OF CHAR );
	VAR f: Files.File;  w: Files.Writer;  top, from, relocSize, i: LONGINT;  m: Module;
	BEGIN
		top := AN;
		m := modules;

		(* output heap *)
		f := Files.New( bootName );

		Files.OpenWriter( w, f, 0 );
		w.RawLInt( heapAdr );
		w.RawLInt( top - heapAdr );

		from := heapAdr + B - AdrSize;
		w.RawLInt( from );  w.RawLInt( top - from );
		WHILE from < top DO  S.GET( from, i );  w.RawLInt( i );  INC( from, 4 )  END;
		w.RawLInt( startModuleBody );  (* entrypoint *)
		w.RawLInt( 0 );

		(* output relocate information *)
		relocSize := w.Pos( );  w.RawNum( ptrFixx );  i := 0;
		WHILE i < ptrFixx DO  w.RawNum( ptrFix[i] - heapAdr );  INC( i )  END;
		w.RawLInt( dlsymAdr - heapAdr );  relocSize := w.Pos( ) - relocSize;
		w.Update;
		Files.Register( f );

		out.String( "heap: " );  out.Int( top - heapAdr, 0 );
		out.String( "  reloc: " );  out.Int( relocSize, 0 );
		out.String( "  file: " );  out.Int( f.Length( ), 0 )
	END OutBootfile;

	PROCEDURE RelocateProcOffsets;	
	VAR i, j: LONGINT; a: Address;
	BEGIN
		FOR i := 0 TO numProcs - 1 DO
			a := S.ADR( procOffsets[i].data.pcFrom );  j := 0;
			REPEAT
				Relocate( a );  INC( a, AdrSize );  INC( j )
			UNTIL j = 4
		END
	END RelocateProcOffsets;

	PROCEDURE RelocatePtrOffsets;
		(*	
			pointer offsets are not used by the GC of UnixAos because
			I found no way to obtain the state (PC, SP, BP) of the
			active Objects (POSIX threads).
		*)
	END RelocatePtrOffsets;

	PROCEDURE Link*( context: Commands.Context );
	VAR bootFileName, name: Name;
		m: Module;
		res: LONGINT;  msg: ARRAY 128 OF CHAR;
		heap: Address;
	BEGIN
		out := context.out;  error := context.error;
		
		S.NEW( S.VAL( ANY, heap ), BootHeapSize );
		IF heap = 0 THEN  
			error.String( "S.NEW( heap, BootHeapSize ) failed" );  error.Ln;  
			error.Update;
			RETURN  
		END;

		IF ~context.arg.GetString( bootFileName ) OR ~context.arg.GetString( name ) THEN
			error.String( "wrong parameter(s), terminating" ); error.Ln;  
			error.Update;  RETURN
		END;
		IF context.arg.GetString( name ) THEN
			Init( heap );
			NewArr( S.VAL( ANY, procOffsets ), procOffsetEntryTag, InitTableLen, 1 );
			numProcs := 0; 
			NewArr( S.VAL( ANY, ptrOffsets ), ptrTableTag, InitPtrTableLen, 1 );
			numPtrs := 0; 
			
			out.String( "linking " );  out.String( bootFileName );  out.Ln;  
			res := Ok;
			REPEAT
				out.String( "    " );  out.String( name );  out.Ln;
				m := Load( name, res, msg );
				IF m = NIL THEN  
					error.String( "loading module " );  error.String( name ); error.String( "   failed: " );  
					error.String( msg ) 
				 END;
				
			UNTIL ~context.arg.GetString( name ) OR (m = NIL);
			IF res = Ok THEN  
				AssignValue( "Modules", "root", S.VAL( Address, modules ), TRUE );
	
				RelocateProcOffsets;
				AssignValue( "Modules", "procOffsets", S.VAL( Address, procOffsets ), TRUE );
				AssignValue( "Modules", "numProcs", S.VAL( Address, numProcs ), FALSE );
				
				RelocatePtrOffsets;
				AssignValue( "Modules", "ptrOffsets", S.VAL( Address, ptrOffsets ), TRUE );
				AssignValue( "Modules", "numPtrs", S.VAL( Address, numPtrs ), FALSE );

				OutBootfile( bootFileName )  
			END;
			out.Ln
		ELSE  
			error.String( "parameter error, module names missing, terminating" ); error.Ln
		END;
		error.Update; out.Update
	END Link;



END BootLinker.



BootLinker.Link  bootFileName := modName0 modName1 ... ~

	All module names must be listed and topologically sorted.

Boot File Format:

	heapAdr4
	heapSize4
	{adr4 len4 {byte1}}		(* len4 times byte1 *)
	entryAdr4 0X 0X 0X 0X
	nofPtr {adr}				(* nofPtr times adr *)
	dlsymAdr


	All numbers in the relocate information part are in compact format and relative to
	heapAdr.
