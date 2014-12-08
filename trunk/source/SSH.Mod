(* ETH Oberon, Copyright 2001 ETH Zuerich Institut fuer Computersysteme, ETH Zentrum, CH-8092 Zuerich.
Refer to the "General ETH Oberon System Source License" contract available at: http://www.oberon.ethz.ch/ *)

MODULE SSH;   (* g.f.	26.07.2002 *)

IMPORT Kernel, Streams, Files, Strings, Out := KernelLog, Commands, IP, TCP,
	T := SSHTransport, A := SSHAuthorize, U := CryptoUtils;

CONST
	GlobalRequest = 50X;  RequestSuccess = 51X;  RequestFailure = 52X;  ChannelOpen = 5AX;  OpenConfirm = 5BX;
	OpenFailure = 5CX;  WindAdjust = 5DX;  Data = 5EX;  ExtData = 5FX;  ChannelEOF = 60X;  ChannelClose = 61X;
	ChannelRequest = 62X;  ChannelSuccess = 63X;  ChannelFailure = 64X;

	WinSize = 8*1024;
	MaxPacketSize = 2048;   (* max packet size *)

	CR = 0DX;  NL = 0AX;

	ChanClosed* = T.Closed;  ChanOpen* = T.Connected;   (* channel states *)

	trace = FALSE;


	(*---------------------- TCP/IP port forwarding ----------------------------*)

TYPE
	ClientHandler = OBJECT 
			VAR
				f: Forwarder; (* this client belogs to *)
				p: T.Packet;
				buf: ARRAY 64 OF CHAR;
				len, res: LONGINT;
				
			
			
			PROCEDURE & Init( forw: Forwarder );
			BEGIN
				f := forw
			END Init;
			
		BEGIN {ACTIVE}
			f.clientHandlerRunning := TRUE;
			LOOP
				len := 16;
				f.clientConn.Receive( buf, 0, len, 1, len, res );
				IF len > 0 THEN
					p := f.chan.NewPacket( len + 32 );
					p.AppArray( buf, 0, len );
					f.chan.SendPacket( p )
				ELSE
					Out.String( "client at port " ); Out.Int( f.localPort, 0 );
					Out.String( " closed connection" ); Out.Ln;
					f.clientConn.Close;  f.clientConn := NIL;
					EXIT
				END
			END;
			f.clientHandlerRunning := FALSE;
		END ClientHandler;
	
	Forwarder = OBJECT
			VAR
				next: Forwarder;

				active: BOOLEAN;
				timer: Kernel.Timer;

				localPort: LONGINT;
				localConn: TCP.Connection;
				clientConn: TCP.Connection;	(* connection to client at localport *)

				destPort: LONGINT;
				remConn: T.Connection;  (* encrypted connection to remote host *)
				chan: Channel;  	(* encrypted channel to destport at remote host *)

				buf: ARRAY 4096 OF CHAR;
				type: CHAR;
				len, res: LONGINT;
				
				clientHandlerRunning: BOOLEAN;
				clientHandler: ClientHandler;


				PROCEDURE OpenTunnel( ): BOOLEAN;
				CONST DestHost = "localhost";
				VAR
					buf: ARRAY 3000 OF CHAR;
					len: LONGINT;  p: T.Packet;
					clientAddress: ARRAY 64 OF CHAR;
					clientPort: LONGINT;
					chanNo: LONGINT;
				BEGIN
					NEW( chan, remConn );
					
					IP.AdrToStr( clientConn.fip, clientAddress );
					clientPort := clientConn.fport;
					chanNo := remConn.GetChannelNo();

					NEW( p, ChannelOpen, 512 );
						p.AppString( "direct-tcpip" );
						p.AppInteger( chanNo );
						p.AppInteger( WinSize );
						p.AppInteger( MaxPacketSize );
						p.AppString( DestHost );
						p.AppInteger( destPort );
						p.AppString( clientAddress );
						p.AppInteger( clientPort );

					remConn.SendPacket( p );
					IF remConn.ReceivePacket( buf, len ) # OpenConfirm THEN
						ErrorResponse( "SSH.OpenTunnel", buf );
						RETURN FALSE
					END;
					chan.rchan := U.GetInt( buf, 5 );
					chan.wsize := U.GetInt( buf, 9 );
					chan.pmax := U.GetInt( buf, 13 );
					
					chan.state := ChanOpen;
					RETURN TRUE
				END OpenTunnel;


				PROCEDURE Stop;
				BEGIN
					active := FALSE;  clientHandlerRunning := FALSE
				END Stop;

				PROCEDURE CloseAllConnections;
				BEGIN
					IF chan # NIL THEN  chan.Close;  chan := NIL  END;  
					remConn.Disconnect( 11, "god bye" );  remConn := NIL;
					IF clientConn # NIL THEN  clientConn.Close;  clientConn := NIL  END;  
					localConn.Close;  localConn := NIL
				END CloseAllConnections;
				
				
				PROCEDURE & Init*( lConn: TCP.Connection; lPort: LONGINT; rConn: T.Connection; dPort: LONGINT );
				BEGIN
					localConn := lConn;
					localPort := lPort;
					remConn := rConn;
					destPort := dPort;

					NEW( timer );  active := TRUE;
				END Init;
				

			BEGIN {ACTIVE}
				Out.String( "Start forwarding port " ); Out.Int( localPort, 0 );  Out.Ln;
				REPEAT
					localConn.Accept( clientConn, res );
					IF res # TCP.Ok THEN
						Out.String( "accept request failed" ); Out.Ln;
						CloseAllConnections;
						RETURN
					END;
					Out.String( "client request accepted" ); Out.Ln;
					IF ~OpenTunnel(  ) THEN
						Out.String( "open tunnel failed" ); Out.Ln;
						CloseAllConnections;
						RETURN
					END;
					NEW( clientHandler, SELF );
					WHILE ~clientHandlerRunning DO  timer.Sleep( 10 )  END;
					LOOP
						IF clientHandlerRunning & remConn.PacketAvailable() THEN	
							type := chan.ReceivePacket( buf, len );
							IF type = Data THEN
								len := U.GetInt( buf, 5 );
								clientConn.Send( buf, 9, len, TRUE, res )
							ELSIF type = 0X THEN  
								Stop  
							END
						ELSE
							IF ~active THEN
								CloseAllConnections;  EXIT
							ELSE
								IF ~clientHandlerRunning THEN  EXIT  END;
								timer.Sleep( 50 )
							END
						END	
					END; (* loop *)
				UNTIL ~active;
				Out.String( "Terminate forwarding port " ); Out.Int( localPort, 0 );  Out.Ln;
			END Forwarder;

VAR
	forwarderList: Forwarder;   (* installed forwarders *)

	hexd: ARRAY 17 OF CHAR;

	(*-----------------------------------------------------------------------*)

TYPE
	Channel* = OBJECT (Streams.Connection)
			VAR
				state-: SHORTINT;
				conn-: T.Connection;
				rchan: LONGINT;
				wsize-: LONGINT;
				clchan: LONGINT;
				clwsize: LONGINT;
				pmax: LONGINT;   (* max packet size accepted by remote *)
				noneblocking: BOOLEAN;
				recBuffer: POINTER TO ARRAY OF CHAR;
				rbstart, rbend: LONGINT;

				PROCEDURE Send*( CONST data: ARRAY OF CHAR;  ofs, len: LONGINT;  propagate: BOOLEAN;  VAR res: LONGINT );
				VAR p: T.Packet; l: LONGINT; t: CHAR;
					buf: ARRAY 512 OF CHAR;
				BEGIN
					NEW( p, Data, len + 32 );
					p.AppInteger( rchan );
					p.AppArray( data, ofs, len );
					WHILE wsize < len DO
						(* wait for server window space *)
						t := ReceivePacket( buf, l );
						IF t = Data THEN  (* must buffer it ? *)
							Error( "got data while waiting for window space" ); RETURN
						ELSIF t = 0X THEN  Error( "unexpected end of data" ); RETURN
						END
					END;
					conn.SendPacket( p );  DEC( wsize, len );  res := Streams.Ok
				END Send;

				PROCEDURE PrintChar( c: CHAR );
				BEGIN
					IF (c >= ' ') & (c <= '~') THEN
						 Out.Char( ' ' );  Out.Char( c )
					ELSE
						Out.Char( hexd[ORD( c ) DIV 16] );
						Out.Char( hexd[ORD( c ) MOD 16] )
					END;
					IF c = 0AX THEN  Out.Ln  END
				END PrintChar;

				PROCEDURE Receive*( VAR data: ARRAY OF CHAR;  ofs, size, min: LONGINT;  VAR len, res: LONGINT );
				VAR
					plen, dlen: LONGINT; pType, ch: CHAR;
				BEGIN
					len := 0;
					LOOP
						WHILE (rbstart < rbend) & ( len < size ) DO
							ch := recBuffer[rbstart];  INC( rbstart );
							data[ofs] := ch;  INC( ofs );  INC( len )
						END;
						IF rbstart >= rbend THEN
							IF conn.PacketAvailable() THEN
								pType := ReceivePacket( recBuffer^, plen );
								IF pType = 0X THEN  res := Streams.EOF;  RETURN  END;
								IF pType = Data THEN
									dlen := U.GetInt( recBuffer^, 5 );
									rbstart := 9;  rbend := 9 + dlen;
								END
							END;
							WHILE (rbstart < rbend) & ( len < size ) DO
								ch := recBuffer[rbstart];  INC( rbstart );
								data[ofs] := ch;  INC( ofs );  INC( len )
							END;
						END;
						IF len >= min THEN  res := Streams.Ok;  RETURN  END;
					END
				END Receive;


				PROCEDURE NewPacket( size: LONGINT ): T.Packet;
				VAR p: T.Packet;
				BEGIN
					NEW( p, Data, size );  p.AppInteger( rchan );
					RETURN p
				END NewPacket;


				PROCEDURE SendPacket*( p: T.Packet );
				VAR buf: ARRAY 4096 OF CHAR;
					len, dsize: LONGINT;  t: CHAR;
				BEGIN
					IF state = ChanOpen THEN
						IF p.buf[0] = Data THEN  dsize := p.len - 9
						ELSIF p.buf[0] = ExtData THEN  dsize := p.len - 13
						ELSE  dsize := 0
						END;
						ASSERT( dsize <= pmax );
						WHILE wsize < dsize DO
							(* wait for server window space *)
							t := ReceivePacket( buf, len );
							IF t = Data THEN  (* must buffer it ? *)
								Error( "got data while waiting for window space" ); RETURN
							ELSIF t = 0X THEN  Error( "unexpected end of data" ); RETURN
							END
						END;
						conn.SendPacket( p );  DEC( wsize, dsize )
					END
				END SendPacket;

				PROCEDURE SendBuffer*( CONST buf: ARRAY OF CHAR;  len: LONGINT );
				VAR p: T.Packet;
				BEGIN
					p := NewPacket( len + 32 );
					p.AppArray( buf, 0, len );
					SendPacket( p );
				END SendBuffer;

				PROCEDURE SendChar*( ch: CHAR  );
				VAR p: T.Packet;
				BEGIN
					p := NewPacket( 128 );  p.AppInteger( 1 );  p.AppChar( ch );
					SendPacket( p );
				END SendChar;

				PROCEDURE ReceivePacket*( VAR buf: ARRAY OF CHAR;  VAR len: LONGINT ): CHAR;
				VAR i, l, add, chan: LONGINT;  pt: CHAR;
					p: T.Packet;  done: BOOLEAN;
				BEGIN
					IF state = ChanClosed THEN  RETURN 0X  END;
					done := FALSE;
					REPEAT
						pt := conn.ReceivePacket( buf, len );
						CASE pt OF
						| WindAdjust:
								add := U.GetInt( buf, 5 );
								INC( wsize, add );
						| RequestSuccess, RequestFailure, OpenConfirm, OpenFailure:
								done := TRUE
						| ChannelSuccess, ChannelFailure:
								 done := TRUE
						| ChannelEOF:
								 done := TRUE
						| ChannelClose:
								conn.Disconnect( 11, "" );
								state := ChanClosed;
								pt := 0X;
								done := TRUE
						| Data:
								l := U.GetInt( buf, 5 );
								DEC( clwsize, l );
								IF clwsize < 1000 THEN
									add := WinSize - clwsize;  INC( clwsize, add );
									NEW( p, WindAdjust, 128 );
									p.AppInteger( rchan );  p.AppInteger( add );
									conn.SendPacket( p );
								END;
								done := TRUE
						| ExtData:  (* stderr *)
								l := U.GetInt( buf, 9 );
								FOR i := 1 TO l  DO  Out.Char( buf[12 + i] )  END;
								Out.Ln
						| GlobalRequest:
								l := U.GetInt( buf, 1 );
								IF buf[5 + l] # 0X THEN
									(* this client does not accept any global request *)
									NEW( p, RequestFailure, 64 );
									conn.SendPacket( p )
								END
						| ChannelOpen:
								chan := U.GetInt( buf, 1 );
								NEW( p, OpenFailure, 128 );
								p.AppInteger( chan );
								p.AppInteger( 1 );   (* reason: prohibited *)
								p.AppString( "channel open rejected by client" );
								p.AppString( "" );   (* language tag *)
								conn.SendPacket( p )
						| ChannelRequest:
							(*	NEW( p, ChannelFailure, 64 );
								conn.SendPacket( p )	*)
						ELSE
							ErrorResponse( "SSH.Channel.read", buf );
							conn.Disconnect( 2, "protocol error" );
							state := ChanClosed;
							pt := 0X;
							done := TRUE
						END;
					UNTIL done;
					RETURN pt
				END ReceivePacket;


				PROCEDURE ReceiveLine*( VAR line: ARRAY OF CHAR;  VAR len: LONGINT );
				VAR bl, i, e: LONGINT;  t, c, c2: CHAR;
					buf: ARRAY 256 OF CHAR;
				BEGIN
					len := 0;
					REPEAT
						t := ReceivePacket( buf, bl );
						IF t = Data THEN
							e := 8 + U.GetInt( buf, 5 );  c := 0X;  i := 9;
							WHILE (i <= e) & (c # NL) DO  c := buf[i];  line[len] := c;  INC( i );  INC( len )  END;
						ELSIF t = ExtData THEN
							(* stderr *)
							e := 12 + U.GetInt( buf, 9 );  c2 := buf[13];  i := 14;
							WHILE i <= e DO
								IF c2 = NL THEN  Out.Ln  ELSE  Out.Char( c2 )  END;
								c2 := buf[i];  INC( i )
							END;
						END
					UNTIL (line[0] = 0X) OR (c = NL)
				END ReceiveLine;


				PROCEDURE AwaitResponse( ): BOOLEAN;
				VAR t: LONGINT;
				BEGIN
					t := Kernel.GetTicks();
					WHILE ~conn.PacketAvailable() DO
						IF Kernel.GetTicks() - t > 500  THEN  RETURN FALSE   END
					END;
					RETURN TRUE
				END AwaitResponse;

				PROCEDURE WindowChange*( width, height: LONGINT );
				VAR p: T.Packet;
				BEGIN
					NEW( p, ChannelRequest, 512 );
					p.AppInteger( rchan );
					p.AppString( "window-change" );
					p.AppChar( 0X );	(* false *)
					p.AppInteger( width );
					p.AppInteger( height );
					p.AppInteger( 0 );	(* width, pixel *)
					p.AppInteger( 0 );	(* height, pixel *)
					SendPacket( p );
				END WindowChange;

				PROCEDURE RemoteCommand*( CONST cmd: ARRAY OF CHAR );
				VAR p: T.Packet;
				BEGIN
					p := NewPacket( 512 );  p.AppString( cmd );  SendPacket( p );
					SendNL;
				END RemoteCommand;

				PROCEDURE Sync*;
				VAR p: T.Packet;
				BEGIN
					p := NewPacket( 128 );  p.AppInteger( 1 );  p.AppChar( 0X );  SendPacket( p );
				END Sync;

				PROCEDURE SendNL*;
				VAR p: T.Packet;
				BEGIN
					p := NewPacket( 128 );  p.AppInteger( 1 );  p.AppChar( NL );  SendPacket( p );
				END SendNL;

				PROCEDURE SendCR*;
				VAR p: T.Packet;
				BEGIN
					p := NewPacket( 128 );  p.AppInteger( 1 );  p.AppChar( CR );  SendPacket( p );
				END SendCR;

				PROCEDURE SendEOF*;
				VAR p: T.Packet;
				BEGIN
					NEW( p, ChannelEOF, 64 );  p.AppInteger( rchan );  SendPacket( p );
				END SendEOF;


				PROCEDURE Flush*;  (* consume any incoming packages until connection is quiet *)
				VAR buf: POINTER TO  ARRAY OF CHAR;
					len, e, i: LONGINT;  t: CHAR;
				BEGIN
					NEW( buf, MaxPacketSize );
					WHILE AwaitResponse( ) DO
						t := ReceivePacket( buf^, len );
						IF trace THEN
							PrintPackageType( buf^ );
							IF t = Data THEN
								Out.String( " '" );
								e := 8 + U.GetInt( buf^, 5 );  i := 9;
								WHILE i <= e DO  PrintChar( buf[i] );  INC( i )  END;
								Out.Char( "'" )
							END;
							Out.Ln
						END;
					END
				END Flush;


				PROCEDURE Close*;
				VAR p: T.Packet;
				BEGIN
					NEW( p, ChannelClose, 64 );  p.AppInteger( rchan );  SendPacket( p );
					clchan := 0;
					Flush;
					state := ChanClosed
				END Close;

				PROCEDURE & Init*( conn: T.Connection );
				BEGIN
					SELF.conn := conn;  state := ChanClosed;  noneblocking := FALSE;
					clchan := conn.GetChannelNo();
					clwsize := WinSize;
					NEW( recBuffer, MaxPacketSize + 32 ); rbstart := 0;  rbend := 0;
				END Init;

			END Channel;


	PROCEDURE OpenSession*( conn: T.Connection;  interactive: BOOLEAN ): Channel;
	VAR len: LONGINT;
		buf: ARRAY 3000 OF CHAR;
		p: T.Packet;  chan: Channel;
	BEGIN
		NEW( chan, conn );

		NEW( p, ChannelOpen, 512 );
		p.AppString( "session" );
		p.AppInteger( chan.clchan );
		p.AppInteger( WinSize );
		IF interactive THEN  p.AppInteger( 512 )  ELSE  p.AppInteger( MaxPacketSize )  END;

		conn.SendPacket( p );
		IF conn.ReceivePacket( buf, len ) # OpenConfirm THEN
			ErrorResponse( "SSH.OpenSession", buf );  RETURN NIL
		END;

		chan.rchan := U.GetInt( buf, 5 );
		chan.wsize := U.GetInt( buf, 9 );
		chan.pmax := U.GetInt( buf, 13 );

		chan.state := ChanOpen;
		chan.Flush;

		NEW( p, ChannelRequest, 512 );
		p.AppInteger( chan.rchan );
		p.AppString( "pty-req" );
		p.AppChar( 0X );   (* don't want reply *)
		p.AppString( "vt100" );
		p.AppInteger( 80 );  p.AppInteger( 24 );   (* chars *)
		p.AppInteger( 640 );  p.AppInteger( 480 );   (* pixels *)
		IF ~interactive THEN
			p.AppInteger( 26 );
			p.AppChar( CHR( 50 ) );  p.AppInteger( 0 );   (* -isig *)
			p.AppChar( CHR( 51 ) );  p.AppInteger( 0 );   (* -icanon*)
			p.AppChar( CHR( 52 ) );  p.AppInteger( 0 );   (* -xcase*)
			p.AppChar( CHR( 53 ) );  p.AppInteger( 0 );   (* -echo *)
			p.AppChar( CHR( 91 ) );  p.AppInteger( 1 );   (* 8 bit mode *)
		ELSE
			p.AppInteger( 1 )
		END;
		p.AppChar( 0X );   (* 0 = TTY OP END *)
		chan.SendPacket( p );

		NEW( p, ChannelRequest, 128 );
		p.AppInteger( chan.rchan );
		p.AppString( "shell" );
		p.AppChar( 1X );   (* want reply *)
		chan.SendPacket( p );

		IF chan.ReceivePacket( buf, len ) # ChannelSuccess THEN
			ErrorResponse( "SSH.OpenSession: shell request", buf );  RETURN NIL
		END;
		RETURN chan
	END OpenSession;

(*-------------------------- misc -------------------------------------*)

	PROCEDURE PrintPackageType( CONST p: ARRAY OF CHAR );
	VAR t: LONGINT;
	BEGIN
		t := ORD( p[0] );
		Out.Char( hexd[t DIV 16] );  Out.Char( hexd[t MOD 16] );
		Out.String( 'X(' );  Out.Int( t, 0 );  Out.String( '), channel ' );
		Out.Int( U.GetInt( p, 1 ), 0 );  Out.Char( ' ' )
	END PrintPackageType;

	PROCEDURE Error( CONST msg: ARRAY OF CHAR );
	BEGIN
		Out.Ln;
		Out.String( "### Error: " ); Out.String( msg );  Out.Ln
	END Error;

	PROCEDURE ErrorResponse( CONST msg, buf: ARRAY OF CHAR );
	VAR errmsg: ARRAY 1024 OF CHAR;
		p: LONGINT;
	BEGIN
		Out.String( msg );
		IF buf[0] = OpenFailure THEN
			Out.String( ": error code = " );  Out.Int( U.GetInt( buf, 5 ), 1 );
			p := 9;  U.GetString( buf, p, errmsg );
			Out.Char( ' ' );  Out.String( errmsg );
		ELSIF buf[0] = RequestFailure THEN
			Out.String( ": request failed " );
		ELSE
			Out.String( ": unexpected response packet type: " );  PrintPackageType( buf );  Out.Ln;
			ShowResp( buf );
		END;
		Out.Ln;
	END ErrorResponse;


	PROCEDURE ShowResp( CONST resp: ARRAY OF CHAR );
	VAR buf: ARRAY 1024 OF CHAR;
		i, j, v: INTEGER;  c: CHAR;  err: BOOLEAN;
	BEGIN
		i := 0;  j := 0; 
		err := ORD( resp[0] ) IN {1, 2};
		IF err THEN  i := 1  END;
		REPEAT
			c := resp[i];  INC( i );
			IF c >= ' ' THEN  buf[j] := c;  INC( j )
			ELSE
				v := ORD( c );  buf[j] := '\';  INC( j );
				buf[j] := CHR( v DIV 64 MOD 8 + 48 );  INC( j );
				buf[j] := CHR( v DIV 8 MOD 8 + 48 );  INC( j );
				buf[j] := CHR( v MOD 8 + 48 );  INC( j );
			END
		UNTIL (i > 256) OR (i >= LEN( resp ));
		FOR i := 0 TO j - 1 DO  
			IF i MOD 64 = 0 THEN  Out.Ln  END;
			Out.Char( buf[i] )
		END
	END ShowResp;


(*----------------------- remote copy -------------------------------*)



	PROCEDURE Connect( arg: Streams.Reader;  VAR remHost: ARRAY OF CHAR ): A.Connection;
	CONST usage = "usage:  SSH.(Send | Receive)  user@host ...";
	VAR
		str, user: ARRAY 128 OF CHAR;
		strings: Strings.StringArray;
		conn: A.Connection;
	BEGIN
		arg.SkipWhitespace; arg.String( str );  conn := NIL;
		strings := Strings.Split( str, '@' );
		IF LEN( strings^ ) = 2 THEN
			COPY( strings[0]^, user );
			COPY( strings[1]^, remHost );
			conn := A.OpenConnection( remHost, user );
			IF conn # NIL THEN
				Out.String( "SSH connection to '" );  Out.String( remHost );  Out.String( "' established" );  Out.Ln
			END
		ELSE  Out.String( usage );
		END;
		RETURN conn
	END Connect;


	(**  SSH.Send  user@host  {  <filename>[:<remote filename> ] }  ~ *)
	PROCEDURE Send*( context: Commands.Context );
	CONST
		usage = "usage:  SSH.Send  user@host  { <filename>[:<remote filename>] } ~";
	VAR
		f: Files.File;
		in: Streams.Reader;
		locFileName, remFileName, str, host, cmd: ARRAY 128 OF CHAR;
		strings: Strings.StringArray;
		chan: Channel;
		conn: A.Connection;
	BEGIN
		in := context.arg;
		conn := Connect( in, host );
		IF conn = NIL THEN  RETURN  END;
		WHILE in.GetString( str ) DO
			strings := Strings.Split( str, ':' );
			CASE LEN( strings^ ) OF
			| 1: COPY( strings[0]^, locFileName );
				remFileName := locFileName
			| 2: COPY( strings[0]^, locFileName );
				COPY( strings[1]^, remFileName )
			ELSE
				Out.String( usage );  Out.Ln;  RETURN
			END;
			Out.String( locFileName );  Out.String( "  -->  " );
			Out.String( host );  Out.Char( ':' );  Out.String( remFileName ); Out.String( "    " );
			f := Files.Old( locFileName );
			IF f # NIL THEN
				chan := OpenSession( conn, FALSE );
				chan.Flush;	(* skip prompt to stout *)
				cmd := "stty -echo raw;  scp -q -t ";  Strings.Append( cmd, remFileName );
				chan.RemoteCommand( cmd );
				SendFile( f, chan, remFileName );
				chan.Close
			ELSE  Out.String( "file not found" )
			END;
		END;
		conn.Disconnect( 11, "Good bye" )
	END Send;

	PROCEDURE SendFile( f: Files.File;  chan: Channel;  CONST name: ARRAY OF CHAR );
	VAR
		buf: ARRAY 10000 OF CHAR;
		flen: LONGINT;
		lbuf: ARRAY 16 OF CHAR;
		r: Files.Reader;  i, j: LONGINT;
	BEGIN
		flen := f.Length( );  buf := "C0644 ";
		Strings.IntToStr( flen, lbuf );  Strings.Append( buf, lbuf );  Strings.Append( buf, " " );
		Strings.Append( buf, name );  Strings.AppendChar( buf, NL );
		chan.SendBuffer( buf, Strings.Length( buf ) );
		Files.OpenReader( r, f, 0 );  i := 0;  j := 0;
		WHILE i < flen DO
			r.Char( buf[j] );  INC( i );  INC( j );
			IF (j = MaxPacketSize) OR (j = chan.pmax) THEN
				chan.SendBuffer( buf, j );  j := 0;  Out.Char( '.' )
			END
		END;
		IF j > 0 THEN  chan.SendBuffer( buf, j );  Out.Char( '.' )  END;
		Out.Char( ' ' );  Out.Int( flen, 0 ); Out.String( " bytes sent." ); Out.Ln
	END SendFile;



	(**  SSH.Receive  user@host  {  <filename>[:<local filename>] }  ~ *)
	PROCEDURE Receive*( context: Commands.Context );
	CONST
		usage = "usage:  SSH.Receive  user@host  { <filename>[:<local filename>] } ~ ";
	VAR
		f: Files.File;
		in: Streams.Reader;
		locFileName, remFileName, str, host, cmd: ARRAY 128 OF CHAR;
		strings: Strings.StringArray;
		chan: Channel;
		conn: A.Connection;
	BEGIN
		in := context.arg;
		conn := Connect( in, host );
		IF conn = NIL THEN  RETURN  END;
		WHILE in.GetString( str ) DO
			strings := Strings.Split( str, ':' );
			CASE LEN( strings^ ) OF
			| 1: COPY( strings[0]^, remFileName );
				strings := Strings.Split( remFileName, '/' );
				COPY( strings[ LEN( strings ) - 1]^, locFileName )
			| 2: COPY( strings[0]^, remFileName );
				COPY( strings[1]^, locFileName )
			ELSE
				Out.String( usage );  Out.Ln;  RETURN
			END;
			Out.String( host );  Out.Char( ':' );  Out.String( remFileName );  Out.String( "  -->  " );
			Out.String( locFileName );  Out.String( "    " );
			f := Files.Old( locFileName );
			IF f = NIL THEN
				chan := OpenSession( conn, FALSE );
				chan.Flush; (* skip prompt to stdout *)
				cmd := "stty -echo raw;  scp -q -f ";  Strings.Append( cmd, remFileName );
				chan.RemoteCommand( cmd );
				ReceiveFile( chan, locFileName );
				chan.Close
			ELSE
				Out.String( "not done: file " ); Out.String( locFileName ); Out.String( " exists" ); Out.Ln
			END;
		END;
		conn.Disconnect( 11, "Good bye" )
	END Receive;


	PROCEDURE ReceiveFile( chan: Channel; CONST name: ARRAY OF CHAR );
	VAR buf: ARRAY 10000 OF CHAR;  type: CHAR;
		plen, dlen, p, i, flen, received: LONGINT;
		pr: ARRAY 256 OF CHAR;
		f: Files.File;  w: Files.Writer;  error: BOOLEAN;
	BEGIN
		chan.Sync;  chan.ReceiveLine( pr, p );
		WHILE pr[0] # 'C' DO
			error := ORD( pr[0] ) IN {1, 2};
			IF error THEN  ShowResp( pr );  RETURN   END;
			chan.ReceiveLine( pr, p )
		END;
		flen := 0;  i := 0;
		WHILE pr[i] # ' ' DO  INC( i )  END;   (* skip file mode *)
		WHILE pr[i] = ' ' DO  INC( i )  END;
		WHILE (pr[i] >= '0') & (pr[i] <= '9') DO  flen := 10*flen + ORD( pr[i] ) - ORD( '0' );  INC( i )  END;
		chan.Sync;
		f := Files.New( name );  Files.OpenWriter( w, f, 0 );  received := 0;
		REPEAT
			type := chan.ReceivePacket( buf, plen );  Out.Char( '.' );
			IF type = Data THEN
				dlen := U.GetInt( buf, 5 );
				IF received + dlen > flen THEN  dlen := flen - received  END;
				FOR i := 9 TO 8 + dlen DO  w.Char( buf[i] );  INC( received )  END;
			END;
		UNTIL received >= flen;
		w.Update;
		Files.Register( f );
		Out.Char( ' ' );  Out.Int( received, 0 );  Out.String( " bytes received." ); Out.Ln
	END ReceiveFile;



(*---------------------- TCP/IP port forwarding ----------------------------*)


	(** SSH.StartForwarding  user@remHost  locPort:destPort  ~  *)
	PROCEDURE StartForwarding*( context: Commands.Context );
	CONST
		usage = "usage: StartForwarding  user@remHost  locPort:destPort  ~";
	VAR
		locConn: TCP.Connection;
		remConn: A.Connection;
		f: Forwarder;
		token, user, remhost: ARRAY 64 OF CHAR;
		locPort, destPort: LONGINT;
		arg: Streams.Reader;
		strings: Strings.StringArray;
		res: LONGINT;
	BEGIN
		arg := context.arg;
		arg.SkipWhitespace; arg.String( token );
		strings := Strings.Split( token, '@' );
		IF LEN( strings^ ) # 2 THEN  Out.String( usage ); Out.Ln;  RETURN  END;
		COPY( strings[0]^, user );
		COPY( strings[1]^, remhost );
		arg.SkipWhitespace; arg.String( token );
		strings := Strings.Split( token, ':' );
		IF  LEN( strings^ ) # 2 THEN  Out.String( usage ); Out.Ln;  RETURN  END;
		Strings.StrToInt( strings[0]^, locPort );
		Strings.StrToInt( strings[1]^, destPort );
 		f := forwarderList;
		WHILE f # NIL DO
			IF f.localPort = locPort THEN
				Out.String( "Error: port in use: " );  Out.Int( f.localPort, 1 );  Out.Ln;  RETURN
			END;
			f := f.next
		END;
		NEW( locConn );
		locConn.Open( locPort, IP.NilAdr, TCP.NilPort, res );
		IF res = TCP.Ok THEN
			remConn := A.OpenConnection( remhost, user );
			IF remConn # NIL THEN
				NEW( f, locConn, locPort, remConn, destPort );
				f.next := forwarderList;  forwarderList := f;
			ELSE
				Out.String( "connecting remote host hailed" ); Out.Ln;
				locConn.Close;
			END
		ELSE
			Out.String( "Error: cannot open port " );  Out.Int( locPort, 1 );  Out.Ln;
		END
	END StartForwarding;

	PROCEDURE Stop( fw: Forwarder );
	VAR pred, t: Forwarder;
	BEGIN
		fw.Stop;
		IF fw = forwarderList THEN  forwarderList := fw.next
		ELSE
			t := forwarderList;
			REPEAT  pred := t;  t := t.next  UNTIL (t = NIL ) OR (t = fw);
			IF t # NIL THEN  pred.next := t.next  END
		END;
	END Stop;

	(**  SSH.StopForwarding all | { portnumber }  ~ *)
	PROCEDURE StopForwarding*( context: Commands.Context );
	VAR
		f: Forwarder;  port: LONGINT;
		arg: Streams.Reader;  str: ARRAY 32 OF CHAR;
	BEGIN
		arg := context.arg;
		IF arg.GetString( str ) & (str = "all") THEN
			f := forwarderList;
			WHILE f # NIL DO  Stop( f );  f := f.next  END
		ELSE
			WHILE str # "" DO
				Strings.StrToInt( str, port );
				f := forwarderList;
				WHILE (f # NIL ) & (f.localPort # port) DO  f := f.next  END;
				IF f # NIL THEN  Stop( f )  END;
				arg.SkipWhitespace; arg.String( str )
			END
		END
	END StopForwarding;

BEGIN
	Out.String( "A2 SSH, version 1.6" );  Out.Ln;
	hexd := "0123456789ABCDEF";
	forwarderList := NIL;
END SSH.


SSHUtilities.SetDebug   0 ~
SSHUtilities.SetDebug 15 ~

SSH.Send fld@einstein@math.uni-bremen.de
	XXX.Mod
	XXX.Data
	~
	Test.Data
	SSH.KnownHosts.Data
	SSH.tar
	SSHTransport.Mod
	~

SSH.Receive fld@einstein.math.uni-bremen.de
	XXX.Mod:TTTT.Mod
	~

SystemTools.Free SSH SSHAuthorize SSHTransport SSHKeys  ~


