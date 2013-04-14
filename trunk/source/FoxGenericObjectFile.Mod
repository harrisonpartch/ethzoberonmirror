MODULE FoxGenericObjectFile; (** AUTHOR "negelef"; PURPOSE "Generic Object File Writer"; *)

IMPORT
	StringPool, Streams, Commands, Basic := FoxBasic, Formats := FoxFormats, Sections := FoxSections, IntermediateCode := FoxIntermediateCode,
	SyntaxTree := FoxSyntaxTree, BinaryCode := FoxBinaryCode,
	FingerPrinter := FoxFingerPrinter, Files, Options, ObjectFile, Diagnostics, SymbolFileFormat := FoxTextualSymbolFile, Strings, KernelLog, D := Debugging;

CONST
	Version = 3;
	Trace = FALSE;

TYPE ObjectFileFormat* = OBJECT (Formats.ObjectFileFormat)
	VAR extension: Files.FileName; binary: BOOLEAN; mergeSections: BOOLEAN;

		PROCEDURE & InitObjectFileFormat;
		BEGIN
			Init; extension := ObjectFile.DefaultExtension;
		END InitObjectFileFormat;


		PROCEDURE Export* (module: Formats.GeneratedModule; symbolFileFormat: Formats.SymbolFileFormat): BOOLEAN;
		VAR fileName: Files.FileName; file: Files.File; writer: Files.Writer; fingerPrinter: FingerPrinter.FingerPrinter; poolMap: ObjectFile.PoolMap;

			PROCEDURE ExportSection (section: IntermediateCode.Section): BOOLEAN;
			VAR name: ARRAY 256 OF CHAR; (* debugging *)
			BEGIN
				(*
				IF section.IsExternal() OR (section.symbol # NIL) & (section.symbol.scope # NIL) & (section.symbol.scope.ownerModule # module(Sections.Module).module) THEN
					(* nothing to do *)
				ELSE
				*)
					IF section.resolved = NIL THEN
						Basic.SegmentedNameToString(section.name, name);
						D.String('"section.resolved = NIL" for '); D.String(name); D.Ln;
						RETURN FALSE
					END;
					section.resolved.identifier.fingerprint := GetFingerPrint (section, fingerPrinter);
					CopyFixups (section.resolved, section.resolved, 0);
					ObjectFile.WriteSection(writer,section.resolved^,binary, poolMap);
				(*
				END;
				*)
				RETURN TRUE
			END ExportSection;

			PROCEDURE MergeSections (sections: Sections.SectionList): BOOLEAN;
			VAR
				section, test: Sections.Section;
				i, j: LONGINT;
				name: ObjectFile.SectionName;
				sname: Basic.SegmentedName;
				msg: ARRAY 256 OF CHAR;
				codeAlign, dataAlign, constAlign: LONGINT;
				codeUnit, dataUnit, constUnit: LONGINT;
				resolved, codeSection, dataSection, constSection: BinaryCode.Section;
				alias: BinaryCode.Alias;
				irSection: IntermediateCode.Section;
			BEGIN
				codeAlign := 0; dataAlign := 0; constAlign := 0;
				FOR i := 0 TO sections.Length() - 1 DO
					section := sections.GetSection(i);
					resolved := section(IntermediateCode.Section).resolved;
					IF resolved = NIL THEN RETURN FALSE END;

					IF (resolved # NIL) & (resolved.alignment # 0) & (~resolved.fixed) & (resolved.priority = 0) THEN
						IF section.type = ObjectFile.Code THEN
							codeAlign := CommonAlignment(codeAlign, resolved.alignment);
							ASSERT((codeUnit=0) OR (codeUnit = resolved.unit));
							codeUnit := resolved.unit;
						ELSIF section.type = ObjectFile.Data THEN
							dataAlign := CommonAlignment(dataAlign, resolved.alignment);
							ASSERT((dataUnit=0) OR (dataUnit = resolved.unit));
							dataUnit := resolved.unit;
						ELSIF section.type = ObjectFile.Const THEN
							constAlign := CommonAlignment(constAlign, resolved.alignment);
							ASSERT((constUnit=0) OR (constUnit = resolved.unit));
							constUnit := resolved.unit;
						END;
					END;
				END;
				IF codeUnit > 0 THEN
					sname := module.moduleName;
					Basic.AppendToSegmentedName(sname,".@CodeSections");
					codeSection := BinaryCode.NewBinarySection(ObjectFile.Code, 0, codeUnit, sname, FALSE, FALSE);
					codeSection.SetAlignment(FALSE,codeAlign);
				END;
				IF dataUnit > 0 THEN
					sname := module.moduleName;
					Basic.AppendToSegmentedName(sname,".@DataSections");
					dataSection := BinaryCode.NewBinarySection(ObjectFile.Data, 0, dataUnit, sname, FALSE, FALSE);
					dataSection.SetAlignment(FALSE,dataAlign);
				END;
				IF constUnit > 0 THEN
					sname := module.moduleName;
					Basic.AppendToSegmentedName(sname,".@ConstSections");
					constSection := BinaryCode.NewBinarySection(ObjectFile.Const, 0, constUnit, sname, FALSE, FALSE);
					constSection.SetAlignment(FALSE,constAlign);
				END;
				(*TRACE(codeAlign, dataAlign, constAlign);*)
				codeAlign := 0; dataAlign := 0; constAlign := 0;
				FOR i := 0 TO sections.Length() - 1 DO
					section := sections.GetSection(i);
					resolved := section(IntermediateCode.Section).resolved;
					IF (resolved # NIL) & (resolved.alignment # 0) & (~resolved.fixed) & (resolved.priority = 0)  THEN
						IF section.type = ObjectFile.Code THEN
							codeSection.Align(resolved.alignment);
							resolved.identifier.fingerprint := GetFingerPrint (section, fingerPrinter);

							NEW(alias, resolved.identifier, codeSection.pc);
							codeSection.aliasList.AddAlias(alias);
							CopyFixups(resolved, codeSection, codeSection.pc);

							codeSection.CopyBits(resolved.bits,0, resolved.pc*codeUnit);

							section(IntermediateCode.Section).SetResolved(NIL);
						ELSIF section.type = ObjectFile.Data THEN
							dataSection.Align(resolved.alignment);
							resolved.identifier.fingerprint := GetFingerPrint (section, fingerPrinter);
							NEW(alias, resolved.identifier, dataSection.pc);
							dataSection.aliasList.AddAlias(alias);
							CopyFixups(resolved, dataSection, dataSection.pc);
							dataSection.CopyBits(resolved.bits,0, resolved.pc*dataUnit );

							section(IntermediateCode.Section).SetResolved(NIL);

						ELSIF section.type = ObjectFile.Const THEN
							constSection.Align(resolved.alignment);
							resolved.identifier.fingerprint := GetFingerPrint (section, fingerPrinter);
							NEW(alias, resolved.identifier, constSection.pc);
							constSection.aliasList.AddAlias(alias);
							CopyFixups(resolved, constSection, constSection.pc);
							constSection.CopyBits(resolved.bits,0, resolved.pc*constUnit);
							section(IntermediateCode.Section).SetResolved(NIL);
						END;
					END;
				END;

				IF codeSection # NIL THEN
					UpdateAliases (codeSection, fingerPrinter);
					irSection := IntermediateCode.NewSection(sections, SHORTINT(codeSection.type), codeSection.identifier.name, NIL, FALSE);
					irSection.SetResolved(codeSection);
				END;
				IF dataSection # NIL THEN
					UpdateAliases (dataSection, fingerPrinter);
					irSection := IntermediateCode.NewSection(sections, SHORTINT(dataSection.type), dataSection.identifier.name, NIL, FALSE);
					irSection.SetResolved(dataSection);
				END;
				IF constSection # NIL THEN
					UpdateAliases (constSection, fingerPrinter);
					irSection := IntermediateCode.NewSection(sections, SHORTINT(constSection.type), constSection.identifier.name, NIL, FALSE);
					irSection.SetResolved(constSection);
				END;
				RETURN TRUE;
			END MergeSections;

			PROCEDURE ExportSections (sections: Sections.SectionList): BOOLEAN;
			VAR
				section, test: Sections.Section;
				i, j: LONGINT;
				name: ObjectFile.SectionName;
				sname: Basic.SegmentedName;
				msg: ARRAY 256 OF CHAR;
				codeAlign, dataAlign, constAlign: LONGINT;
				codeUnit, dataUnit, constUnit: LONGINT;
				resolved, codeSection, dataSection, constSection: BinaryCode.Section;
				alias: BinaryCode.Alias;
				irSection: IntermediateCode.Section;
			BEGIN

				FOR i := 0 TO sections.Length() - 1 DO
					section := sections.GetSection(i);
					IF section(IntermediateCode.Section).resolved # NIL THEN
						IF ~ExportSection(section(IntermediateCode.Section)) THEN RETURN FALSE END;
						IF  (section(IntermediateCode.Section).resolved.identifier.fingerprint # 0) THEN
							FOR j := 0 TO i - 1 DO
								test := sections.GetSection(j);
								IF (test(IntermediateCode.Section).resolved # NIL)
								&  (test(IntermediateCode.Section).resolved.identifier.fingerprint = section(IntermediateCode.Section).resolved.identifier.fingerprint) THEN
									msg := "duplicate fingerPrints: ";
									ObjectFile.SegmentedNameToString(section(IntermediateCode.Section).resolved.identifier.name,name);
									Strings.Append(msg, name);
									Strings.Append(msg, ", ");
									ObjectFile.SegmentedNameToString(test(IntermediateCode.Section).resolved.identifier.name,name);
									Strings.Append(msg, name);
									diagnostics.Warning(module.moduleName,Diagnostics.Invalid,Diagnostics.Invalid,msg);
								END
							END
						END
					END
				END;
				RETURN TRUE
			END ExportSections;

			PROCEDURE ExportModule (module: Sections.Module): BOOLEAN;
			BEGIN
				IF mergeSections & ~MergeSections(module.allSections) THEN RETURN FALSE END;
				WriteHeader(writer,binary,module.allSections,poolMap, fingerPrinter);
				RETURN ExportSections (module.allSections)
			END ExportModule;

		BEGIN
			IF Trace THEN D.String(">>> export generic object file"); D.Ln END;

			IF ~(module IS Sections.Module) THEN
				diagnostics.Error (module.moduleName, Diagnostics.Invalid, Diagnostics.Invalid, "generated module format does not match object file format");
				RETURN FALSE;
			END;

			IF path # "" THEN Files.JoinPath (path, module.moduleName, fileName); ELSE COPY (module.moduleName, fileName); END;
			Files.JoinExtension (fileName, extension, fileName);

			IF Trace THEN D.String(">>> filename: "); D.String(fileName); D.Ln END;

			file := Files.New (fileName);
			IF file = NIL THEN
				diagnostics.Error(module.moduleName,Diagnostics.Invalid,Diagnostics.Invalid,"failed to open object file");
				RETURN FALSE;
			END;

			NEW (fingerPrinter, module.system);
			Files.OpenWriter (writer, file, 0);
			IF ExportModule (module(Sections.Module)) THEN
				writer.Update;
				Files.Register (file);
				RETURN TRUE;
			ELSE
				RETURN FALSE
			END
		END Export;

		PROCEDURE DefineOptions* (options: Options.Options);
		BEGIN
			options.Add(0X,"objectFileExtension",Options.String);
			options.Add(0X,"textualObjectFile",Options.Flag);
			options.Add(0X,"mergeSections",Options.Flag);
		END DefineOptions;

		PROCEDURE GetOptions* (options: Options.Options);
		BEGIN
			IF ~options.GetString("objectFileExtension",extension) THEN extension := ObjectFile.DefaultExtension; END;
			binary := ~options.GetFlag("textualObjectFile");
			mergeSections := options.GetFlag("mergeSections");
		END GetOptions;

		PROCEDURE DefaultSymbolFileFormat(): Formats.SymbolFileFormat;
		BEGIN RETURN SymbolFileFormat.Get();
		END DefaultSymbolFileFormat;

		PROCEDURE GetExtension(VAR ext: ARRAY OF CHAR);
		BEGIN COPY(extension, ext)
		END GetExtension;


	END ObjectFileFormat;

	PROCEDURE GetFingerPrint (section: Sections.Section; fingerPrinter: FingerPrinter.FingerPrinter): LONGINT;
	VAR fingerPrint: SyntaxTree.FingerPrint; fp: LONGINT; string: Basic.SectionName;
	BEGIN
		IF section.fingerprint # 0 THEN
			fp := section.fingerprint
		ELSIF (section.symbol = NIL) OR (section.symbol.scope = NIL) THEN
			fp := 0;
			IF (section(IntermediateCode.Section).resolved # NIL) THEN
				Basic.SegmentedNameToString(section.name, string);
				FingerPrinter.FPString(fp, string)
			END
		ELSIF fingerPrinter # NIL THEN
			fingerPrint := fingerPrinter.SymbolFP (section.symbol);
			fp := fingerPrint.shallow;
		END;
		RETURN fp
	END GetFingerPrint;

	PROCEDURE UpdateFixups (section: BinaryCode.Section;  fingerPrinter: FingerPrinter.FingerPrinter);
	VAR fixup: BinaryCode.Fixup; i: INTEGER; fixupList: ObjectFile.Fixups; fixups: LONGINT; index: LONGINT;
	BEGIN
		fixup := section.fixupList.firstFixup; i := 0; fixups := 0; fixupList := NIL;
		WHILE fixup # NIL DO
			(*! fingerprint := GetFingerPrint(fixup.symbol, fingerPrinter);  *)
			index := ObjectFile.AddFixup(fixups, fixupList, fixup.symbol.name, fixup.symbol.fingerprint, fixup.mode,fixup.scale, fixup.patterns, fixup.pattern);
			ObjectFile.AddPatch(fixupList[index].patches, fixupList[index].patch, fixup.displacement,  fixup.offset);
			fixup := fixup.nextFixup; INC (i);
		END;
		ObjectFile.SetFixups(section^, fixups, fixupList);
	END UpdateFixups;

	PROCEDURE CopyFixups(from, to: BinaryCode.Section; offset: LONGINT);
	VAR fixup: BinaryCode.Fixup; i: INTEGER; index: LONGINT;	fixupList: ObjectFile.Fixups; fixups: LONGINT;
	BEGIN
		fixup := from.fixupList.firstFixup; i := 0; fixups := to.fixups; fixupList := to.fixup;
		WHILE fixup # NIL DO
			(*! fingerprint := GetFingerPrint(fixup.symbol, fingerPrinter);  *)
			index := ObjectFile.AddFixup(fixups, fixupList, fixup.symbol.name, fixup.symbol.fingerprint, fixup.mode,fixup.scale, fixup.patterns, fixup.pattern);
			ObjectFile.AddPatch(fixupList[index].patches, fixupList[index].patch, fixup.displacement,  fixup.offset+offset);
			fixup := fixup.nextFixup; INC (i);
		END;
		ObjectFile.SetFixups(to^, fixups, fixupList);
	END CopyFixups;

	PROCEDURE UpdateAliases (section: BinaryCode.Section;  fingerPrinter: FingerPrinter.FingerPrinter);
	VAR alias: BinaryCode.Alias; i: INTEGER; aliasList: ObjectFile.Aliases; aliases: LONGINT; index: LONGINT;
	BEGIN
		alias := section.aliasList.firstAlias; i := 0; aliases := 0; aliasList := NIL;
		WHILE alias # NIL DO
			(*! fingerprint := GetFingerPrint(alias.symbol, fingerPrinter);  *)
			index := ObjectFile.AddAlias(aliases, aliasList, alias.identifier.name, alias.identifier.fingerprint, alias.offset);
			alias := alias.nextAlias; INC (i);
		END;
		ObjectFile.SetAliases(section^, aliases, aliasList);
	END UpdateAliases;

	PROCEDURE Get*(): Formats.ObjectFileFormat;
	VAR objectFileFormat: ObjectFileFormat;
	BEGIN NEW(objectFileFormat); RETURN objectFileFormat
	END Get;

	PROCEDURE ReadHeader(reader: Streams.Reader; VAR binary: BOOLEAN; VAR poolMap: ObjectFile.PoolMap);
	VAR ch: CHAR; version: LONGINT; string: ARRAY 32 OF CHAR; i,j,pos,size: LONGINT; name: ObjectFile.SectionName;
	BEGIN
		reader.String(string);
		binary := string="FoxOFB";
		IF ~binary THEN ASSERT(string="FoxOFT") END;
		reader.SkipWhitespace;
		reader.Char(ch); ASSERT(ch='v');
		reader.Int(version,FALSE);
		IF version < Version THEN KernelLog.String("warning: old object file encountered, recompile all sources"); KernelLog.Ln END;
		reader.Char(ch); ASSERT(ch='.');
		IF ~binary THEN reader.SkipWhitespace
		ELSE
			NEW(poolMap,64);
			poolMap.Read(reader);
		END;
	END ReadHeader;

	PROCEDURE WriteHeader(writer: Streams.Writer; binary: BOOLEAN; sections: Sections.SectionList; VAR poolMap: ObjectFile.PoolMap; fingerPrinter:FingerPrinter.FingerPrinter);
	VAR p1,p2, size,i: LONGINT; section: Sections.Section; fixups: LONGINT; fixupList: ObjectFile.Fixups;

		PROCEDURE ProcessSection(section: IntermediateCode.Section);
		VAR i: LONGINT; fixup: BinaryCode.Fixup; index: LONGINT; alias: BinaryCode.Alias; name: ARRAY 256 OF CHAR;
		BEGIN
			IF section.resolved # NIL THEN
				poolMap.PutSegmentedName(section.resolved.identifier.name);
				(* for those sections that have been already resolved *)
				FOR i := 0 TO section.resolved.fixups-1 DO
					poolMap.PutSegmentedName(section.resolved.fixup[i].identifier.name);
				END;
				fixup := section.resolved.fixupList.firstFixup; i := 0;
				WHILE fixup # NIL DO
					poolMap.PutSegmentedName(fixup.symbol.name);
					fixup := fixup.nextFixup;
				END;
				alias:= section.resolved.aliasList.firstAlias; i := 0;
				WHILE alias # NIL DO
					poolMap.PutSegmentedName(alias.identifier.name);
					alias := alias.nextAlias;
				END;
				FOR i := 0 TO section.resolved.aliases-1 DO
					poolMap.PutSegmentedName(section.resolved.alias[i].identifier.name);
				END;
			END;
		END ProcessSection;

	BEGIN
		IF binary THEN writer.String("FoxOFB");
		ELSE writer.String("FoxOFT");
		END;
		writer.Char(' ');
		writer.Char('v'); writer.Int(Version,0); writer.Char(".");
		IF ~binary THEN writer.Ln
		ELSE
			NEW(poolMap,512);
			poolMap.BeginWriting(writer);
			FOR i := 0 TO sections.Length()-1 DO
				section := sections.GetSection(i);
				ProcessSection(section(IntermediateCode.Section));
			END;
			poolMap.EndWriting;

			FOR i := 0 TO fixups-1 DO
				D.String("fingerprint: "); Basic.WriteSegmentedName(D.Log, fixupList[i].identifier.name); D.Ln;
			END;

			IF Trace THEN D.String("pos "); D.Int(writer.Pos(),1); D.Ln END;
		END;
	END WriteHeader;

	PROCEDURE GCD(a,b: LONGINT): LONGINT;
	VAR h: LONGINT;
	BEGIN
		WHILE b # 0 DO
			h := a MOD b;
			a := b;
			b := h;
		END;
		RETURN a
	END GCD;

	PROCEDURE SCM(a,b: LONGINT): LONGINT;
	BEGIN
		RETURN a*b DIV GCD(a,b)
	END SCM;

	PROCEDURE CommonAlignment(a,b: LONGINT): LONGINT;
	BEGIN
		(*TRACE(a,b);*)
		IF a = 0 THEN RETURN b
		ELSIF b = 0 THEN RETURN a
		ELSE RETURN SCM(a,b)
		END;
	END CommonAlignment;



	PROCEDURE Show*(context: Commands.Context);
	VAR
		fileName: Files.FileName; file: Files.File; reader: Files.Reader; writer: Streams.Writer;
		section: ObjectFile.Section; binary: BOOLEAN; poolMap, poolMapDummy: ObjectFile.PoolMap;
	BEGIN
		IF context.arg.GetString(fileName) THEN
			file := Files.Old(fileName);
			IF file # NIL THEN
				NEW(reader,file,0);
				writer := Basic.GetWriter(Basic.GetDebugWriter(fileName));
				ReadHeader(reader, binary, poolMap);
				WriteHeader(writer, FALSE, NIL, poolMapDummy, NIL);
				WHILE reader.Peek () # 0X DO
					ObjectFile.ReadSection (reader, section,binary, poolMap);
					ObjectFile.WriteSection(writer, section, FALSE, NIL); (* textual *)
					reader.SkipWhitespace;
				END;
				writer.Update;
			ELSE
				context.error.String("file not found "); context.error.String(fileName); context.error.Ln
			END;
		ELSE
			context.error.String("no file specificed"); context.error.Ln
		END;
	END Show;


END FoxGenericObjectFile.
