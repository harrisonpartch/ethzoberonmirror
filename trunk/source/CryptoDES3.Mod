
MODULE CryptoDES3;   (** AUTHOR "G.F."; PUROSE "Triple DES Cipher";	 *)

(*  based on  POLARSSL des.c *)

IMPORT Ciphers := CryptoCiphers, U := CryptoUtils, DES := CryptoDES, S := SYSTEM;

	
	
TYPE
	Cipher* = OBJECT (Ciphers.Cipher)
			VAR ske, skd: ARRAY 96 OF SET; ski: LONGINT;
				ivx, ivy: SET;

				PROCEDURE InitKey*( CONST src: ARRAY OF CHAR;  pos: LONGINT;  keybits: LONGINT );
				VAR X, Y: SET;  i: LONGINT;
				BEGIN
					ASSERT( keybits = 192 );
					InitKey^( src, pos, 64 );
					
					X := U.SetFromBufferBE( src, pos );  Y := U.SetFromBufferBE( src, pos + 4 );
					DES.ComputeSubkeys( X, Y, ske, 0 );
					
					X := U.SetFromBufferBE( src, pos + 8 );  Y := U.SetFromBufferBE( src, pos + 12 );
					DES.ComputeSubkeys( X, Y, skd, 32 );
					
					X := U.SetFromBufferBE( src, pos + 16);  Y := U.SetFromBufferBE( src, pos + 20 );
					DES.ComputeSubkeys( X, Y, ske, 64 );
					
					FOR i := 0 TO 30 BY 2 DO
						skd[i + 0] := ske[94 - i];
						skd[i + 1] := ske[95 - i];
						
						ske[i + 32] := skd[62 - i];
						ske[i + 33] := skd[63 - i];
						
						skd[i + 64] := ske[30 - i];
						skd[i + 65] := ske[31 - i]
					END
				END InitKey;

				PROCEDURE SetIV*( CONST src: ARRAY OF CHAR;  p: LONGINT );
				BEGIN
					SetIV^( src, p );   (* set mode *)
					ivx := U.SetFromBufferBE( src, p );  ivy := U.SetFromBufferBE( src, p+4 )
				END SetIV;

				PROCEDURE Encrypt*( VAR buf: ARRAY OF CHAR;  ofs, len: LONGINT );
				VAR i, r: LONGINT;  X, Y: SET;
				BEGIN
					ASSERT( isKeyInitialized );
					ASSERT( len MOD blockSize = 0 );   (* padding must have been added *)
					i := 0;
					WHILE i < len DO
						X := U.SetFromBufferBE( buf, ofs + i );  Y := U.SetFromBufferBE( buf, ofs + i + 4 );
						IF mode = Ciphers.CBC THEN  X := X / ivx;  Y := Y / ivy   END;

						DES.IP( X, Y );
						ski := 0;
						FOR r := 0 TO 7 DO  
							RoundE( Y, X );
							RoundE( X, Y );
						END;
						FOR r := 0 TO 7 DO  
							RoundE( X, Y );
							RoundE( Y, X );
						END;
						FOR r := 0 TO 7 DO  
							RoundE( Y, X );
							RoundE( X, Y );
						END;
						DES.FP( Y, X );
						
						U.SetToBufferBE( Y, buf, ofs + i );   U.SetToBufferBE( X, buf, ofs + i + 4); 
						IF mode = Ciphers.CBC THEN  ivx := Y;  ivy := X  END;
						INC( i, blockSize )
					END
				END Encrypt;

				PROCEDURE Decrypt*( VAR buf: ARRAY OF CHAR;  ofs, len: LONGINT );
				VAR i, r: LONGINT;  X, Y, X0, Y0: SET;
				BEGIN
					ASSERT( isKeyInitialized );
					ASSERT( len MOD blockSize = 0 );   (* padding must have been added *)
					i := 0;
					WHILE i < len DO
						X := U.SetFromBufferBE( buf, ofs + i );  Y := U.SetFromBufferBE( buf, ofs + i + 4 );
						IF mode = Ciphers.CBC THEN  X0 := X;  Y0 := Y  END;
						
						DES.IP( X, Y );
						ski := 0;
						FOR r := 0 TO 7 DO  
							RoundD( Y, X );
							RoundD( X, Y );
						END;
						FOR r := 0 TO 7 DO  
							RoundD( X, Y );
							RoundD( Y, X );
						END;
						FOR r := 0 TO 7 DO  
							RoundD( Y, X );
							RoundD( X, Y );
						END;
						DES.FP( Y, X );
						
						IF mode = Ciphers.CBC THEN  
							Y := Y / ivx;  X := X / ivy  ; 
							ivx := X0;  ivy := Y0  
						END;
						U.SetToBufferBE( Y, buf, ofs + i );   U.SetToBufferBE( X, buf, ofs + i + 4); 
						INC( i, blockSize )
					END
				END Decrypt;


				PROCEDURE RoundE*( VAR x, y: SET );
				VAR t: LONGINT;
				BEGIN
					t := S.VAL( LONGINT, ske[ski] / x );  INC(ski );
					y := y / 
						DES.sb8[t MOD 40H] / 
						DES.sb6[t DIV 100H MOD 40H] /
						DES.sb4[t DIV 10000H MOD 40H] / 
						DES.sb2[t DIV 1000000H MOD 40H];
					t := S.VAL( LONGINT, ske[ski] / ROT( x, -4 ) );  INC( ski );
					y := y / 
						DES.sb7[t MOD 40H] / 
						DES.sb5[t DIV 100H MOD 40H] /
						DES.sb3[t DIV 10000H MOD 40H] / 
						DES.sb1[t DIV 1000000H MOD 40H]
				END RoundE;
				
				PROCEDURE RoundD*( VAR x, y: SET );
				VAR t: LONGINT;
				BEGIN
					t := S.VAL( LONGINT, skd[ski] / x );  INC( ski );
					y := y / 
						DES.sb8[t MOD 40H] / 
						DES.sb6[t DIV 100H MOD 40H] /
						DES.sb4[t DIV 10000H MOD 40H] / 
						DES.sb2[t DIV 1000000H MOD 40H];
					t := S.VAL( LONGINT, skd[ski] / ROT( x, -4 ) );  INC(ski );
					y := y / 
						DES.sb7[t MOD 40H] / 
						DES.sb5[t DIV 100H MOD 40H] /
						DES.sb3[t DIV 10000H MOD 40H] / 
						DES.sb1[t DIV 1000000H MOD 40H]
				END RoundD;

				PROCEDURE & Init*;
				BEGIN
					SetNameAndBlocksize( "3des", 8 );
				END Init;

			END Cipher;
			


	PROCEDURE NewCipher*( ): Ciphers.Cipher;
	VAR cipher: Cipher;
	BEGIN
		NEW( cipher );  RETURN cipher
	END NewCipher;


END CryptoDES3.

