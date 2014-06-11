MODULE CryptoSHA3;	(** AUTHOR "GF"; PURPOSE "SHA-3"; *)
(*
	The Keccak sponge function, designed by Guido Bertoni, Joan Daemen,
	Michaël Peeters and Gilles Van Assche. For more information, feedback or
	questions, please refer to our website: http://keccak.noekeon.org/
*)

IMPORT	Hashes := CryptoHashes, Sponge := CryptoKeccakSponge;

TYPE
	Hash* = OBJECT (Hashes.Hash)
		VAR
			sponge: Sponge.Instance;
			rate, capacity: LONGINT;
			dsuffix: LONGINT;
			
		PROCEDURE &Init*;
		BEGIN
			NEW( sponge );
			rate := Sponge.DefaultRate; 
			capacity := Sponge.DefaultCapacity;
			dsuffix := 7FH;
			Initialize	(* with default properties *)
		END Init;

		PROCEDURE Initialize*;
		BEGIN
			sponge.Initialize( rate, capacity );
			initialized := TRUE
		END Initialize;
		
		PROCEDURE InitializeProperties*( rate, capacity, hashBitSize: LONGINT; delimitedSuffix: CHAR );
		BEGIN
			ASSERT( (rate + capacity = Sponge.Width) & (hashBitSize MOD 8 = 0) );
			ASSERT( delimitedSuffix # 0X );
			SetNameAndSize( "sha3", hashBitSize DIV 8 );
			SELF.rate := rate;  SELF.capacity := capacity;
			dsuffix := ORD( delimitedSuffix );
			
			Initialize;
		END InitializeProperties;


		(** data: value to be hashed *)
		PROCEDURE Update*( CONST data: ARRAY OF CHAR;  pos, len: LONGINT );
		BEGIN
			ASSERT( initialized );	
			sponge.Absorb( data, pos, len )
		END Update;
		
		(** data: value to be hashed *)
		PROCEDURE UpdateBits*( CONST data: ARRAY OF CHAR;  bitLength: LONGINT );
		VAR lastbits, lb: LONGINT; tdata: ARRAY 4 OF CHAR;
		BEGIN
			ASSERT( initialized );
			sponge.Absorb( data, 0, bitLength DIV 8 );
			lastbits := bitLength MOD 8;
			IF lastbits # 0 THEN
				lb := ORD( data[bitLength DIV 8] );
				lb := LSH( lb, -(8 - lastbits) ) + LSH( dsuffix, lastbits );
				IF lb DIV 100H = 0 THEN
					dsuffix := lb
				ELSE
					tdata[0] := CHR( lb MOD 100H );
					sponge.Absorb( tdata, 0, 1 );
					dsuffix := lb DIV 100H MOD 100H
				END
			END
		END UpdateBits;

		(** get the hashvalue of length SELF.size *)
		PROCEDURE GetHash*( VAR buf: ARRAY OF CHAR;  pos: LONGINT );
		BEGIN
			sponge.Squeeze( buf, pos, size )
		END GetHash;

	END Hash;



	(** get an instance of SHA-3 *)
	PROCEDURE NewHash*( ) : Hashes.Hash;
		VAR h: Hash;
	BEGIN
		NEW( h );  RETURN h
	END NewHash;





END CryptoSHA3.