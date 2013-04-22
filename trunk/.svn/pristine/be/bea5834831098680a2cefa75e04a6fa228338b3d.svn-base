(* Aos, Copyright 2001, Pieter Muller, ETH Zurich *)

MODULE DNS;   (** AUTHOR "pjm, mvt, gf"; PURPOSE "DNS client"; *)


IMPORT S := SYSTEM, Out := KernelLog, Unix, IP, Files;

CONST
	(** Error codes *)
	Ok* = 0;  NotFound* = 3601;  BadName* = 3602;
	MaxNofServer* = 10;   (* max. number registered of DNS servers *)
	

TYPE
	Address = ADDRESS;
	Name* = ARRAY 128 OF CHAR;   (* domain or host name type *)
	
	
	Hostent = POINTER TO RECORD
			name		: Address;
			aliases		: Address;
			addrtype	: LONGINT;
			length		: LONGINT;
			addrlist		: Address
		END;

VAR
	(** Local domain name *)
	domain*: Name;
	
	nlib: Address;

	gethostbyaddr		: PROCEDURE {C} ( adr: Address; len, typ: LONGINT ): Hostent;
	gethostbyname		: PROCEDURE {C} ( name: Address ): Hostent;
	gethostname		: PROCEDURE {C} ( name: Address; len: LONGINT ): LONGINT;

	(* Statistic variables *)
	NDNSReceived-, NDNSSent-, NDNSMismatchID-, NDNSError-: LONGINT;

	(** Find the host responsible for mail exchange of the specified domain. *)
	PROCEDURE MailHostByDomain*( CONST domain: ARRAY OF CHAR;  VAR hostname: ARRAY OF CHAR;  VAR res: LONGINT );
	BEGIN
		HALT( 99 );	(* not implemented yet. needed ?? *)
		hostname[0] := 0X
	END MailHostByDomain;

	(** Find the IP address of the specified host. *)

	PROCEDURE HostByName*( CONST hostname: ARRAY OF CHAR;  VAR addr: IP.Adr;  VAR res: LONGINT );
	VAR 
		hostent: Hostent;  
		firstaddrPtr: Address;
	BEGIN {EXCLUSIVE}
		hostent := gethostbyname( ADDRESSOF( hostname ) );
		IF hostent # NIL THEN		
			S.GET( hostent.addrlist, firstaddrPtr );
			IF hostent.length = 4 THEN
				S.MOVE( firstaddrPtr, ADDRESSOF( addr.ipv4Adr ), 4 );
				addr.usedProtocol := IP.IPv4;
			ELSE
				S.MOVE( firstaddrPtr, ADDRESSOF( addr.ipv6Adr ), 16 );
				addr.usedProtocol := IP.IPv6;			
			END;
			res := Ok
		ELSE 
			res := NotFound
		END
	END HostByName;

	(** Find the host name of the specified IP address. *)

	PROCEDURE HostByNumber*( addr: IP.Adr;  VAR hostname: ARRAY OF CHAR;  VAR res: LONGINT );
	VAR 
		hostent: Hostent;
		namePtr: Address;
		ch: CHAR; i: INTEGER;
	BEGIN {EXCLUSIVE}
		IF IP.IsNilAdr( addr ) THEN
			hostname[0] := 0X;  res := BadName;  RETURN
		END;
		IF addr.usedProtocol = IP.IPv4 THEN
			hostent := gethostbyaddr( ADDRESSOF( addr.ipv4Adr ), 4, Unix.PFINET ) 
		ELSE
			hostent := gethostbyaddr( ADDRESSOF( addr.ipv6Adr ), 16, Unix.PFINET6 )
		END;		
		IF hostent # NIL THEN	(* err points to struct hostent *)
			S.GET( hostent.name, namePtr );
			i := 0;
			REPEAT		
				S.GET( namePtr + i, ch ); 
				hostname[i]:= ch;  INC( i )
			UNTIL ch = 0X;
			res := Ok
		ELSE	
			res := NotFound
		END
	END HostByNumber;
	
	(* none portable, Unix ports only! *)
	PROCEDURE GetHostName*( VAR name: ARRAY OF CHAR;  VAR res: LONGINT );
	VAR len, x: LONGINT;
	BEGIN
		x := gethostname( ADDRESSOF( name ), ADDRESSOF( len ) );
		IF x >= 0 THEN  res := Ok  ELSE  res := NotFound  END
	END GetHostName;
	

	PROCEDURE GetLocalDomain( VAR dom: ARRAY OF CHAR );
	VAR f: Files.File;  r: Files.Reader;  buf: ARRAY 256 OF CHAR; ignore: BOOLEAN;
	BEGIN
		f := Files.Old( "/etc/resolv.conf" );
		IF f # NIL THEN
			Files.OpenReader( r, f, 0 ); 
			WHILE r.GetString( buf ) & (buf # "domain") DO  
				IF buf[0] = "#" THEN  r.Ln( buf )  END	(* skip comment *)
			END;
			IF buf = "domain" THEN  ignore := r.GetString( buf );
			ELSE  buf := "unknown.edu"
			END
		ELSE  buf := "unknown.edu"
		END;
		COPY( buf, dom )
	END GetLocalDomain;


BEGIN
	GetLocalDomain( domain );
	NDNSReceived := 0;
	NDNSSent := 0; 
	NDNSMismatchID := 0;
	NDNSError := 0;
	
	IF Unix.version = "Darwin" THEN
		nlib := Unix.libc
	ELSE
		nlib := Unix.Dlopen( "libnsl.so.1", 2 );
		IF nlib = 0 THEN  nlib := Unix.Dlopen( "libnsl.so", 2 )  END;
		IF nlib = 0 THEN  
			Out.String( "Unix.Dlopen( 'libnsl.so' ) failed" );  Out.Ln  
		END;
	END;
	Unix.Dlsym( nlib, "gethostbyaddr", S.VAL( Address, gethostbyaddr ) );
	Unix.Dlsym( nlib, "gethostbyname", S.VAL( Address, gethostbyname ) );
	Unix.Dlsym( nlib, "gethostname", S.VAL( Address, gethostname ) );
END DNS.


