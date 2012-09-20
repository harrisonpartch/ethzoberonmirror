MODULE FoxTest;	(** AUTHOR "fof"; PURPOSE "Fox tester"; *)
(* (c) fof ETH Zürich, 2008 *)

IMPORT Basic := FoxBasic, TestSuite, Diagnostics, Streams, Commands, Shell, Options, Files, Strings, Versioning;

TYPE
	Command = ARRAY 256 OF CHAR;

	Tester = OBJECT (TestSuite.Tester)
	VAR
		log: Streams.Writer;
		fileLog: Streams.Writer;

		mayTrap: BOOLEAN;
		command, prolog, epilog: Command;
		fileName: Files.FileName;

		PROCEDURE &InitTester (log, logFileWriter: Streams.Writer;  diagnostics: Diagnostics.Diagnostics; mayTrap: BOOLEAN; CONST prolog, command, epilog: Command; CONST fileName: ARRAY OF CHAR);
		BEGIN
			Init (diagnostics); SELF.log := log; SELF.mayTrap := mayTrap; SELF.fileLog := logFileWriter;
			COPY(prolog, SELF.prolog);
			COPY(epilog, SELF.epilog);
			COPY(command, SELF.command);
			COPY(fileName, SELF.fileName);
		END InitTester;

		PROCEDURE Handle (r: Streams.Reader; position: LONGINT; CONST name: ARRAY OF CHAR; type: TestSuite.TestType): INTEGER;
		VAR result: INTEGER; msg: ARRAY 128 OF CHAR; res: LONGINT; f: Files.File; w: Files.Writer; ch: CHAR;
		BEGIN
			result := TestSuite.Failure;
			IF log # NIL THEN log.String ("testing: "); log.String (name); log.Ln END;

			(* prepare tester input as a file for all test cases *)
			f := Files.New(fileName);
			NEW(w,f,0);
			WHILE r.Available() > 0 DO
				r.Char(ch); w.Char(ch)
			END;
			w.Update;
			Files.Register(f);

			res := Commands.Ok;
			IF prolog # "" THEN
				Commands.Call(prolog, {Commands.Wait}, res, msg);
				IF (res # Commands.Ok) & (log # NIL)  THEN
					log.String("prolog failed: "); log.String(msg); log.Ln;
				END;
			END;

			IF (command # "") & (res = Commands.Ok) THEN
				Commands.Call(command, {Commands.Wait}, res, msg);
				IF res = Commands.Ok THEN
					result := TestSuite.Positive
				ELSIF (res < 3500) & (res >= 3440) THEN (* loader error *)
					result := TestSuite.Failure
				ELSIF ~mayTrap & (res = Commands.CommandTrapped) THEN (* command error, trap *)
					result := TestSuite.Failure
				ELSE
					result := TestSuite.Negative
				END;
				IF (result # type) & (log # NIL) THEN
					log.String (msg); log.Ln;
				END;
			ELSIF (command # "") THEN result := TestSuite.Failure
			END;

			IF epilog # "" THEN
				Commands.Call(epilog, {Commands.Wait}, res, msg);
			END;

			IF fileLog # NIL THEN
				IF result = type THEN
					fileLog.String("success: ")
				ELSE
					fileLog.String("failure: ")
				END;
				fileLog.String(name); fileLog.Ln;
			END;
		FINALLY
			RETURN result;
		END Handle;

	END Tester;

	PROCEDURE DriveTest (context: Commands.Context);
	VAR
		diagnostics: Diagnostics.StreamDiagnostics; tester: Tester; writer: Streams.Writer; prolog, epilog, command: Command;
		options: Options.Options; verbose, mayTrap: BOOLEAN; report: TestSuite.StreamReport; fileName, logFileName: Files.FileName; logFileWriter, log:Streams.Writer;
		testname, resultname: Files.FileName; test, result, logFile: Files.File; reader: Files.Reader; s: ARRAY 64 OF CHAR;
	BEGIN
		IF (context.caller # NIL) & (context.caller IS Shell.Shell) THEN
			writer := context.out
		ELSE
			writer := Basic.GetDebugWriter("Oberon Compiler Test Results")
		END;
		NEW(options);

		options.Add("p","prolog", Options.String);
		options.Add("e","epilog", Options.String);
		options.Add("c","command", Options.String);
		options.Add("v","verbose",Options.Flag);
		options.Add("t","mayTrap",Options.Flag);
		options.Add("f","fileName",Options.String);
		options.Add("l","logFile",Options.String);

		NEW (diagnostics, writer);
		IF options.Parse(context.arg,context.error) THEN
			IF ~options.GetString("p", prolog) THEN prolog := "" END;
			IF ~options.GetString("c",  command) THEN command := "" END;
			IF ~options.GetString("e", epilog) THEN epilog := "" END;
			IF ~options.GetString("f", fileName) THEN fileName := "TesterInput.txt" END;
			mayTrap := options.GetFlag("t");
			verbose := options.GetFlag("verbose");

			IF context.arg.GetString (testname) THEN
				test := Files.Old (testname);
				IF test = NIL THEN
					context.error.String ("Failed to open test file "); context.error.String (testname); context.error.Ln;
					RETURN;
				END;
			ELSE
				context.result := Commands.CommandParseError;
			END;

			IF options.GetString("l",logFileName) THEN
				logFileWriter := Versioning.NewLogWriter(logFileName, "Test",testname);
				logFileWriter.Ln;
				logFileWriter.String("prolog= "); logFileWriter.String(prolog); logFileWriter.Ln;
				logFileWriter.String("command= "); logFileWriter.String(command); logFileWriter.Ln;
				logFileWriter.Ln;
			END;
			IF verbose THEN log := writer ELSE log := NIL END;
			NEW (tester, log, logFileWriter, diagnostics, mayTrap, prolog, command, epilog, fileName);

			NEW (report, writer);
			NEW (reader, test, 0);
			IF ~context.arg.GetString (resultname) THEN
				resultname := "";
			END;
			TestSuite.DriveByReader(reader, context.error, resultname, tester);
			tester.Print (report);
			IF logFileWriter # NIL THEN
				logFileWriter.Update;
				context.out.String("testing logged in "); context.out.String(logFileName); context.out.Ln;
			END;
		END;
		writer.Update;
	END DriveTest;

	PROCEDURE Compile* (context: Commands.Context);
	BEGIN DriveTest (context);
	END Compile;

END FoxTest.

SystemTools.Free FoxTest TestSuite Versioning ~

	FoxTest.Compile
		--verbose --mayTrap
		--prolog="Compiler.Compile TesterInput.txt"
		--command="SystemTools.Free Test Dummy B A;SystemTools.Load Test"
		--logFile="FoxExecutionTest.Log"
	Oberon.Execution.Test Oberon.Execution.AMD64TestDiff ~

	FoxTest.Compile
		--verbose
		--command="Compiler.Compile TesterInput.txt"
	Oberon.Compilation.Test Oberon.Compilation.AMD64TestDiff ~



	Test.log