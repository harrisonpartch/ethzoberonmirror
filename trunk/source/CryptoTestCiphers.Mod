MODULE CryptoTestCiphers;	(** AUTHOR "F.N."; PURPOSE "Ciphers Test"; *)

IMPORT
	U := CryptoUtils,	Ciphers := CryptoCiphers, Kernel,	Commands, Out := KernelLog;

	PROCEDURE  Ecb1*(context : Commands.Context);
		VAR
			hex, bindata, binkey, modname: ARRAY 64 OF CHAR; cipher: Ciphers.Cipher;
			keybits: LONGINT;
	BEGIN
		(* read in the parameter *)
		context.arg.SkipWhitespace; context.arg.String(modname);
		context.arg.SkipWhitespace; context.arg.Int(keybits, FALSE);
		(* encryption *)
		cipher := Ciphers.NewCipher( modname );
		hex := "0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF";
		U.Hex2Bin( hex, 0, binkey, 0, 24 );	U.Hex2Bin( hex, 0, bindata, 0, 8 );
		cipher.InitKey( binkey, 0, keybits );
		Out.Ln; Out.String( "*********************************" );
		Out.Ln; Out.String( "Encrypt-Decrypt-Test in ECB-mode: " ); Out.String( cipher.name );
		Out.Ln; Out.String( "Key: " ); U.PrintHex( binkey, 0, keybits DIV 8 );
		Out.Ln; Out.String( "Original: " ); U.PrintHex( bindata, 0, 8 );
		cipher.Encrypt( bindata, 0, 8 );
		Out.Ln; Out.String( "Encrypted: " ); U.PrintHex( bindata, 0, 8 );
		(* decryption *)
		cipher.Decrypt( bindata, 0, 8 );
		Out.Ln; Out.String( "Decrypted: " ); U.PrintHex( bindata, 0, 8 );
	END Ecb1;

	PROCEDURE  Cbc1*(context : Commands.Context);
		VAR
			hex, bindata, binkey, modname, iv: ARRAY 64 OF CHAR; cipher: Ciphers.Cipher;
			keybits: LONGINT;
	BEGIN
		(* read in the parameter *)
		context.arg.SkipWhitespace; context.arg.String(modname);
		context.arg.SkipWhitespace; context.arg.Int(keybits, FALSE);
				(* encryption *)
		cipher := Ciphers.NewCipher( modname );
		hex := "0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF";
		U.Hex2Bin( hex, 0, binkey, 0, 24 );	U.Hex2Bin( hex, 0, bindata, 0, 8 );
		cipher.InitKey( binkey, 0, keybits );
		U.RandomBytes( iv, 0, cipher.blockSize );
		cipher.SetIV( iv, 0 );
		Out.Ln; Out.String( "*********************************" );
		Out.Ln; Out.String( "Encrypt-Decrypt-Test in CBC-mode: " ); Out.String( cipher.name );
		Out.Ln; Out.String( "Key: " ); U.PrintHex( binkey, 0, keybits DIV 8 );
		Out.Ln; Out.String( "Original: " ); U.PrintHex( bindata, 0, 8 );
		cipher.Encrypt( bindata, 0, 8 );
		Out.Ln; Out.String( "Encrypted: " ); U.PrintHex( bindata, 0, 8 );
		(* decryption *)
		cipher.SetIV( iv, 0 );
		cipher.Decrypt( bindata, 0, 8 );
		Out.Ln; Out.String( "Decrypted: " ); U.PrintHex( bindata, 0, 8 );
	END Cbc1;

	(** encrypt input with key (ebc-mode). output is a testvector *)
	PROCEDURE  Ecb2*( context : Commands.Context; modname, input, output, key: ARRAY OF CHAR; datalen, keybits: LONGINT );
		VAR
			cipher: Ciphers.Cipher;
			temp: ARRAY 64 OF CHAR;
	BEGIN
		cipher := Ciphers.NewCipher( modname );
		U.Hex2Bin( key, 0, temp, 0, keybits DIV 8 );
		cipher.InitKey( temp, 0, keybits );
		Out.Ln; Out.String( "*********************************" );
		Out.Ln; Out.String( "Encryption-Test: " ); Out.String( cipher.name );
		Out.Ln; Out.String( "Key: " ); U.PrintHex( temp, 0, keybits DIV 8 );
		U.Hex2Bin( input, 0, temp, 0, datalen );
		Out.Ln; Out.String( "plaintext: " ); U.PrintHex( temp, 0, datalen );
		cipher.Encrypt( temp, 0, datalen );
		Out.Ln; Out.String( "encryption: " ); U.PrintHex( temp, 0, datalen );
		U.Hex2Bin( output, 0, temp, 0, datalen );
		Out.Ln; Out.String( "correct encryption: " ); U.PrintHex( temp, 0, datalen );
	END Ecb2;

	(** encrypt input with key (cbc-mode). output is a testvector *)
	PROCEDURE  Cbc2*(context : Commands.Context; modname, input, output, key, iv: ARRAY OF CHAR; datalen, keybits: LONGINT );
		VAR
			cipher: Ciphers.Cipher;
			temp, temp2: ARRAY 64 OF CHAR;
	BEGIN
		cipher := Ciphers.NewCipher( modname );
		U.Hex2Bin( key, 0, temp, 0, keybits DIV 8 );
		cipher.InitKey( temp, 0, keybits );
		U.Hex2Bin( iv, 0, temp2, 0, cipher.blockSize );
		cipher.SetIV( temp2, 0 );
		Out.Ln; Out.String( "*********************************" );
		Out.Ln; Out.String( "Encryption-Test: " ); Out.String( cipher.name );
		Out.Ln; Out.String( "Key: " ); U.PrintHex( temp, 0, keybits DIV 8 );
		U.Hex2Bin( input, 0, temp, 0, datalen );
		Out.Ln; Out.String( "plaintext: " ); U.PrintHex( temp, 0, datalen );
		cipher.Encrypt( temp, 0, datalen );
		Out.Ln; Out.String( "encryption: " ); U.PrintHex( temp, 0, datalen );
		U.Hex2Bin( output, 0, temp, 0, datalen );
		Out.Ln; Out.String( "correct encryption: " ); U.PrintHex( temp, 0, datalen );
	END Cbc2;

	PROCEDURE MeasureTime*(context : Commands.Context);
		VAR
			buf, key: ARRAY 1024 OF CHAR;
			milliTimer : Kernel.MilliTimer;
			i, j, k, t, keybits: LONGINT;
			c: Ciphers.Cipher;
			modname, mode, iv: ARRAY 64 OF CHAR;
	BEGIN
		(* read in the parameter *)
		context.arg.SkipWhitespace; context.arg.String(modname);
		context.arg.SkipWhitespace; context.arg.String(mode);
		context.arg.SkipWhitespace; context.arg.Int(keybits, FALSE);
		(* measure time *)
		FOR i := 0 TO 1023 DO	buf[i] := 'a'	END;
		c := Ciphers.NewCipher( modname );
		c.InitKey( key, 0, keybits );
		IF mode = "CBC" THEN	c.SetIV( iv, 0 )	END;
		Out.Ln; Out.String( "***********************************" );
		Out.Ln; Out.String( "Encrypting 100 MB with " ); Out.String( c.name );
		Kernel.SetTimer(milliTimer, 0);
		FOR k := 0 TO 9 DO
			Out.String( "." );
			FOR j := 0 TO 9 DO
				FOR i := 0 TO 999 DO	c.Encrypt( buf, 0, 1024 )	END(* 100 MB data *)
			END
		END;
		t := Kernel.Elapsed(milliTimer);
		Out.Int( t, 4 ); Out.String( " ms" ); Out.Ln;
	END MeasureTime;

	PROCEDURE DesEcb2*(context : Commands.Context);
		VAR input, output, key: ARRAY 64 OF CHAR;
	BEGIN
		key := "0123456789ABCDEF";
		input := "4E6F772069732074";		output := "3FA40E8A984D4815";
		Ecb2(context, "CryptoDES", input, output, key, 8, 64 );
	END DesEcb2;

(*	PROCEDURE Des3Ecb2*(context : Commands.Context);
		VAR input, output, key: ARRAY 64 OF CHAR;
	BEGIN
		key := "0123456789ABCDEF11111111111111110000000000000000";
		input := "1111111111111111";		output := "4A5B2F42AA771925";
		Ecb2(context, "CryptoDES3", input, output, key, 8, 192 );
	END Des3Ecb2;  *)
	
	PROCEDURE Des3Ecb2*(context : Commands.Context);
		VAR input, output, key: ARRAY 64 OF CHAR;
	BEGIN
		key := "0123456789ABCDEF23456789ABCDEF01456789ABCDEF0123";
		input := "4E6F772069732074";		output := "314F8327FA7A09A8";
		Ecb2(context, "CryptoDES3", input, output, key, 8, 192 );
	END Des3Ecb2; 

	PROCEDURE  IdeaEcb2*(context : Commands.Context);
		VAR input, output, key: ARRAY 64 OF CHAR;
	BEGIN
		key := "00010002000300040005000600070008";
		input := "0000000100020003";		output := "11FBED2B01986DE5";
		Ecb2(context, "CryptoIDEA", input, output, key, 8, 128 );
	END IdeaEcb2;

	PROCEDURE  Arc4Ecb2*(context : Commands.Context);
		VAR input, output, key: ARRAY 64 OF CHAR;
	BEGIN
		key := "0123456789abcdef";
		input := "0123456789abcfef";		output := "75b7878099e0c596";
		Ecb2(context,  "CryptoARC4", input, output, key, 8, 64 );
	END Arc4Ecb2;

	PROCEDURE  DesCbc2*(context : Commands.Context);
		VAR input, output, key, iv: ARRAY 64 OF CHAR;
	BEGIN
		key := "0123456789ABCDEF";		iv := "0123456789ABCDEF";
		input := "4E6F772069732074";		output := "96C3D4A6DC1C0117";
		Cbc2(context, "CryptoDES", input, output, key, iv, 8, 64 );
	END DesCbc2;

	PROCEDURE  IdeaCbc2*(context : Commands.Context);
		VAR input, output, key, iv: ARRAY 64 OF CHAR;
	BEGIN
		key := "00010002000300040005000600070008";		iv := "0000000000000000";
		input := "0000000100020003";		output := "11FBED2B01986DE5";
		Cbc2(context, "CryptoIDEA", input, output, key, iv, 8, 128 );
	END IdeaCbc2;

END CryptoTestCiphers.


     SystemTools.Free  CryptoTestCiphers CryptoDES3 CryptoDES CryptoIDEA CryptoARC4   ~

     CryptoTestCiphers.DesEcb2 ~
     CryptoTestCiphers.Des3Ecb2 ~
     CryptoTestCiphers.IdeaEcb2 ~
     CryptoTestCiphers.Arc4Ecb2 ~

     CryptoTestCiphers.DesCbc2 ~
     CryptoTestCiphers.IdeaCbc2 ~

     CryptoTestCiphers.Ecb1 CryptoDES 64 ~
     CryptoTestCiphers.Ecb1 CryptoDES3 192 ~
     CryptoTestCiphers.Ecb1 CryptoIDEA 128 ~
     CryptoTestCiphers.Ecb1 CryptoARC4 128 ~

     CryptoTestCiphers.Cbc1 CryptoDES 64 ~
     CryptoTestCiphers.Cbc1 CryptoDES3 192 ~
     CryptoTestCiphers.Cbc1 CryptoIDEA 128 ~

     CryptoTestCiphers.MeasureTime CryptoDES ECB 64 ~
     CryptoTestCiphers.MeasureTime CryptoDES CBC 64 ~
     CryptoTestCiphers.MeasureTime CryptoDES3 ECB 192 ~
     CryptoTestCiphers.MeasureTime CryptoDES3 CBC 192 ~
     CryptoTestCiphers.MeasureTime CryptoAES ECB 128 ~
     CryptoTestCiphers.MeasureTime CryptoAES CBC 128 ~
     CryptoTestCiphers.MeasureTime CryptoIDEA ECB 128 ~
     CryptoTestCiphers.MeasureTime CryptoIDEA CBC 128 ~
     CryptoTestCiphers.MeasureTime CryptoARC4 ECB 128 ~



