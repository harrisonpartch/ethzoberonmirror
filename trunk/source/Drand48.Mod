
MODULE Drand48;	(** AUTOR "G.F.";  PURPOSE "A2 port of the drand48 random generator"; *)


CONST
	B = 10000H;	(* 16-bit barrier *)
	
	X0 = 0330EH;  X1 = 0ABCDH;  X2 = 01234H;
	A0 = 0E66DH;  A1 = 0DEECH;  A2 = 05H;
	
TYPE 
	Pair = RECORD h, l: LONGINT END;	(* unsigned 16-bit values *)
	
	Triple* = ARRAY 3 OF LONGINT;		(* unsigned 16-bit values *)
	Seed16v* = POINTER TO Triple;
	
	Generator* = OBJECT
	VAR
		x, a: Triple; c: LONGINT;
		
		PROCEDURE & Init*;
		BEGIN
			x[0] := X0;  x[1] := X1;  x[2] := X2;  
			a[0] := A0;  a[1] := A1;  a[2] := A2;  
			c := 0BH
		END Init;
		
		
		PROCEDURE Drand48*(): LONGREAL;
		CONST two16m = 1.0D0 / B;
		BEGIN
			Next;  RETURN two16m*(two16m*(two16m*x[0] + x[1]) + x[2])
		END Drand48;
	
		PROCEDURE Lrand48*(): LONGINT;		(* [0 .. 2^31-1] *)
		BEGIN
			Next;  RETURN x[2]*8000H + x[1] DIV 2 MOD 8000H
		END Lrand48;
		
		PROCEDURE Mrand48*(): LONGINT;		(* [0 .. 2^32-1] *)
		BEGIN
			Next;  RETURN x[2]*B + x[1]
		END Mrand48;
		
		PROCEDURE Xrand48*(): HUGEINT;		(* [0 .. 2^48-1] *)
		BEGIN
			Next;  RETURN ASH( LONG( x[2] ), 32 ) + x[1]*B + x[0]
		END Xrand48;
		
		
		PROCEDURE Srand48*( seedval: LONGINT );
		BEGIN
			Seed( X0, seedval MOD B, seedval DIV B  MOD B )
		END Srand48;
		
		PROCEDURE Seed48*( CONST seed16v: ARRAY OF LONGINT ): Seed16v;
		VAR lastx: Seed16v;
		BEGIN
			NEW( lastx );  lastx^ := x;
			Seed( seed16v[0] MOD B, seed16v[1] MOD B, seed16v[2] MOD B );
			RETURN lastx 
		END Seed48;
		
		PROCEDURE Lcong48*( CONST param: ARRAY OF LONGINT );
		BEGIN
			x[0] := param[0] MOD B;  x[1] := param[1] MOD B;  x[2] := param[2] MOD B;
			a[0] := param[3] MOD B;  a[1] := param[4] MOD B;  a[2] := param[5] MOD B;
			c := param[6] MOD B
		END Lcong48;
		
		
		PROCEDURE Seed( x0, x1, x2: LONGINT );
		BEGIN
			x[0] := x0;  x[1] := x1;  x[2] := x2;
			a[0] := A0;  a[1] := A1;  a[2] := A2
		END Seed;
		
		
		PROCEDURE Next;
		VAR p, q, r: Pair;  c0, c1, c2: LONGINT;
		BEGIN
			p := Mul( a[0], x[0] );
			c0 := Addequ( p.h, Addequ( p.l, c ) );
			q := Mul( a[0], x[1] );
			c1 := Addequ( p.h, q.l );
			r := Mul( a[1], x[0] );
			IF p.h + r.l < B THEN  c2 := 0  ELSE  c2 := 1  END;
			x[2] := (c0 + c1 + c2 + q.h + r.h + a[0]*x[2] + a[1]*x[1] + a[2]*x[0]) MOD B;
			x[1] := (p.h + r.l) MOD B;
			x[0] := p.l MOD B
		END Next;
	
	END Generator;


	
	
	PROCEDURE Mul( x, y: LONGINT ): Pair;
	VAR z: Pair;  t: LONGINT;
	BEGIN
		t := x*y;
		z.l := t MOD B;  z.h := t DIV B MOD B;
		RETURN z
	END Mul;
	
	PROCEDURE Addequ( VAR x: LONGINT;  y: LONGINT ): LONGINT;
	BEGIN
		x := x + y;
		IF x < B THEN  RETURN 0  END;
		x := x MOD B;  RETURN 1
	END Addequ;

END Drand48.


