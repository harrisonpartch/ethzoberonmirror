(* ETH Oberon, Copyright 2002 ETH Zuerich Institut fuer Computersysteme, ETH Zentrum, CH-8092 Zuerich.
Refer to the "General ETH Oberon System Source License" contract available at: http://www.oberon.ethz.ch/ *)

MODULE Heaps;	(** AUTHOR "G.F."; PURPOSE "Heap management and garbage collector"; *)

IMPORT S := SYSTEM, Trace, Unix, Machine;

TYPE
	Address = S.ADDRESS;
	Size = S.SIZE;


CONST
	Stats* = TRUE; (* maintain statistical counters *)

	
	AdrSize = S.SIZEOF( S.ADDRESS );
	SizeSize = S.SIZEOF( S.SIZE );


	FlagsOfs = AdrSize * 3;			(* flags offset in TypeDesc *)
	ModOfs* = AdrSize * 4;			(* moduleAdr offset in TypeDesc *)
(*	TypeNameOfs = AdrSize * 5;		(* type name offset in TypeDesc *)
	ModNameOfs = AdrSize * 2;		(* module name offset in ModuleDesc *)
*)	
	NilVal* = 0;
	
	MinPtrOfs = -40000000H;	(* sentinel offset for ptrOfs *)
	MethodEndMarker* = MinPtrOfs;   (* marks the end of the method addresses, used in Info.ModuleDetails *)

	ArrayAlignment = 8;
	HeapBlockOffset* = - 2*AdrSize;
	TypeDescOffset* = -AdrSize;
	
	MaxMarkDepth = 8000;



	(* ----------------- object finalization ------------------------------*)

TYPE
	Finalizer* = PROCEDURE {DELEGATE}( obj: ANY );

	FinalizerNode* = POINTER TO RECORD
				objWeak*{UNTRACED}: ANY;	(* weak reference to checked object *)
				markAdr: Address;   				(* address of type tag of object *)
				nextFin: FinalizerNode;   		(* in finalization list *)
				objStrong*: ANY;   				(* strong reference to object to be finalized *)
				finalizer*{UNTRACED}: Finalizer;	(* finalizer, if any *)
				finalizerStrong: Finalizer			(* strong ref. to the obj that is referenced by the finalyzer, if any *)
			END;

VAR
	checkRoot: FinalizerNode;   (* list of checked objects (contains weak references to the checked objects) *)
	finalizeRoot: FinalizerNode;   (* objects scheduled for finalization (contains references to scheduled objects) *)

	(* ------------------------- Heap ------------------------------- *)
CONST
	BlockSize = 32;
	MaxFreeLists = 14; 	(* number of free lists *)
	FreeListBarrier = 7;
	
	ProtOfs = 2*BlockSize + 16;	(*! mod 32 = 16 ! *)
	ProtTypeBit* = 31;   (** flags in TypeDesc, low bits reserved for extLevel *)

	MarkBit* = 0;  ArrayBit* = 1;  FreeBit* = 2;  SubObjBit* = 3;  ProtObjBit* = 4;
	FlagBits* = {MarkBit, ArrayBit, FreeBit, SubObjBit, ProtObjBit};

TYPE
	FreeBlock = POINTER TO RECORD
				tag: Address;  (* = S.ADR( size ) *)
				size: Size;
				next{UNTRACED}: FreeBlock;
			END;
	
	FreeList = RECORD 
				minSize: LONGINT;  
				first{UNTRACED}: FreeBlock;
				last{UNTRACED}: FreeBlock
			END;
	
	ProcessQueue* = RECORD
		head*, tail*: ANY
	END;
			
	ProtRecBlock* = POINTER TO ProtRecBlockDesc;
	ProtRecBlockDesc* = RECORD 
		recSize: Size;	(* needed by SizeOf(blk) in Sweep *)
		
		awaitingLock*:	ProcessQueue;	(* unused in UnixAos *)
		awaitingCond*: ProcessQueue;
		lockedBy*: ANY;	
		lock*: ANY;	(* used by Win32, unused for I386 and UnixAos *)
		
		mtx*: Unix.Mutex_t;			(* processes blocked awaiting lock (UnixAos only) *)
		enter*: Unix.Condition_t;	(* processes blocked awaiting lock (UnixAos only) *)
	END;

	RootObject* = OBJECT 
		PROCEDURE FindRoots*;	(** abstract *)
		BEGIN HALT( 301 ) END FindRoots;
	END RootObject;

	StaticTypeBlock* = POINTER TO StaticTypeDesc;
	StaticTypeDesc = RECORD
		recSize: Size;
		pointerOffsets* {UNTRACED}: PointerOffsets;
	END;

	PointerOffsets = POINTER TO ARRAY OF Size;
	
VAR
	freeLists: ARRAY MaxFreeLists + 1 OF FreeList;

	candidates: ARRAY 1024 OF  Address;
	nofcand: LONGINT;
	
	deferred: ARRAY 1000 OF Address;
	noDeferred: LONGINT;
	
	heapSize, heapAvailable: Size;

	throuput:  Size;
	GC* : PROCEDURE;
	InvokeGC* : PROCEDURE;
	collecting-: BOOLEAN;
	markDepth: LONGINT;
	
	
	
	(** Statistics. Will only be maintained if Stats = TRUE *)

	(** Memory allocation statistics *)
	Nnew- : LONGINT;			(** Number of times NewBlock has been called since system startup *)
	NnewBytes- : HUGEINT;		(** Number of bytes allocated by NewBlock since system startup *)

	(** Garbage collection statistics *)
	Ngc- : LONGINT;  (** Number of GC cycles since system startup *)

	(** Statistics considering the last GC cyle *)
	Nmark-, Nmarked-, NfinalizeAlive-, NfinalizeDead-: LONGINT;
	NgcCyclesMark-, NgcCyclesLastRun-, NgcCyclesMax-, NgcCyclesAllRuns- : HUGEINT;

	
	PROCEDURE EmptyProc;
	END EmptyProc;

	(* ----------------- object finalization ---------------------------*)


	PROCEDURE AddFinalizer*( obj: ANY;  n: FinalizerNode );
	VAR adr: Address;
	BEGIN
		n.objWeak := obj;  n.objStrong := NIL;  n.finalizerStrong := NIL;
		adr := S.VAL( Address, obj );
		IF SubObjBit IN S.VAL( SET, obj ) THEN  (* indirect tag *)
			n.markAdr := S.GET32( adr - AdrSize ) - AdrSize
		ELSIF ProtObjBit IN S.VAL( SET, obj ) THEN  (* protected object *)
			n.markAdr := adr - ProtOfs - AdrSize
		ELSE  n.markAdr := adr - AdrSize
		END;
		Machine.Acquire( Machine.Heaps );
		n.nextFin := checkRoot;  checkRoot := n;
		Machine.Release( Machine.Heaps )
	END AddFinalizer;

	(* Check reachability of finalized objects. *)
	PROCEDURE CheckFinalizedObjects;
	VAR n, p, t: FinalizerNode;  

		PROCEDURE MarkDelegate( p: Finalizer );
		VAR pointer: ANY;
		BEGIN
			S.GET( S.ADR( p ) + AdrSize, pointer );
			IF pointer # NIL THEN  Mark( pointer )  END
		END MarkDelegate;

	BEGIN
		n := checkRoot;
		WHILE n # NIL DO  (* move unmarked checked objects to finalize list *)
			IF ~(MarkBit IN S.VAL( SET, S.GET32( n.markAdr ) )) THEN
				IF n = checkRoot THEN  checkRoot := n.nextFin  ELSE  p.nextFin := n.nextFin  END;
				n.objStrong := n.objWeak;		(* anchor the object for finalization *)
				n.finalizerStrong := n.finalizer;	(* anchor the finalizer for finalization *)
				t := n.nextFin;  n.nextFin := finalizeRoot;  finalizeRoot := n;  n := t;
				IF Stats THEN DEC(NfinalizeAlive); INC(NfinalizeDead) END
			ELSE  p := n;  n := n.nextFin
			END
		END;

		(* now trace the weak references to keep finalized objects alive during this collection *)
		n := finalizeRoot;
		WHILE n # NIL DO
			MarkDelegate( n.finalizerStrong );
			Mark( n.objStrong );  n := n.nextFin
		END;

		n := checkRoot;
		WHILE n # NIL DO (* list of objects that had been marked before entering CheckFinalizedObjects *)
			(* we still have to mark the weak finalizers, as they might have not been marked before  *)
			MarkDelegate( n.finalizer );  n := n.nextFin
		END;
	END CheckFinalizedObjects;

	(** Return the next scheduled finalizer or NIL if none available.  Called by finalizer object in AosKernel. *)
	PROCEDURE GetFinalizer*( ): FinalizerNode;
	VAR n: FinalizerNode;
	BEGIN
		n := NIL;
		IF finalizeRoot # NIL THEN
			Machine.Acquire( Machine.Heaps );
			n := finalizeRoot;   (* take one finalizer *)
			IF n # NIL THEN
				finalizeRoot := n.nextFin;   n.nextFin := NIL;
				IF Stats THEN DEC(NfinalizeDead) END;
			END;
			Machine.Release( Machine.Heaps );
		END;
		RETURN n
	END GetFinalizer;

	(** Check finalizers registered in the specified module, which is about to be freed or shut down.
			Remove all finalizer procedures in this module from the finalizer lists so they won't be called any more. *)
	PROCEDURE CleanupModuleFinalizers*( codeAdr: Address; codeLen: Size;  CONST name: ARRAY OF CHAR );
	VAR n, p, t: FinalizerNode;  codeEnd: Address;  N1, N2: LONGINT;
	BEGIN
		codeEnd := codeAdr + codeLen;  N1 := 0; N2 := 0;
		Machine.Acquire( Machine.Heaps );
		n := checkRoot;
		WHILE n # NIL DO  (* iterate over checked list *)
			t := n;  n := n.nextFin;
			IF Machine.LessOrEqual( codeAdr, S.VAL( Address, t.finalizer ) ) & 
			    Machine.LessOrEqual( S.VAL( Address, t.finalizer ), codeEnd ) THEN
				IF t = checkRoot THEN  checkRoot := t.nextFin  ELSE  p.nextFin := t.nextFin  END;
				IF Stats THEN DEC(NfinalizeAlive) END;
				INC( N1 )
			ELSE  
				p := t
			END
		END;
		(* also remove finalizers from list, so they won't be called *)
		n := finalizeRoot;
		WHILE n # NIL DO  (* iterate over finalized list *)
			t := n;  n := n.nextFin;
			IF Machine.LessOrEqual( codeAdr, S.VAL( Address, t.finalizer ) ) & 
			    Machine.LessOrEqual( S.VAL( Address, t.finalizer ), codeEnd ) THEN
				IF t = finalizeRoot THEN  finalizeRoot := t.nextFin  ELSE  p.nextFin := t.nextFin  END;
				IF Stats THEN DEC(NfinalizeDead) END;
				INC( N2 )
			ELSE  
				p := t
			END
		END;
		Machine.Release( Machine.Heaps );
		IF (N1 # 0) OR (N2 # 0) THEN
			Machine.Acquire ( Machine.TraceOutput );
			Trace.String( name );  Trace.Char( " " );
			Trace.Int( N1, 1 );  Trace.String( " discarded finalizers, " );
			Trace.Int( N2, 1 );  Trace.StringLn( " pending finalizers" );
			Machine.Release ( Machine.TraceOutput );
		END
	END CleanupModuleFinalizers;
	
	
	
	(* Add a root object to the set of traversable objects. If in allocated heap then mark and traverse, if in Module Heap (Bootfile) then only traverse. *)
	PROCEDURE AddRootObject*( rootObject: RootObject );
	BEGIN
		IF rootObject = NIL THEN (* nothing *)
		(*
		ELSIF CheckPointer(SYSTEM.VAL(SYSTEM.ADDRESS,rootObject)) THEN
			(* object in heap, must be fully marked and traversed *)
			Mark(rootObject)
		ELSE
			(* object in bootfile, traverse as root object only *)
			rootObject.nextRoot := rootList; rootList := rootObject;	(* link root list *)
		*)
		ELSE
			Mark( rootObject )
		END;
	END AddRootObject;



	(* ------------------------- garbage collector ----------------------- *)


	PROCEDURE UnmarkedObject( ptr: ANY ): BOOLEAN; (* FALSE: alredy marked or sysblock or subobj *)
	VAR taddr, haddr, block: Address;  hval, tag: SET;  sysblock: BOOLEAN;
	BEGIN
		IF ptr = NIL THEN  RETURN FALSE  END;
		block := S.VAL( Address, ptr );
		IF ~ValidPointer( block ) THEN  RETURN FALSE  END;	
		sysblock := FALSE;  taddr := block - AdrSize;
		IF SubObjBit IN S.VAL( SET, block ) THEN
			(* Subobject or sysblock *)
			S.GET( taddr, tag );
			haddr := S.VAL( Address, tag - {ArrayBit, MarkBit} ) - AdrSize;
			IF taddr - haddr # 24 THEN
				(* subobject! don't mark it *)  RETURN FALSE
			END;
			sysblock := TRUE
		ELSIF ProtObjBit IN S.VAL( SET, block ) THEN  haddr := taddr - ProtOfs;
		ELSE  haddr := taddr;
		END;

		S.GET( haddr, hval );
		IF ~(MarkBit IN hval) THEN
			S.PUT( haddr, hval + {MarkBit} );   (* mark this block *)  INC( Nmarked );
			IF ~sysblock THEN  
				IF ptr IS RootObject THEN  ptr(RootObject).FindRoots  END;	
				RETURN TRUE  
			END
		END;
		RETURN FALSE
	END UnmarkedObject;

	PROCEDURE MarkRecordFields( rec: Address; sTB: StaticTypeBlock );
	VAR ptr: ANY; i, n: Size;  
	BEGIN
		n := LEN( sTB.pointerOffsets ); i := 0;
		WHILE i < n DO
			S.GET( rec + sTB.pointerOffsets[i], ptr );
			IF ptr # NIL THEN  Mark( ptr )  END;
			INC( i )
		END
	END MarkRecordFields;
	
	PROCEDURE Mark*( ptr: ANY );
	VAR 
		block, cur, lastElem: Address;  
		tag: SET;  sTB{UNTRACED}: StaticTypeBlock;
	BEGIN
		IF Stats THEN  INC(Nmark)  END;
		INC( markDepth );  
		
		IF UnmarkedObject( ptr ) THEN
			block := S.VAL( Address, ptr );
			S.GET( block - AdrSize, tag );
			sTB := S.VAL( StaticTypeBlock, tag - {ArrayBit, MarkBit} );
			IF ArrayBit IN tag THEN
				IF markDepth <= MaxMarkDepth - 10 THEN
					 S.GET( block, lastElem );
					 S.GET( block + 2*AdrSize, cur );   
					 REPEAT
						MarkRecordFields( cur, sTB );						
						INC( cur, sTB.recSize );
					UNTIL Machine.GreaterThan( cur, lastElem )
				ELSE
					deferred[noDeferred] := block;  INC( noDeferred );
				END;
			ELSE  
				IF markDepth <= MaxMarkDepth THEN
					MarkRecordFields( block, sTB )
				ELSE
					deferred[noDeferred] := block;  INC( noDeferred );
				END;	
			END;			
		END;
		DEC( markDepth );
		IF (markDepth <= 0) & (noDeferred > 0) THEN  MarkDeferred  END
	END Mark;

	PROCEDURE MarkDeferred;
	VAR 
		block, cur, lastElem: Address;  
		tag: SET;  sTB{UNTRACED}: StaticTypeBlock;
	BEGIN
		markDepth := 1;
		WHILE noDeferred > 0 DO
			DEC( noDeferred );  
			block := deferred[noDeferred];  
			S.GET( block - AdrSize, tag );
			sTB := S.VAL( StaticTypeBlock, tag - {ArrayBit, MarkBit} );
			IF ArrayBit IN tag THEN
				 S.GET( block, lastElem );
				 S.GET( block + 2*AdrSize, cur );   
				 REPEAT
					MarkRecordFields( cur, sTB );						
					INC( cur, sTB.recSize );
				UNTIL Machine.GreaterThan( cur, lastElem )
			ELSE  
				MarkRecordFields( block, sTB )
			END;			
		END;
	END MarkDeferred;


	PROCEDURE AppendFree( VAR freeList: FreeList; block: FreeBlock );
	BEGIN
		IF freeList.first = NIL THEN
			freeList.first := block;  freeList.last := block
		ELSE
			freeList.last.next := block;
			freeList.last := block;
		END;
		block.next := NIL
	END AppendFree;
	
	PROCEDURE Recycle( blkAdr: Address; blkSize: Size );
	VAR i: LONGINT;  block, x: FreeBlock;
	BEGIN
		block := S.VAL( FreeBlock, blkAdr );
		block.tag := blkAdr + AdrSize;
		block.size := blkSize - AdrSize;
		block.next := NIL;
		
		i := 0;
		WHILE (freeLists[i].minSize < blkSize) & (i < MaxFreeLists) DO  INC( i )  END;
		
		IF i < FreeListBarrier THEN	
			AppendFree( freeLists[i], block )
		ELSE
			(* keep them ordered to avoid unnecessary splits *)
			(* this optimization has positive impact on heap utilization
			    130 MB vs. 240 MB heap for compiling and linking a new system
			    but it slows down heap allocation speed. 	*)
			x := freeLists[MaxFreeLists].first;
			IF (x = NIL) OR (x.size > blkSize - AdrSize) THEN 
				block.next := x;
				freeLists[MaxFreeLists].first := block
			ELSE
				WHILE ( x.next # NIL) & (x.next.size < block.size) DO  x := x.next  END;
				block.next := x.next;
				x.next := block 
			END	
		END;	
		
		INC( heapAvailable, blkSize );
	END Recycle;
	
	
	PROCEDURE ClearFreeLists;
	VAR i, minSize: LONGINT;
	BEGIN
		minSize := BlockSize;
		FOR i := 0 TO MaxFreeLists DO  
			freeLists[i].minSize := minSize;
			freeLists[i].first := NIL;
			freeLists[i].last := NIL;
			IF i < FreeListBarrier THEN  INC( minSize, BlockSize )  ELSE  minSize := 2 * minSize  END
		END;
		heapAvailable := 0
	END ClearFreeLists;
	

	PROCEDURE Sweep;
	VAR
		block, freeBlock, endBlockAdr: Address;  tag: SET;  
		blockSize, freeSize: Size;
		memBlock, nextMemBlock: Machine.MemoryBlock;
	BEGIN
		ClearFreeLists;
		heapAvailable := 0; 

		memBlock := Machine.memBlockHead;  
		WHILE memBlock # NIL DO
			block := memBlock.beginBlockAdr;  endBlockAdr := memBlock.endBlockAdr;

			freeSize := 0;
			WHILE Machine.LessThan( block, endBlockAdr ) DO
				blockSize := SizeOf( block );
				S.GET( block, tag );
				IF ~(MarkBit IN tag) THEN
					(* collect *)
					IF freeSize = 0 THEN  freeBlock := block  END;
					INC( freeSize, blockSize );
				ELSE
					S.PUT( block, tag - {MarkBit} );	(* remove mark bit *)
					IF freeSize > 0 THEN
						Recycle( freeBlock, freeSize );
						freeSize := 0
					END
				END;
				INC( block, blockSize );
			END;

			nextMemBlock := memBlock.next;
			
			IF (freeSize = endBlockAdr - memBlock.beginBlockAdr)  THEN
				(* whole block is free, unlink it*)
				Machine.FreeMemBlock( S.VAL( Machine.MemoryBlock, memBlock ) );
				heapSize := GetHeapSize();
			ELSIF freeSize > 0 THEN
				Recycle( freeBlock, freeSize ); (* last collected block: *)
			END;
			
			memBlock := nextMemBlock;
		END
	END Sweep;


	PROCEDURE SizeOf( block: Address ): Size;
	VAR tag: SET;  lastElem: Address;  recSize, blockSize: Size;
	BEGIN
		S.GET( block, tag );
		S.GET( S.VAL( Address, tag - {ArrayBit, MarkBit} ), recSize );
		IF ArrayBit IN tag THEN
			S.GET( block + AdrSize, lastElem );
			blockSize := lastElem + recSize - block
		ELSE
			blockSize := recSize + AdrSize
		END;
		INC( blockSize, (-blockSize) MOD BlockSize );
		RETURN blockSize
	END SizeOf;
	
	
	PROCEDURE SortCandidates;
	VAR i, j, h: LONGINT;  p: Address;
	BEGIN
		(* sort them in increasing order using shellsort *)
		h := 1;
		REPEAT  h := h*3 + 1  UNTIL h > nofcand;
		REPEAT
			h := h DIV 3;  i := h;
			WHILE i < nofcand DO
				p := candidates[i];  j := i;
				WHILE (j >= h) & Machine.GreaterThan(candidates[j - h], p) DO  
					candidates[j] := candidates[j - h];  j := j - h  
				END;
				candidates[j] := p;  INC( i )
			END
		UNTIL h = 1;
	END SortCandidates;

	PROCEDURE CheckCandidates;  
	VAR
		i: LONGINT; sb: Machine.MemoryBlock;
		p, tag1, tag2, block, endBlockAdr: Address;
		blkSize: Size;
	BEGIN
		IF nofcand = 0 THEN  RETURN  END;
		
		SortCandidates;

		(* sweep phase *)
		i := 0;  p := candidates[i];

		sb := Machine.memBlockHead;
		LOOP
			IF sb = NIL THEN  EXIT   END;

			block := sb.beginBlockAdr;  endBlockAdr := sb.endBlockAdr;
			blkSize := SizeOf( block );

			LOOP
				IF Machine.LessOrEqual( p, block + AdrSize ) THEN
					IF p = block + AdrSize THEN
						S.GET( block, tag1 );
						IF tag1 # p THEN  (* not a free block *) Mark( S.VAL( ANY, p ) )  END
					END;
					INC( i );
					IF i = nofcand THEN  EXIT   END;
					p := candidates[i]
				ELSIF p = block + AdrSize + 24 THEN  (* system block ? *)
					S.GET( block, tag1 );
					S.GET( p - AdrSize, tag2 );
					IF (tag2 = p - 24) & (tag2 = tag1)  THEN
						(* really a sysblock *)  Mark( S.VAL( ANY, p ) );
					END;
					INC( i );
					IF i = nofcand THEN  EXIT   END;
					p := candidates[i]
				ELSIF (blkSize > AdrSize + ProtOfs) & (p = block + AdrSize + ProtOfs)  THEN  (* prot. obj. ? *)
					S.GET( block, tag1 );
					IF tag1 = block + AdrSize THEN  Mark( S.VAL( ANY, p ) )  END;
					INC( i );
					IF i = nofcand THEN  EXIT   END;
					p := candidates[i]
				ELSE
					block := block + blkSize;
					IF Machine.GreaterOrEqual( block, endBlockAdr ) THEN  EXIT   END;
					blkSize := SizeOf( block );
				END;
			END;

			IF i = nofcand THEN  EXIT   END;
			sb := sb.next;
		END;
		nofcand := 0
	END CheckCandidates;


	PROCEDURE AddCandidate*( p: Address );
	VAR tag0Addr, tag0: Address;  tag: SET;
	BEGIN
		IF p MOD 32 = 0 THEN
			tag0Addr := p - AdrSize (* RecBlk, ArrBlk *)
		ELSIF p MOD 32 = 16 THEN
			tag0Addr := p - ProtOfs - AdrSize (* ProtObj *)
		ELSIF p MOD 16 = 8 THEN
			tag0Addr := p - 24 - AdrSize (* SysBlk *)
		ELSE  RETURN
		END;
		IF ValidAddress( tag0Addr ) THEN
			S.GET( tag0Addr, tag0 );
			IF ODD( tag0 ) THEN  RETURN  END;  (* already marked *)
			S.GET ( p - AdrSize, tag );
			IF ValidAddress( S.VAL( Address, tag - {ArrayBit, MarkBit} ) ) THEN
				candidates[nofcand] := p;  INC( nofcand );
				IF nofcand = LEN( candidates ) THEN  CheckCandidates  END
			END;
		END
	END AddCandidate;



	PROCEDURE CollectGarbage*( root: RootObject );
	VAR time1, time2 : HUGEINT; 
	BEGIN
		IF Stats THEN
			Nmark := 0; Nmarked := 0;
			INC(Ngc);
			time1 := Machine.GetTimer ();
		END;
		collecting := TRUE;  markDepth := 0; noDeferred := 0;
		
		Mark( root );
		CheckCandidates;  CheckFinalizedObjects;
		Sweep;

		collecting := FALSE;  throuput := 0;
		IF Stats THEN
			time2 := Machine.GetTimer ();
			NgcCyclesLastRun := time2 - time1;
			IF NgcCyclesLastRun > NgcCyclesMax THEN NgcCyclesMax := NgcCyclesLastRun; END;
			INC(NgcCyclesAllRuns, NgcCyclesLastRun);
			NgcCyclesMark := NgcCyclesLastRun
		END;
	END CollectGarbage;
	


	(* -------------------------- memory allocation ----------------------- *)

	PROCEDURE FindFreeBlock( size: Size ): FreeBlock;
	VAR prev, block: FreeBlock;  i: LONGINT;
	BEGIN
		i := 0;
		WHILE (i < MaxFreeLists) & (freeLists[i+1].minSize <= size)  DO  INC( i )  END;
		
		REPEAT
			block := freeLists[i].first;
			IF block # NIL THEN  
				IF block.size + AdrSize >= size THEN
					IF block = freeLists[i].last THEN  freeLists[i].first := NIL;  freeLists[i].last := NIL
					ELSE freeLists[i].first := block.next;  block.next := NIL
					END;
				ELSE  (* i = MaxFreeLists *)
					REPEAT  prev := block;  block := block.next
					UNTIL (block = NIL) OR (block.size + AdrSize >= size);
					IF block # NIL THEN  prev.next := block.next  END
				END
			END;
			INC( i )
		UNTIL (block # NIL) OR (i > MaxFreeLists);
		RETURN block
	END FindFreeBlock;
	
	

	PROCEDURE GetBlock( size: Size ): Address;   (* size MOD B = 0 *)
	VAR 
		block: FreeBlock;  blkSize: Size;  blkAdr, adr2: Address;
	BEGIN
		IF (throuput > Machine.MemBlockSize) & (Machine.lock[Machine.GC] = 'N') THEN
			Machine.Release( Machine.Heaps );
			GC;
			Machine.Acquire( Machine.Heaps );
			throuput := 0;
		END;

		REPEAT
			block := FindFreeBlock( size );
			IF block = NIL THEN
				IF (throuput > 0) & (Machine.lock[Machine.GC] = 'N') THEN
					Machine.Release( Machine.Heaps );
					GC;
					Machine.Acquire( Machine.Heaps );
					throuput := 0;  
				ELSE
					Machine.ExpandHeap( 0, size, S.VAL( Address, block ), adr2 );
					IF block # NIL  THEN  
						heapSize := GetHeapSize();
					ELSE
						Trace.Ln;  
						Trace.String( "Heapspace exhaustet" ); Trace.Ln;  
						Machine.Release( Machine.Heaps );
						HALT( 99 )
					END
				END
			END
		UNTIL block # NIL;

		blkSize := block.size + AdrSize;
		blkAdr := S.VAL( Address, block );
		DEC( heapAvailable, blkSize );
		IF blkSize > size THEN  Recycle( blkAdr + size, blkSize - size )  END;
		
		INC( throuput, size );
		IF Stats THEN  INC(Nnew); INC(NnewBytes, size)  END;
		Machine.Fill32( blkAdr, size, 0 );
		RETURN blkAdr
	END GetBlock;



	(** Private compiler interface. Do not use. *)
	PROCEDURE NewRec*( VAR p: ANY;  tag: Address; isRealtime: BOOLEAN );   (* implementation of NEW( ptr ) *)
	VAR size, recSize: Size;  ptr: Address;  typeInfoAdr: Address;  flags: SET;
	BEGIN
		S.GET( tag - AdrSize, typeInfoAdr );   
		S.GET( typeInfoAdr + FlagsOfs, flags );
		IF ProtTypeBit IN flags THEN  (* protected record *)
			NewProtRec( p, tag, isRealtime );  RETURN
		END;
		S.GET( tag, recSize );
		size := recSize + AdrSize;  INC( size, (-size) MOD BlockSize );
		
		Machine.Acquire( Machine.Heaps );
		ptr := GetBlock( size ) + AdrSize;
		S.PUT( ptr - AdrSize, tag );
		p := S.VAL( ANY, ptr );
		Machine.Release( Machine.Heaps )
	END NewRec;
	
	
	(** Private compiler interface. Do not use. *)
	PROCEDURE NewProtRec*( VAR p: ANY;  tag: Address; isRealtime: BOOLEAN );
	VAR recSize, size: Size;  ptr0, ptr: Address;
	BEGIN
		S.GET( tag, recSize );
		(* add space for tag and header and round up to BlockSize *)
		size := recSize + ProtOfs + AdrSize;  INC( size, (-size) MOD BlockSize );
		
		Machine.Acquire( Machine.Heaps );
		ptr0 := GetBlock( size ) + AdrSize;
		S.PUT( ptr0 - AdrSize, ptr0 );		(* set the tag used by Sweep *)
		S.PUT( ptr0, size - AdrSize );		(* size, needed by SizeOf(blk) in Sweep *)
		
		ptr := ptr0 + ProtOfs;				(* mod 32 = 16 ! *)
		S.PUT( ptr + HeapBlockOffset, ptr0 );
		S.PUT( ptr + TypeDescOffset, tag );	(* set the tag *)
				
		p := S.VAL( ANY, ptr );
		Machine.Release( Machine.Heaps );
	END NewProtRec;


	(** Private compiler interface. Do not use. *)
	PROCEDURE NewSys*( VAR p: ANY;  size: Size; isRealtime: BOOLEAN );   (* implementation of S.NEW(ptr, size) *)
	VAR ptr: Address;
	BEGIN
		size := size + AdrSize + 24;  INC( size, (-size) MOD BlockSize );
		Machine.Acquire( Machine.Heaps );
		ptr := GetBlock( size ) + AdrSize;  
		S.PUT( ptr - AdrSize, ptr );		(* tag used by Sweep *)
		S.PUT( ptr, size - AdrSize );		(* size, needed by SizeOf(blk) in Sweep *)
		S.PUT( ptr + AdrSize, S.VAL( Address, -AdrSize ) );	
		
		S.PUT( ptr + 24 - AdrSize, ptr );	(* tag *)
		p := S.VAL( ANY, ptr + 24 );		(* mod 16 = 8 ! *)
		Machine.Release( Machine.Heaps )
	END NewSys;

	(** Private compiler interface. Do not use. *)
	PROCEDURE NewArr*( VAR p: ANY;  eltag: Address;  nofelem, nofdim: Size; isRealtime: BOOLEAN );
	VAR elSize, arrSize, blkSize, dataOffset, ptrOffset: Size;  ptr, firstElem: Address; 
	BEGIN
		S.GET( eltag, elSize );
		arrSize := nofelem*elSize;
		IF arrSize = 0 THEN
			NewSys( p, nofdim*4 + 3*AdrSize, isRealtime );
		ELSE
			dataOffset := 3*AdrSize + nofdim*AdrSize;
			INC( dataOffset, (-dataOffset) MOD ArrayAlignment );
			S.GET( eltag + AdrSize, ptrOffset );
			IF ptrOffset = -AdrSize THEN
				(* no pointers in element type *)
				NewSys( p, dataOffset + arrSize, isRealtime );
			ELSE
				blkSize := dataOffset + arrSize + AdrSize; INC( blkSize, (-blkSize) MOD BlockSize );
				Machine.Acquire( Machine.Heaps );
				ptr := GetBlock( blkSize ) + AdrSize;
				S.PUT( ptr - AdrSize, S.VAL( SET, eltag ) + {ArrayBit} );
				firstElem := ptr + dataOffset;
				S.PUT( ptr, firstElem + arrSize - elSize );  (* last elem *)
				(* ptr + 4 is reserved for mark phase *)
				S.PUT( ptr + 2*AdrSize, firstElem );
				p := S.VAL( ANY, ptr );
				Machine.Release( Machine.Heaps )
			END
		END;
	END NewArr;

	PROCEDURE FillStaticType* ( VAR staticTypeAddr: Address;
								   startAddr, typeInfoAdr: Address;
								   size, recSize: Size;
								   numPtrs, numSlots: LONGINT );
	VAR 
		p, offset: Address;  sTB {UNTRACED}: StaticTypeBlock;
	BEGIN
		Machine.Acquire( Machine.Heaps );
		
		Machine.Fill32( startAddr, size, 0 );	(* clear whole static type, size MOD AdrSize = 0 implicitly, see WriteType in PCOF.Mod *)
		S.PUT( startAddr, S.VAL( Address, -AdrSize ) );	(* sentinel *)

		(* methods and tags filled in later *)

		offset := AdrSize*(numSlots + 1 + 1);  (* #methods, max. no. of tags, method end marker (sentinel), pointer to type information*)
		p := startAddr + offset;
		S.PUT( p - AdrSize, typeInfoAdr ); 	(* pointer to typeInfo *)
		sTB := S.VAL( StaticTypeBlock, p );
		sTB.recSize := recSize;
		staticTypeAddr := p;
		
		(* create the pointer for the dynamic array of pointer offsets, the dynamic array of pointer offsets 
		    is stored in the static type descriptor, it has no header part *)
		INC( p, S.SIZEOF(StaticTypeDesc) );
		IF p MOD (2 * AdrSize) # 0 THEN  INC( p, AdrSize )  END;
		S.PUT( p + 3 * AdrSize, numPtrs ); (* internal structure of dynamic array without pointers: the first 3 fields are unused *)
		sTB.pointerOffsets := S.VAL( PointerOffsets, p ); (* the fourth field contains the dimension of the array *)

		(* ptrOfs filled in later *)

		Machine.Release( Machine.Heaps )
	END FillStaticType;



	(*------------------------------  misc  ----------------------------------------*)

	(** WriteType - Write a type name (for tracing only). *)
	PROCEDURE WriteType*( t: Address );		(* t is static type descriptor *)
	VAR m: Address; i: LONGINT;  ch: CHAR;  a: Address;
	BEGIN
		S.GET( t - AdrSize, t );
		S.GET( t + 4*AdrSize, m );
		IF m # 0 THEN
			a := m + AdrSize;
			i := 0;  S.GET( a, ch );
			WHILE (ch >= '0') & (ch <= 'z') & (i < 32) DO
				Trace.Char( ch );
				INC( i );  S.GET( a + i, ch )
			END
		ELSE  Trace.String( "NIL" )
		END;
		Trace.Char( '.' );
		a := t + 5*AdrSize;  i := 0;  S.GET( a, ch );
		WHILE (ch >= '0') & (ch <= 'z') & (i < 32) DO
			Trace.Char( ch );
			INC( i );  S.GET( a + i, ch )
		END;
		IF i = 0 THEN  Trace.String( "-" )  END;	
	END WriteType;


	PROCEDURE ValidAddress*( p: Address ): BOOLEAN;
	VAR sb: Machine.MemoryBlock;
	BEGIN
		IF (p # 0 ) & (p MOD 4 = 0) THEN
			sb := Machine.memBlockHead;
			WHILE sb # NIL DO
				IF Machine.LessOrEqual( sb.beginBlockAdr, p ) & 
				    Machine.LessOrEqual( p, sb.endBlockAdr ) THEN  RETURN TRUE  END;
				sb := sb.next;
			END
		END;
		RETURN FALSE
	END ValidAddress;

	PROCEDURE ValidPointer( p: Address ): BOOLEAN;   (* check if p is a valid pointer into the Heap *)
	VAR tag: SET;  ok: BOOLEAN;
	BEGIN
		ok := FALSE;  tag := {};
		IF (p MOD 8 = 0) & ValidAddress( p ) THEN
			IF p MOD 16 = 8 THEN  ok := TRUE (* subobject or sysblock *)
			ELSE
				S.GET( p - AdrSize, tag );
				ok := ValidAddress( S.VAL( Address, tag - {ArrayBit, MarkBit} ) )
			END
		END;
		IF ~ok THEN
			Trace.String( "illegal pointer value: " ); Trace.Hex( p, -8 );
			IF tag # {} THEN  
				Trace.String( " (bad tag: " );  Trace.Hex( S.VAL( Address, tag ), -8 );  Trace.Char( ')' )  
			END;
			Trace.Ln
		END;
		RETURN ok
	END ValidPointer;
	

	(* Returns the size in bytes of the remaining free heap *)
	PROCEDURE Available( ): Size;
	VAR i: LONGINT;  avail: Size;  block: FreeBlock;
	BEGIN
		avail := 0;  i := 0;
		WHILE i <= MaxFreeLists DO
			block := freeLists[i].first;
			WHILE block # NIL  DO
				INC( avail, block.size + AdrSize );  block := block.next
			END;
			INC( i )
		END;
		RETURN avail
	END Available;
	

	(** Returns the total heap size of the Oberon system. *)
	PROCEDURE HeapSize*( ): LONGINT;
	BEGIN
		RETURN heapSize;
	END HeapSize;
	
	
	PROCEDURE GetHeapInfo*( VAR total, free, largest: Size );
	VAR i: LONGINT;  block: FreeBlock;
	BEGIN
		free := 0;  largest := 0;  i := 0;
		Machine.Acquire( Machine.Heaps );
		total := heapSize;
		WHILE i <= MaxFreeLists DO
			block := freeLists[i].first;
			WHILE block # NIL DO
				INC( free, block.size + AdrSize );  
				IF block.size > largest THEN  largest := block.size  END;
				block := block.next;
			END;
			INC( i )
		END;
		Machine.Release( Machine.Heaps );
	END GetHeapInfo;

	PROCEDURE Used*( ): LONGINT;
	VAR used: LONGINT;
	BEGIN
		Machine.Acquire( Machine.Heaps );
		used := heapSize - heapAvailable;
		Machine.Release( Machine.Heaps );
		RETURN used
	END Used;

	PROCEDURE GetHeapSize( ): Size;
	VAR heap: Size;  sb: Machine.MemoryBlock;
	BEGIN
		sb := Machine.memBlockHead;  heap := 0;
		WHILE sb # NIL DO  heap := heap + sb.size;  sb := sb.next  END;
		RETURN heap;
	END GetHeapSize;



	(*------------------ Initialization --------------------------------------------------*)

	
	(*
	(* for debugging the static linker output *)
	PROCEDURE BlockInfo( block: Address );
	VAR tag: SET;  lastElem: Address;  recSize, blockSize: Size;
		tag0, ttag: Address;
	BEGIN
		S.GET( block, tag );
		S.GET( S.VAL( Address, tag - {ArrayBit, MarkBit} ), recSize );
		tag0 := S.VAL( Address, tag - {ArrayBit, MarkBit} );
		Trace.Hex( block, -8 );  Trace.Char( ' ' );  Trace.Hex( tag0, -8 ); Trace.Char( ' ' );
		IF ArrayBit IN tag THEN
			S.GET( block + AdrSize, lastElem );
			blockSize := lastElem + recSize - block;
			INC( blockSize, (-blockSize) MOD BlockSize );
			
			Trace.String( "array of " );  WriteType( tag0 )
		ELSE
			blockSize := recSize + AdrSize;
			INC( blockSize, (-blockSize) MOD BlockSize );
			
			IF tag0 # block + AdrSize THEN  
				WriteType( tag0 )
			ELSE
				S.GET( block + 24, ttag );
				IF ttag = tag0 THEN  Trace.String( "sysblock" )
				ELSE
					S.GET( block + ProtOfs - AdrSize, ttag );
					IF ttag = tag0 THEN 
						Trace.String( "prot. " );
						S.GET( block + ProtOfs, ttag );  WriteType( ttag )
					ELSE
						Trace.String( "?" )
					END
				END
			END
		END;
		
		Trace.Char( ' ' );  Trace.Int( blockSize, 1 );  
		Trace.Ln
	END BlockInfo;
	*)
	
	PROCEDURE InitHeap;
	VAR adr2: Address;
		block, tag: Address;  frBlock:FreeBlock;
		n: LONGINT;
	BEGIN
		n := 0;
		block := Machine.memBlockHead.beginBlockAdr;
		S.GET( block, tag );
		WHILE tag # 0 DO
		(*	IF n < 200 THEN  BlockInfo( block );  INC( n )  END;	*)
			INC( block, SizeOf( block ) );
			S.GET( block, tag );
		END;

		S.PUT( block, block + AdrSize );	(* tag *)
		S.PUT( block + AdrSize,  Machine.memBlockHead.endBlockAdr - block - AdrSize );	(* size *)
		S.PUT( block + AdrSize + SizeSize, S.VAL( Address, 0 ) );		(* next *)
	
		ClearFreeLists;
		freeLists[MaxFreeLists].first := S.VAL( FreeBlock, block );
		
		Machine.ExpandHeap( 0, 2*Machine.MemBlockSize - BlockSize, S.VAL( Address, frBlock ), adr2 );
		IF frBlock # NIL  THEN  freeLists[MaxFreeLists].first.next := frBlock  END;

		heapSize := GetHeapSize();
		heapAvailable := Available()
	END InitHeap;


	PROCEDURE Init;
	BEGIN
		IF Stats THEN
			Ngc := 0;
			Nmark := 0; Nmarked := 0; NfinalizeAlive := 0; NfinalizeDead := 0;
			NgcCyclesMark := 0; NgcCyclesLastRun := 0; NgcCyclesMax := 0; NgcCyclesAllRuns := 0;
		END;

		GC := EmptyProc;			(* no GC until EmptyProc gets replaced (in module Objects) *)
		nofcand := 0; 

		InitHeap;
	END Init;


BEGIN
	Init;
END Heaps.