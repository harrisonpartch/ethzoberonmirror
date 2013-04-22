
MODULE Clipboard;	(** AUTHOR "G.F."; PUROSE "X11 clipboard interface";  *)

IMPORT	SYSTEM, Unix, Machine, X11, X11Api, Displays, XDisplay, Plugins, Log := KernelLog, 
		Modules, Texts, TextUtilities, Strings, HostClipboard, Objects;

CONST  
	BufferSize = 2000H;
	
TYPE
	Buffer = POINTER TO ARRAY BufferSize OF CHAR;
	
	Grabber = OBJECT
	CONST 
		HSize = 256;
	VAR 
		terminate: BOOLEAN;
		lastSelectionHead: ARRAY HSize OF CHAR;
		
	
		PROCEDURE &Init;
		BEGIN 
			terminate := FALSE; 
			lastSelectionHead := "";
		END Init;
		
		PROCEDURE SelectionIsNew(): BOOLEAN;
		VAR i: LONGINT;  rc, lc: CHAR;
		BEGIN 
			rc := recBuffer[0];  lc := lastSelectionHead[0];  i := 0;
			WHILE (rc = lc) & (rc # 0X) & (lc # 0X) & (i < HSize-1) DO 
				INC( i );   rc := recBuffer[i];  lc := lastSelectionHead[i];
			END;
			RETURN rc # lc
		END SelectionIsNew;
		
		PROCEDURE SaveSelection;
		VAR i: LONGINT;  c: CHAR;
		BEGIN
			i := 0; 
			REPEAT  c := recBuffer[i];  lastSelectionHead[i] := c;  INC( i )
			UNTIL (c = 0X) OR (i >= HSize) 
		END SaveSelection;
			
	BEGIN{ACTIVE}
		LOOP
			GetX11Selection;
			IF SelectionIsNew() THEN
				SaveSelection;
				UnixToA2;  
				
				Texts.clipboard.AcquireWrite;	
				Texts.clipboard.Delete( 0, Texts.clipboard.GetLength() );
				TextUtilities.StrToText( Texts.clipboard, 0, recBuffer2^ );
				Texts.clipboard.ReleaseWrite;
			END;
			IF terminate THEN  Objects.Terminate  END;
			Objects.Sleep( 350 )
		END;
	END Grabber;


VAR
	sendBuffer, recBuffer, recBuffer2: Buffer;
	rlen, slen, rlen2	: LONGINT;
	received	: BOOLEAN;
	
	grabber		: Grabber;
	
	myProperty	: X11.Atom;
	xdisp		: X11.DisplayPtr;
	primary		: X11.Window;
	

	
	PROCEDURE A2ToUnix;
	VAR i, j: LONGINT; c, c2: CHAR;
	BEGIN
		j := 0;  i := 0;
		WHILE i < slen  DO
			c := sendBuffer[i];  INC( i );
			IF ORD( c ) < 128 THEN sendBuffer[j] := c; INC( j )
			ELSE	(* utf-8 to unicode *)
				c2 := sendBuffer[i];  INC( i );
				sendBuffer[j] := CHR( ORD( c ) MOD 20H * 40H + ORD( c2 ) MOD 40H );  INC( j )
			END 
		END;
		slen := j
	END A2ToUnix;
	
	
	PROCEDURE UnixToA2;
	VAR i: LONGINT; c: CHAR;
	BEGIN
		i := 0;  rlen2 := 0;
		WHILE (i < rlen) & (rlen2 < BufferSize - 3) DO
			c := recBuffer[i];
			IF ORD(c) < 129 THEN  recBuffer2[rlen2] := c;  INC( rlen2 )
			ELSE	(* small unicode to utf-8 *)
				recBuffer2[rlen2] := CHR( 0C0H + ORD(c) DIV 40H );  INC( rlen2 );
				recBuffer2[rlen2] := CHR( 80H + ORD(c) MOD 40H );  INC( rlen2 )
			END;
			INC( i )
		END;
		recBuffer2[rlen2] := 0X;  INC( rlen2 )
	END UnixToA2;
	
	


	
	PROCEDURE ClearSelection;
	BEGIN 
	(*	Texts.ClearLastSelection	*)
	END ClearSelection;
	

	PROCEDURE ClipboardChanged( sender, data : ANY );
	BEGIN
		Texts.clipboard.AcquireRead;
		PutToClipboard( Texts.clipboard );
		Texts.clipboard.ReleaseRead;
	END ClipboardChanged;



	(** Copy text to X11 clipboard *)
	PROCEDURE PutToClipboard( text : Texts.Text );
	BEGIN
		ASSERT((text # NIL) & (text.HasReadLock()));	
		TextUtilities.TextToStr( text, sendBuffer^ );  slen := Strings.Length( sendBuffer^ );
		A2ToUnix;
		Machine.Acquire( Machine.X11 );
		X11.SetSelectionOwner( xdisp, X11.XAPRIMARY, primary, X11.lastEventTime );	
		Machine.Release( Machine.X11 );
	END PutToClipboard;

	PROCEDURE SendSelection( VAR event: X11Api.XSelectionRequestEvent );
	VAR ev: X11.SelectionEvent; 
	BEGIN
		ev.typ := X11.SelectionNotify;
		ev.requestor := event.requestor;
		ev.selection := event.selection;
		ev.target := event.target;
		ev.time := event.time;
		IF (event.selection = X11.XAPRIMARY) & (event.target = X11.XASTRING) THEN
			ev.property := event.property;
			Machine.Acquire( Machine.X11 );
			X11.ChangeProperty( xdisp, ev.requestor, ev.property, ev.target, 8, X11.PropModeReplace, ADDRESSOF(sendBuffer[0]), slen );
			Machine.Release( Machine.X11 );
		ELSE
			ev.property := X11.None
		END;
		Machine.Acquire( Machine.X11 );
		X11.SendEvent( xdisp, ev.requestor, X11.False, 0, ADDRESSOF(ev) );
		Machine.Release( Machine.X11 );
	END SendSelection;



	(** Copy text of X11 clipboard to text *)
	PROCEDURE GetFromClipboard( text : Texts.Text );
	BEGIN
		ASSERT((text # NIL) & (text.HasWriteLock()));
		GetX11Selection;
		UnixToA2;
		TextUtilities.StrToText( text, 0, recBuffer2^ );
	END GetFromClipboard;
	
	
	PROCEDURE GetX11Selection;
	BEGIN{EXCLUSIVE}
		received := FALSE;
		Machine.Acquire( Machine.X11 );
		X11.ConvertSelection( xdisp, X11.XAPRIMARY, X11.XASTRING, myProperty, primary, X11.lastEventTime );
		Machine.Release( Machine.X11 );
		AWAIT( received );
	END GetX11Selection;

	PROCEDURE ReceiveSelection( VAR event: X11Api.XSelectionEvent );
	VAR type: X11.Atom;  format, len, after: LONGINT;  prop, adr: ADDRESS; ch: CHAR; 
	BEGIN {EXCLUSIVE}
		rlen := 0; recBuffer[0] := 0X;
		IF (event.selection = X11.XAPRIMARY) & (event.property = myProperty) THEN
			Machine.Acquire( Machine.X11 );
			X11.GetWindowProperty( xdisp, event.requestor, event.property, 0, BufferSize, X11.False, event.target, type, format, len, after, prop );
			Machine.Release( Machine.X11 );
			adr := prop;
			IF len >= BufferSize THEN len := BufferSize - 2  END;
			WHILE len > 0 DO
				SYSTEM.GET( adr, ch ); INC( adr ); DEC( len );
				IF ch # 0X THEN  recBuffer[rlen] := ch;  INC( rlen )  END	
			END;
			recBuffer[rlen] := 0X;  INC( rlen );
			Machine.Acquire( Machine.X11 );
			X11.Free( prop );  X11.DeleteProperty( xdisp, event.requestor, event.property );
			Machine.Release( Machine.X11 );
		END;
		received := TRUE;
	END ReceiveSelection;



	PROCEDURE GetXDisplay;
	VAR p: Plugins.Plugin;  disp: XDisplay.Display;
	BEGIN
		p := Displays.registry.Await("XDisplay");
		disp := p(XDisplay.Display);
		xdisp := disp.xdisp;  
		primary := disp.primary;  
	END GetXDisplay;

	(* set Selection handlers to NIL *)
	PROCEDURE Cleanup;
	BEGIN
		grabber.terminate := TRUE;
		Objects.Sleep( 1000 );
		
		X11Api.SendSelection := NIL;
		X11Api.ReceiveSelection := NIL;
		X11Api.ClearSelection := NIL;
		
		Texts.clipboard.onTextChanged.Remove( ClipboardChanged );
		HostClipboard.SetHandlers( NIL, NIL );
		
		Log.Enter; Log.String( "X11Clipboard: Unregistered clipboard at host clipboard interface." );  Log.Exit;
	END Cleanup;


	PROCEDURE Install*;
	BEGIN
		IF Unix.Version = "Darwin" THEN
			Log.String( "X11Clipboard: can't register clipboard in the Darwin port (ABI incompatiblity)" ); Log.Ln
		ELSE
			GetXDisplay;  
			X11Api.SendSelection := SendSelection;
			X11Api.ReceiveSelection := ReceiveSelection;
			X11Api.ClearSelection := ClearSelection;
			
			Machine.Acquire( Machine.X11 );
			myProperty := X11.InternAtom( xdisp, ADDRESSOF("UnixAosProperty"), X11.False );
			Machine.Release( Machine.X11 );
			
			NEW( sendBuffer );  NEW( recBuffer );  slen := 0;  rlen := 0;
			NEW( recBuffer2 );  rlen2 := 0;
			
			(* register with AosText clipboard *)
			Texts.clipboard.onTextChanged.Add( ClipboardChanged );
			HostClipboard.SetHandlers( GetFromClipboard, PutToClipboard );
			
			NEW( grabber );
			
			Modules.InstallTermHandler( Cleanup );
			Log.Enter; Log.String("X11Clipboard: Registered clipboard at host clipboard interface."); Log.Exit;
		END
	END Install;


BEGIN
END Clipboard.



Clipboard.Install ~


SystemTools.Free Clipboard ~
	
