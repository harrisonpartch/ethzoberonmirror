(* Aos Runtime: IP, Copyright 2005, Emil J. Zeller *)

(* Aos, Copyright 2001, Pieter Muller, ETH Zurich *)

MODULE IP; (** AUTHOR "pjm, mvt"; PURPOSE "IP and ARP protocols"; *)

IMPORT SYSTEM, WSock32, Network, Strings, KernelLog;

CONST
	(** Error codes *)
	Ok* = 0;

	(** IP address constants *)
	NilAdrIPv4 = 0;

	(* Comparators for Adr.usedProtocols *)
	IPv4* = 4;
	IPv6* = 6;
	NilAdrIdent = -1;	(* usedProtocol of NilAdrs *)


TYPE

	Adr* = RECORD
		ipv4Adr*: LONGINT;
		ipv6Adr*: ARRAY 16 OF CHAR;
		usedProtocol*: LONGINT;
		data*: LONGINT;
	END; (** An IP Address.	usedProtocol = 0: No protocol yet used
							usedProtocol = IPv4: IPv4 address stored in field ipv4Adr
							usedProtocol = IPv6: IPv6 address stored in field ipv6Adr
							data can be used to store additional informations. I.e. in IPv6 the
							prefix length is stored in the data field *)

	(** IP interface. See note at the end of the module. *)
	Interface* = OBJECT
	VAR
		(** IP addresses of this interface *)
		localAdr-: Adr;

	END Interface;

VAR
	default-: Interface;

	(* IP *)
	NilAdr*: Adr; (* To check if an IP address is NIL use IsNilAdr instead *)

(** Is address not yet specified *)
PROCEDURE IsNilAdr* (adr: Adr): BOOLEAN;
VAR
	isNil: BOOLEAN;
	i: LONGINT;

BEGIN
	CASE adr.usedProtocol OF
		IPv4:
			RETURN (adr.ipv4Adr = NilAdrIPv4)

		|IPv6:
			isNil := TRUE;
			i := 0;
			WHILE ((i<16) & isNil) DO
				IF adr.ipv6Adr[i] # 0X THEN
					isNil := FALSE;
				END;
				INC(i);
			END;
			RETURN isNil;

		|NilAdrIdent:
			RETURN TRUE;

		ELSE
			RETURN TRUE;
	END;
END IsNilAdr;


(* Checks if two addresses are equal *)
PROCEDURE AdrsEqual* (adr1, adr2: Adr): BOOLEAN;
VAR
	equal: BOOLEAN;
	i: LONGINT;

BEGIN
	IF adr1.usedProtocol # adr2.usedProtocol THEN
		RETURN FALSE;
	END;

	CASE adr1.usedProtocol OF
		IPv4:
			IF adr1.ipv4Adr = adr2.ipv4Adr THEN
				RETURN TRUE;
			END;

		|IPv6:
			equal := TRUE;
			i := 0;
			WHILE ((i < 16) & equal) DO
				IF adr1.ipv6Adr[i] # adr2.ipv6Adr[i] THEN
					equal := FALSE;
				END;
				INC(i);
			END;

			IF adr1.data # adr2.data THEN
				equal := FALSE;
			END;

			RETURN equal;

		|NilAdrIdent:
			(* both addresses NIL therefore equal *)
			IF adr2.usedProtocol = NilAdrIdent THEN
				RETURN TRUE;
			ELSE
				RETURN FALSE;
			END;

		ELSE
			RETURN FALSE;
	END;
	RETURN FALSE;
END AdrsEqual;

(** Convert a dotted-decimal string to an ip address. Return NilAdr on failure. *)
PROCEDURE StrToAdr*(CONST s: ARRAY OF CHAR): Adr;
VAR
	i, j, x: LONGINT;
	adr: ARRAY 4 OF CHAR;
	ok: BOOLEAN;
	ip: Adr;
BEGIN
	i := 0; j := 0; x := -1; ok := FALSE;
	LOOP
		IF (s[i] = ".") OR (s[i] = 0X) THEN
			IF (x < 0) OR (x > 255) OR (j = 4) THEN EXIT END;
			adr[j] := CHR(x);
			IF s[i] = 0X THEN ok := (j = 3); EXIT END;
			x := -1; INC(i); INC(j)
		ELSIF (s[i] >= "0") & (s[i] <= "9") THEN
			IF x = -1 THEN x := 0 END;
			x := x*10 + (ORD(s[i])-ORD("0"));
			INC(i)
		ELSE
			EXIT
		END
	END;
	IF ok THEN
		ip.ipv4Adr := SYSTEM.VAL(LONGINT,adr);
		ip.usedProtocol := IPv4;
		RETURN ip;
	ELSE
		RETURN NilAdr;
	END
END StrToAdr;

(** Convert an IP address to a dotted-decimal string. *)
PROCEDURE AdrToStr*(adr: Adr; VAR string: ARRAY OF CHAR);
VAR
	i, j, x: LONGINT;
	a: ARRAY 4 OF CHAR;
	val : LONGINT;
	hexToStr: ARRAY 5 OF CHAR;
	prefixLenStr: ARRAY 64 OF CHAR;
	maxZeroRow: LONGINT;
	currentZeroRow: LONGINT;
	maxZeroStart: LONGINT;
	currentZeroStart: LONGINT;
	lastZero: BOOLEAN;
	lastDPoint: BOOLEAN;
	countEnded: BOOLEAN;

BEGIN
	CASE adr.usedProtocol OF
		IPv4:
			ASSERT(LEN(string) >= 16);	(* enough space for largest result *)
			Network.Put4(a, 0, adr.ipv4Adr);
			i := 0;
			FOR j := 0 TO 3 DO
				x := ORD(a[j]);
				IF x >= 100 THEN string[i] := CHR(ORD("0")+x DIV 100); INC(i) END;
				IF x >= 10 THEN string[i] := CHR(ORD("0")+x DIV 10 MOD 10); INC(i) END;
				string[i] := CHR(ORD("0")+x MOD 10); INC(i);
				IF j = 3 THEN string[i] := 0X ELSE string[i] := "." END;
				INC(i)
			END

		|IPv6:
			FOR i := 0 TO (LEN(adr.ipv6Adr) -1) BY 2 DO
				(* simple version *)
				val :=  ORD(adr.ipv6Adr[i]) * 256;
				val := val + ORD(adr.ipv6Adr[i+1]);
				Strings.IntToHexStr (val, 3, hexToStr);

				(* Delete leading zeros *)
				WHILE (hexToStr[0] = "0") & (hexToStr[1] # 0X) DO
					Strings.Delete(hexToStr, 0, 1);
				END;
				Strings.Append (string, hexToStr);

				IF i # (LEN(adr.ipv6Adr) - 2) THEN
					Strings.Append (string, ":");
				END;
			END;

			(* replace longest row of zeros with :: *)
			maxZeroRow := 0;
			currentZeroRow := 0;
			maxZeroStart := 0;
			currentZeroStart := 0;
			i := 0;
			lastZero := FALSE;
			lastDPoint := TRUE;
			countEnded :=TRUE;

			WHILE string[i] # 0X DO
				IF string[i] = "0" THEN
					IF lastDPoint THEN
						INC(currentZeroRow);
						lastZero := TRUE;
						lastDPoint := FALSE;
						IF countEnded THEN
							currentZeroStart := i;
							countEnded := FALSE;
						END;
					END;
				ELSIF string[i] = ":" THEN
					lastDPoint := TRUE;
					IF lastZero THEN
						lastZero := FALSE;
					END;
				ELSE
					IF lastDPoint THEN
						lastDPoint := FALSE;
						countEnded := TRUE;
						IF currentZeroRow > maxZeroRow THEN
							maxZeroRow := currentZeroRow;
							maxZeroStart := currentZeroStart;
						END;
					END;
				END;

				INC(i);
			END;

			IF ~countEnded THEN
				IF currentZeroRow > maxZeroRow THEN
					maxZeroRow := currentZeroRow;
					maxZeroStart := currentZeroStart;
				END;
			END;
			IF maxZeroRow # 0 THEN
				(* write a :: *)
				IF maxZeroStart = 0 THEN
					string[0] := ":";
					i := 1;
					WHILE ((string[i] # 0X) & ~((string[i] # "0") & (string[i] # ":"))) DO INC(i); END;
					IF string[i] = 0X THEN
						string := "::";
					ELSE
						Strings.Delete(string, 1, i-2);
					END;
				ELSE
					i := maxZeroStart;
					WHILE ((string[i] = "0") OR (string[i] = ":")) DO INC(i); END;
					IF string[i] = 0X THEN
						string[maxZeroStart] := ":";
						string[maxZeroStart+1] := 0X;
					ELSE
						Strings.Delete(string, maxZeroStart, i - maxZeroStart - 1);
					END;
				END;
			END;

			IF adr.data # 0 THEN
				(* write prefix *)
				Strings.IntToStr(adr.data, prefixLenStr);
				Strings.Append (string, "/");
				Strings.Append (string, prefixLenStr);
			END;

		ELSE
			IF IsNilAdr (adr) THEN
				string := "";
			END;
	END;
END AdrToStr;

	(** Convert a IP address from an array [ofs..ofs+x] to an
	Adr-type variable.
	Example for IPv4:
	If the LSB (least significant byte) is stored the the beginning [ofs],
	LSBfirst must be set to TRUE.
		(address "a.b.c.d" is stored as [d,c,b,a])
	If the LSB is stored at the end [ofs+3], LSBfirst must be set to FALSE.
		(address "a.b.c.d" is stored as [a,b,c,d])
*)
PROCEDURE ArrayToAdr*(CONST  array: ARRAY OF CHAR; ofs, protocol: LONGINT; LSBfirst: BOOLEAN): Adr;
VAR
	adr: Adr;
	i, swapTemp: LONGINT;
BEGIN
	ASSERT((protocol = 4) OR (protocol = 6));

	IF protocol = IPv4 THEN  (* index check *)
		IF ~(ofs + 4 <= LEN(array)) THEN
			RETURN NilAdr;
		END;

		SYSTEM.MOVE(ADDRESSOF(array[ofs]), ADDRESSOF(adr.ipv4Adr), 4);
		IF LSBfirst THEN
			SwapEndian(adr.ipv4Adr);
		END;
		adr.usedProtocol := IPv4;

	ELSIF protocol = IPv6 THEN
		IF ~(ofs + 16 <= LEN(array)) THEN
			RETURN NilAdr;
		END;

		SYSTEM.MOVE(ADDRESSOF(array[ofs]), ADDRESSOF(adr.ipv6Adr), 16);
		IF LSBfirst THEN
			FOR i := 0 TO 3 DO
				SYSTEM.MOVE(ADDRESSOF(adr.ipv6Adr[i*4]), ADDRESSOF(swapTemp), 4);
				SwapEndian(swapTemp);
				SYSTEM.MOVE(ADDRESSOF(swapTemp), ADDRESSOF(adr.ipv6Adr[i*4]), 4);
			END;
		END;
		adr.usedProtocol := IPv6;
	ELSE
		RETURN NilAdr;
	END;
	RETURN adr;
END ArrayToAdr;


(** Convert an Adr-type variable  into an array [ofs..ofs+x]
	Example in IPv4:
	If the LSB (least significant byte) should be stored the the
	beginning [ofs], LSBfirst must be set to TRUE.
		(address "a.b.c.d" is stored as [d,c,b,a])
	If the LSB should be stored at the end [ofs+3], LSBfirst must be set to FALSE.
		(address "a.b.c.d" is stored as [a,b,c,d])
*)
PROCEDURE AdrToArray*(adr: Adr; CONST array: ARRAY OF CHAR; ofs: LONGINT; LSBfirst: BOOLEAN);
VAR
	tempAdr: Adr;
	i, swapTemp: LONGINT;

BEGIN
	tempAdr := adr;

	CASE adr.usedProtocol OF
		IPv4:
			IF ~(ofs+4 <= LEN(array)) THEN
				tempAdr := NilAdr;
			END;

			IF LSBfirst THEN
				SwapEndian(tempAdr.ipv4Adr);
			END;
			SYSTEM.MOVE(ADDRESSOF(tempAdr.ipv4Adr), ADDRESSOF(array[ofs]), 4);

		| IPv6:
			IF ~(ofs + 16 <= LEN(array)) THEN
				tempAdr := NilAdr;
			END;

			IF LSBfirst THEN
				FOR i := 0 TO 3 DO
					SYSTEM.MOVE(ADDRESSOF(tempAdr.ipv6Adr[i*4]), ADDRESSOF(swapTemp), 4);
					SwapEndian(swapTemp);
					SYSTEM.MOVE(ADDRESSOF(swapTemp), ADDRESSOF(tempAdr.ipv6Adr[i*4]), 4);
				END;
			END;
			SYSTEM.MOVE(ADDRESSOF(adr.ipv6Adr), ADDRESSOF(array[ofs]), 16);
	ELSE
	END;
END AdrToArray;

(** Return the interface on which packets with "dst" address should be sent. Return NIL if no interface matches. *)
PROCEDURE InterfaceByDstIP*(dst: Adr): Interface;
BEGIN
	RETURN default
END InterfaceByDstIP;

PROCEDURE Init;
	VAR name: ARRAY 256 OF CHAR; res: LONGINT; hint: WSock32.addrinfo; ai: WSock32.Paddrinfo;
BEGIN
	KernelLog.String("IP.Init. Hostname ");
	res := WSock32.gethostname(name, 256);
	IF res = 0 THEN
		KernelLog.String("="); KernelLog.String(name)
	ELSE
		KernelLog.String("failed "); KernelLog.Int(res, 0);KernelLog.Ln;
		RETURN
	END;
	KernelLog.String(", IP ");
	hint.aiFlags := {};
	hint.aiFamily := WSock32.AFINet;
	hint.aiSocktype := WSock32.SockStream;
	hint.aiProtocol := WSock32.IPProtoTCP;
	hint.aiCanonname := 0;
	hint.aiAddr := NIL;
	hint.aiNext := NIL;
	NilAdr.usedProtocol := IPv4;
	(*ALEX 2005.11.25 for win2k*)
	IF WSock32.getaddrinfo # NIL THEN
		res := WSock32.getaddrinfo(name, NIL, hint, ai);
		IF (res = 0) & (ai # NIL) THEN
			KernelLog.String("=");
			IF (ai.aiFamily = WSock32.AFINet) & (ai.aiAddrlen = SIZEOF(WSock32.sockaddrIn)) & (ai.aiAddr.sinFamily = WSock32.AFINet) THEN
				NEW(default);
				default.localAdr.usedProtocol := IPv4;
				default.localAdr.ipv4Adr :=  ai.aiAddr.sinAddr; (* WSock32.ntohl(ai.aiAddr.sinAddr);*)
				AdrToStr(default.localAdr, name); KernelLog.String(name)
			ELSE
				KernelLog.String(" failed.")
			END;

			WSock32.freeaddrinfo(ai)

		ELSE
			KernelLog.String("failed: "); KernelLog.Int(res, 0)
		END;
		KernelLog.Ln()
	ELSE KernelLog.String("failed because getaddrinfo was not found!"); KernelLog.Ln
	END
END Init;

(* Swap internal representation of an IP address from big to little endian or vice versa. *)
PROCEDURE -SwapEndian(VAR adr: LONGINT);
CODE {SYSTEM.i386}
	POP EAX
	MOV ECX, [EAX]
	XCHG CL, CH
	ROL ECX, 16
	XCHG CL, CH
	MOV [EAX], ECX
END SwapEndian;

BEGIN
	default := NIL; Init()
END IP.
