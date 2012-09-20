MODULE CryptoSHA256;	(** AUTHOR "G.F."; PURPOSE "SHA-256"; *)

IMPORT
	S := SYSTEM,  Hashes := CryptoHashes;

CONST
	BlockSize = 64;
	
VAR 
	K256: ARRAY 64 OF LONGINT;
	
	
TYPE
	Context = RECORD
		h: ARRAY 8 OF LONGINT;	(* state *)
		Nl, Nh: LONGINT;
		data: ARRAY BlockSize OF CHAR;	(* pending data *)
		n: LONGINT	(* number of chars in data *)
	END;

	Hash* = OBJECT (Hashes.Hash)
		VAR
			c: Context;

		PROCEDURE &Init*;
		BEGIN
			SetNameAndSize( "sha256", 32 ); 
			initialized := FALSE
		END Init;

		PROCEDURE Initialize*;
		BEGIN
			c.h[0] := 6A09E667H;	c.h[1] := SHORT( 0BB67AE85H );
			c.h[2] := 3C6EF372H;	c.h[3] := SHORT( 0A54FF53AH );
			c.h[4] := 510E527FH;	c.h[5] := SHORT( 09B05688CH );
			c.h[6] := 1F83D9ABH;	c.h[7] := 5BE0CD19H;
			c.Nl := 0;
			c.Nh := 0;
			c.n := 0;
			initialized := TRUE
		END Initialize;

		(** data: value to be hashed *)
		PROCEDURE Update*( CONST data: ARRAY OF CHAR;  pos, len: LONGINT );
			VAR n, i, l: LONGINT;
		BEGIN
			ASSERT( initialized );
			l := c.Nl + len*8;
			IF l < c.Nl THEN INC( c.Nh )  (* overflow *)  END;
			c.Nh := c.Nh + ASH( len, -29 );  c.Nl := l;

			IF c.n > 0 THEN
				IF c.n + len < BlockSize THEN
					i := c.n;  INC( c.n, len );
					WHILE i < c.n  DO  c.data[i] := data[pos];  INC( i ); INC( pos )  END;
					RETURN
				ELSE
					WHILE c.n < BlockSize  DO
						c.data[c.n] := data[pos];  INC( c.n );  INC( pos );  DEC( len )
					END;
					HashContextBlock( c );
				END
			END;

			n := 0;
			WHILE n < len DIV BlockSize  DO  HashBlock( c, data, pos );  INC( n )  END;
			len := len MOD BlockSize;
			WHILE c.n < len  DO c.data[c.n] := data[pos];  INC( c.n );  INC( pos )  END;
		END Update;

		(** get the hashvalue of length SELF.size *)
		PROCEDURE GetHash*( VAR buf: ARRAY OF CHAR;  pos: LONGINT );
			VAR p, i: LONGINT;
		BEGIN
			c.data[c.n] := 80X;  INC( c.n );
			IF c.n > BlockSize - 8 THEN
				WHILE c.n < BlockSize  DO  c.data[c.n] := 0X;  INC( c.n )  END;
				HashContextBlock( c );
			END;
			p := BlockSize - 8;
			WHILE c.n < p  DO  c.data[c.n] := 0X;  INC( c.n )  END;
			int2chars( c.Nh, c.data, p );  int2chars( c.Nl, c.data, p );
			HashContextBlock( c );
			
			FOR i := 0 TO 7 DO  int2chars( c.h[i], buf, pos )  END;
		END GetHash;

	END Hash;



	(* PROCEDURES *******************************************************************************)

	(** get an instance of SHA256 *)
	PROCEDURE NewHash*( ) : Hashes.Hash;
		VAR h: Hash;
	BEGIN
		NEW( h );  RETURN h
	END NewHash;

	PROCEDURE chars2int( CONST buf: ARRAY OF CHAR;  VAR p, int: LONGINT );
	BEGIN
		int :=	ASH( LONG( ORD( buf[p] ) ), 24 ) +
				ASH( LONG( ORD( buf[p + 1] ) ), 16 ) +
				ASH( LONG( ORD( buf[p + 2] ) ), 8 ) +
				ORD( buf[p + 3] );
		INC( p, 4 );
	END chars2int;

	PROCEDURE int2chars( v: LONGINT;  VAR buf: ARRAY OF CHAR;  VAR p: LONGINT );
	VAR i: LONGINT;
	BEGIN
		INC( p, 4 );
		FOR i := 1 TO 4 DO  buf[p - i] := CHR( v MOD 256);  v := v DIV 256  END
	END int2chars;


	PROCEDURE Sigma0Maj( x, y, z: LONGINT ): LONGINT;
	VAR a, b: LONGINT;
	BEGIN 
		a := S.VAL( LONGINT, 
			S.VAL( SET, S.ROT( x , 30 ) ) / S.VAL( SET, S.ROT( x, 19 ) ) / S.VAL( SET, S.ROT( x, 10 ) ) );
		b := S.VAL( LONGINT,
			(S.VAL( SET, x ) * S.VAL( SET, y )) / (S.VAL( SET, x ) * S.VAL( SET, z )) / (S.VAL( SET, y ) * S.VAL( SET, z )) );
		RETURN a + b
	END Sigma0Maj;
	
	PROCEDURE Sigma1Ch( x, y, z: LONGINT ): LONGINT;
	VAR a, b: LONGINT;
	BEGIN 
		a := S.VAL( LONGINT, 
				S.VAL( SET, S.ROT( x , 26 ) ) / S.VAL( SET, S.ROT( x, 21 ) ) / S.VAL( SET, S.ROT( x, 7 ) ) );
		b := S.VAL( LONGINT,
				(S.VAL( SET, x ) * S.VAL( SET, y )) / ((-S.VAL( SET, x )) * S.VAL( SET, z )) );
		RETURN a + b
	END Sigma1Ch;

	PROCEDURE sigma0( x: LONGINT ): LONGINT;
	BEGIN 
		RETURN S.VAL( LONGINT, 
				S.VAL( SET, S.ROT( x , 25 ) ) / S.VAL( SET, S.ROT( x, 14 ) ) / S.VAL( SET, S.LSH( x, -3 ) ) )
	END sigma0;
	
	PROCEDURE sigma1( x: LONGINT ): LONGINT;
	BEGIN 
		RETURN S.VAL( LONGINT, 
				S.VAL( SET, S.ROT( x , 15 ) ) / S.VAL( SET, S.ROT( x, 13 ) ) / S.VAL( SET, S.LSH( x, -10 ) ) )
	END sigma1;
	

	PROCEDURE HashBlock( VAR ctx: Context;  CONST buf: ARRAY OF CHAR;  VAR pos: LONGINT );
	VAR a, b, c, d, e, f, g, h, s0, s1, s, T1, T2, i: LONGINT;
		X: ARRAY 16 OF LONGINT
	BEGIN
		a := ctx.h[0];  b := ctx.h[1];  c := ctx.h[2];  d := ctx.h[3];
		e := ctx.h[4];  f := ctx.h[5];  g := ctx.h[6];  h := ctx.h[7];
			
		FOR i := 0 TO 63 DO
			IF i < 16 THEN
				chars2int( buf, pos, X[i] );
			ELSE
				s0 := sigma0( X[(i + 1) MOD 16] );
				s1 := sigma1( X[(i + 14) MOD 16] );
				s := s0 + s1 + X[(i + 9) MOD 16];
				INC( X[i MOD 16], s );  
			END;
			T1 := X[i MOD 16] + h + Sigma1Ch(e,f,g) + K256[i];
			T2 := Sigma0Maj( a, b, c );
			h := g;  g := f;  f := e;  e := d + T1;
			d := c;  c := b;  b := a;  a := T1 + T2;
		END;
		
		INC( ctx.h[0], a );  INC( ctx.h[1],  b );  INC( ctx.h[2],  c );  INC( ctx.h[3],  d );
		INC( ctx.h[4], e );  INC( ctx.h[5],  f );  INC( ctx.h[6],  g );  INC( ctx.h[7],  h );
	END HashBlock;

	PROCEDURE HashContextBlock( VAR ctx: Context );
	VAR p: LONGINT;
	BEGIN
		p := 0;  HashBlock( ctx, ctx.data, p );  ctx.n := 0
	END HashContextBlock;
	
	
	PROCEDURE InitializeK;
	VAR buf: ARRAY 2048 OF CHAR; i, k: LONGINT;
	
		PROCEDURE Append( CONST str: ARRAY OF CHAR );
		VAR j: LONGINT;  c: CHAR;
		BEGIN
			c := str[0];  j := 1;
			WHILE c # 0X DO  buf[i] := c;  INC( i );  c := str[j];  INC( j )  END
		END Append;
		
		PROCEDURE GetInt(): LONGINT;
		VAR j, d, li: LONGINT; c: CHAR;
		BEGIN
			li := 0;
			FOR j := 0 TO 7 DO
				REPEAT c := buf[i];  INC( i )  UNTIL c > ' ';
				IF (c >= '0') & (c <= '9')  THEN  d := ORD( c ) - ORD( '0' )
				ELSE d := ORD( c ) - ORD( 'A' ) + 10
				END;
				li := 16*li + d
			END;
			RETURN li
		END GetInt
		
	BEGIN
		Append( "428A2F98		71374491	B5C0FBCF	E9B5DBA5  " );
		Append( "3956C25B		59F111F1	923F82A4	AB1C5ED5  " );
		Append( "D807AA98	12835B01	243185BE	550C7DC3  " );
		Append( "72BE5D74	80DEB1FE	9BDC06A7	C19BF174  " );
		Append( "E49B69C1		EFBE4786	0FC19DC6	240CA1CC  " );
		Append( "2DE92C6F		4A7484AA	5CB0A9DC	76F988DA  " );
		Append( "983E5152		A831C66D	B00327C8	BF597FC7  " );
		Append( "C6E00BF3		D5A79147	06CA6351	14292967  " );
		Append( "27B70A85		2E1B2138	4D2C6DFC	53380D13  " );
		Append( "650A7354		766A0ABB	81C2C92E	92722C85  " );
		Append( "A2BFE8A1		A81A664B	C24B8B70	C76C51A3  " );
		Append( "D192E819		D6990624	F40E3585	106AA070  " );
		Append( "19A4C116		1E376C08	2748774C	34B0BCB5  " );
		Append( "391C0CB3		4ED8AA4A	5B9CCA4F	682E6FF3  " );
		Append( "748F82EE		78A5636F	84C87814	8CC70208  " );
		Append( "90BEFFFA		A4506CEB	BEF9A3F7	C67178F2  " );
		i := 0;
		FOR k := 0 TO 63 DO K256[k] := GetInt()  END;
	END InitializeK;

BEGIN
	InitializeK
END CryptoSHA256.