MODULE CryptoTwofish;   (** Twofish en/decryption *)

(*	Oberon port, based on twofish.c (vers. 1.0, Apr. 1998),
		2002.07.22	g.f.
 *)

IMPORT S := SYSTEM, Ciphers := CryptoCiphers, Out := KernelLog, Files;

CONST
	datafile = "CryptoTwofish.Data";
	N = 16;

TYPE
	Block = ARRAY 4 OF SET;
	LI = LONGINT;

	SKey = ARRAY 4 OF SET;

VAR
	tab: ARRAY 2, 256 OF SET;

TYPE
	Cipher* = OBJECT (Ciphers.Cipher)
			VAR keybits: LONGINT;
				sbox: ARRAY 4 OF LONGINT;
				subkeys: ARRAY 8 + 2*N OF LONGINT;
				iv: Block;

				PROCEDURE InitKey*( CONST src: ARRAY OF CHAR;  pos: LONGINT;  keybits: LONGINT );
				CONST step = 02020202H;  bump = 01010101H;
				VAR
					i, A, B, m, nsub: LONGINT;
					k32e, k32o: ARRAY 4 OF LONGINT;   (* even/odd key dwords *)
				BEGIN
					InitKey^( src, pos, keybits );  SELF.keybits := keybits;
					FOR i := 0 TO keybits DIV 32 - 1 DO
						IF ODD( i ) THEN  k32o[i DIV 2] := Int( src, pos + i*4 )
						ELSE  k32e[i DIV 2] := Int( src, pos + i*4 )
						END
					END;
					m := keybits DIV 64 - 1;
					FOR i := 0 TO m DO
						(* compute S-box keys using (12,8) Reed-Solomon code over GF(256) *)
						sbox[m - i] := Encode( k32e[i], k32o[i] );   (* reverse order *)
					END;
					nsub := 8 + N*2;
					FOR i := 0 TO nsub DIV 2 - 1 DO
						(* compute round subkeys for PHT *)
						A := f32( i*step, k32e, keybits );  			 (* A uses even key dwords *)
						B := f32( i*step + bump, k32o, keybits );   (* B uses odd  key dwords *)
						B := ROT( B, 8 );
						subkeys[i*2] := A + B;   							(* combine with a PHT *)
						subkeys[i*2 + 1] := ROT( A + 2*B, 9 );
					END
				END InitKey;

				PROCEDURE SetIV*( CONST src: ARRAY OF CHAR;  pos: LONGINT );
				VAR i: INTEGER;
				BEGIN
					SetIV^( src, pos );   (* set mode *)
					FOR i := 0 TO 3 DO  iv[i] := Set( src, pos + 4*i )  END;
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
				VAR x: Block;  t0, t1, i, r: LONGINT;  s0, s1: SET;
				BEGIN
					(* copy in the block, add whitening *)
					FOR i := 0 TO 3 DO
						x[i] := Set( buf, pos + i*4 )/S.VAL( SET, subkeys[i] );
						IF mode = Ciphers.CBC THEN  x[i] := x[i]/iv[i]  END
					END;
					(* main Twofish encryption loop *)
					FOR r := 0 TO N - 1 DO
						t0 := f32( S.VAL( LI, x[0] ), sbox, keybits );
						t1 := f32( ROT( S.VAL( LI, x[1] ), 8 ), sbox, keybits );
						x[3] := ROT( x[3], 1 );
						x[2] := x[2]/S.VAL( SET, t0 + t1 + subkeys[8 + 2*r] );
						x[3] := x[3]/S.VAL( SET, t0 + t1*2 + subkeys[8 + 2*r + 1] );
						x[2] := ROT( x[2], -1 );
						IF r < N - 1 THEN  (* unswap, except for last round *)
							s0 := x[0];  x[0] := x[2];  x[2] := s0;  s1 := x[1];  x[1] := x[3];  x[3] := s1;
						END
					END;
					(* copy out, with whitening *)
					FOR i := 0 TO 3 DO
						x[i] := x[i]/S.VAL( SET, subkeys[4 + i] );  Chars( x[i], buf, pos + i*4 );
						IF mode = Ciphers.CBC THEN  iv[i] := x[i]  END
					END;
				END EncryptBlock;

				PROCEDURE DecryptBlock( VAR buf: ARRAY OF CHAR;  pos: LONGINT );
				VAR x0, x: Block;  t0, t1, i, r: LONGINT;  s0, s1: SET;
				BEGIN
					(* copy in the block, add whitening *)
					FOR i := 0 TO 3 DO  x0[i] := Set( buf, pos + i*4 );  x[i] := x0[i]/S.VAL( SET, subkeys[4 + i] );   END;
					(* main Twofish decryption loop *)
					FOR r := N - 1 TO 0 BY -1 DO
						t0 := f32( S.VAL( LI, x[0] ), sbox, keybits );
						t1 := f32( ROT( S.VAL( LI, x[1] ), 8 ), sbox, keybits );
						x[2] := ROT( x[2], 1 );  x[2] := x[2]/S.VAL( SET, t0 + t1 + subkeys[8 + 2*r] );
						x[3] := x[3]/S.VAL( SET, t0 + t1*2 + subkeys[8 + 2*r + 1] );  x[3] := ROT( x[3], -1 );
						IF r > 0 THEN  (* unswap, except for last round *)
							s0 := x[0];  x[0] := x[2];  x[2] := s0;
							s1 := x[1];  x[1] := x[3];  x[3] := s1;
						END
					END;
					(* copy out, with whitening *)
					FOR i := 0 TO 3 DO
						x[i] := x[i]/S.VAL( SET, subkeys[i] );
						IF mode = Ciphers.CBC THEN  x[i] := x[i]/iv[i];  iv[i] := x0[i]  END;
						Chars( x[i], buf, pos + i*4 );
					END;
				END DecryptBlock;

				PROCEDURE & Init*;
				BEGIN
					SetNameAndBlocksize( "twofish", 16 )
				END Init;

			END Cipher;

	PROCEDURE NewCipher*(): Ciphers.Cipher;
	VAR cipher: Cipher;
	BEGIN
		NEW( cipher );  RETURN cipher
	END NewCipher;

(*-------------------------------------------------------------------------------*)

	PROCEDURE m1( x: LONGINT ): SET;
	BEGIN
		RETURN S.VAL( SET, x )
	END m1;

	PROCEDURE mx( x: LONGINT ): SET;
	CONST FDBK = 169H;
	VAR t: SET;
	BEGIN
		t := S.VAL( SET, x DIV 4 );
		IF ODD( x DIV 2 ) THEN  t := t/S.VAL( SET, FDBK DIV 2 )  END;
		IF ODD( x ) THEN  t := t/S.VAL( SET, FDBK DIV 4 )  END;
		RETURN S.VAL( SET, x )/t
	END mx;

	PROCEDURE my( x: LONGINT ): SET;
	CONST FDBK = 169H;
	VAR t1, t2: SET;
	BEGIN
		t1 := S.VAL( SET, x DIV 2 );  t2 := S.VAL( SET, x DIV 4 );
		IF ODD( x DIV 2 ) THEN  t2 := t2/S.VAL( SET, FDBK DIV 2 )  END;
		IF ODD( x ) THEN  t1 := t1/S.VAL( SET, FDBK DIV 2 );  t2 := t2/S.VAL( SET, FDBK DIV 4 )  END;
		RETURN S.VAL( SET, x )/t1/t2
	END my;

	PROCEDURE split( x: LONGINT;  VAR v: SKey );
	BEGIN
		v[0] := S.VAL( SET, x MOD 256 );  x := x DIV 256;
		v[1] := S.VAL( SET, x MOD 256 );  x := x DIV 256;
		v[2] := S.VAL( SET, x MOD 256 );  x := x DIV 256;
		v[3] := S.VAL( SET, x MOD 256 );
	END split;

	PROCEDURE Int( CONST s: ARRAY OF CHAR;  p: LONGINT ): LONGINT;
	VAR i, val: LONGINT;
	BEGIN
		val := 0;
		FOR i := p + 3 TO p BY -1 DO  val := val*100H + ORD( s[i] )  END;
		RETURN val
	END Int;

	PROCEDURE Set( CONST s: ARRAY OF CHAR;  p: LONGINT ): SET;
	VAR i, val: LONGINT;
	BEGIN
		val := 0;
		FOR i := p + 3 TO p BY -1 DO  val := val*100H + ORD( s[i] )  END;
		RETURN S.VAL( SET, val )
	END Set;

	PROCEDURE Chars( s: SET;  VAR txt: ARRAY OF CHAR;  p: LONGINT );
	VAR i, v: LONGINT;
	BEGIN
		v := S.VAL( LI, s );
		FOR i := p TO p + 3 DO  txt[i] := CHR( v MOD 100H );  v := v DIV 100H  END;
	END Chars;

	PROCEDURE f32( x: LONGINT;  CONST k32: ARRAY OF LONGINT;  keybits: LONGINT ): LONGINT;
	VAR a, b, c, d, l: LONGINT;  k, k1: SKey;
	BEGIN
		(* Run each byte thru 8x8 S-boxes, xoring with key byte at each stage. *)
		(* Note that each byte goes through a different combination of S-boxes.*)
		a := x MOD 256;  x := x DIV 256;
		b := x MOD 256;  x := x DIV 256;
		c := x MOD 256;  x := x DIV 256;
		d := x MOD 256;

		l := ((keybits + 63) DIV 64) MOD 4;
		IF l = 0 THEN  (* 256 bits of key *)
			split( k32[3], k );  a := S.VAL( LI, tab[1, a]/k[0] );  b := S.VAL( LI, tab[0, b]/k[1] );  c := S.VAL( LI, tab[0, c]/k[2] );
			d := S.VAL( LI, tab[1, d]/k[3] );
		END;
		IF l IN {0, 3} THEN  (* 192 <= bits of key *)
			split( k32[2], k );  a := S.VAL( LI, tab[1, a]/k[0] );
			b := S.VAL( LI, tab[1, b]/k[1] );
			c := S.VAL( LI, tab[0, c]/k[2] );
			d := S.VAL( LI, tab[0, d]/k[3] )
		END;
		(* 128 <= bits of key *)
		split( k32[1], k1 );  split( k32[0], k );  a := S.VAL( LI, tab[1, S.VAL( LI, tab[0, S.VAL( LI, tab[0, a]/k1[0] )]/k[0] )] );
		b := S.VAL( LI, tab[0, S.VAL( LI, tab[0, S.VAL( LI, tab[1, b]/k1[1] )]/k[1] )] );
		c := S.VAL( LI, tab[1, S.VAL( LI, tab[1, S.VAL( LI, tab[0, c]/k1[2] )]/k[2] )] );
		d := S.VAL( LI, tab[0, S.VAL( LI, tab[1, S.VAL( LI, tab[1, d]/k1[3] )]/k[3] )] );

		(* Now perform the MDS matrix multiply  *)
		RETURN S.VAL( LI, m1( a )/my( b )/mx( c )/mx( d ) ) +
						ASH( S.VAL( LI, mx( a )/my( b )/my( c )/m1( d ) ), 8 ) +
						ASH( S.VAL( LI, my( a )/mx( b )/m1( c )/my( d ) ), 16 ) +
						ASH( S.VAL( LI, my( a )/m1( b )/my( c )/mx( d ) ), 24 );
	END f32;

	(* RS_MDS_Encode *)
	PROCEDURE Encode( k0, k1: LONGINT ): LONGINT;
	TYPE LI = LONGINT;
	VAR i, j: INTEGER;  g2, g3: SET;  r, b: LONGINT;  g216, g324, g38: SET;
	BEGIN
		r := k1;
		FOR i := 0 TO 1 DO
			IF i # 0 THEN  r := S.VAL( LI, S.VAL( SET, r )/S.VAL( SET, k0 ) )  END;
			FOR j := 0 TO 3 DO
				(* r := g( r ) *)
				 b := ASH( r, -24 ) MOD 256;

				g2 := S.VAL( SET, b*2 );
				IF b > 7FH THEN  g2 := (g2/S.VAL( SET, 14DH ))*S.VAL( SET, 0FFH )  END;
				g216 := S.VAL( SET, ASH( S.VAL( LI, g2 ), 16 ) );

				g3 := S.VAL( SET, b DIV 2 )/g2;
				IF ODD( b ) THEN  g3 := g3/S.VAL( SET, 0A6H )  END;
				g38 := S.VAL( SET, ASH( S.VAL( LI, g3 ), 8 ) );
				g324 := S.VAL( SET, ASH( S.VAL( LI, g38 ), 16 ) );

				r := S.VAL( LI, S.VAL( SET, r*256 )/g324/g216/g38/S.VAL( SET, b ) )
			END
		END;
		RETURN r
	END Encode;

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
		IF f = NIL THEN
			Out.String( "File '" );  Out.String( datafile );  Out.String( "' not found" );  Out.Ln
		ELSE
			Files.OpenReader( r, f, 0 );  r.SkipWhitespace;  r.Token( token );
			IF token # "Twofish.P8x8" THEN  FError
			ELSE
				FOR i := 0 TO 1 DO
					FOR j := 0 TO 255 DO  r.SkipWhitespace; r.Int( val, TRUE );  tab[i, j] := S.VAL( SET, val )  END;
				END;
			END
		END
	END Init0;

BEGIN
	Init0
END CryptoTwofish.