(* ETH Oberon, Copyright 2000 ETH Zuerich Institut fuer Computersysteme, ETH Zentrum, CH-8092 Zuerich.
Refer to the "General ETH Oberon System Source License" contract available at: http://www.oberon.ethz.ch/ *)

MODULE Traps;  (** AUTHOR "G.F."; PURPOSE "Exception Trap and symbolic debugging"; *)

(* 2000.02.06	g.f.	UnixOberon release 2.3.6d	*)
(* 2006.07.09	g.f.	UnixAos version	*)

IMPORT S := SYSTEM, Trace, Glue, Unix, Objects, Machine, Heaps, Streams, Modules, Reflection, 
		TrapWriters, Commands, StdIO;  


TYPE 		
	SigHandler = PROCEDURE ( sig: LONGINT; scp, ucp, dum: ADDRESS );  
	
VAR 
	InstallSignalHandler: PROCEDURE ( h: SigHandler );  
	
	TrapHandlingLevel: INTEGER;  
	
	trace: BOOLEAN;  
	
	unix: Commands.Context;
		
	
	PROCEDURE Append( VAR ar: ARRAY OF CHAR;  CONST this: ARRAY OF CHAR );
	VAR i, j: LONGINT;
	BEGIN
		i := 0;  j := 0;
		WHILE ar[i] # 0X DO  INC( i )  END;
		WHILE (i < LEN( ar ) - 1) & (this[j] # 0X) DO  ar[i] := this[j];  INC( i );  INC( j )  END;
		ar[i] := 0X
	END Append;
	
	
	PROCEDURE GetTypeName( tag: ADDRESS;  VAR name: ARRAY OF CHAR );
	VAR  typ: Modules.TypeDesc;
	BEGIN
		S.GET( tag - 4, typ );  name[0] := 0X;
		IF typ.mod # NIL THEN  Append( name, typ.mod.name );  Append( name,  "." )  END;
		Append( name, typ.name )
	END GetTypeName;

	PROCEDURE Trap( sig: LONGINT;  ucp: Unix.Ucontext );  
	VAR 
		pc, sp, bp: ADDRESS;  
		trapno: LONGINT;  
		trProcess: Objects.Process;  handled: BOOLEAN;  
		w: Streams.Writer;
	
		PROCEDURE FinishTrapText( exitAos: BOOLEAN );
		VAR tag: ADDRESS;  name: ARRAY 72 OF CHAR;
		BEGIN
			
			w.Ln; w.Ln; 
			w.String("----------------------------------------------------"); w.Ln; 
			w.Char( 2X );   (* end of trap text *) 
			w.Update;
			TrapWriters.Trapped;
			
			IF exitAos THEN  Unix.exit( 1 )  END;
			
			S.GET( S.VAL( ADDRESS, trProcess.obj ) - 4, tag );
			GetTypeName( tag, name );
			IF name = "Oberon.System.OberonRunner" THEN  UnlockOberon  END;
			TrapHandlingLevel := 0;
			Machine.Release( Machine.Trap );
		END FinishTrapText;
		
		
		PROCEDURE TimeTag;
		VAR 
			tv: Unix.Timeval;  tz: Unix.Timezone;  t: Unix.TmPtr;  ret: LONGINT;
			
			PROCEDURE Int( i: LONGINT );
			BEGIN
				IF i < 10 THEN  w.Char( '0' )  END;
				w.Int( i, 0 )
			END Int;
			
		BEGIN
			ret := Unix.gettimeofday( tv, tz );
			t := Unix.localtime( tv );
			w.Int( 1900 + t.year, 4 );  w.Char( '/' );  Int( t.mon + 1 );  w.Char( '/' );  Int( t.mday );  
			w.String( "  " );  Int( t.hour );  w.Char( ':' );  Int( t.min );  w.Ln;
		END TimeTag;
		
	BEGIN 
		INC( TrapHandlingLevel ); 
		IF trace THEN  
			Trace.String( "Aos Trap:  signal = " );  Trace.Int( sig, 0 );  
			Trace.String( ",  ucp = " );  Trace.Hex( S.VAL( ADDRESS, ucp ), -8 );  
			Trace.String( ", traphandling  level = " ); Trace.Int( TrapHandlingLevel, 1 );  
			Trace.Ln;  
		END;  
				
		trProcess := Objects.CurrentProcess( );  
		w := TrapWriters.GetWriter();
		w.Char( 1X );   (* begin of trap text *) 
		w.Ln;  
		w.String( Machine.version ); w.String( "   " );  TimeTag;
		w.Ln;
		IF TrapHandlingLevel = 1 THEN  
			Machine.Acquire( Machine.Trap );
			w.String( "Trap " ) 
		ELSE  
			w.String( "==== recursive Trap" )  
		END;  
		CASE sig OF 
		| 1:		w.String( "1 (Hangup signal)" );   
		| 2:  	w.String( "2 (User interrupt)" );   
		| 3:		w.String( "3 (Quit signal)" );   
		| 4:  	w.String( "4 (Illegal instruction)" );   
		| 5:   	w.String( "5." );  
				sp := ucp.mc.espatsig;
				S.GET( sp, trapno );  w.Int( trapno, 0 );  
				CASE trapno OF 
				| 1:       w.String( "  (WITH guard failed)" ) 
				| 2:       w.String( "  (CASE invalid)" ) 
				| 3:       w.String( "  (RETURN missing)" ) 
				| 5:       w.String( "  (Implicit type guard failed)" ) 
				| 6:       w.String( "  (Type guard failed)" ) 
				| 7:       w.String( "  (Index out of range)" ) 
				| 8:       w.String( "  (ASSERT failed)" ) 
				| 9:       w.String( "  (Array dimension error)" ) 
				ELSE 
					IF trapno >= 30 THEN  w.String( "  (programmed HALT)" )  
					ELSE  w.String( "  (unknown exception, division error?)" )   
					END  
				END;   
		|  8:	w.String( "8 (Arithmetic exception)" );   
		|10: 	w.String( "10 (Bus Error)" ) 
		|11:	w.String( "11 (Segmentation violation)" ) 
		|13:	w.String( "13 (Broken pipe)" ) 
		|14:	w.String( "14 (Alarm signal)" ) 
		ELSE 
			w.String( "(Signal " );  w.Int( sig, 0 );  w.Char( ')' );  
		END;  
		w.Ln;  
		IF TrapHandlingLevel > 1 THEN 
			FinishTrapText( Heaps.collecting OR (TrapHandlingLevel > 2) );
			Objects.Terminate
		ELSE
			pc := ucp.mc.eip;  bp := ucp.mc.ebp;
			IF pc = 0 THEN  
				(* assume call of procedure variable with value NIL *)
				S.GET( sp, pc );   (* get return address on top of stack *)
			END;  	
			w.Ln;
			w.String( "    sp = " );  w.Address( sp );  w.String( ", fp = " );  w.Address( bp ); 
			w.String( ", pc = " );  w.Address( pc );  w.Ln;  
			w.Ln;  
			Reflection.StackTraceBack( w, pc, bp, Objects.GetStackBottom(trProcess), TRUE, FALSE );
			HandleException( trProcess, ucp, handled ); 
			IF handled THEN   
				w.Ln;  w.Ln;
				w.String( "### program continues with exception handler ###" );   w.Ln				
			END;  
			FinishTrapText( FALSE );
			IF handled THEN  RETURN  (* to exception handler! *)END;
			
			IF Machine.standaloneAppl THEN	
				unix.error.Ln;  unix.error.Ln;
				unix.error.String( "### Program aborted. Stack backtrace in logfile" );  unix.error.Ln;
				unix.error.Update
			END;
			IF Heaps.collecting OR Machine.standaloneAppl THEN  
				Machine.Shutdown( FALSE );  Objects.Terminate  
			END;  
			IF trace THEN  
				Trace.String( "Teminating trapped thread " );  Trace.Int( trProcess.id , 0 ); Trace.Ln
			END;  
			Objects.ExitTrap() 
		END
	END Trap;  
	
	
	PROCEDURE UnlockOberon;
	CONST OberonKernel = "Oberon.Kernel";
	VAR c: PROCEDURE;
	BEGIN
		IF Modules.ModuleByName( OberonKernel ) # NIL THEN
			GETPROCEDURE( OberonKernel, "UnlockOberon", c );
			IF c # NIL THEN  c  END
		END;
	END UnlockOberon;
	

	(* Handles an exception. Interrupts are on during this procedure. *)
	PROCEDURE HandleException( obj: Objects.Process; cont: Unix.Ucontext;  VAR handled: BOOLEAN );  
	VAR handler, fp, sp, pc: LONGINT;
	BEGIN 
		IF Unix.version = "Darwin" THEN  handled := FALSE;  RETURN  END;
		(* in Darwin ModifyContext fails with bus error *)
		
		pc := cont.mc.eip;  fp := cont.mc.ebp;  sp := cont.mc.espatsig;
		IF pc = 0 THEN  
			(* assume call of procedure variable with value NIL *)
			S.GET( sp, pc );   (* get return address on top of stack *)
		END;  
		handler := Modules.GetExceptionHandler( pc );   
		IF handler # -1 THEN  (* Handler in the current PAF *)
			Unix.ModifyContext( cont, handler, fp, sp );
			handled := TRUE;  
		ELSE  
			WHILE Machine.LessOrEqual( fp, obj.stackBottom) & (handler = -1) DO  
				S.GET( fp + 4, pc );  
				pc := pc - 1;   (*  CALL instruction, machine dependant!!! *)
				handler := Modules.GetExceptionHandler( pc );  
				sp := fp;   (* Save the old framepointer into the stack pointer *)
				S.GET( fp, fp ) (* Unwind PAF *)
			END;  
			IF handler = -1 THEN  handled := FALSE   
			ELSE 
				Unix.ModifyContext( cont, handler, fp, sp );
				handled := TRUE  
			END  
		END;  
	END HandleException;  
	
	
	PROCEDURE SignalHandler( signal: LONGINT;  scp, ucp, dummy: ADDRESS );   
		(* 'dummy' for 16 byte stack alignment, MacOS! *)
	CONST SIGALRM = 14;  
	VAR ures: LONGINT;
	BEGIN 
		IF trace THEN  
			Trace.String( "Traps.SignalHander: received signal " );  
			Trace.Int( signal, 1 );  Trace.Ln  
		END;  
		IF signal IN  {1, 2, 15} (* SIGHUP, SIGINT, SIGTERM *) THEN  RETURN   END;  
		IF Heaps.collecting THEN  
			IF signal = SIGALRM THEN  
				(* delay delivery *)  ures := Unix.alarm( 1 );  RETURN  
			ELSE  
				Trace.Ln;  Trace.String( "PANIC: Trap " );  Trace.Int( signal, 0 );  
				Trace.String( " in garbage collector" );  Trace.Ln;  
				Machine.Release( Machine.Heaps );
				Machine.Release( Machine.X11 );
				Trap( signal, S.VAL( Unix.Ucontext, ucp ) )  
			END;  
		ELSE  
			Trap( signal, S.VAL( Unix.Ucontext, ucp ) )  
		END  
	END SignalHandler;  
	


BEGIN 
	trace := 3 IN Glue.debug; 
	Unix.Dlsym( 0, "InstallTrap", S.VAL( ADDRESS, InstallSignalHandler ) );
	InstallSignalHandler( SignalHandler );
	unix := StdIO.env
END Traps.
