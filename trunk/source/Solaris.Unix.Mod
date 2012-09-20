(* ETH Oberon, Copyright 2000 ETH Zuerich Institut fuer Computersysteme, ETH Zentrum, CH-8092 Zuerich.
Refer to the "General ETH Oberon System Source License" contract available at: http://www.oberon.ethz.ch/ *)

MODULE Unix;   (* Josef Templ, 5.3.90	SVR4 system calls *)  (** Solaris x86 version, non portable *)

(* Linux PPC version	g.f. 18.04.98	*)
(* Linux x86 version	g.f 10.11.99 	*)
(* Solaris x86 version	g.f 16.11.99 	*)
(*	2000.12.17	g.f.	[C] - flag for new ompiler *)
(*	2002.06.27	g.f.	TmDesc fixed,  new: Utime, Mktime *)
(*	2006.07.31	g.f.	shared memory support added *)
(*	2007.04.13	g.f.	Thread priorities added *)
(*	2008.04.25	g.f.	Trap handling unified	*)

IMPORT S := SYSTEM, Glue, Trace;

TYPE
	Address = S.ADDRESS;
	Size = S.SIZE;

CONST
	version* = "Solaris";

	libcname* = "libc.so.1";
	libmname* = "libm.so.1";
	libX11name* = "libX11.so.4";
	libXextname* = "libXext.so.0";

	LittleEndian* = TRUE;   (** byte order of basic types *)
	LsbIs0* = TRUE;   (** bit order of SET type *)

	PageSize* = 4096;	(* least MMU page size *)

	stdin* = 0;  stdout* = 1;  stderr* = 2;

	(** Unix error codes:	*)
	EPERM* = 1;   (* Not super-user *)
	ENOENT* = 2;   (* No such file or directory *)
	ESRCH* = 3;   (* No such process *)
	EINTR* = 4;   (* interrupted system call *)
	EIO* = 5;   (* I/O error *)
	ENXIO* = 6;   (* No such device or address *)
	E2BIG* = 7;   (* Arg list too long *)
	ENOEXEC* = 8;   (* Exec format error *)
	EBADF* = 9;   (* Bad file number *)
	ECHILD* = 10;   (* No children *)
	EAGAIN* = 11;   (* No more processes *)
	ENOMEM* = 12;   (* Not enough core *)
	EACCES* = 13;   (* Permission denied *)
	EFAULT* = 14;   (* Bad address *)
	ENOTBLK* = 15;   (* Block device required *)
	EBUSY* = 16;   (* Mount device busy *)
	EEXIST* = 17;   (* File exists *)
	EXDEV* = 18;   (* Cross-device link *)
	ENODEV* = 19;   (* No such device *)
	ENOTDIR* = 20;   (* Not a directory *)
	EISDIR* = 21;   (* Is a directory *)
	EINVAL* = 22;   (* Invalid argument *)
	ENFILE* = 23;   (* File table overflow *)
	EMFILE* = 24;   (* Too many open files *)
	ENOTTY* = 25;   (* Inappropriate ioctl for device *)
	ETXTBSY* = 26;   (* Text file busy *)
	EFBIG* = 27;   (* File too large *)
	ENOSPC* = 28;   (* No space left on device *)
	ESPIPE* = 29;   (* Illegal seek *)
	EROFS* = 30;   (* Read only file system *)
	EMLINK* = 31;   (* Too many links *)
	EPIPE* = 32;   (* Broken pipe *)
	EDOM* = 33;   (* Math arg out of domain of func *)
	ERANGE* = 34;   (* Math result not representable *)
	ENOMSG* = 42;   (* No message of desired type *)
	EIDRM* = 43;   (* Identifier removed *)
	ECHRNG* = 44;   (* Channel number out of range *)
	EL2NSYNC* = 45;   (* Level 2 not synchronized *)
	EL3HLT* = 46;   (* Level 3 halted *)
	EL3RST* = 47;   (* Level 3 reset *)
	ELNRNG* = 48;   (* Link number out of range *)
	EUNATCH* = 49;   (* Protocol driver not attached *)
	ENOCSI* = 50;   (* No CSI structure available *)
	EL2HLT* = 51;   (* Level 2 halted *)
	EDEADLK* = 35;   (* Deadlock condition. *)
	ENOLCK* = 37;   (* No record locks available. *)

	(* open flags *)
	rdonly* = {};  rdwr* = {1};  creat* = {8};  trunc* = {9};

	(* access modes *)
	rwrwr* = {2, 4, 5, 7, 8};  rwxrwxrwx* = {0..8};
	
	F_OK* = {};  X_Ok* = {0};  W_OK* = {1};  R_OK* = {2};

	(*--------------------------- Threads -------------------------------*)

TYPE
	Thread_t* = LONGINT;
	Mutex_t* = S.ADDRESS;
	Condition_t* = S.ADDRESS;
	
CONST
	(* Thread priorities *)
	ThreadLow* = 0; ThreadNormal* = 20; ThreadHigh* = 100;	
	NumPriorities* = 101;	(* number of priority levels *)


	(*---------------------------- IP -----------------------------------*)

CONST
	(* domain *)
		AFINET* = 2;
		AFINET6* = 26;
		
		PFINET* = AFINET;
		PFINET6* = AFINET6;
		
	(* types of connection *)
		SockStream*	= 2;
		SockDGram*	= 1;
		
	(* protocols *)
		IpProtoUDP*	= 17;
		IpProtoTCP*		=  6;

	(* setsockopt *)
		SoLSocket*		= 0FFFFH;	(* socket option level *)
		SoLinger*		= 80H; 		(* linger (gracefully close the connection)*)
		SoKeepAlive*	= 8;			(* keep connection alive *)
		
	(* ioctl *)
		FioNRead*		= 4004667FH;	(* something to read ? *)
		
	(* recv *)
		MsgPeek*		= 2;
		MsgDontWait*	= 80H;		(* non blocking read *)
		
	(* shutdown *)
		ShutRDWR*	= 2;
		
	SockAddrSizeV4*	= 16;
	SockAddrSizeV6*	= 32;

	(*------------------------------------------------------------------*)


TYPE
	DevT* = LONGINT;

	Status* = RECORD
				dev-		: DevT;
				pad1-		: ARRAY 3 OF LONGINT;
				ino-		: LONGINT;
				mode-		: LONGINT;
				nlink-		: LONGINT;
				uid-		: LONGINT;
				gid-		: LONGINT;
				rdev-		: DevT;
				pad2-		: ARRAY 2 OF LONGINT;
				size-		: LONGINT;
				pad3-		: LONGINT;
				atime-		: Timeval;
				mtime-		: Timeval;
				ctime-		: Timeval;
				blksize-		: LONGINT;
				blocks-		: LONGINT;
				fstype-		: ARRAY 16 OF CHAR;
				pad4-		: ARRAY 8 OF LONGINT;
			END;

	Timeval* = RECORD
				sec*	: LONGINT;
				usec*	: LONGINT
			END;

	TmPtr* = POINTER TO Tm;
	Tm* = RECORD
				sec*, min*, hour*, mday*, mon*, year*, wday*, yday*, isdst*: LONGINT;
				gmtoff*, tmzone*: LONGINT;
			END;

	Tms* = RECORD
				utime*, stime*, cutime*, cstime*: LONGINT
			END;

	Timezone* = RECORD
				minuteswest*, dsttime*: LONGINT
			END;

	Itimerval* = RECORD
				interval*, value*: Timeval
			END;


	FdSet* = ARRAY 32 OF SET;
	FdSetPtr* = POINTER TO FdSet;

	Dirent* = POINTER TO RECORD
				ino-, off-	: LONGINT;
				reclen-		: INTEGER;
				name-		: (*array of*) CHAR;
			END;

	Sigset* = ARRAY 4 OF SET;

	Stack* = RECORD
				sp*		: Address;
				size*	: Size;
				flags*	: SET;
			END;

	Ucontext* = POINTER TO UcontextDesc;
	UcontextDesc* = RECORD
				flags-		: SET;
				link-		: Address;
				sigmask-	: Sigset;
				stack-		: Stack;
				mc-		: McontextDesc;
			END;

	Mcontext* = POINTER TO McontextDesc;
	McontextDesc* = RECORD
				gs-, gsh-	: INTEGER;
				fs-, fsh-	: INTEGER;
				es-, esh-	: INTEGER;
				ds-, dsh-	: INTEGER;
				edi-		: LONGINT;
				esi-		: LONGINT;
				ebp-		: LONGINT;
				esp-		: LONGINT;
				ebx-		: LONGINT;
				edx-		: LONGINT;
				ecx-		: LONGINT;
				eax-		: LONGINT;
				trapno-		: LONGINT;
				err-		: LONGINT;
				eip-		: LONGINT;
				cs-, csh-	: INTEGER;
				eflags-		: LONGINT;
				espatsig-	: LONGINT;
				ss-, ssh-	: INTEGER;
				fpc-		: FPcontextDesc;
			END;

	FPcontext* = POINTER TO FPcontextDesc;
	FPcontextDesc* = RECORD
				i387-	: ARRAY 95 OF LONGINT;
				filler-	: ARRAY 5 OF LONGINT
			END;


VAR
	argc-: LONGINT;  argv-: Address;
	aargc: Address;

	sysinfo-: RECORD
				sysname-, nodename-, release-, version-, machine-: ARRAY 65 OF CHAR;
			END;



	read-			: PROCEDURE {C} ( fd: LONGINT; buf: Address; n: Size ): LONGINT;
	write-			: PROCEDURE {C} ( fd: LONGINT; buf: Address; n: Size ): LONGINT;
	open-			: PROCEDURE {C} ( name: Address;  flags, mode: SET ): LONGINT;
	close-			: PROCEDURE {C} ( fd: LONGINT ): LONGINT;
	lseek-			: PROCEDURE {C} ( fd: LONGINT; offset, origin: Size ): LONGINT;
	fsync-			: PROCEDURE {C} ( fd: LONGINT ): LONGINT;
	ioctl-			: PROCEDURE {C} ( fd: LONGINT; request: LONGINT; arg: Address ): LONGINT;
	unlink-			: PROCEDURE {C} ( name: Address ): LONGINT;
	rename-		: PROCEDURE {C} ( oldname, newname: Address ): LONGINT;
	ftruncate-		: PROCEDURE {C} ( fd: LONGINT;  length: Size ): LONGINT;
	chmod-			: PROCEDURE {C} ( name: Address;  mode: SET ): LONGINT;
	utime-			: PROCEDURE {C} ( fd: LONGINT;  tb: Address ): LONGINT;
	access-			: PROCEDURE {C} ( name: Address;  mode: SET ): LONGINT;
	select-			: PROCEDURE {C} ( width: LONGINT; rd, wr, ex: FdSetPtr;  VAR timeout: Timeval ): LONGINT;

	chdir-			: PROCEDURE {C} ( name: Address ): LONGINT;
	mkdir-			: PROCEDURE {C} ( name: Address;  mode: SET ): LONGINT;
	rmdir-			: PROCEDURE {C} ( path: Address ): LONGINT;

	stat-			: PROCEDURE {C} ( name: Address;  VAR buf: Status ): LONGINT;
	lstat-			: PROCEDURE {C} ( name: Address;  VAR buf: Status ): LONGINT;
	fstat-			: PROCEDURE {C} ( fd: LONGINT;  VAR buf: Status ): LONGINT;

	getpid-			: PROCEDURE {C} ( ): LONGINT;
	getuid-			: PROCEDURE {C} ( ): LONGINT;

	malloc-			: PROCEDURE {C} ( size: Size ): Address;
	valloc-			: PROCEDURE {C} ( size: Size ): Address;
	free-			: PROCEDURE {C} ( p: Address );
	mprotect-		: PROCEDURE {C} ( p: Address; len: Size; prot: LONGINT ): LONGINT;

	alarm-			: PROCEDURE {C} ( ms: LONGINT ): LONGINT;
	setitimer-		: PROCEDURE {C} ( which: LONGINT;  VAR value, ovalue: Itimerval ): LONGINT;
	getitimer-		: PROCEDURE {C} ( which: LONGINT;  VAR value: Itimerval ): LONGINT;

	gettimeofday-	: PROCEDURE {C} ( VAR tv: Timeval;  VAR tz: Timezone ): LONGINT;
	mktime-		: PROCEDURE {C} ( VAR tm: Tm ): LONGINT;
	localtime-		: PROCEDURE {C} ( CONST tv: Timeval ): TmPtr;
	time-			: PROCEDURE {C} ( VAR tv: Timeval ): LONGINT;
	times-			: PROCEDURE {C} ( VAR tms: Tms ): LONGINT;

	system-			: PROCEDURE {C} ( cmd: Address );
	uname-		: PROCEDURE {C} ( utsname: Address ): LONGINT;

	getcwd-		: PROCEDURE {C} ( buf: Address;  len: Size ): LONGINT;
	getenv-		: PROCEDURE {C} ( name: Address ): LONGINT;

	opendir-		: PROCEDURE {C} ( name: Address ): Address;
	readdir-		: PROCEDURE {C} ( dir: Address ): Dirent;
	closedir-		: PROCEDURE {C} ( dir: Address );

	sigsetjmp-		: PROCEDURE {C} ( env: Address;  savemask: LONGINT ): LONGINT;
	siglongjmp-		: PROCEDURE {C} ( env: Address;  val: LONGINT );

	kill-			: PROCEDURE {C} ( pid, sig: LONGINT ): LONGINT;
	exit-			: PROCEDURE {C} ( status: LONGINT );
	perror-			: PROCEDURE {C} ( msg: Address );
	errno-			: PROCEDURE {C} ( ): LONGINT;



	libc-: Address;

	libraryPaths: ARRAY 7 OF ARRAY 32 OF CHAR;
	
	PROCEDURE ModifyContext*( cont: Ucontext;  pc, bp, sp: LONGINT );
	BEGIN
		cont.mc.eip := pc;
		cont.mc.ebp := bp;
		cont.mc.esp := sp;
		cont.mc.espatsig := sp
	END ModifyContext;

	PROCEDURE Perror*( CONST msg: ARRAY OF CHAR );
	BEGIN
		perror( S.ADR( msg ) )
	END Perror;

	PROCEDURE Dlsym*( lib: LONGINT;  CONST sym: ARRAY OF CHAR;  VAR var: Address );
	BEGIN
		var := 0;  Glue.dlsym( lib, S.ADR( sym ), S.ADR( var ) );
		IF var = 0 THEN
			Trace.String( "Unix.Dlsym:  entry '" );  Trace.String( sym );  Trace.String( "' not found" );
			Trace.Ln
		END
	END Dlsym;

	PROCEDURE Dlopen*( CONST libname: ARRAY OF CHAR;  mode: LONGINT ): LONGINT;
	VAR h: LONGINT;  i, j, k: INTEGER;
		p: ARRAY 256 OF CHAR;
	BEGIN
		IF libname[0] = '/' THEN  h := Glue.dlopen( S.ADR( libname ), mode );
		ELSE
			i := 0;  h := 0;
			WHILE (h = 0) & (i <= 6) DO
				COPY( libraryPaths[i], p );  j := 0;
				WHILE p[j] # 0X DO  INC( j )  END;
				p[j] := '/';  k := 0;
				REPEAT  INC( j );  p[j] := libname[k];  INC( k )  UNTIL p[j] = 0X;
				h := Glue.dlopen( S.ADR( p ), mode );  INC( i )
			END
		END;
		IF h = 0 THEN
			Trace.String( "Unix.Dlopen: loading library " );
			Trace.String( libname );  Trace.String( " failed" );  Trace.Ln
		END;
		RETURN h
	END Dlopen;

	PROCEDURE Dlclose*( lib: LONGINT );
	BEGIN
		Glue.dlclose( lib )
	END Dlclose;

	PROCEDURE GetArg*( no: LONGINT;  VAR val: ARRAY OF CHAR );
	VAR ch: CHAR;  adr, i: LONGINT;
	BEGIN
		IF no >= argc THEN  val[0] := 0X
		ELSE
			S.GET( argv + 4*no, adr );  i := 0;
			REPEAT  S.GET( adr, ch );  val[i] := ch;  INC( adr );  INC( i );   UNTIL (ch = 0X) OR (i >= LEN( val ));
		END
	END GetArg;

	PROCEDURE GetArgval*(  CONST argName: ARRAY OF CHAR;  VAR val: ARRAY OF CHAR );
	VAR i: INTEGER;
		buf: ARRAY 40 OF CHAR;
	BEGIN
		i := 1;
		WHILE i < argc - 1 DO
			GetArg( i, buf );
			IF buf = argName THEN  GetArg( i + 1, val );  RETURN   END;
			INC( i )
		END;
		val[0] := 0X
	END GetArgval;

	PROCEDURE getSysinfo;
	VAR res: LONGINT;  p: INTEGER;
		buf: ARRAY 4096 OF CHAR;

		PROCEDURE copy( VAR p: INTEGER;  VAR dest: ARRAY OF CHAR );
		VAR i: INTEGER;
		BEGIN
			WHILE buf[p] <= ' ' DO  INC( p )  END;
			i := 0;
			REPEAT  dest[i] := buf[p];  INC( i );  INC( p )  UNTIL (buf[p - 1] = 0X) OR (i >= LEN( dest ));
			dest[i - 1] := 0X
		END copy;

	BEGIN
		FOR p := 0 TO 4096 - 1 DO  buf[p] := 0X  END;
		res := uname( S.ADR( buf ) );
		p := 0;
		copy( p, sysinfo.sysname );
		copy( p, sysinfo.nodename );
		copy( p, sysinfo.release );
		copy( p, sysinfo.version );
		copy( p, sysinfo.machine );
	END getSysinfo;

BEGIN
	Dlsym( 0, "argc", aargc );  S.GET( aargc, argc );
	Dlsym( 0, "argv", argv );

	libraryPaths[0] := "/usr/lib";
	libraryPaths[1] := "/lib";
	libraryPaths[2] := "/usr/dt/lib";
	libraryPaths[3] := "/usr/openwin/lib";
	libraryPaths[4] := "/usr/local/X11R6/lib";
	libraryPaths[5] := "/usr/local/X11/lib";
	libraryPaths[6] := "/usr/local/lib";


	libc := Dlopen( libcname, 2 );

	Dlsym( libc, "read", S.VAL( Address, read ) );
	Dlsym( libc, "write", S.VAL( Address, write ) );
	Dlsym( libc, "open", S.VAL( Address, open ) );
	Dlsym( libc, "close", S.VAL( Address, close ) );
	Dlsym( libc, "lseek", S.VAL( Address, lseek ) );
	Dlsym( libc, "fsync", S.VAL( Address, fsync ) );
	Dlsym( libc, "ioctl", S.VAL( Address, ioctl ) );
	Dlsym( libc, "unlink", S.VAL( Address, unlink ) );
	Dlsym( libc, "rename", S.VAL( Address, rename ) );
	Dlsym( libc, "ftruncate", S.VAL( Address, ftruncate ) );
	Dlsym( libc, "chmod", S.VAL( Address, chmod ) );
	Dlsym( libc, "utime", S.VAL( Address, utime ) );
	Dlsym( libc, "access", S.VAL( Address, access ) );
	Dlsym( libc, "select", S.VAL( Address, select ) );

	Dlsym( libc, "chdir", S.VAL( Address, chdir ) );
	Dlsym( libc, "mkdir", S.VAL( Address, mkdir ) );
	Dlsym( libc, "rmdir", S.VAL( Address, rmdir ) );

	Dlsym( libc, "stat", S.VAL( Address, stat ) );
	Dlsym( libc, "lstat", S.VAL( Address, lstat ) );
	Dlsym( libc, "fstat", S.VAL( Address, fstat ) );

	Dlsym( libc, "getpid", S.VAL( Address, getpid ) );
	Dlsym( libc, "getuid", S.VAL( Address, getuid ) );

	Dlsym( libc, "alarm", S.VAL( Address, alarm ) );
	Dlsym( libc, "setitimer", S.VAL( Address, setitimer ) );
	Dlsym( libc, "getitimer", S.VAL( Address, getitimer ) );

	Dlsym( libc, "gettimeofday", S.VAL( Address, gettimeofday ) );
	Dlsym( libc, "mktime", S.VAL( Address, mktime ) );
	Dlsym( libc, "localtime", S.VAL( Address, localtime ) );
	Dlsym( libc, "time", S.VAL( Address, time ) );
	Dlsym( libc, "times", S.VAL( Address, times ) );

	Dlsym( libc, "getcwd", S.VAL( Address, getcwd ) );
	Dlsym( libc, "getenv", S.VAL( Address, getenv ) );

	Dlsym( libc, "opendir", S.VAL( Address, opendir ) );
	Dlsym( libc, "readdir", S.VAL( Address, readdir ) );
	Dlsym( libc, "closedir", S.VAL( Address, closedir ) );

	Dlsym( libc, "sigsetjmp", S.VAL( Address, sigsetjmp ) );
	Dlsym( libc, "siglongjmp", S.VAL( Address, siglongjmp ) );

	Dlsym( libc, "malloc", S.VAL( Address, malloc ) );
	Dlsym( libc, "valloc", S.VAL( Address, valloc ) );
	Dlsym( libc, "free", S.VAL( Address, free ) );
	Dlsym( libc, "mprotect", S.VAL( Address, mprotect ) );

	Dlsym( libc, "system", S.VAL( Address, system ) );
	Dlsym( libc, "uname", S.VAL( Address, uname ) );

	Dlsym( libc, "kill", S.VAL( Address, kill ) );
	Dlsym( libc, "exit", S.VAL( Address, exit ) );
	Dlsym( libc, "perror", S.VAL( Address, perror ) );
	Dlsym( libc, "errno", S.VAL( Address, errno ) );


	getSysinfo;
END Unix.