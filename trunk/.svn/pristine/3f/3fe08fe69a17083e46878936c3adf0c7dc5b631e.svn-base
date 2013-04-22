MODULE CryptoBlowfish;   (** Blowfish en/decryption *)

(* 2002.07.08	g.f.

	based on 'blowfish.c' created by Paul Kocher <pck@netcom.com>  in 1997.
*)


IMPORT Ciphers := CryptoCiphers, S := SYSTEM, Out := KernelLog, Files;

CONST
	N = 16;  datafile = "CryptoBlowfish.Data";

TYPE
	TP = ARRAY N + 2 OF SET;
	TS = ARRAY 4, 256 OF LONGINT;
	LI = LONGINT;

VAR
	p0: TP;  s0: TS;

TYPE
	Cipher* = OBJECT (Ciphers.Cipher)
			VAR
				p: TP;
				s: TS;
				ivl, ivr: SET;

				PROCEDURE InitKey*( CONST src: ARRAY OF CHAR;  pos: LONGINT;  keybits: LONGINT );
				VAR i, j, m: LONGINT;  xl, xr: SET;
				BEGIN
					InitKey^( src, pos, keybits );  m := keybits DIV 8;  s := s0;
					FOR i := 0 TO N + 1 DO  p[i] := p0[i]/Set( src, pos + (4*i) MOD m )  END;
					xl := {};  xr := {};
					FOR i := 0 TO N BY 2 DO  encrypt0( s, p, xl, xr, xl, xr );  p[i] := xl;  p[i + 1] := xr  END;
					FOR i := 0 TO 3 DO
						FOR j := 0 TO 254 BY 2 DO
							encrypt0( s, p, xl, xr, xl, xr );  s[i, j] := S.VAL( LI, xl );  s[i, j + 1] := S.VAL( LI, xr );
						END
					END
				END InitKey;

				PROCEDURE SetIV*( CONST src: ARRAY OF CHAR;  pos: LONGINT );
				BEGIN
					SetIV^( src, pos );  ivl := Set( src, pos );  ivr := Set( src, pos + 4 );
				END SetIV;

				PROCEDURE Encrypt*( VAR buf: ARRAY OF CHAR;  ofs, len: LONGINT );
				VAR i: LONGINT;
				BEGIN
					ASSERT( isKeyInitialized );
					ASSERT( len MOD blockSize = 0 );   (* padding must have been added *)
					i := 0;
					WHILE i < len DO  EncryptBlock( buf, ofs + i );  INC( i, blockSize );   END
				END Encrypt;

				PROCEDURE Decrypt*( VAR buf: ARRAY OF CHAR;  ofs, len: LONGINT );
				VAR i: LONGINT;
				BEGIN
					ASSERT( isKeyInitialized );
					ASSERT( len MOD blockSize = 0 );   (* padding must have been added *)
					i := 0;
					WHILE i < len DO  DecryptBlock( buf, ofs + i );  INC( i, blockSize );   END
				END Decrypt;

				PROCEDURE EncryptBlock( VAR buf: ARRAY OF CHAR;  pos: LONGINT );
				VAR xl, xr, yl, yr: SET;
				BEGIN
					xl := Set( buf, pos );  xr := Set( buf, pos + 4 );
					IF mode = Ciphers.CBC THEN  xl := xl/ivl;  xr := xr/ivr  END;
					encrypt0( s, p, xl, xr, yl, yr );
					Chars( yl, buf, pos );  Chars( yr, buf, pos + 4 );
					IF mode = Ciphers.CBC THEN  ivl := yl;  ivr := yr  END
				END EncryptBlock;

				PROCEDURE DecryptBlock( VAR buf: ARRAY OF CHAR;  pos: LONGINT );
				VAR xl, xr, yl, yr: SET;
				BEGIN
					xl := Set( buf, pos );  xr := Set( buf, pos + 4 );
					decrypt0( s, p, xl, xr, yl, yr );
					IF mode = Ciphers.CBC THEN  yl := yl/ivl;  yr := yr/ivr;  ivl := xl;  ivr := xr  END;
					Chars( yl, buf, pos );  Chars( yr, buf, pos + 4 )
				END DecryptBlock;

				PROCEDURE & Init*;
				BEGIN
					Init^;  SetNameAndBlocksize( "blowfish", 8 );
				END Init;

			END Cipher;

	PROCEDURE NewCipher*(): Ciphers.Cipher;
	VAR cipher: Cipher;
	BEGIN
		NEW( cipher );  RETURN cipher
	END NewCipher;


(*-------------------------------------------------------------------------------*)

	PROCEDURE F( CONST s: TS;  xs: SET ): SET;
	VAR a, b, c, d, x, y: LONGINT;
	BEGIN
		x := S.VAL( LI, xs );
		d := x MOD 256;  x := x DIV 256;  c := x MOD 256;  x := x DIV 256;
		b := x MOD 256;  x := x DIV 256;  a := x MOD 256;
		y := s[0, a] + s[1, b];
		y := S.VAL( LI, S.VAL( SET, y )/S.VAL( SET, s[2, c] ) );
		y := y + s[3, d];
		RETURN S.VAL( SET, y );
	END F;

	PROCEDURE encrypt0( CONST s: TS;  CONST p: TP;  xl, xr: SET;  VAR yl, yr: SET );
	VAR t: SET;  i: INTEGER;
	BEGIN
		FOR i := 0 TO N - 1 DO
			xl := xl/p[i];  xr := F( s, xl )/xr;
			t := xl;  xl := xr;  xr := t
		 END;
		t := xl;  xl := xr;  xr := t;
		yr := xr/p[N];  yl := xl/p[N + 1];
	END encrypt0;

	PROCEDURE decrypt0( CONST s: TS;  CONST p: TP;  xl, xr: SET;  VAR yl, yr: SET );
	VAR t: SET;  i: INTEGER;
	BEGIN
		FOR i := N + 1 TO 2 BY -1 DO
			xl := xl/p[i];  xr := F( s, xl )/xr;
			t := xl;  xl := xr;  xr := t
		END;
		t := xl;  xl := xr;  xr := t;
		yr := xr/p[1];  yl := xl/p[0];
	END decrypt0;

	PROCEDURE Set( CONST buf: ARRAY OF CHAR;  pos: LONGINT ): SET;
	BEGIN
		RETURN S.VAL( SET, ASH( ORD( buf[pos] ) MOD 256, 24 ) +
							ASH( ORD( buf[pos + 1] ) MOD 256, 16 ) +
							ASH( ORD( buf[pos + 2] ) MOD 256, 8 ) +
							ORD( buf[pos + 3] ) MOD 256 );
	END Set;

	PROCEDURE Chars( s: SET;  VAR buf: ARRAY OF CHAR;  pos: LONGINT );
	VAR v: LONGINT;
	BEGIN
		v := S.VAL( LI, s );
		buf[pos] := CHR( LSH( v, -24 ) );
		buf[pos + 1] := CHR( LSH( v, -16 ) MOD 100H );
		buf[pos + 2] := CHR( LSH( v, -8 ) MOD 100H );
		buf[pos + 3] := CHR( v MOD 100H );
	END Chars;

	PROCEDURE FError;
	BEGIN
		Out.String( "Format error in " );  Out.String( datafile );  Out.Ln
	END FError;

	PROCEDURE Init0;
	VAR
		i, j, val: LONGINT;
		r: Files.Reader;
		f: Files.File;
		token: ARRAY 64 OF CHAR;
	BEGIN
		f := Files.Old( datafile );
		IF f = NIL THEN  Out.String( "File '" );  Out.String( datafile );  Out.String( "' not found" );  Out.Ln
		ELSE
			Files.OpenReader( r, f, 0 );  r.SkipWhitespace;  r.Token( token );
			IF token # "Blowfish.P" THEN  FError
			ELSE
				FOR i := 0 TO N + 2 - 1 DO  r.SkipWhitespace; r.Int( val, TRUE );  p0[i] := S.VAL( SET, val )  END;
				r.SkipWhitespace;  r.Token( token );
				IF token # "Blowfish.S" THEN  FError
				ELSE
					FOR i := 0 TO 3 DO
						FOR j := 0 TO 255 DO  r.SkipWhitespace; r.Int( s0[i, j], TRUE )  END
					END;
				END
			END
		END
	END Init0;

BEGIN
	Init0
END CryptoBlowfish.

