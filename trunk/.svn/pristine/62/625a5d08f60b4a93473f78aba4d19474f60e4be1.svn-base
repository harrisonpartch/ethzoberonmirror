MODULE PrettyPrint; (* g.f. *)

(* prepare program sources for pretty printing on a color printer *)

IMPORT Commands, Files, Strings, Streams;

CONST PPDir = "PPr";

	PROCEDURE CheckSubDirectory( CONST dname: ARRAY OF CHAR ): BOOLEAN;
	VAR en: Files.Enumerator;
		fname, cname: ARRAY 64 OF CHAR; time, date, size: LONGINT; flags: SET;
	BEGIN
		cname := "./";  Strings.Append( cname, dname );
		NEW( en );
		en.Open( "./*", {} );
		WHILE en.GetEntry( fname, flags, time, date, size ) DO
			IF fname = cname THEN  RETURN TRUE  END
		END;
		RETURN FALSE
	END CheckSubDirectory;


	(*  create syntax highlighted Oberon texts of the program sources in subdir PPr *)
	PROCEDURE Do*( context: Commands.Context );	(*  {filename} ~ *)
	VAR 
		fileName: ARRAY 64 OF CHAR;  res: LONGINT;
		src, dest, cmd, msg: ARRAY 128 OF CHAR;
		overwrite: BOOLEAN; f: Files.File;
		out, err: Streams.Writer;
	BEGIN
		out := context.out;  err := context.error;
		out.String( "PrettyPrint.Do" ); out.Ln;
		IF ~CheckSubDirectory( PPDir ) THEN  Files.CreateDirectory( PPDir, res )  END;
		WHILE context.arg.GetString( fileName ) DO
			out.String( "    " );  out.String( fileName );  out.Update;
			f := Files.Old( fileName );
			IF f = NIL THEN
				err.String( " : file not found" ); err.Ln;  err.Update;  
			ELSE
				f.GetName( src );
				dest := PPDir; Strings.Append( dest, "/" ); Strings.Append( dest, fileName );
				overwrite := TRUE;
				Files.CopyFile( src, dest, overwrite, res );

				cmd := "SEQ TextConverter.Oberon ";  Strings.Append( cmd, dest );
				Strings.Append( cmd, ";SyntaxHighlighter.Highlight " );
				Strings.Append( cmd, dest );  Strings.Append( cmd, " Oberon" );
				Commands.Call( cmd, {}, res, msg );
				IF res # 0 THEN
					err.String( msg );  err.Ln;  err.Update;
				ELSE
					out.String( " => " ); out.String( PPDir ); out.Char( '/' ); out.String( fileName ); 
					out.Ln;  out.Update
				END
			END
		END
	END Do;

END PrettyPrint.

	(*

	PrettyPrint.Do  TestProgram.Mod  PrettyPrint.Mod Unix.Objects.Mod ~

	The real printing can be done in the Oberon subsystem:
		
		Desktops.PrintDoc  <printer name>	PPr/PrettyPrint.Mod ~
	
	*)
