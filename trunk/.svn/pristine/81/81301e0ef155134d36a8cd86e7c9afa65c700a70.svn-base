/*------------------------------------------------------
 * Oberon Boot File Loader RC, JS 27.4.93/2.12.93, HP-UX 9.0 Version
 *
 * Oberon Boot File Loader for Linux
 * derived from HP and Windows Boot Loader
 * MAD, 23.05.94
 * PR,  01.02.95  support for sockets added
 * PR,  05.02.95  support for V24 added
 * PR,  23.12.95  migration to shared ELF libraries
 * g.f. 01.11.99  added InstallTrap
 *		  added Threads support
 *		  removed cmd line parameter evaluation
 * g.f. 22.11.04  call to mprotect added
 * g.f. 03.04.07  Darwin/Intel version
 *
 *-----------------------------------------------------------*/

#ifdef DARWIN
#  define	__ENVIRONMENT_MAC_OS_X_VERSION_MIN_REQUIRED__	1059
#endif

#include <sys/types.h>
#include <fcntl.h>
#include <dlfcn.h>
#include <unistd.h>
#include <stdlib.h>
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <sys/stat.h>
#include <setjmp.h>	
#ifdef DARWIN
#  include <sys/ucontext.h>
#  include <sys/_types.h>
#endif
#include <signal.h>
#include <limits.h>
#include "Threads.h"
#include <sys/mman.h>
#include <X11/Xlib.h>


typedef unsigned long	u_long;
typedef void * 	Address;

typedef void (*OberonProc)();

FILE *fd;
char *AOSPATH;
char path[4096];
char *dirs[255];
char fullname[512];
int nofdir;
char defaultpath[] = ".:/usr/aos/obj:/usr/aos/system";
#ifdef SOLARIS
  char bootname[64] = "SolarisAosCore";
#endif
#ifdef LINUX
  char bootname[64] = "LinuxAosCore";
#endif
#ifdef DARWIN
  char bootname[64] = "DarwinAosCore";
#endif
size_t heapSize;
size_t codeSize;
Address heapAdr;
int Argc;
char **Argv;
int debug;
int suid_root;

static stack_t sigstk;

#define BLSIZE	4096
#define SIGSTACKSIZE 32*BLSIZE

typedef	void(*trap_t)(long, void*, void*, int);

static trap_t	AosTrap;


static void sighandler( int sig, void *scp, void *ucp ) {
	
	if (debug | (AosTrap == NULL)) {
	    printf("\nhandler for signal %d got called, ucp = %x\n", sig, ucp);
	    if (AosTrap == NULL) exit(1);
	}
	AosTrap(0, ucp, scp, sig); /* rev. order: Oberon <--> C */
}


static void installHandler(int sig) {
	struct sigaction act;
	sigset_t mask;
	sigemptyset(&mask);
	act.sa_mask = mask;
	act.sa_flags =  SA_SIGINFO|SA_ONSTACK|SA_NODEFER;
#ifdef LINUX
	act.sa_handler = (__sighandler_t)sighandler;
#else
	act.sa_handler = sighandler;
#endif
	if (sigaction( sig, &act, NULL ) != 0) {
		perror("sigaction");
	}
}


void InitSignalHandler() {
	int i;
	
	for (i = 1; i <= 15; i++) {
	     if (i != 9) installHandler( i );
	}
}


static void InstallTrap(trap_t p) {
	
	if (debug)
		printf("Installing Aos Trap\n");
	AosTrap = p;
}


void SetSigaltstack() {

	if (sigaltstack(&sigstk, NULL) < 0)
		perror("sigaltstack");
}


static void CreateSignalstack() {
	sigstk.ss_sp = mmap( NULL, SIGSTACKSIZE, 
			     PROT_READ | PROT_WRITE, 
			     MAP_PRIVATE | MAP_ANON, 
			     -1, 0);
        if (sigstk.ss_sp == MAP_FAILED){
		printf("mmap for signalstack failed\n" );
		exit( 1 );
	}
	sigstk.ss_size = SIGSTACKSIZE;
	sigstk.ss_flags = 0;
	if (debug)
		printf( "Signalstack created [%x ... %x]\n", 
	 	        sigstk.ss_sp, sigstk.ss_sp + SIGSTACKSIZE );
	SetSigaltstack();
}



void* o_dlopen(char *lib, int mode) {
    void* handle;

    if (debug&1) printf("o_dlopen: %s\n", lib);
    if ((handle = dlopen(lib, mode)) == NULL) {
        if (debug&1)
	    printf("o_dlopen: %s not loaded, error = %s\n", lib, dlerror());
    }
    if (debug&1) printf("o_dlopen: handle = %x\n", handle);

    return handle;
}

void o_dlclose(void* handle)	/* not necessary */
{
  dlclose(handle);
}

static int o_errno() {

	return errno;
}


int o_stat(char* name, void* buf) {
	return stat(name, (struct stat *) buf);
}

int o_lstat(char* name, void* buf) {
	return lstat(name, (struct stat *) buf);
}

int o_fstat(int fd, void* buf) {
	return fstat(fd, (struct stat *) buf);
}

int o_open(char* name, int flags, int mode) {
	return open(name, flags, mode);
}

void *o_malloc( long size ) {
	return malloc( size );
}

void *o_memalign( long alignment, long size ) {
	return calloc( (size + alignment - 1)/alignment, alignment );
}

void *o_calloc( long nelem, long elsize ) {
	return calloc( nelem, elsize );
}

int o_mprotect( void* addr, long len, int prot ) {
	return mprotect( addr, len, prot );
}

int o_lseek( int fd, long pos, int whence ) {
	return lseek( fd, pos, whence );
}

int o_cout( char c ) {
	printf( "%c", c );
}


static void (*oberonXErrorHandler) (long p4, long p3, long err, long displ );
static void (*oberonXIOErrorHandler) (long p4, long p3, long p2, long displ );

static int X11ErrorHandler( Display *d, XErrorEvent *err ) {
	printf( "X11ErrorHandler called\n" );
	oberonXErrorHandler( 0, 0, (long)err, (long)d );
}


static int X11IOErrorHandler( Display *d ) {
	printf( "X11IOErrorHandler called\n" );
	oberonXIOErrorHandler( 0, 0, 0, (long)d );
}


void SetupXErrHandlers( void* XE, void* XIOE ) {
	
	if (debug)
		printf( "Setup X11 ErrorHandlers\n" );
	oberonXErrorHandler = XE;
	oberonXIOErrorHandler = XIOE;
	
	XSetErrorHandler(X11ErrorHandler);
	XSetIOErrorHandler(X11IOErrorHandler);	
}


void o_dlsym(void* handle, char* symbol, void** adr)
{
  if (debug==(-1)) printf("o_dlsym: %x %s\n", handle, symbol);
  
  if      (strcmp("dlopen",		symbol) == 0) *adr = o_dlopen;
  else if (strcmp("dlclose",		symbol) == 0) *adr = o_dlclose;
  else if (strcmp("debug",		symbol) == 0) *(int*)adr = debug;
  else if (strcmp("heapAdr",		symbol) == 0) *adr = heapAdr;
  else if (strcmp("heapSize",		symbol) == 0) *(size_t*)adr = heapSize;
  else if (strcmp("argc",		symbol) == 0) *adr = &Argc;
  else if (strcmp("argv",		symbol) == 0) *adr = Argv;
  else if (strcmp("errno",		symbol) == 0) *adr = o_errno;
  else if (strcmp("cout",		symbol) == 0) *adr = o_cout;
  
  else if (strcmp("open",		symbol) == 0) *adr = o_open;
  else if (strcmp("stat",		symbol) == 0) *adr = o_stat;
  else if (strcmp("lstat",		symbol) == 0) *adr = o_lstat;
  else if (strcmp("fstat",		symbol) == 0) *adr = o_fstat;
  else if (strcmp("lseek",		symbol) == 0) *adr = o_lseek;

  else if (strcmp("malloc",		symbol) == 0) *adr = o_malloc;
  else if (strcmp("calloc",		symbol) == 0) *adr = o_calloc;
  else if (strcmp("memalign",		symbol) == 0) *adr = o_memalign;
  else if (strcmp("mprotect",		symbol) == 0) *adr = o_mprotect;

  else if (strcmp("InstallTrap",	symbol) == 0) *adr = InstallTrap;
  else if (strcmp("InitXErrH", 		symbol) == 0) *adr = SetupXErrHandlers;
#ifdef LINUX
  else if (strcmp("sigsetjmp",		symbol) == 0) *adr = __sigsetjmp;
  else if (strcmp("setjmp",		symbol) == 0) *adr = __sigsetjmp;
#endif
  else if (strcmp("mtxInit",   		symbol) == 0) *adr = o_mtxInit;
  else if (strcmp("mtxDestroy", 	symbol) == 0) *adr = o_mtxDestroy;
  else if (strcmp("mtxLock",    	symbol) == 0) *adr = o_mtxLock;
  else if (strcmp("mtxUnlock",  	symbol) == 0) *adr = o_mtxUnlock;
  else if (strcmp("conInit",  		symbol) == 0) *adr = o_conInit;
  else if (strcmp("conDestroy", 	symbol) == 0) *adr = o_conDestroy;
  else if (strcmp("conWait",  		symbol) == 0) *adr = o_conWait;
  else if (strcmp("conSignal",  	symbol) == 0) *adr = o_conSignal;
  else if (strcmp("thrStart",		symbol) == 0) *adr = o_thrStart;
  else if (strcmp("thrThis",		symbol) == 0) *adr = o_thrThis;
  else if (strcmp("thrSleep",		symbol) == 0) *adr = o_thrSleep;
  else if (strcmp("thrYield",		symbol) == 0) *adr = o_thrYield;
  else if (strcmp("thrExit",		symbol) == 0) *adr = o_thrExit;
  else if (strcmp("thrSuspend",		symbol) == 0) *adr = o_thrSuspend;
  else if (strcmp("thrResume",		symbol) == 0) *adr = o_thrResume;
  else if (strcmp("thrGetPriority",	symbol) == 0) *adr = o_thrGetprio;
  else if (strcmp("thrSetPriority",	symbol) == 0) *adr = o_thrSetprio;
  else if (strcmp("thrKill",		symbol) == 0) *adr = o_thrKill;
  else if (strcmp("thrInitialize",	symbol) == 0) *adr = o_thrInitialize;
  else {
    *adr = dlsym(handle, symbol);
    if (*adr == 0) {
      printf("o_dlsym: symbol %s not found\n", symbol); 
    }
  }
}


/*----- Files Reading primitives -----*/

int Rint() {
  unsigned char b[4];

  /* b[3] = fgetc(fd); b[2] = fgetc(fd); b[1] = fgetc(fd); b[0] = fgetc(fd); */

  /* little endian machine reading little endian integer */
  b[0] = fgetc(fd); b[1] = fgetc(fd); b[2] = fgetc(fd); b[3] = fgetc(fd);
  return *((int *) b);
}

int RNum() {
  int n, shift;
  unsigned char x;

  shift = 0; n = 0; x = fgetc(fd);
  while (x >= 128) {
    n += (x & 0x7f) << shift;
    shift += 7;
    x = fgetc(fd);
  }
  return n + (((x & 0x3f) - ((x >> 6) << 6)) << shift);
}

void Assert( caddr_t x ) {
  caddr_t y;

  if((x < heapAdr) | (x >= heapAdr + heapSize)) {
    printf("bad reloc. pos %x [%x, %x]\n", x, heapAdr, heapAdr+heapSize);
  }
  if (x > heapAdr+codeSize) {
    y = *(caddr_t*)x;
    if((y < heapAdr) | (y >= heapAdr+heapSize)) {
      printf("bad reloc. value %x [%x, %x]\n", y, heapAdr, heapAdr+heapSize);
    }
  }
}

	
void Relocate(Address heapAdr, size_t shift) {
  int len; Address adr; 
  
  len = RNum(); 
  while (len != 0) { 
    adr = RNum(); 
    adr += (u_long)heapAdr; 
    *((Address*)adr) += shift; 
    Assert( adr );
    len--; 
  } 
}


void Boot() {
  u_long adr, len, fileHeapAdr, dlsymAdr;
  size_t shift, fileHeapSize;
  int d, notfound;  
  OberonProc body;

  d = 0; notfound = 1;
  while ((d < nofdir) && notfound) {
    strcat(strcat(strcpy(fullname, dirs[d++]), "/"), bootname);
    fd = fopen(fullname, "r");
    if (fd != NULL) notfound = 0;
  }
  if (notfound) {
    printf("Aos BootLoader: boot file %s not found\n", bootname);  
    exit(-1);
  }
  fileHeapAdr = Rint(); fileHeapSize = Rint();
  if (fileHeapSize >= heapSize) {
    printf("Aos BootLoader: heap too small\n");  
    exit(-1);
  }
  adr = heapAdr; len = fileHeapSize + 32; 
  while (len > 0) { 
    *((int*)adr) = 0; 
    len -= 4; adr += 4; 
  } 
  shift = heapAdr - fileHeapAdr;
  adr = Rint(); len = Rint();
  while (len != 0) {
    adr += shift;
    len += adr;
    codeSize = len - (u_long)heapAdr;
    while (adr != len) { *((int*)adr) = Rint(); adr += 4; }
    adr = Rint(); len = Rint();
  }
  body = (OberonProc)(adr + shift);
  Relocate(heapAdr, shift);
  dlsymAdr = Rint();
  *((int *)(heapAdr + dlsymAdr)) = (int)o_dlsym;
  fclose(fd);
  if(mprotect((void*)heapAdr, heapSize, PROT_READ|PROT_WRITE|PROT_EXEC) != 0)
     perror("mprotect");
  (*body)();
}

void InitPath() {
  int pos;
  char ch;
  
  if ((AOSPATH = getenv("AOSPATH")) == NULL) AOSPATH = defaultpath;
  strcpy(path, AOSPATH);
  pos = 0; nofdir = 0;
  ch = path[pos++];
  while (ch != '\0') {
    while ((ch == ' ') || (ch == ':')) ch = path[pos++];
    dirs[nofdir] = &path[pos-1];
    while ((ch > ' ') && (ch != ':')) ch = path[pos++];
    path[pos-1] = '\0';
    nofdir ++;
  }
}


int main(int argc, char *argv[])
{
  char* p;
  void *a, *h;
  
  Argc = argc; Argv = argv;

  /* check if we have suid root privileges */
  if (geteuid() == 0) {
     suid_root = 1;
     seteuid( getuid() );
  } else {
     suid_root = 0;
  }

  debug = 0;
  p = getenv("AOSDEBUG");
  if (p != NULL) debug = atoi(p);

  if (debug) {
     printf( "UnixAos Boot Loader 16.06.2011\n" );
     printf( "debug = %d\n", debug );
  }

  heapSize = 0x200000;
#ifdef DARWIN
  heapAdr = (Address)calloc(0x200, 0x1000);
#else
  heapAdr = (Address)memalign(4096, heapSize);
#endif
  if (heapAdr == 0) {
    printf("Aos BootLoader: cannot allocate initial heap space\n");  
    exit(-1);
  }

  InitPath();
  CreateSignalstack();
  InitSignalHandler();
  
  Boot();
  return 0;
}

