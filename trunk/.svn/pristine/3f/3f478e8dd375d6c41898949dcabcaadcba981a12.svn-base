MODULE CryptoCAST;   (* g.f.	22.10.02 *)

IMPORT S := SYSTEM, Ciphers := CryptoCiphers, Out := KernelLog, Files;

CONST
	datafile = "CryptoCAST.Data";

TYPE
	LI = LONGINT;
	Key =	RECORD
				val: LONGINT;
				rot: SHORTINT
			END;
	Keys =	RECORD
				short: BOOLEAN;
				data: ARRAY 16 OF Key
			END;

	Block = ARRAY 2 OF SET;

VAR
	T: ARRAY 8, 256 OF SET;

TYPE
	Cipher* = OBJECT (Ciphers.Cipher)
			VAR keys: Keys;
				iv: Block;

				PROCEDURE InitKey*( CONST src: ARRAY OF CHAR;  pos: LONGINT;  keybits: LONGINT );
				BEGIN
					ASSERT( keybits MOD 8 = 0 );
					InitKey^( src, pos, keybits );
					InitKeys( keys, src, pos, keybits DIV 8 )
				END InitKey;

				PROCEDURE SetIV*( CONST src: ARRAY OF CHAR;  p: LONGINT );
				BEGIN
					SetIV^( src, p );   (* set mode *)
					iv[0] := c2s( src, p );  iv[1] := c2s( src, p + 4 );
				END SetIV;

				PROCEDURE Encrypt*( VAR buf: ARRAY OF CHAR;  ofs, len: LONGINT );
				VAR i: LONGINT;
				BEGIN
					ASSERT( isKeyInitialized );
					ASSERT( len MOD blockSize = 0 );   (* padding must have been added *)
					i := 0;
					WHILE i < len DO  EncryptBlock( buf, ofs + i );  INC( i, blockSize )   END
				END Encrypt;

				PROCEDURE Decrypt*( VAR buf: ARRAY OF CHAR;  ofs, len: LONGINT );
				VAR i: LONGINT;
				BEGIN
					ASSERT( isKeyInitialized );
					ASSERT( len MOD blockSize = 0 );   (* padding must have been added *)
					i := 0;
					WHILE i < len DO  DecryptBlock( buf, ofs + i );  INC( i, blockSize )   END
				END Decrypt;

				PROCEDURE EncryptBlock( VAR buf: ARRAY OF CHAR;  p: LONGINT );
				VAR b: Block;
				BEGIN
					b[0] := c2s( buf, p );  b[1] := c2s( buf, p + 4 );
					IF mode = Ciphers.CBC THEN  b[0] := b[0]/iv[0];  b[1] := b[1]/iv[1]  END;
					encrypt( keys, b );
					s2c( b[0], buf, p );  s2c( b[1], buf, p + 4 );
					IF mode = Ciphers.CBC THEN  iv := b  END
				END EncryptBlock;

				PROCEDURE DecryptBlock( VAR buf: ARRAY OF CHAR;  p: LONGINT );
				VAR b0, b: Block;
				BEGIN
					b[0] := c2s( buf, p );  b[1] := c2s( buf, p + 4 );
					IF mode = Ciphers.CBC THEN  b0 := b  END;
					decrypt( keys, b );
					IF mode = Ciphers.CBC THEN  b[0] := b[0]/iv[0];  b[1] := b[1]/iv[1];  iv := b0  END;
					s2c( b[0], buf, p );  s2c( b[1], buf, p + 4 )
				END DecryptBlock;

				PROCEDURE & Init*;
				BEGIN
					SetNameAndBlocksize( "cast", 8 );
				END Init;

			END Cipher;

	PROCEDURE NewCipher*(): Ciphers.Cipher;
	VAR cipher: Cipher;
	BEGIN
		NEW( cipher );  RETURN cipher
	END NewCipher;


(*-------------------------------------------------------------------------------*)


	PROCEDURE InitKeys( VAR keys: Keys;  CONST src: ARRAY OF CHAR;  pos: LONGINT;  len: LONGINT );
	VAR buf: ARRAY 16 OF CHAR;
		X, Z: ARRAY 4 OF SET;
		x, z: ARRAY 16 OF INTEGER;
		k: ARRAY 32 OF SET;
		i, j: LONGINT;

		PROCEDURE Zz( i: INTEGER;  s: SET );
		VAR l: LONGINT;
		BEGIN
			Z[i DIV 4] := s;  l := S.VAL( LONGINT, s );
			z[i + 3] := SHORT( l MOD 256 );  l := l DIV 256;
			z[i + 2] := SHORT( l MOD 256 );  l := l DIV 256;
			z[i + 1] := SHORT( l MOD 256 );  l := l DIV 256;
			z[i + 0] := SHORT( l MOD 256 );
		END Zz;

		PROCEDURE Xx( i: INTEGER;  s: SET );
		VAR l: LONGINT;
		BEGIN
			X[i DIV 4] := s;  l := S.VAL( LONGINT, s );
			x[i + 3] := SHORT( l MOD 256 );  l := l DIV 256;
			x[i + 2] := SHORT( l MOD 256 );  l := l DIV 256;
			x[i + 1] := SHORT( l MOD 256 );  l := l DIV 256;
			x[i + 0] := SHORT( l MOD 256 );
		END Xx;

	BEGIN
		IF len > 16 THEN  len := 16  END;
		FOR i := 0 TO 15 DO  buf[i] := 0X  END;
		FOR i := 0 TO len - 1 DO  buf[i] := src[pos + i]  END;
		FOR i := 0 TO 15 DO  x[i] := ORD( buf[i] )  END;
		FOR i := 0 TO 3 DO  X[i] := c2s( buf, 4*i )  END;
		keys.short := len <= 10;

		FOR i := 0 TO 1 DO
			j := 16*i;
			Zz(   0, X[0]/T[4, x[13]]/T[5, x[15]]/T[6, x[12]]/T[7, x[14]]/T[6, x[  8]] );
			Zz(   4, X[2]/T[4,  z[  0]]/T[5,  z[  2]]/T[6, z[  1]]/T[7,  z[  3]]/T[7, x[10]] );
			Zz(   8, X[3]/T[4,  z[  7]]/T[5,  z[  6]]/T[6, z[  5]]/T[7,  z[  4]]/T[4, x[  9]] );
			Zz( 12, X[1]/T[4,  z[10]]/T[5,  z[  9]]/T[6, z[11]]/T[7,  z[  8]]/T[5, x[11]] );

			k[j + 0] := T[4, z[  8]]/T[5, z[  9]]/T[6, z[7]]/T[7, z[6]]/T[4, z[  2]];
			k[j + 1] := T[4, z[10]]/T[5, z[11]]/T[6, z[5]]/T[7, z[4]]/T[5, z[  6]];
			k[j + 2] := T[4, z[12]]/T[5, z[13]]/T[6, z[3]]/T[7, z[2]]/T[6, z[  9]];
			k[j + 3] := T[4, z[14]]/T[5, z[15]]/T[6, z[1]]/T[7, z[0]]/T[7, z[12]];

			Xx(   0, Z[2]/T[4,  z[  5]]/T[5, z[7]]/T[6,  z[  4]]/T[7, z[6]]/T[6, z[0]] );
			Xx(   4, Z[0]/T[4, x[  0]]/T[5, x[2]]/T[6, x[  1]]/T[7, x[3]]/T[7, z[2]] );
			Xx(   8, Z[1]/T[4, x[  7]]/T[5, x[6]]/T[6, x[  5]]/T[7, x[4]]/T[4, z[1]] );
			Xx( 12, Z[3]/T[4, x[10]]/T[5, x[9]]/T[6, x[11]]/T[7, x[8]]/T[5, z[3]] );

			k[j + 4] := T[4, x[3]]/T[5, x[2]]/T[6, x[12]]/T[7, x[13]]/T[4, x[  8]];
			k[j + 5] := T[4, x[1]]/T[5, x[0]]/T[6, x[14]]/T[7, x[15]]/T[5, x[13]];
			k[j + 6] := T[4, x[7]]/T[5, x[6]]/T[6, x[  8]]/T[7, x[  9]]/T[6, x[  3]];
			k[j + 7] := T[4, x[5]]/T[5, x[4]]/T[6, x[10]]/T[7, x[11]]/T[7, x[  7]];

			Zz(   0, X[0]/T[4, x[13]]/T[5, x[15]]/T[6, x[12]]/T[7, x[14]]/T[6, x[  8]] );
			Zz(   4, X[2]/T[4,  z[  0]]/T[5,  z[  2]]/T[6, z[  1]]/T[7,  z[  3]]/T[7, x[10]] );
			Zz(   8, X[3]/T[4,  z[  7]]/T[5,  z[  6]]/T[6, z[  5]]/T[7,  z[  4]]/T[4, x[  9]] );
			Zz( 12, X[1]/T[4,  z[10]]/T[5,  z[  9]]/T[6, z[11]]/T[7,  z[  8]]/T[5, x[11]] );

			k[j +   8] := T[4, z[3]]/T[5, z[2]]/T[6, z[12]]/T[7, z[13]]/T[4, z[  9]];
			k[j +   9] := T[4, z[1]]/T[5, z[0]]/T[6, z[14]]/T[7, z[15]]/T[5, z[12]];
			k[j + 10] := T[4, z[7]]/T[5, z[6]]/T[6, z[  8]]/T[7, z[  9]]/T[6, z[  2]];
			k[j + 11] := T[4, z[5]]/T[5, z[4]]/T[6, z[10]]/T[7, z[11]]/T[7, z[  6]];

			Xx(   0, Z[2]/T[4,  z[  5]]/T[5, z[7]]/T[6,  z[  4]]/T[7,  z[6]]/T[6, z[0]] );
			Xx(   4, Z[0]/T[4, x[  0]]/T[5, x[2]]/T[6, x[  1]]/T[7, x[3]]/T[7, z[2]] );
			Xx(   8, Z[1]/T[4, x[  7]]/T[5, x[6]]/T[6, x[  5]]/T[7, x[4]]/T[4, z[1]] );
			Xx( 12, Z[3]/T[4, x[10]]/T[5, x[9]]/T[6, x[11]]/T[7, x[8]]/T[5, z[3]] );

			k[j + 12] := T[4, x[  8]]/T[5, x[  9]]/T[6, x[7]]/T[7, x[6]]/T[4, x[  3]];
			k[j + 13] := T[4, x[10]]/T[5, x[11]]/T[6, x[5]]/T[7, x[4]]/T[5, x[  7]];
			k[j + 14] := T[4, x[12]]/T[5, x[13]]/T[6, x[3]]/T[7, x[2]]/T[6, x[  8]];
			k[j + 15] := T[4, x[14]]/T[5, x[15]]/T[6, x[1]]/T[7, x[0]]/T[7, x[13]];
		END;
		FOR i := 0 TO 15 DO
			keys.data[i].val := S.VAL( LONGINT, k[i] );
			keys.data[i].rot := SHORT( SHORT( (S.VAL( LONGINT, k[i + 16] ) + 16) MOD 32 ) );
		END
	END InitKeys;

	PROCEDURE CAST1( VAR k: Key;  VAR L, R: SET );   (* +, xor, - *)
	VAR a, b: SET;  t, c, d: LONGINT;
	BEGIN
		t := ROT( k.val + S.VAL( LI, R ), k.rot );
		b := T[1, t MOD 256];  t := t DIV 256;
		a := T[0, t MOD 256];  t := t DIV 256;
		d := S.VAL( LI, T[3, t MOD 256] );  t := t DIV 256;
		c := S.VAL( LI, T[2, t MOD 256] );
		L := L/S.VAL( SET, S.VAL( LI, a/b ) - c + d );
	END CAST1;

	PROCEDURE CAST2( VAR k: Key;  VAR L, R: SET );   (* xor, -, + *)
	VAR d: SET;  t, a, b, c: LONGINT;
	BEGIN
		t := ROT( S.VAL( LI, S.VAL( SET, k.val )/R ), k.rot );
		b := S.VAL( LI, T[1, t MOD 256] );  t := t DIV 256;
		a := S.VAL( LI, T[0, t MOD 256] );  t := t DIV 256;
		d := T[3, t MOD 256];  t := t DIV 256;
		c := S.VAL( LI, T[2, t MOD 256] );  L := L/(S.VAL( SET, a - b + c )/d);
	END CAST2;

	PROCEDURE CAST3( VAR k: Key;  VAR L, R: SET );   (* -, +, xor *)
	VAR c: SET;  t, a, b, d: LONGINT;
	BEGIN
		t := ROT( k.val - S.VAL( LI, R ), k.rot );
		b := S.VAL( LI, T[1, t MOD 256] );  t := t DIV 256;
		a := S.VAL( LI, T[0, t MOD 256] );  t := t DIV 256;
		d := S.VAL( LI, T[3, t MOD 256] );  t := t DIV 256;
		c := T[2, t MOD 256];  L := L/S.VAL( SET, S.VAL( LI, S.VAL( SET, a + b )/c ) - d );
	END CAST3;

	PROCEDURE c2s( CONST buf: ARRAY OF CHAR;  p: LONGINT ): SET;   (* big endian *)
	BEGIN
		RETURN S.VAL( SET, ASH( LONG( ORD( buf[p + 0] ) ), 24 ) +
							ASH( LONG( ORD( buf[p + 1] ) ), 16 ) +
							ASH( LONG( ORD( buf[p + 2] ) ), 8 ) +
							ORD( buf[p + 3] ) );
	END c2s;

	PROCEDURE s2c( s: SET;  VAR buf: ARRAY OF CHAR;  p: LONGINT );   (* big endian *)
	VAR v: LONGINT;
	BEGIN
		v := S.VAL( LONGINT, s );
		buf[p + 3] := CHR( v MOD 100H );  v := v DIV 100H;
		buf[p + 2] := CHR( v MOD 100H );  v := v DIV 100H;
		buf[p + 1] := CHR( v MOD 100H );  v := v DIV 100H;
		buf[p + 0] := CHR( v MOD 100H )
	END s2c;

	PROCEDURE encrypt( VAR k: Keys;  VAR b: Block );
	VAR l, r: SET;
	BEGIN
		l := b[0];  r := b[1];
		CAST1( k.data[0], l, r );  CAST2( k.data[  1], r, l );  CAST3( k.data[  2], l, r );
		CAST1( k.data[3], r, l );  CAST2( k.data[  4], l, r );  CAST3( k.data[  5], r, l );
		CAST1( k.data[6], l, r );  CAST2( k.data[  7], r, l );  CAST3( k.data[  8], l, r );
		CAST1( k.data[9], r, l );  CAST2( k.data[10], l, r );  CAST3( k.data[11], r, l );
		IF ~k.short THEN
			CAST1( k.data[12], l, r );  CAST2( k.data[13], r, l );
			CAST3( k.data[14], l, r );  CAST1( k.data[15], r, l );
		END;
		b[0] := r;  b[1] := l
	END encrypt;

	PROCEDURE decrypt( VAR k: Keys;  VAR b: Block );
	VAR l, r: SET;
	BEGIN
		l := b[0];  r := b[1];
		IF ~k.short THEN
			CAST1( k.data[15], l, r );  CAST3( k.data[14], r, l );
			CAST2( k.data[13], l, r );  CAST1( k.data[12], r, l );
		END;
		CAST3( k.data[11], l, r );  CAST2( k.data[10], r, l );  CAST1( k.data[9], l, r );
		CAST3( k.data[  8], r, l );  CAST2( k.data[  7], l, r );  CAST1( k.data[6], r, l );
		CAST3( k.data[  5], l, r );  CAST2( k.data[  4], r, l );  CAST1( k.data[3], l, r );
		CAST3( k.data[  2], r, l );  CAST2( k.data[  1], l, r );  CAST1( k.data[0], r, l );
		b[0] := r;  b[1] := l
	END decrypt;

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
		IF f = NIL  THEN
			Out.String( "File '" );  Out.String( datafile );  Out.String( "' not found" );  Out.Ln
		ELSE
			Files.OpenReader( r, f, 0 );  r.SkipWhitespace;  r.Token( token );
			IF token # "CAST.S.T" THEN  FError
			ELSE
				FOR i := 0 TO 7 DO
					FOR j := 0 TO 255 DO r.SkipWhitespace; r.Int( val, TRUE );  T[i, j] := S.VAL( SET, val )  END;
				END
			END
		END
	END Init0;

BEGIN
	ASSERT( S.VAL( LONGINT, {0} ) = 1 );  Init0
END CryptoCAST.
