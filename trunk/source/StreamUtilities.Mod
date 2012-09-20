MODULE StreamUtilities; (** AUTHOR "Patrick Hunziker"; PURPOSE "stream utilities"; *)
(* daisychaining of readers or writers with 'logging side-stream', or with size limitation*)

IMPORT Streams(* , KernelLog, Commands*);
	
CONST 
	ReaderBufSize = Streams.DefaultReaderSize;
	WriterBufSize = Streams.DefaultWriterSize;
	
(* writer that can daisychained with another writer that extracts a copy of the data flow to a monitor stream*)
TYPE	WriterMonitor* = OBJECT (Streams.Writer);
		VAR out, monitor : Streams.Writer;
		
		PROCEDURE &Init*(out:Streams.Writer; monitor: Streams.Writer);
		BEGIN
			InitWriter(Sender, WriterBufSize);
			SELF.out := out;	
			SELF.monitor:=monitor;
			Reset;
		END Init;

		PROCEDURE Sender(CONST outBuf: ARRAY OF CHAR; ofs, len: LONGINT; propagate: BOOLEAN; VAR res: LONGINT);
		BEGIN
			out.Bytes(outBuf, ofs, len);
			monitor.Bytes(outBuf, ofs, len);
			INC(sent,len);
			IF propagate THEN out.Update; monitor.Update END;
			res:=out.res;
		END Sender;
		
		PROCEDURE CanSetPos*(): BOOLEAN;
		BEGIN RETURN out.CanSetPos()
		END CanSetPos;

		PROCEDURE SetPos*(pos: LONGINT);
		BEGIN Reset; out.SetPos(pos);
		END SetPos;

		PROCEDURE Pos*(): LONGINT;
		BEGIN RETURN out.Pos()
		END Pos;

	END WriterMonitor;
	
	(* reader that can daisychained with another reader that extracts a copy of the data flow to a monitor stream*)
	ReaderMonitor* = OBJECT(Streams.Reader)
		VAR in: Streams.Reader;
			monitor: Streams.Writer;
	
		PROCEDURE &Init*(in: Streams.Reader; monitor: Streams.Writer);
		BEGIN
			InitReader(Receiver, ReaderBufSize);
			SELF.in := in;	
			SELF.monitor:=monitor;
		END Init;

		PROCEDURE Receiver(VAR buf: ARRAY OF CHAR; ofs, size, min: LONGINT; VAR len, res: LONGINT);
		BEGIN
			ASSERT((size > 0) & (min <= size) & (min >= 0));
			in.Bytes(buf, ofs, size, len);
			INC(received,len);
			res:=in.res;
			monitor.Bytes(buf, ofs, len); 
			monitor.Update; 
		END Receiver;
		
		PROCEDURE CanSetPos*(): BOOLEAN;
		BEGIN RETURN in.CanSetPos()
		END CanSetPos;

		PROCEDURE SetPos*(pos: LONGINT);
		BEGIN Reset; in.SetPos(pos)
		END SetPos;

		PROCEDURE Pos*(): LONGINT;
		BEGIN RETURN in.Pos()
		END Pos;

	END ReaderMonitor;
	
	LimitedWriter* = OBJECT (Streams.Writer);
		VAR out : Streams.Writer;
			size, remain-: LONGINT;
		
		PROCEDURE &Init*(out:Streams.Writer; size: LONGINT);
		BEGIN
			InitWriter(Sender, MIN(size, WriterBufSize));
			SELF.out := out;	
			SELF.size:=size; remain:=size;
		END Init;

		PROCEDURE Sender(CONST outBuf: ARRAY OF CHAR; ofs, len: LONGINT; propagate: BOOLEAN; VAR res: LONGINT);
		VAR num:LONGINT;
		BEGIN
			num:=MIN(remain,len); 
			out.Bytes(outBuf, ofs, num);
			DEC(remain, num);
			IF propagate THEN out.Update END;
			IF num<len THEN res:=Streams.EOF ELSE res:=out.res END;
		END Sender;
		
		PROCEDURE Reset*;
		BEGIN
			remain:=size;
		END Reset;
		
	END LimitedWriter;

	LimitedReader* = OBJECT (Streams.Reader);
		VAR in : Streams.Reader;
			total, remain-: LONGINT;
		
		PROCEDURE &Init*(in:Streams.Reader; size: LONGINT);
		BEGIN
			InitReader(Receiver, MIN(size, ReaderBufSize));
			SELF.in := in;	
			total:=size; remain:=size;
		END Init;

		PROCEDURE Receiver(VAR buf: ARRAY OF CHAR; ofs, size, min: LONGINT; VAR len, res: LONGINT);
		VAR num:LONGINT;
		BEGIN
			ASSERT(size >= 0);
			IF (remain=0) THEN len:=0; res:=Streams.EOF; RETURN END;
			in.Bytes(buf, ofs, MIN(remain,size), len);
			DEC(remain,len); INC(received,len);
			res:=in.res;
		END Receiver;
		
		PROCEDURE Reset*;
		BEGIN
			remain:=total;
		END Reset;
	END LimitedReader;

	(*open a monitoring writer on the out stream*)
	PROCEDURE OpenWriterMonitor*(VAR w: Streams.Writer; out:Streams.Writer; monitor: Streams.Writer);
	VAR wm: WriterMonitor;
		BEGIN
			NEW(wm, out, monitor); w:=wm;
		END OpenWriterMonitor;

	(*open a monitoring reader on the in stream*)
	PROCEDURE OpenReaderMonitor*(VAR r: Streams.Reader; in:Streams.Reader; monitor: Streams.Writer);
	VAR rm: ReaderMonitor;
		BEGIN
			NEW(rm, in, monitor); r:=rm;
		END OpenReaderMonitor;

	(*open a size limited writer r on the out stream*)
	PROCEDURE OpenLimitedWriter*(VAR w: Streams.Writer; out: Streams.Writer; size:LONGINT);
	VAR lw: LimitedWriter;
		BEGIN
			NEW(lw, out, size); w:=lw;
		END OpenLimitedWriter;

	(*open a size limited reader r on the in stream*)
	PROCEDURE OpenLimitedReader*(VAR r: Streams.Reader; in: Streams.Reader; size:LONGINT);
	VAR lr: LimitedReader;
		BEGIN
			NEW(lr, in, size); r:=lr;
		END OpenLimitedReader;
(*
(* application example: reader/writer monitors *)
PROCEDURE Test*(context:Commands.Context);
VAR w, log: Streams.Writer;
	r:Streams.Reader;
	s: ARRAY 64 OF CHAR;
	res:BOOLEAN;
BEGIN
	NEW(log, KernelLog.Send, WriterBufSize);

	OpenReaderMonitor(r, context.arg, log); (*monitor the context.arg reader and send monitored input to log *)
	res:=r.GetString(s); 

	OpenWriterMonitor(w, context.out, log);(* monitor the context.out writer and send monitored data to log*)
	w.String("holla"); w.Ln; 
	w.Update; 
END Test;

(* application example: size limited streams *)
PROCEDURE Test2*(context:Commands.Context);
VAR w, log: Streams.Writer;
	r:Streams.Reader;
	s: ARRAY 64 OF CHAR;
	res:BOOLEAN;
BEGIN
	NEW(log, KernelLog.Send, WriterBufSize);
	
	OpenLimitedReader(r, context.arg, 7); (*monitor the context.arg reader and send monitored input to log *)
	res:=r.GetString(s); 
	log.String(s); log.Ln;
	res:=r.GetString(s); 
	log.String(s); log.Ln; 
	log.Update;
	
	OpenLimitedWriter(w, log, 6);(* monitor the context.out writer and send monitored data to log*)
	w.String("123456789"); w.Ln; w.Update; 
END Test2;
*)
END StreamUtilities.

StreamUtilities.Test hello ~
StreamUtilities.Test2 abcd efghijk ~

SystemTools.FreeDownTo StreamUtilities ~


