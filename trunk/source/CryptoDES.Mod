MODULE CryptoDES;   (* g.f.	30.7.02 *)

IMPORT S := SYSTEM, Ciphers := CryptoCiphers, U := CryptoUtils, Out := KernelLog, Files;

CONST
	datafile = "CryptoDES.Data";

TYPE
	Block* = ARRAY 2 OF SET;
	KeyBlock = ARRAY 32 OF SET;


VAR
	skb	: ARRAY 8, 64 OF SET;
	T	: ARRAY 8, 64 OF SET;

TYPE
	Cipher* = OBJECT (Ciphers.Cipher)
			VAR
				keys: KeyBlock;
				iv: Block;

				PROCEDURE InitKey*( CONST src: ARRAY OF CHAR;  pos: LONGINT;  keybits: LONGINT );
				CONST Shifts = {2..7, 9..14};  Mask28 = {0..27};
				VAR c, d, t, s: SET;  i, j: LONGINT;
				BEGIN
					ASSERT( keybits = 64 );
					InitKey^( src, pos, keybits );

					c := U.LESetFrom( src, pos );
					d := U.LESetFrom( src, pos + 4 );

					perm( d, c, 4, 0F0F0F0FH );
					hperm( c );  hperm( d );
					perm( d, c, 1, 55555555H );
					perm( c, d, 8, 00FF00FFH );
					perm( d, c, 1, 55555555H );

					d := S.LSH( d*{0..7}, 16 ) + d*{8..15} + S.LSH( d, -16 )*{0..7} + S.LSH( c, -4 )*{24..27};
					c := c*Mask28;

					FOR i := 0 TO 15 DO
						IF i IN Shifts THEN
							c := (S.LSH( c, -2 ) + S.LSH( c, 26 ))*Mask28;
							d := (S.LSH( d, -2 ) + S.LSH( d, 26 ))*Mask28;
						ELSE
							c := (S.LSH( c, -1 ) + S.LSH( c, 27 ))*Mask28;
							d := (S.LSH( d, -1 ) + S.LSH( d, 27 ))*Mask28;
						END;
						s :=
							skb[0, sm( c,    0, 3FH )] +
							skb[1, sm( c,  -6, 03H ) + sm( c,   -7, 3CH )] +
							skb[2, sm( c, -13, 0FH ) + sm( c, -14, 30H )] +
							skb[3, sm( c, -20, 01H ) + sm( c, -21, 06H ) + sm( c, -22, 38H )];
						t :=
							skb[4, sm( d,    0, 3FH )] +
							skb[5, sm( d,  -7, 03H ) + sm( d,   -8, 3CH )] +
							skb[6, sm( d, -15, 3FH )] +
							skb[7, sm( d, -21, 0FH ) + sm( d, -22, 30H )];

						j := 2*i;
						keys[j] := S.ROT( S.LSH( t, 16 ) + s*{0..15}, -30 );
						keys[j+1] := S.ROT( S.LSH( s, -16 ) + t*{16..31}, -26 )
					END;
				END InitKey;

				PROCEDURE SetIV*( CONST src: ARRAY OF CHAR;  p: LONGINT );
				BEGIN
					SetIV^( src, p );   (* set mode *)
					U.CharsToBlockLE( src, p, iv )
				END SetIV;


				PROCEDURE Encrypt*( VAR buf: ARRAY OF CHAR;  ofs, len: LONGINT );
				VAR i: LONGINT;  b: Block;
				BEGIN
					ASSERT( isKeyInitialized );
					ASSERT( len MOD blockSize = 0 );   (* padding must have been added *)
					i := 0;
					WHILE i < len DO
						U.CharsToBlockLE( buf, ofs + i, b );
						IF mode = Ciphers.CBC THEN  U.XORBlock( b, iv )  END;
						IP( b[0], b[1] );
						Encrypt0( b );
						FP( b[0], b[1] );
						U.BlockToCharsLE( b, buf, ofs + i );
						IF mode = Ciphers.CBC THEN  iv := b  END;
						INC( i, blockSize )
					END
				END Encrypt;

				PROCEDURE Encrypt0*( VAR block: Block );
				VAR r, l: SET;  i: LONGINT;
				BEGIN
					r := block[0];  l := block[1];
					l := S.ROT( l, -29 );  r := S.ROT(r, -29 );
					FOR i := 0 TO 7 DO
						Round( l, r, 4*i + 0 );
						Round( r, l, 4*i + 2 );
					END;
					block[0] := S.ROT( l, -3 );  block[1] :=  S.ROT( r, -3 );
				END Encrypt0;


				PROCEDURE Decrypt*( VAR buf: ARRAY OF CHAR;  ofs, len: LONGINT );
				VAR i: LONGINT;  b0, b: Block;
				BEGIN
					ASSERT( isKeyInitialized );
					ASSERT( len MOD blockSize = 0 );   (* padding must have been added *)
					i := 0;
					WHILE i < len DO
						U.CharsToBlockLE( buf, ofs + i, b );
						IF mode = Ciphers.CBC THEN  b0 := b  END;
						IP( b[0], b[1] );
						Decrypt0( b );
						FP( b[0], b[1] );
						IF mode = Ciphers.CBC THEN  U.XORBlock( b, iv );  iv := b0  END;
						U.BlockToCharsLE( b, buf, ofs + i );
						INC( i, blockSize )
					END
				END Decrypt;

				PROCEDURE Decrypt0*( VAR block: Block );
				VAR r, l: SET;  i: LONGINT;
				BEGIN
					r := block[0];  l := block[1];
					l := S.ROT( l, -29 );  r := S.ROT(r, -29 );
					FOR i := 7 TO 0 BY -1 DO
						Round( l, r, 4*i + 2 );
						Round( r, l, 4*i + 0 );
					END;
					block[0] := S.ROT( l, -3 );  block[1] :=  S.ROT( r, -3 );
				END Decrypt0;


				PROCEDURE Round( VAR l, r: SET;  i: LONGINT );
				VAR a0, a1, a2, a3, b0, b1, b2, b3: LONGINT;
				BEGIN
					split( r / keys[i], b0, b1, b2, b3 );
					split( S.ROT( r / keys[i + 1], -4 ), a0, a1, a2, a3 );
					l := l / (  T[0, b0] / T[2, b1] / T[4, b2] / T[6, b3] / T[1, a0] / T[3, a1] / T[5, a2] / T[7, a3] );
				END Round;


				PROCEDURE & Init*;
				BEGIN
					SetNameAndBlocksize( "des", 8 );
				END Init;

			END Cipher;

	PROCEDURE NewCipher*(): Ciphers.Cipher;
	VAR cipher: Cipher;
	BEGIN
		NEW( cipher );  RETURN cipher
	END NewCipher;





	PROCEDURE hperm( VAR a: SET );
	VAR t: SET;
	BEGIN
		t := (S.LSH( a, 18 ) / a)*S.VAL( SET, LONGINT( 0CCCC0000H ) );
		a := a / t / S.LSH( t, -18 )
	END hperm;

	PROCEDURE perm( VAR a, b: SET;  n, m: LONGINT );
	VAR t: SET;
	BEGIN
		t := (S.LSH( a, -n ) / b)*S.VAL( SET, m );
		b := b / t;
		a := a / S.LSH( t, n )
	END perm;

	PROCEDURE sm( s: SET;  n, m: LONGINT ): LONGINT;  (* shift & mask *)
	BEGIN
		RETURN  S.VAL( LONGINT, S.LSH( s, n )*S.VAL( SET, m ) );
	END sm;


	PROCEDURE IP*( VAR l, r: SET );
	BEGIN
		perm( r, l, 4, 0F0F0F0FH );
		perm( l, r, 16, 0000FFFFH );
		perm( r, l, 2, 33333333H );
		perm( l, r, 8, 00FF00FFH );
		perm( r, l, 1, 55555555H );
	END IP;

	PROCEDURE FP*( VAR l, r: SET );
	BEGIN
		perm( r, l, 1, 55555555H );
		perm( l, r, 8, 00FF00FFH );
		perm( r, l, 2, 33333333H );
		perm( l, r, 16, 0000FFFFH );
		perm( r, l, 4, 0F0F0F0FH );
	END FP;

	PROCEDURE split( s: SET;  VAR i0, i1, i2, i3: LONGINT );   (* split set into 4 index values *)
	BEGIN
		i0 := S.VAL( LONGINT, S.LSH( s, -2 ) ) MOD 40H;
		i1 := S.VAL( LONGINT, S.LSH( s, -10 ) ) MOD 40H;
		i2 := S.VAL( LONGINT, S.LSH( s, -18 ) ) MOD 40H;
		i3 := S.VAL( LONGINT, S.LSH( s, -26 ) ) MOD 40H;
	END split;


	PROCEDURE StringToKey*( CONST str: ARRAY OF CHAR; VAR key: ARRAY OF CHAR );
	VAR i, l, ll, j, k: LONGINT; skey: ARRAY 8 OF SET;  s: SET;  odd: BOOLEAN;
	BEGIN
		FOR i := 0 TO 7 DO  skey[i] := {}  END;
		FOR i := 0 TO LEN( str ) - 1 DO
			l := ORD( str[i] );
			IF i MOD 16 < 8 THEN
				k := i MOD 8;
				skey[k] := skey[k] / S.VAL( SET, l*2 );
			ELSE
				ll := 0; k := 7 - (i MOD 8);
				FOR j := 0 TO 7 DO
					ll := 2 * ll;
					IF ODD( l ) THEN  INC( ll )  END;
					l := l DIV 2
				END;
				skey[k] := skey[k] / S.VAL( SET, ll )
			END
		END;
		(* set odd parity *)
		FOR i := 0 TO 7 DO
			s := skey[i];  odd := FALSE;
			FOR j := 0 TO 7 DO
				IF j IN s THEN  odd := ~odd  END
			END;
			IF ~odd THEN
				IF 0 IN s THEN  EXCL( s, 0 )  ELSE  INCL( s, 0 )  END;
				skey[i] := s
			END;
		END;
		FOR i := 0 TO 7 DO  key[i] := CHR( S.VAL( LONGINT, skey[i] ) )  END
	END StringToKey;

	PROCEDURE Init;
	VAR
		i, j, val: LONGINT;
		r: Files.Reader;
		f: Files.File;
		token: ARRAY 64 OF CHAR;

		PROCEDURE FError;
		BEGIN
			Out.String( "Format error in " );  Out.String( datafile );  Out.String( ",  pos  " );
			Out.Int( r.Pos(), 1 );  Out.Ln
		END FError;

	BEGIN
		f := Files.Old( datafile );
		IF f = NIL THEN
			Out.String( "File '" );  Out.String( datafile );  Out.String( "' not found" );  Out.Ln
		ELSE
			Files.OpenReader( r, f, 0 );  r.SkipWhitespace;  r.Token( token );
			IF token # "des.skb" THEN  FError;  RETURN   END;
			FOR i := 0 TO 7 DO
				FOR j := 0 TO 63 DO
					IF r.GetInteger( val, TRUE ) THEN  skb[i, j] := S.VAL( SET, val )
					ELSE  FError;  RETURN
					END
				END;
			END;
			r.SkipWhitespace;  r.Token( token );
			IF token # "des.SPtrans" THEN  FError;  RETURN   END;
			FOR i := 0 TO 7 DO
				FOR j := 0 TO 63 DO
					IF r.GetInteger( val, TRUE ) THEN  T[i, j] := S.VAL( SET, val )
					ELSE  FError;  RETURN
					END
				END;
			END;
		END
	END Init;

BEGIN
	ASSERT( S.VAL( LONGINT, {0} ) = 1 );
	Init
END CryptoDES.



