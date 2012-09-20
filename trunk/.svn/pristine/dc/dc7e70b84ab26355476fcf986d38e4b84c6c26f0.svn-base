(* ETH Oberon, Copyright 2000 ETH Zuerich Institut fuer Computersysteme, ETH Zentrum, CH-8092 Zuerich.
Refer to the "General ETH Oberon System Source License" contract available at: http://www.oberon.ethz.ch/ *)

MODULE Glue;   (* g.f.  25.2.98 *)	(** non portable *)

(** Interface to the dynamic linker of Unix *)


IMPORT S := SYSTEM, Trace;

TYPE
	Address = S.ADDRESS;
	
	PtrElemDesc* = RECORD  a: ANY  END;	(* used by BootLinker only *)
		(* has same type descriptor as element of ARRAY OF POINTER TO ... *)

CONST
	AdrSize = S.SIZEOF( S.ADDRESS );


VAR
	(* the first variable ("AA...") gets initialized by the bootfile loader *)
	AAgetadr	: Address;	(* address of procedure dlsym *)

	dlsym-		: PROCEDURE {C} ( handle: Address;  name: Address; adr: Address );
	dlopen-	: PROCEDURE {C} ( pathname: Address;  mode: LONGINT ): Address;
	dlclose-	: PROCEDURE {C} ( handle: Address );
	cout		: PROCEDURE {C} ( c: CHAR );	(* output to Unix stdout *)

	debug-		: SET;	(* value of environment variable  OBERON_DEBUG  *)


	stackBottom-	: Address;	(* of main thread *)


	PROCEDURE Char ( c: CHAR );
	BEGIN
		cout( c )
	END Char;



	PROCEDURE Init;
	VAR i: LONGINT;
	BEGIN
		S.MOVE( S.ADR( AAgetadr ), S.ADR( dlsym ), AdrSize );
		dlsym( 0, S.ADR( "dlopen" ), S.ADR( dlopen ) );
		dlsym( 0, S.ADR( "dlclose" ), S.ADR( dlclose ) );
		
		dlsym( 0, S.ADR( "debug" ), S.ADR( debug ) );
		dlsym( 0, S.ADR( "cout" ), S.ADR( cout ) );
		
		stackBottom := S.ADR( i ) + 2*AdrSize;
		
		Trace.Char := Char;
	END Init;

BEGIN
	Init;
END Glue.
