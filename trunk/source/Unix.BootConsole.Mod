MODULE BootConsole;	(** AUTHOR "G.F."; PURPOSE "Boot console"; *)

IMPORT S := SYSTEM, Trace, Glue, Unix, Heaps, Modules, Objects, Commands;

TYPE
	Module = Modules.Module;
	CommandProc = PROCEDURE;

	CommandThread = OBJECT
		BEGIN {ACTIVE}
			Execute( modName, cmdName );
			Modules.Shutdown( Modules.Reboot )
		END CommandThread;

VAR
	modName, cmdName: ARRAY 32 OF CHAR;
	appl: CommandThread;


	PROCEDURE LoadModule( CONST name: ARRAY OF CHAR );
	VAR
		m: Module;  res: LONGINT;  msg: ARRAY 256 OF CHAR;
	BEGIN
		m := Modules.ThisModule( name, res, msg );
		IF m = NIL THEN
			Trace.String( "could not load module " );  Trace.String( name );  Trace.Ln
		END
	END LoadModule;



	PROCEDURE Command( CONST cmd: ARRAY OF CHAR );
	VAR
		res: LONGINT;
		s: ARRAY 256 OF CHAR;
	BEGIN
		Commands.Call( cmd, {}, res, s );
		IF res # 0 THEN  Trace.String( s ); Trace.Ln  END
	END Command;


	(** Return the named command. *)
	PROCEDURE ThisCommand( m: Module;  CONST name: ARRAY OF CHAR ): CommandProc;
	VAR cmd: Modules.Command; i: LONGINT;  found: BOOLEAN;
	BEGIN		
		i := 0;  found := FALSE;
		WHILE ~found & (i # LEN( m.command^ )) DO
			IF m.command[i].name = name THEN  found := TRUE;  cmd := m.command[i]  ELSE  INC( i )  END
		END;
		IF (cmd.entryAdr # 0) & (cmd.argTdAdr = 0) & (cmd.retTdAdr = 0) THEN
			RETURN S.VAL( CommandProc, cmd.entryAdr )
		ELSE  
			RETURN NIL
		END
	END ThisCommand;

	PROCEDURE Execute( CONST modName, procName: ARRAY OF CHAR );
	VAR m: Module;  cmd: CommandProc;  res: LONGINT;
		msg: ARRAY 256 OF CHAR;
	BEGIN
		m := Modules.ThisModule( modName, res, msg );
		IF m # NIL THEN
			cmd := ThisCommand( m, procName );
			IF cmd # NIL THEN  cmd
			ELSE
				Trace.String( "BootConsole.Execute:  module '" );  Trace.String( modName );
				Trace.String( "' has no command '" );  Trace.String( procName );  Trace.Char( "'" );
				Trace.Ln;
			END
		ELSE  
			Trace.String( "BootConsole.Execute:  could not load module " );  Trace.String( modName );  
			Trace.Ln;
			Trace.String( msg );  Trace.Ln
		END
	END Execute;


	PROCEDURE CommandError( CONST cmd, msg: ARRAY OF CHAR );
	BEGIN
		Trace.String( "bad command line parameter: -x " );  Trace.String( cmd );  Trace.Ln;
		IF msg # "" THEN  Trace.String( msg );  Trace.Ln  END;
		Unix.exit( 1 )
	END CommandError;
	
	PROCEDURE GetCmd( ): BOOLEAN;
	VAR cmd: ARRAY 65 OF CHAR; (* plus dot if available *)
		i, j, k: INTEGER;  c: CHAR;
	BEGIN
		Unix.GetArgval( "-x", cmd );
		IF cmd = "" THEN  RETURN FALSE	
		ELSE
      			i := 0;
         
			c := cmd[0];
			IF ~((('a' <= c) & (c <= 'z')) OR (( 'A' <= c) & (c <= 'Z'))) THEN
				CommandError( cmd, "first character is not a character in module name" ); 
			END;
			modName[0] := c;
			INC( i );
         
			REPEAT  c := cmd[i];  modName[i] := c;  INC( i );
				IF i > 31 THEN
					CommandError( cmd, "# of characters is > 31 in module name" )
				END;
			UNTIL ~( ("a" <= c) & (c <= "z") OR ("A" <= c) & (c <= "Z") OR ("0" <= c) & (c <= "9"));
			IF (c = '.') & (i > 1) THEN
				modName[i - 1] := 0X;  j := i;  k := 0;

				c := cmd[j];
				IF ~((('a' <= c) & (c <= 'z')) OR (( 'A' <= c) & (c <= 'Z'))) THEN
					CommandError( cmd, "first character is not a character in command name" )
				END;
				cmdName[k] := c;
				INC( j ); INC( k );
            
				REPEAT  c := cmd[j];  cmdName[k] := c;  INC( j );  INC( k );
					IF k > 31 THEN
						CommandError( cmd, "# of characters is > 31 in command name" )
					END;
				UNTIL ~(("a" <= c) & (c <= "z") OR ("A" <= c) & (c <= "Z") OR ("0" <= c) & (c <= "9"));
				cmdName[k - 1] := 0X;
				IF k < 2 THEN  CommandError( cmd, "invalid command name" )  END
			ELSE
				CommandError( cmd, "invalid module name" ); 
			END;
			RETURN TRUE
		END
	END GetCmd;
	
	PROCEDURE InitPrelinkedModules;
	TYPE Body = PROCEDURE;
	VAR m: Modules.Module;  body: Body;  trace, heapsOk: BOOLEAN;
	BEGIN
		m := Modules.root;  trace := FALSE;  heapsOk := FALSE;
		LOOP
			IF m.name = "BootConsole" THEN  EXIT   END;   (* initialize modules belonging to bootfile only *)
			IF trace THEN
				Trace.String( "Initializing " );  Trace.StringLn( m.name )
			END;
			IF heapsOk THEN  Heaps.InitProtHeader( S.VAL( S.ADDRESS, m ) )  END;
			body := S.VAL( Body, S.ADR( m.code[0] ) );
			body;	
			IF m.name = "Glue" THEN  trace := Glue.debug # {}  END;
			IF m.name = "Heaps" THEN  heapsOk := TRUE  END;
			m := m.next
		END
	END InitPrelinkedModules;


	PROCEDURE StartSystem;
	BEGIN
		IF GetCmd()  THEN
			(* start the procedure specified in the command line (aos  -x M.P) *)
			IF Glue.debug # {} THEN
				Trace.String( "Starting " );
				Trace.String( modName );  Trace.Char( "." );  Trace.String( cmdName );
				Trace.Ln
			END;
			NEW( appl )
		ELSE
			(* normal system start *)
			LoadModule( "Clock" );
			Execute( "XDisplay",  "Install" );
			Execute( "KbdMouse",  "Init" );


			Command( "WindowManager.Install" );
			Command( "DisplayRefresher.Install" );

			Command( "Autostart.Run" );
		END
	END StartSystem;



BEGIN
	InitPrelinkedModules;
	StartSystem;
	
	Objects.SetPriority( Objects.GCPriority );
	Objects.GCLoop;
END BootConsole.


