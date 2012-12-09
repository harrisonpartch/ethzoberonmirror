MODULE UsbTouchscreen;  (** AUTHOR "felixf"; PURPOSE "USB Touchscreen drivers"; *)
(**
	extracted from UsbHidDrivers and tailored towards touch screen interface
	implemented simplest single-touch driver
**)

IMPORT
	SYSTEM, KernelLog, Modules, Inputs, Usbdi, UsbHid, HidParser := UsbHidParser, UsbHidReport, UsagePage := UsbHidUP, Displays, Plugins;
TYPE

	HidDriver= OBJECT (UsbHid.HidDriver);
	VAR
		x,y: UsbHidReport.UsageTuple;
		minX, maxX, minY, maxY: LONGINT;

		tipSwitch, inRange: UsbHidReport.UsageTuple;
		prevS: BOOLEAN;

		(*itemParser is responsible for parsing the usb hid report descriptor*)
		itemParser 	: HidParser.ItemParser;
		endpoint	: LONGINT;
		pipe 		: Usbdi.Pipe;

		(*where the report interrupt in report is stored*)
		reportBuffer				: Usbdi.BufferPtr;
		reportManager			: UsbHidReport.HidReportManager;
		hidReportItemQueue	: UsbHidReport.ReportItemQueue;
		useReportIDMechanism	: BOOLEAN;

		display: Displays.Display;

		(*
		 * This procedure is called by the USB system software after an instance of this object has been passed to it via the probe procedure.
		 * Typically, the code here sets up the communication pipe(s) use by the driver using device.GetPipe(endpointnumber).
		 *)
		PROCEDURE Connect() : BOOLEAN;
		VAR
			hidDescriptor 		: UsbHid.HidDescriptor;
			i					: LONGINT;
			reportDescBuffer 	: Usbdi.BufferPtr;
			status 				: Usbdi.Status;
		BEGIN
			(*parse the hid report descriptor*)
			NEW(itemParser);

			(*get interface descriptor*)
			hidDescriptor := GetHidDescriptor();
			IF (hidDescriptor = NIL) THEN
				RETURN FALSE;
			END;

			NEW(reportDescBuffer, hidDescriptor.wDescriptorLength);
			IF ~GetDescriptor(hidDescriptor.bClassDescriptorType,  0, interface.bInterfaceNumber , hidDescriptor.wDescriptorLength, reportDescBuffer^) THEN
				KernelLog.String("    Could not get reportDescriptor"); KernelLog.Ln;
				RETURN FALSE;
			END;

			IF(~itemParser.ParseReportDescriptor(hidDescriptor, reportDescBuffer)) THEN (* there is still a chance to work .. *) END;
			(*get reportManager and hidReportItemQueue*)
			reportManager := itemParser.GetReportManager();
			hidReportItemQueue := reportManager.GetReportItemQueue();

			i := 0;
			WHILE (i< LEN(interface.endpoints)) & (interface.endpoints[i].type # Usbdi.InterruptIn) DO INC(i) END;
			IF i<LEN(interface.endpoints) THEN
				endpoint := SHORT(SYSTEM.VAL(LONGINT, SYSTEM.VAL(SET, interface.endpoints[0].bEndpointAddress) * {0,1,2,3,7}));
			ELSE
				RETURN FALSE;
			END;

			pipe := device.GetPipe(endpoint);
			IF pipe = NIL THEN RETURN FALSE END;

			IF ~InitializeDriver() THEN RETURN FALSE END;

			useReportIDMechanism	:= reportManager.UsesReportIDMechanism();

			NEW(reportBuffer, pipe.maxPacketSize);

			pipe.SetTimeout(0);
			pipe.SetCompletionHandler(HandleHidEvent);

			status := pipe.Transfer(pipe.maxPacketSize, 0, reportBuffer^);

			RETURN TRUE;
		END Connect;

		(*called when detaching a usb hid device*)
		PROCEDURE Disconnect;
		BEGIN
			itemParser.Disconnect();
			itemParser:=NIL;
		END Disconnect;

		(*is always called, when new report arrived*)
		PROCEDURE HandleHidEvent(status : Usbdi.Status; actLen : LONGINT);
		VAR
			ri			: UsbHidReport.ReportItem;
			i, bitIndex	: LONGINT;
			reportID	: LONGINT;
			usageTuple	: UsbHidReport.UsageTuple;

			(*
			* update the reportManager with the newest values
			*)
			PROCEDURE HandleReportItem;
			BEGIN
				FOR i:=0 TO (ri.reportItemCount-1) DO
					IF(ri.values=NIL) THEN
						(*there are no values to read, because the reportItem describes a constant field*)
					ELSE
						usageTuple := ri.values[i];
						usageTuple.usageValue := ReadBits(bitIndex,ri.reportItemSize);
					END;

					bitIndex := bitIndex + ri.reportItemSize;
				END;
			END HandleReportItem;
		BEGIN
			(*fill up report buffer with new values*)
			ri := hidReportItemQueue.first;

			IF(ri=NIL) THEN
				KernelLog.String("ri=NIL"); KernelLog.Ln;
				RETURN;
			END;
			(*index in the reportBuffer*)
			bitIndex := 0;
			IF (useReportIDMechanism) THEN
				reportID := ReadBits(0, 8);
				bitIndex := bitIndex + 8;

				WHILE(ri#NIL) DO
					IF(ri.reportID=reportID) THEN
						HandleReportItem;
					END;
					ri := ri.next;
				END;
			ELSE
				WHILE(ri#NIL) DO
					HandleReportItem;
					ri := ri.next;
				END;
			END;

			IF (  (status = Usbdi.Ok) OR (status=Usbdi.ShortPacket)) THEN
				HandleDriver;
				(*get new message from hid device*)
				status := pipe.Transfer(pipe.maxPacketSize, 0, reportBuffer^);
			ELSE
				IF (status = Usbdi.Stalled) THEN
					IF pipe.ClearHalt() THEN
						status := pipe.Transfer(pipe.maxPacketSize, 0, reportBuffer^); (* ignore status *)
					ELSE
						device.FreePipe(pipe);
					END;
				END;
			END;
		END HandleHidEvent;

		PROCEDURE InitializeDriver():BOOLEAN;
		VAR
			collection	: UsbHidReport.HidCollection;
			temp			: UsbHidReport.HidReport;
		BEGIN
			collection := reportManager.GetCollection(0DH, 04H);
			IF (collection#NIL) THEN
				x 		:= reportManager.GetUsage(UsagePage.GenericDesktopPage, 30H, collection,temp);
				y 		:= reportManager.GetUsage(UsagePage.GenericDesktopPage, 31H, collection,temp);
				tipSwitch := reportManager.GetUsage(0DH, 042H, collection,temp);
				inRange := reportManager.GetUsage(0DH, 032H, collection,temp);
				KernelLog.String("initialized touchscreen driver"); KernelLog.Ln;
				RETURN TRUE;
			ELSE
				RETURN FALSE;
			END;
		END InitializeDriver;

		(**
		 * Is called by handleHidEvent when mouse device is found
		 *)
		PROCEDURE HandleDriver;
		VAR
			mm : 			Inputs.AbsMouseMsg;
			x,y,w,h: LONGINT;
			o: Plugins.Plugin;
		BEGIN
			IF display = NIL THEN
				o := Displays.registry.Get("");
				IF o # NIL THEN display := o(Displays.Display) END;
			END;
			IF display # NIL THEN
				w := display.width; h := display.height
			ELSE
				w := 1024; h := 768
			END;
			x := SELF.x.usageValue;
			y := SELF.y.usageValue;

			IF (tipSwitch.usageValue#0) THEN mm.keys := mm.keys + {0}; END;
			(* these dimensions are very specific to the model we currently need. The driver has to be factored our to a separate module *)
			mm.x := (x-minX) * w DIV (maxX-minX+1); mm.y := (y-minY) * h DIV (maxY-minY+1);


			IF (0 IN mm.keys) &  ~prevS THEN
				(* patch window manager issue: expects that the mouse is there without button pressed previously... *)
				EXCL(mm.keys, 0);
				Inputs.mouse.Handle(mm);
				INCL(mm.keys, 0);
			END;

			Inputs.mouse.Handle(mm);
			prevS := 0 IN mm.keys;
		END HandleDriver;


		(**
		 * Reads bitlen bits from a position index
		 * @param index[in bits]: where to start reading [1..32]
		 * @param bitLen: the amount of bits to read
		 * @return value
		 *)
		 PROCEDURE ReadBits(index, bitLen: LONGINT):LONGINT;
		VAR rv : LONGINT;
		BEGIN
			rv := ReadBitsBuffer(index,bitLen,reportBuffer);
			RETURN rv;
		END ReadBits;

		 (**
		 * Reads bitlen bits from a position index
		 * @param index[in bits]: where to start reading [1..32]
		 * @param bitLen: the amount of bits to read
		 * @param localBuf: the buffer to read from
		 * @return value
		 *)
		PROCEDURE ReadBitsBuffer(index, bitLen: LONGINT; localBuf: Usbdi.BufferPtr):LONGINT;
		VAR
			endIndex	: LONGINT;
			rv			: LONGINT;
			temp		: LONGINT;
			indexEightAligned : LONGINT;
			bitsToShift	: LONGINT;
			set			: SET;
		BEGIN
			endIndex := index + bitLen-1;

			IF bitLen<=0 THEN RETURN 0 END;

			IF(endIndex>=(8*LEN(localBuf))) THEN
				RETURN 0;
			END;

			IF (bitLen=1) THEN
				(*simply get the bit*)
				set := SYSTEM.VAL(SET, localBuf[index DIV 8]);
				IF (index MOD 8) IN set THEN
					rv := 1;
				ELSE
					rv := 0;
				END;
				RETURN rv;
			END;

			IF ((index DIV 8) = (endIndex DIV 8)) THEN
				(*detect reading simple byte*)

				temp := SYSTEM.VAL(LONGINT, ORD(localBuf[index DIV 8]));

				IF (bitLen=8) THEN
					rv:= temp;
					RETURN rv;
				ELSE
					(*simply read in the byte index DIV 8*)

					temp := SYSTEM.VAL(LONGINT,(SYSTEM.VAL(SET, temp) * {(index MOD 8)..(endIndex MOD 8)}));
					bitsToShift := index MOD 8;
					rv := SYSTEM.VAL(LONGINT,LSH(SYSTEM.VAL(CHAR,temp),-bitsToShift));


				END;
			ELSE
				(* the index and the endIndex are not in the same byte

					block position k of index is k="index DIV 8"
					so endBit in the same block is   eb=k * 8 + 7
					ex: given: index := 27;
					asked:	how many bits to shift the current rv to left

							k := 27 div 8
							k := 3;
							eb := 3 * 8 + 7= 31

				*)
				indexEightAligned := SYSTEM.VAL(LONGINT,SYSTEM.VAL(SET,index)+{0..2});
				temp := ReadBitsBuffer(indexEightAligned+1,endIndex-indexEightAligned, localBuf);
				temp := LSH(temp,indexEightAligned-index+1);
				rv := temp + ReadBitsBuffer(index, indexEightAligned-index+1,localBuf);
			END;
			RETURN rv;
		END ReadBitsBuffer;

	END HidDriver;

(*check, whether the device is a hid device
 *	return 	HidDriver, if hid device found, NIL otherwise
 *)
PROCEDURE Probe(dev : Usbdi.UsbDevice; if : Usbdi.InterfaceDescriptor) : Usbdi.Driver;
VAR hidDriver : HidDriver;
BEGIN
	hidDriver := NIL;
	IF (dev.descriptor.idVendor = 3EBH) & (dev.descriptor.idProduct =201CH) THEN
		NEW(hidDriver); hidDriver.minX := 0; hidDriver.minY := 0; hidDriver.maxX := 16274; hidDriver.maxY := 12152
	END;
	RETURN hidDriver;
END Probe;

(* Called, when detaching the UsbHidDriver *)
PROCEDURE Cleanup;
BEGIN
	Usbdi.drivers.Remove("Atmel");
END Cleanup;

PROCEDURE InstallCDT975*;
BEGIN
	Usbdi.drivers.Add(Probe, "Atmel", "CDT 9.75", 10);
END InstallCDT975;

BEGIN
	Modules.InstallTermHandler(Cleanup);
END UsbTouchscreen.