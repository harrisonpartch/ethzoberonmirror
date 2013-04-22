MODULE Unix;   (* Josef Templ, 5.3.90	SVR4 system calls *)  (** Linux x86 version, non portable *)

(* Linux PPC version	g.f. 18.04.98	*)
(* Linux x86 version	g.f 10.11.99 	*)
(*	2000.09.19	g.f.	'Sigaltstack' added	*)
(*	2002.06.27	g.f.	TmDesc fixed,  new: Utime, Mktime *)
(*	2006.07.31	g.f.	shared memory support added *)
(*	2007.04.13	g.f.	Thread priorities added *)

IMPORT S := SYSTEM, Glue, Trace;


CONST
	Version* = "Linux";

  	libcname* = "libc.so.6";
	libmname* = "libm.so.6";
	libX11name* = "libX11.so.6";
	libXextname* = "libXext.so.6";

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
	rdonly* = {};  rdwr* = {1};  creat* = {6};  trunc* = {9};

	(* access modes *)
	rwrwr* = {2, 4, 5, 7, 8};  rwxrwxrwx* = {0..8};
	
	F_OK* = {};  X_Ok* = {0};  W_OK* = {1};  R_OK* = {2};

	(*--------------------------- Threads -------------------------------*)

TYPE
	Thread_t* = ADDRESS;
	Mutex_t* = ADDRESS;
	Condition_t* = ADDRESS;
	
CONST
	(* Thread priorities *)
	ThreadLow* = 1; ThreadNormal* = 20; ThreadHigh* = 99;	
	NumPriorities* = 99;	(* number of priority levels *)


	(*---------------------------- IP -----------------------------------*)

CONST
	(* domain *)
		AFINET* = 2;
		AFINET6* = 26;
		
		PFINET* = AFINET;
		PFINET6* = AFINET6;
		
	(* types of connection*)
		SockStream*	= 1;
		SockDGram*	= 2;
		
	(* Protocols *)
		IpProtoUDP*	= 17;
		IpProtoTCP*		=  6;

	(* setsockopt *)
		SoLSocket*		= 1;			(* socket option level *)
		SoLinger* 		= 13; 		(* linger (gracefully close the connection)*)
		SoKeepAlive*	= 9;			(* keep connection alive *)
		SoNoDelay*	= 1;			(* no delay *)

	(* ioctl *)
		FioNRead*		= 541BH;	(* something to read ? *)
		
	(* recv *)
		MsgPeek*		= 2;
		MsgDontWait*	= 40H;		(* non blocking read *)
		
	(* shutdown *)
		ShutRDWR*	= 2;

	SockAddrSizeV4*	= 16;
	SockAddrSizeV6*	= 28;

	(*------------------------------------------------------------------*)


TYPE
	DevT* = HUGEINT;

	Status* = RECORD
				dev-		: DevT;
				unused1-	: LONGINT;
				ino-		: LONGINT;
				mode-		: LONGINT;
				nlink-		: LONGINT;
				uid-		: LONGINT;
				gid-		: LONGINT;
				rdev-		: DevT;
				unused2-	: LONGINT;
				size-		: LONGINT;
				blksize-		: LONGINT;
				blocks-		: LONGINT;
				atime-		: Timeval;
				mtime-		: Timeval;
				ctime-		: Timeval;
				unused-	: ARRAY 2 OF LONGINT;
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

	Tms* = POINTER TO RECORD
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
				ino-, off-	: LONGINT;   (* these may change to HUGEINT in future Linux releases!! *)
				reclen-		: INTEGER;
				typ-		: CHAR;
				name-		: (*array of*) CHAR;
			END;

	Stack* = RECORD
				sp*			: ADDRESS;
				flags*		: SET;
				size*		: SIZE
			END;

	Ucontext* = POINTER TO UcontextDesc;
	UcontextDesc* = RECORD
				flags-		: SET;
				link-		: ADDRESS;
				stack-		: Stack;
				mc-		: McontextDesc
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
				fpc-{UNTRACED}		: FPcontext;
				oldmask-	: LONGINT;
				cr2-		: LONGINT
			END;

	FPcontext* = POINTER TO FPcontextDesc;
	FPcontextDesc* = RECORD
				(* ... *)
			END;


VAR
	argc-: LONGINT;  argv-: ADDRESS;
	aargc: ADDRESS;

	sysinfo-: RECORD
				sysname-, nodename-, release-, version-, machine-: ARRAY 65 OF CHAR;
			END;



	read-			: PROCEDURE {C} ( fd: LONGINT; buf: ADDRESS; n: SIZE ): LONGINT;
	write-			: PROCEDURE {C} ( fd: LONGINT; buf: ADDRESS; n: SIZE ): LONGINT;
	open-			: PROCEDURE {C} ( name: ADDRESS;  flags, mode: SET ): LONGINT;
	close-			: PROCEDURE {C} ( fd: LONGINT ): LONGINT;
	lseek-			: PROCEDURE {C} ( fd: LONGINT; offset, origin: SIZE ): LONGINT;
	fsync-			: PROCEDURE {C} ( fd: LONGINT ): LONGINT;
	ioctl-			: PROCEDURE {C} ( fd: LONGINT; request: LONGINT; arg: ADDRESS ): LONGINT;
	unlink-			: PROCEDURE {C} ( name: ADDRESS ): LONGINT;
	rename-		: PROCEDURE {C} ( oldname, newname: ADDRESS ): LONGINT;
	ftruncate-		: PROCEDURE {C} ( fd: LONGINT;  length: SIZE ): LONGINT;
	chmod-			: PROCEDURE {C} ( name: ADDRESS;  mode: SET ): LONGINT;
	utime-			: PROCEDURE {C} ( fd: LONGINT;  tb: ADDRESS ): LONGINT;
	access-			: PROCEDURE {C} ( name: ADDRESS;  mode: SET ): LONGINT;
	select-			: PROCEDURE {C} ( width: LONGINT; rd, wr, ex: FdSetPtr;  VAR timeout: Timeval ): LONGINT;

	chdir-			: PROCEDURE {C} ( name: ADDRESS ): LONGINT;
	mkdir-			: PROCEDURE {C} ( name: ADDRESS;  mode: SET ): LONGINT;
	rmdir-			: PROCEDURE {C} ( path: ADDRESS ): LONGINT;

	stat-			: PROCEDURE {C} ( name: ADDRESS;  VAR buf: Status ): LONGINT;
	lstat-			: PROCEDURE {C} ( name: ADDRESS;  VAR buf: Status ): LONGINT;
	fstat-			: PROCEDURE {C} ( fd: LONGINT;  VAR buf: Status ): LONGINT;

	getpid-			: PROCEDURE {C} ( ): LONGINT;
	getuid-			: PROCEDURE {C} ( ): LONGINT;

	malloc-			: PROCEDURE {C} ( size: SIZE ): ADDRESS;
	valloc-			: PROCEDURE {C} ( size: SIZE ): ADDRESS;
	free-			: PROCEDURE {C} ( p: ADDRESS );
	mprotect-		: PROCEDURE {C} ( p: ADDRESS; len: SIZE; prot: LONGINT ): LONGINT;

	alarm-			: PROCEDURE {C} ( ms: LONGINT ): LONGINT;
	setitimer-		: PROCEDURE {C} ( which: LONGINT;  VAR value, ovalue: Itimerval ): LONGINT;
	getitimer-		: PROCEDURE {C} ( which: LONGINT;  VAR value: Itimerval ): LONGINT;

	gettimeofday-	: PROCEDURE {C} ( VAR tv: Timeval;  VAR tz: Timezone ): LONGINT;
	mktime-		: PROCEDURE {C} ( VAR tm: Tm ): LONGINT;
	localtime-		: PROCEDURE {C} ( CONST tv: Timeval ): TmPtr;
	time-			: PROCEDURE {C} ( VAR tv: Timeval ): LONGINT;
	times-			: PROCEDURE {C} ( VAR tms: Tms ): LONGINT;

	system-			: PROCEDURE {C} ( cmd: ADDRESS );
	uname-		: PROCEDURE {C} ( utsname: ADDRESS ): LONGINT;

	getcwd-		: PROCEDURE {C} ( buf: ADDRESS;  len: SIZE ): LONGINT;
	getenv-		: PROCEDURE {C} ( name: ADDRESS ): LONGINT;

	opendir-		: PROCEDURE {C} ( name: ADDRESS ): ADDRESS;
	readdir-		: PROCEDURE {C} ( dir: ADDRESS ): Dirent;
	closedir-		: PROCEDURE {C} ( dir: ADDRESS );

	sigsetjmp-		: PROCEDURE {C} ( env: ADDRESS;  savemask: LONGINT ): LONGINT;
	siglongjmp-		: PROCEDURE {C} ( env: ADDRESS;  val: LONGINT );

	kill-			: PROCEDURE {C} ( pid, sig: LONGINT ): LONGINT;
	exit-			: PROCEDURE {C} ( status: LONGINT );
	perror-			: PROCEDURE {C} ( msg: ADDRESS );
	errno-			: PROCEDURE {C} ( ): LONGINT;


	libc-: LONGINT;

	libraryPaths: ARRAY 8 OF ARRAY 32 OF CHAR;


	PROCEDURE ModifyContext*( cont: Ucontext;  pc, bp, sp: LONGINT );
	BEGIN
		cont.mc.eip := pc;
		cont.mc.ebp := bp;
		cont.mc.esp := sp;
		cont.mc.espatsig := sp
	END ModifyContext;

	PROCEDURE Perror*( CONST msg: ARRAY OF CHAR );
	BEGIN
		perror( ADDRESSOF( msg ) )
	END Perror;


	PROCEDURE Dlsym*( lib: LONGINT;  CONST sym: ARRAY OF CHAR;  VAR var: ADDRESS );
	BEGIN
		var := 0;  Glue.dlsym( lib, ADDRESSOF( sym ), ADDRESSOF( var ) );
		IF var = 0 THEN
			Trace.String( "Unix.Dlsym:  entry '" );  Trace.String( sym );  Trace.String( "' not found" );
			Trace.Ln
		END
	END Dlsym;

	PROCEDURE Dlopen*( CONST libname: ARRAY OF CHAR;  mode: LONGINT ): LONGINT;
	VAR h: LONGINT;  i, j, k: INTEGER;
		p: ARRAY 256 OF CHAR;
	BEGIN
		IF libname[0] = '/' THEN  h := Glue.dlopen( ADDRESSOF( libname ), mode );
		ELSE
			i := 0;  h := 0;
			WHILE (h = 0) & (i <= 7) DO
				COPY( libraryPaths[i], p );  j := 0;
				WHILE p[j] # 0X DO  INC( j )  END;
				p[j] := '/';  k := 0;
				REPEAT  INC( j );  p[j] := libname[k];  INC( k )  UNTIL p[j] = 0X;
				h := Glue.dlopen( ADDRESSOF( p ), mode );  INC( i )
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
		res := uname( ADDRESSOF( buf ) );
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

	libraryPaths[0] := "/lib32";
	libraryPaths[1] := "/usr/lib32";
	libraryPaths[2] := "/lib/i386-linux-gnu";
	libraryPaths[3] := "/usr/lib/i386-linux-gnu";
	libraryPaths[4] := "/lib";
	libraryPaths[5] := "/usr/lib";
	libraryPaths[6] := "/usr/X11R6/lib";
	libraryPaths[7] := "/usr/X11/lib";


	libc := Dlopen( libcname, 2 );

	Dlsym( libc, "read", S.VAL( ADDRESS, read ) );
	Dlsym( libc, "write", S.VAL( ADDRESS, write ) );
	Dlsym( libc, "open", S.VAL( ADDRESS, open ) );
	Dlsym( libc, "close", S.VAL( ADDRESS, close ) );
	Dlsym( libc, "lseek", S.VAL( ADDRESS, lseek ) );
	Dlsym( libc, "fsync", S.VAL( ADDRESS, fsync ) );
	Dlsym( libc, "ioctl", S.VAL( ADDRESS, ioctl ) );
	Dlsym( libc, "unlink", S.VAL( ADDRESS, unlink ) );
	Dlsym( libc, "rename", S.VAL( ADDRESS, rename ) );
	Dlsym( libc, "ftruncate", S.VAL( ADDRESS, ftruncate ) );
	Dlsym( libc, "chmod", S.VAL( ADDRESS, chmod ) );
	Dlsym( libc, "utime", S.VAL( ADDRESS, utime ) );
	Dlsym( libc, "access", S.VAL( ADDRESS, access ) );
	Dlsym( libc, "select", S.VAL( ADDRESS, select ) );

	Dlsym( libc, "chdir", S.VAL( ADDRESS, chdir ) );
	Dlsym( libc, "mkdir", S.VAL( ADDRESS, mkdir ) );
	Dlsym( libc, "rmdir", S.VAL( ADDRESS, rmdir ) );

	Dlsym( libc, "stat", S.VAL( ADDRESS, stat ) );
	Dlsym( libc, "lstat", S.VAL( ADDRESS, lstat ) );
	Dlsym( libc, "fstat", S.VAL( ADDRESS, fstat ) );

	Dlsym( libc, "getpid", S.VAL( ADDRESS, getpid ) );
	Dlsym( libc, "getuid", S.VAL( ADDRESS, getuid ) );

	Dlsym( libc, "alarm", S.VAL( ADDRESS, alarm ) );
	Dlsym( libc, "setitimer", S.VAL( ADDRESS, setitimer ) );
	Dlsym( libc, "getitimer", S.VAL( ADDRESS, getitimer ) );

	Dlsym( libc, "gettimeofday", S.VAL( ADDRESS, gettimeofday ) );
	Dlsym( libc, "mktime", S.VAL( ADDRESS, mktime ) );
	Dlsym( libc, "localtime", S.VAL( ADDRESS, localtime ) );
	Dlsym( libc, "time", S.VAL( ADDRESS, time ) );
	Dlsym( libc, "times", S.VAL( ADDRESS, times ) );

	Dlsym( libc, "getcwd", S.VAL( ADDRESS, getcwd ) );
	Dlsym( libc, "getenv", S.VAL( ADDRESS, getenv ) );

	Dlsym( libc, "opendir", S.VAL( ADDRESS, opendir ) );
	Dlsym( libc, "readdir", S.VAL( ADDRESS, readdir ) );
	Dlsym( libc, "closedir", S.VAL( ADDRESS, closedir ) );

	Dlsym( libc, "sigsetjmp", S.VAL( ADDRESS, sigsetjmp ) );
	Dlsym( libc, "siglongjmp", S.VAL( ADDRESS, siglongjmp ) );

	Dlsym( libc, "malloc", S.VAL( ADDRESS, malloc ) );
	Dlsym( libc, "valloc", S.VAL( ADDRESS, valloc ) );
	Dlsym( libc, "free", S.VAL( ADDRESS, free ) );
	Dlsym( libc, "mprotect", S.VAL( ADDRESS, mprotect ) );

	Dlsym( libc, "system", S.VAL( ADDRESS, system ) );
	Dlsym( libc, "uname", S.VAL( ADDRESS, uname ) );

	Dlsym( libc, "kill", S.VAL( ADDRESS, kill ) );
	Dlsym( libc, "exit", S.VAL( ADDRESS, exit ) );
	Dlsym( libc, "perror", S.VAL( ADDRESS, perror ) );
	Dlsym( libc, "errno", S.VAL( ADDRESS, errno ) );


	getSysinfo;
END Unix.