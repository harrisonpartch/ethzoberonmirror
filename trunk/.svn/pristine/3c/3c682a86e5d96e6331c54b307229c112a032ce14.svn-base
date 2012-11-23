(* ETH Oberon, Copyright 2000 ETH Zuerich Institut fuer Computersysteme, ETH Zentrum, CH-8092 Zuerich.
Refer to the "General ETH Oberon System Source License" contract available at: http://www.oberon.ethz.ch/ *)

MODULE BootLinker;   (** AUTHOR "G.F." ; PURPOSE "UnixAos bootlinker"; *)

(* based on Oberon for Windows bootlinker (MH) and  MIPS bootlinker (RC) *)


IMPORT S := SYSTEM, Heaps := BootLinkerHeaps,  Modules := BootLinkerModules, Loader := BootLinkerLoader, 
		Commands, Streams, Files;

CONST	
	AdrSize = S.SIZEOF( S.ADDRESS );


TYPE
	Address = S.ADDRESS; 

VAR
	out: Streams.Writer;
	error: Streams.Writer;


	

	PROCEDURE OutBootfile( CONST bootName: ARRAY OF CHAR );
	VAR f: Files.File;  w: Files.Writer;  top, from, i: LONGINT;  m: Modules.Module;
	BEGIN
		top := Heaps.AN;
		m := Modules.root;

		f := Files.New( bootName );  Files.OpenWriter( w, f, 0 );
		
		(* output heap *)
		w.RawLInt( Heaps.heapAdr );
		w.RawLInt( top - Heaps.heapAdr );
		from := Heaps.heapAdr + Heaps.BlockSize - AdrSize;
		w.RawLInt( from );  w.RawLInt( top - from );
		WHILE from < top DO  S.GET( from, i );  w.RawLInt( i );  INC( from, 4 )  END;
		w.RawLInt( Loader.entrypoint );  
		w.RawLInt( 0 );

		(* output relocate information *)
		w.RawNum( Heaps.numRelocations );  i := 0;
		WHILE i < Heaps.numRelocations DO  w.RawNum( Heaps.relocAddr[i] - Heaps.heapAdr );  INC( i )  END;
		
		w.RawLInt( Loader.dlsymAdr - Heaps.heapAdr );  
		
		w.Update;  Files.Register( f );

		out.String( "used heap space: " );  out.Int( (top - Heaps.heapAdr) DIV 1024, 0 );
		out.String( "KB,  relocations: " );  out.Int( Heaps.numRelocations, 0 );
		out.String( ",  file: " );  out.Int( f.Length( ), 0 )
	END OutBootfile;


	PROCEDURE Link*( context: Commands.Context );
	CONST
		Ok = 0;
	VAR 
		bootFileName, name: Modules.Name;
		m: Modules.Module;
		res: LONGINT;  msg: ARRAY 128 OF CHAR;
	BEGIN
		out := context.out;  error := context.error;
		
		IF ~context.arg.GetString( bootFileName ) OR 
		    ~context.arg.GetString( name ) OR 
		    (name # ":=") THEN
			error.String( "wrong parameter(s), terminating" ); error.Ln;  
			error.Update;  RETURN
		END;
		
		IF context.arg.GetString( name ) THEN
			out.String( "linking " );  out.String( bootFileName );  out.Ln;  
			
			Heaps.Initialize( context.error );
			Modules.Initialize( context.error );;
			Loader.Initialize( context.error );
						
			res := Ok;
			REPEAT
				out.String( "    " );  out.String( name );  out.Ln;
				m := Loader.Load( name, res, msg );
				IF m = NIL THEN  
					error.String( "loading module " );  error.String( name ); 
					error.String( "   failed: " );  error.String( msg );  error.Ln
				 END;
			UNTIL ~context.arg.GetString( name ) OR (m = NIL);
			
			IF res = Ok THEN  
				Modules.AssignValue( "Modules", "root", S.VAL( Address, Modules.root ), TRUE );
	
				Modules.RelocateProcOffsets;
				Modules.AssignValue( "Modules", "procOffsets", S.VAL( Address, Modules.procOffsets ), TRUE );
				Modules.AssignValue( "Modules", "numProcs", S.VAL( Address, Modules.numProcs ), FALSE );
				
				Modules.RelocatePtrOffsets;
				Modules.AssignValue( "Modules", "ptrOffsets", S.VAL( Address, Modules.ptrOffsets ), TRUE );
				Modules.AssignValue( "Modules", "numPtrs", S.VAL( Address, Modules.numPtrs ), FALSE );

				OutBootfile( bootFileName )  
			END;
			out.Ln
		ELSE  
			error.String( "parameter error, module names missing, terminating" ); error.Ln
		END;
		error.Update; out.Update
	END Link;



END BootLinker.


Compiler.Compile
	Unix.BootLinkerHeaps.Mod  Unix.BootLinkerModules.Mod  Unix.BootLinkerLoader.Mod  Unix.BootLinker.Mod ~

SystemTools.Free  BootLinker BootLinkerLoader  BootLinkerModules  BootLinkerHeaps ~


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
