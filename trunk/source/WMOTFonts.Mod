MODULE WMOTFonts;	(** AUTHOR "PL"; PURPOSE "OpenType Support" *)

IMPORT
	KernelLog, WMGraphics, Raster, WMFontManager, Strings, WMRectangles,
	Files, OpenTypeFonts, OpenType, OpenTypeInt, OpenTypeScan, Zip;

CONST
	ScreenDPI = 71;
	Debug = FALSE;
	PersistentFontCache=FALSE;

TYPE
	Glyph*  = RECORD
		img- : WMGraphics.Image;
		code- : LONGINT; 										(* import only *)
		dx, x, y, w, h : LONGINT;
	END;
	GlyphArray* = POINTER TO ARRAY OF Glyph;

	GlyphRange* = RECORD
		firstCode-, lastCode- : LONGINT;							 (* inclusive *)
		glyphs- : GlyphArray;
		loaded- : BOOLEAN;
	END;
	GlyphRangeArray* = POINTER TO ARRAY OF GlyphRange;

	Font*  = OBJECT(WMGraphics.Font)
	VAR nofGlyphs- : LONGINT;
		nofGlyphRanges- : LONGINT;
		glyphRanges : GlyphRangeArray;
		placeholderimg : WMGraphics.Image;
		fontFile : Files.File;
		empty : WMRectangles.Rectangle;
		fname-, subfam- : ARRAY 256 OF CHAR;
		ofont : OpenType.Font;
		inst: OpenType.Instance;
		glyph : OpenType.Glyph;
		inCache, outCache: POINTER TO ARRAY OF CHAR; (* caches for antialiasing algorithm to avoid excessive allocation *)
		ras: OpenTypeScan.Rasterizer;

		PROCEDURE &Init*;
		VAR mode : Raster.Mode; pix : Raster.Pixel;
		BEGIN
			Init^;
			nofGlyphRanges := 0;
			empty := WMRectangles.MakeRect(0, 0, 0, 0);		(* save the proc call *)
			NEW(placeholderimg); Raster.Create(placeholderimg, 16, 16, Raster.A1);
			Raster.InitMode(mode, Raster.srcCopy);
			Raster.SetRGBA(pix, 255, 0, 0, 0);
			Raster.Fill(placeholderimg, 0, 0, 15, 15, pix, mode);
			ascent := 16; descent := 5;
		END Init;

		(* support the oberon encoding scheme *)
		PROCEDURE MapCode(VAR code : LONGINT);
		BEGIN
			IF (code >= 126) & (code <= 155) THEN code := OpenType.CharToUnicode[code] END;
		END MapCode;

		PROCEDURE GetGlyphMap*(code : LONGINT; VAR map : WMGraphics.Image);
		VAR g : Glyph; range : LONGINT;
		BEGIN
			IF FindGlyphRange(code, range) THEN
				IF FindGlyph(code, g) THEN
					map := g.img
				ELSE map := placeholderimg
				END
			ELSE map := placeholderimg
			END
		END GetGlyphMap;

		PROCEDURE HasChar*(code : LONGINT) : BOOLEAN;
		VAR dummy : LONGINT;
		BEGIN
			RETURN FindGlyphRange(code, dummy)
		END HasChar;

		PROCEDURE GetGlyphSpacings*(code : LONGINT; VAR glyphSpacings : WMGraphics.GlyphSpacings);
		VAR g : Glyph; range : LONGINT;
		BEGIN
			IF FindGlyphRange(code, range) THEN
				IF FindGlyph(code, g) THEN
					glyphSpacings.width := g.w;
					glyphSpacings.ascent := ascent; glyphSpacings.descent := descent;
					glyphSpacings.bearing.l := g.x;
					glyphSpacings.bearing.r := g.dx - (g.w + g.x);

					glyphSpacings.height := g.h;
					glyphSpacings.dy := ascent - g.h - g.y
				ELSE glyphSpacings.width := 5; glyphSpacings.height := 15; glyphSpacings.ascent := 16;
				END
			ELSE
				KernelLog.String("code= "); KernelLog.Int(code, 0); KernelLog.String("out of range"); KernelLog.Ln;
			glyphSpacings.width := 5; glyphSpacings.height := 15; glyphSpacings.ascent := 16;
			END
		END GetGlyphSpacings;

		PROCEDURE GetCacheFileName(gri: LONGINT; VAR name: ARRAY OF CHAR);
		BEGIN
			COPY(fname,name);
			Strings.Append(name, "_");
			Strings.AppendInt(name, size);
			Strings.Append(name, "_");
			Strings.AppendInt(name, gri);
			Strings.Append(name,".fontCache");
		END GetCacheFileName;


		PROCEDURE TryCacheFile(gri: LONGINT): BOOLEAN;
		VAR y,w,h: LONGINT; mode: Raster.Mode;
			reader: Files.Reader;
			file: Files.File;
			fileName: Files.FileName;
			i: LONGINT;
			archive: Zip.Archive;
			res: LONGINT;
			entry: Zip.Entry;
			rider: Files.Rider;

			PROCEDURE ReadGlyph(VAR g: Glyph);
			VAR len: LONGINT;
			BEGIN
				reader.RawNum(g.dx);
				reader.RawNum(g.x);
				reader.RawNum(g.y);
				reader.RawNum(g.w);
				reader.RawNum(g.h);
				reader.RawNum(w);
				reader.RawNum(h);
				IF (w>0) & (h>0) THEN
					NEW(g.img); Raster.Create(g.img, w, h, Raster.A8);
					IF (inCache = NIL) OR (LEN(inCache) < h*w) THEN NEW(inCache, h*w) END;

					reader.Bytes(inCache^, 0, h*w, len);
					ASSERT(len = h*w);
					(* copy data to char array for faster access *)
					Raster.InitMode(mode, Raster.srcCopy);
					FOR y := 0 TO h-1 DO
						Raster.PutPixels(g.img, 0,y,w,Raster.A8, inCache^, y*w,mode);
					END;
				END;

			END ReadGlyph;

		BEGIN
			GetCacheFileName(gri, fileName);
			(* first try direct -- if not in zip file it is faster *)
			file := Files.Old(fileName);
			(* then try in zip file *)
			IF (file = NIL) THEN
				archive := Zip.OpenArchive("FontCache.zip", res);
				IF res # Zip.Ok THEN
					RETURN FALSE
				ELSE
					entry := Zip.GetEntry(archive, fileName, res);
					IF res # Zip.Ok THEN RETURN FALSE END;
					file := Files.New("");
					file.Set(rider,0);
					Zip.ExtractEntry(archive, entry, rider, res);
				END;
			END;
			(* if file is still not here then the cache is not yet created *)
			IF file = NIL THEN
				RETURN FALSE
			ELSE
				Files.OpenReader(reader, file, 0);
				FOR i := glyphRanges[gri].firstCode TO glyphRanges[gri].lastCode DO
					ReadGlyph(glyphRanges[gri].glyphs[i - glyphRanges[gri].firstCode])
				END;
				glyphRanges[gri].loaded := TRUE;
				RETURN TRUE
			END;
		END TryCacheFile;

		PROCEDURE ToCacheFile(gri: LONGINT);
		VAR y,w,h: LONGINT; mode: Raster.Mode;
			writer: Files.Writer;
			file: Files.File;
			fileName: Files.FileName;
			i,res: LONGINT;
			archive: Zip.Archive;
			r: Files.Rider;

			PROCEDURE WriteGlyph(CONST g: Glyph);
			BEGIN
				writer.RawNum(g.dx);
				writer.RawNum(g.x);
				writer.RawNum(g.y);
				writer.RawNum(g.w);
				writer.RawNum(g.h);
				IF g.img # NIL THEN
					w := g.img.width; h := g.img.height;
				ELSE
					w := 0; h := 0;
				END;
				writer.RawNum(w);
				writer.RawNum(h);

				IF (w>0) & (h>0) THEN
					IF (inCache = NIL) OR (LEN(inCache) < h*w) THEN NEW(inCache, h*w) END;
					(* copy data to char array for faster access *)
					Raster.InitMode(mode, Raster.srcCopy);
					FOR y := 0 TO h-1 DO
						Raster.GetPixels(g.img, 0,y,w,Raster.A8, inCache^, y*w,mode);
					END;
					writer.Bytes(inCache^, 0, h*w);
				END;

			END WriteGlyph;

		BEGIN
			GetCacheFileName(gri, fileName);
			file := Files.New("");

			Files.OpenWriter(writer, file, 0);
			FOR i := glyphRanges[gri].firstCode TO glyphRanges[gri].lastCode DO
				WriteGlyph(glyphRanges[gri].glyphs[i - glyphRanges[gri].firstCode])
			END;
			writer.Update;
			Files.Register(file);
			archive := Zip.OpenArchive("FontCache.zip", res);
			IF res # Zip.Ok THEN
				archive := Zip.CreateArchive("FontCache.zip",res);
			END;
			file.Set(r, 0);
			Zip.AddEntry(archive, fileName, r, file.Length(), 9, 2, res);
		END ToCacheFile;

		PROCEDURE LoadGlyphRange(gri : LONGINT);
		VAR i: LONGINT;
		BEGIN
			IF glyphRanges[gri].glyphs = NIL THEN
				NEW(glyphRanges[gri].glyphs, glyphRanges[gri].lastCode - glyphRanges[gri].firstCode + 1);
				FOR i := glyphRanges[gri].firstCode TO glyphRanges[gri].lastCode DO
					glyphRanges[gri].glyphs[i - glyphRanges[gri].firstCode].code := -1;
				END;
			END;

			(* epxeriment *)
			glyphRanges[gri].loaded := TRUE;
			RETURN;


			IF ~PersistentFontCache OR ~TryCacheFile(gri) THEN
				FOR i := glyphRanges[gri].firstCode TO glyphRanges[gri].lastCode DO
					ReadGlyph(i, glyphRanges[gri].glyphs[i - glyphRanges[gri].firstCode])
				END;
				glyphRanges[gri].loaded := TRUE;
				IF PersistentFontCache THEN
					ToCacheFile(gri)
				END;
			END;
		END LoadGlyphRange;

		PROCEDURE FindGlyphRange(code : LONGINT; VAR gri : LONGINT) : BOOLEAN;
		VAR a, b, m : LONGINT;
		BEGIN
			gri := 0;
			a := 0; b := LEN(glyphRanges)- 1;
			WHILE (a < b) DO m := (a + b) DIV 2;
				IF glyphRanges[m].lastCode < code THEN a := m + 1
				ELSE b := m
				END
			END;
			IF (glyphRanges[a].firstCode <= code) & (glyphRanges[a].lastCode >= code) THEN
				IF ~glyphRanges[a].loaded THEN LoadGlyphRange(a) END;
				gri := a; RETURN TRUE
			ELSE RETURN FALSE
			END
		END FindGlyphRange;

		PROCEDURE FindGlyph(code : LONGINT; VAR glyph : Glyph) : BOOLEAN;
		VAR gri : LONGINT;
		BEGIN
			IF FindGlyphRange(code, gri) THEN
				IF glyphRanges[gri].glyphs[code - glyphRanges[gri].firstCode].code # code THEN
					ReadGlyph(code, glyphRanges[gri].glyphs[code - glyphRanges[gri].firstCode])
				END;
				glyph := glyphRanges[gri].glyphs[code - glyphRanges[gri].firstCode];
				RETURN TRUE
			ELSE RETURN FALSE
			END
		END FindGlyph;

		PROCEDURE CountGlyphes():LONGINT;
		VAR i, c : LONGINT;
		BEGIN
			FOR i := 0 TO nofGlyphRanges - 1 DO
				c := c + glyphRanges[i].lastCode - glyphRanges[i].firstCode + 1;
			END;
			RETURN c
		END CountGlyphes;

		PROCEDURE ReadGlyph(code : LONGINT; VAR g : Glyph);
		VAR no, k, l, bytes, pos, xw, bits, b : LONGINT;
			ch : CHAR;
			data : OpenTypeFonts.RasterData;
			p1 : Raster.Pixel;
			mode : Raster.Mode;
			obuf: POINTER TO ARRAY OF CHAR;
		BEGIN
			Raster.SetRGBA(p1, 0, 0, 0, 255);
			Raster.InitMode(mode, Raster.srcCopy);

			no := OpenType.UnicodeToGlyph(ofont, code);
			IF Debug THEN KernelLog.String("Reading Glyph Nr: "); KernelLog.Int(no, 0); KernelLog.String(" Code: u"); KernelLog.Hex(code, 4); KernelLog.Ln END;
			OpenType.LoadGlyph(inst, glyph, ras, no,  {OpenType.Hinted, OpenType.Width , OpenType.Raster });
			g.dx := glyph.awx;													(* advance *)
			g.x := glyph.hbx;													(* horizontal bearing x *)
			g.y := glyph.hby;														(* horizontal bearing y *)
			g.w := glyph.rw;														(* image width *)
			g.h := glyph.rh;														(* image height *)
			g.code := code;


			IF glyph.rw * glyph.rh # 0 THEN

				data.rect := OpenTypeFonts.FillRect; data.adr := ADDRESSOF(Pattern); data.bpr := (glyph.rw+7) DIV 8; data.len := LEN(Pattern);
				bytes := glyph.rh * ((glyph.rw+7) DIV 8);
				ASSERT(bytes < LEN(Pattern));
				ASSERT(bytes > 0);
				k := 0; REPEAT Pattern[k] := 0X; INC(k) UNTIL k = bytes;
				OpenType.EnumRaster(ras, data);

				xw := ((glyph.rw + 7) DIV 8) * 8;
				l := xw * glyph.rh DIV 8;

				IF (outCache = NIL) OR (LEN(outCache) < xw) THEN NEW(outCache, xw) END; obuf := outCache;


				IF xw *  glyph.rh > 0 THEN
					NEW(g.img);
					Raster.Create(g.img, xw, glyph.rh, Raster.A8);

					pos := 0; k := 0;
					WHILE l > 0 DO
						ch := Pattern[k]; bits := ORD(ch); DEC(l); INC(k);
						FOR b := 0 TO 7 DO
							IF (pos MOD xw < glyph.rw) & bit[ORD(ch), b] THEN
								obuf[pos MOD xw] := 0FFX;
							ELSE
								obuf[pos MOD xw] := 0X;
								(*
								Raster.Put(g.img, pos MOD xw, glyph.rh - pos DIV xw - 1, p1, mode);
								*)
							END;
							INC(pos);
							IF pos MOD xw = 0 THEN
								Raster.PutPixels(g.img, 0, glyph.rh - (pos-1) DIV xw - 1, xw, Raster.A8, obuf^, 0, mode);
							END;
						END
					END;

				END;
				Antialias(g.img);
			END;

			OpenTypeScan.DisposeRasterizer(ras);
		END ReadGlyph;

		PROCEDURE Antialias(img: Raster.Image);
		VAR x,y,w,h,pos: LONGINT; ibuf, obuf: POINTER TO ARRAY OF CHAR; mode: Raster.Mode; v,vl,vr,vu,vb: LONGINT;

			PROCEDURE Get(x,y: LONGINT): LONGINT;
			BEGIN
				IF (x<0) OR (x>=w) THEN RETURN 0 END;
				IF (y<0) OR (y>=h) THEN RETURN 0 END;
				RETURN ORD(ibuf[y*w+x])
			END Get;

		BEGIN
		(*	IF size <= 20 THEN RETURN END;		gf *)
			w := img.width; h := img.height;
			IF (inCache = NIL) OR (LEN(inCache) < h*w) THEN NEW(inCache, h*w) END;
			IF (outCache = NIL) OR (LEN(outCache) < w) THEN NEW(outCache, w) END;
			ibuf := inCache; obuf := outCache;

			(* copy data to char array for faster access *)
			Raster.InitMode(mode, Raster.srcCopy);
			FOR y := 0 TO img.height-1 DO
				Raster.GetPixels(img, 0,y,w,Raster.A8, ibuf^, y*w,mode);
			END;
	
			pos := 0;
			FOR y := 0 TO h-1 DO
				FOR x := 0 TO w-1 DO
					v := ORD(ibuf[pos]);
					IF x > 0 THEN
					vl := ORD(ibuf[pos-1]);
					ELSE
					vl := 0;
					END;
					IF x < w-1 THEN
						vr := ORD(ibuf[pos+1]);
					ELSE
						vr := 0
					END;
					IF y > 0 THEN
						vb := ORD(ibuf[pos-w]);
					ELSE
						vb := 0
					END;
					IF y < h-1 THEN
						vu := ORD(ibuf[pos+w]);
					ELSE
						vu := 0;
					END;
					(* interpolate pixels only on boundary not in vertices *)
				(*	IF (((size > 24) OR (v = 0)) & (v#vl) # (v#vr)) & ((v#vb) # (v#vu)) THEN
						obuf[x] := CHR( (10*v+ 3*vl + 3*vr + 2*vb + 2*vu) DIV 24);	gf *)
					IF (v = 0) & ((v#vl) # (v#vr)) & ((v#vb) # (v#vu)) THEN
						obuf[x] := CHR( (3*vl + 2*vr + 2*vb + 2*vu) DIV 28)
					ELSE
						obuf[x] := CHR(v);
					END;
					INC(pos);
				END;
				Raster.PutPixels(img, 0, y, w, Raster.A8, obuf^, 0, mode);
			END;
		END Antialias;


		PROCEDURE Load(filename : ARRAY OF CHAR; size : LONGINT) : BOOLEAN;
		VAR i, j, k, ngri, splitCount : LONGINT; res : INTEGER;
			ascent, descent : LONGINT;

		BEGIN
			fontFile := Files.Old(filename);															(* open file *)
			IF fontFile = NIL THEN RETURN FALSE END;
			ofont := OpenType.Open(filename);														(* read file *)
			IF ofont = NIL THEN KernelLog.String("OT: Could not open Font: "); KernelLog.String(filename); KernelLog.Ln; RETURN FALSE END;

			NEW(glyph);
			OpenType.InitGlyph(glyph, ofont);
			res := ScreenDPI;
			OpenType.GetInstance(ofont, 40H*size, res, res, OpenType.Identity, inst);					(* get instance *)
			IF inst = NIL THEN KernelLog.String("OT: Could not get Instance: "); KernelLog.String(filename);  KernelLog.Ln; RETURN FALSE END;

			OpenType.GetName(ofont, 1, fname);													(* get Name *)
			OpenType.GetName(ofont, 2, subfam);													(* get SubFamily *)

			nofGlyphs := glyph.font.maxp.numGlyphs;													(* number of glyphs *)
			nofGlyphRanges := 0; (*ofont.cmap.segCount;*)											(* number of ranges *)

			(* split into ranges of max size 256 *)
			ngri := ofont.cmap.segCount;
			FOR i := 0 TO ngri - 1 DO
				IF (ofont.cmap.seg[i].end # 0) THEN
					INC(nofGlyphRanges, 1 + ((ofont.cmap.seg[i].end - ofont.cmap.seg[i].start) MOD 10000H) DIV 100H)
				END
			END;

			NEW(glyphRanges, nofGlyphRanges); i := 0; k := 0;
			IF Debug  THEN KernelLog.String("-- Building Ranges: "); KernelLog.Int(nofGlyphRanges, 0); KernelLog.Ln END;
			WHILE k < ngri DO
				IF ofont.cmap.seg[k].end # 0 THEN
					splitCount := ((ofont.cmap.seg[k].end - ofont.cmap.seg[k].start) MOD 10000H) DIV 100H; j := 0;
					WHILE j < splitCount DO
						glyphRanges[i+j].firstCode := (ofont.cmap.seg[k].start MOD 10000H) + 100H*j; glyphRanges[i+j].lastCode := (ofont.cmap.seg[k].start MOD 10000H) + 100H*(j+1) - 1;
						IF Debug THEN KernelLog.String("  SRange: "); KernelLog.Int(i+j, 0); KernelLog.String("  Start: "); KernelLog.Int(glyphRanges[i+j].firstCode, 0); KernelLog.String("  End: "); KernelLog.Int(glyphRanges[i+j].lastCode, 0); KernelLog.Ln END;
						INC(j);
					END;
					glyphRanges[i+j].firstCode := (ofont.cmap.seg[k].start MOD 10000H) + 100H*splitCount ; glyphRanges[i+j].lastCode := ofont.cmap.seg[k].end MOD 10000H;
					IF Debug THEN KernelLog.String("  Range: "); KernelLog.Int(i+j, 0); KernelLog.String("  Start: "); KernelLog.Int(glyphRanges[i+j].firstCode, 0); KernelLog.String("  End: "); KernelLog.Int(glyphRanges[i+j].lastCode, 0); KernelLog.Ln END;
					INC(i, splitCount+1);
				END;
				INC(k)
			END;

(*			height := inst.font.hhea.ascender + inst.font.hhea.descender + inst.font.hhea.lineGap;
			SELF.height := SHORT(OpenTypeInt.MulDiv(height, inst.yppm, 40H*LONG(inst.font.head.unitsPerEm)));		(* height *)
*)
			ascent := inst.font.hhea.ascender;
			SELF.ascent := SHORT(OpenTypeInt.MulDiv(ascent, inst.yppm, 40H*LONG(inst.font.head.unitsPerEm)));		(* ascent *)
			descent := inst.font.hhea.descender;
			SELF.descent := -SHORT(OpenTypeInt.MulDiv(descent, inst.yppm, 40H*LONG(inst.font.head.unitsPerEm)));	(* descent *)

			RETURN TRUE
		END Load;

	END Font;

(* ------------------------------------------------- *)

VAR bit: ARRAY 100H, 8 OF BOOLEAN;					(* Bit[b, i] means bit i in byte b is set *)
	Pattern: ARRAY 360*360 DIV 8 OF CHAR;				(* enough for 36 point at 720 dpi *)
	font : Font;
	

PROCEDURE InitBitTable;
VAR b, i: LONGINT;
BEGIN
	FOR b := 0 TO 0FFH DO
		FOR i := 0 TO 7 DO
			bit[b, i] := ODD(ASH(b, -i))
		END
	END
END InitBitTable;

PROCEDURE LoadFont(name : ARRAY OF CHAR; size : LONGINT) : Font;
BEGIN
	IF Debug THEN KernelLog.String("Loading Font: "); KernelLog.String(name); KernelLog.Ln END;
	NEW(font); IF ~font.Load(name, size) THEN RETURN NIL END;
	RETURN font
END LoadFont;

PROCEDURE LoadExactFont*(fi : WMFontManager.FontInfo) : WMGraphics.Font;
VAR exactName : ARRAY 256 OF CHAR; f : WMGraphics.Font; try: LONGINT;
BEGIN
	try := 0;
	REPEAT
		COPY(fi.name^, exactName);

		IF try > 0 THEN  Strings.Append(exactName, "_")  END;
		(*	ALEX 2006.06.05 bold fonts are suffixed with bd; ex.: arialbd.ttf
			fof: but not all of them, such as calibri --> calibrib
		*)

		IF WMGraphics.FontBold IN fi.style THEN Strings.Append(exactName, "b") END;
		IF WMGraphics.FontItalic IN fi.style THEN Strings.Append(exactName, "i") END;
		Strings.Append(exactName, ".ttf");
		f := LoadFont(exactName, fi.size);
		
		IF (f = NIL) & (WMGraphics.FontBold IN fi.style) & ~(WMGraphics.FontItalic IN fi.style) THEN
			(* some fonts do use "bd" or "_bd" as suffix *)
			COPY(fi.name^, exactName);
			IF try > 0 THEN  Strings.Append(exactName, "_")  END;
			Strings.Append(exactName, "bd.ttf");
			f := LoadFont(exactName, fi.size);
		END;
		INC( try )
	UNTIL (f # NIL) OR (try >= 2);
	IF f # NIL THEN
		COPY(fi.name^, f.name);
		f.size := fi.size;
		f.style := fi.style;
	END;
	RETURN f
END LoadExactFont;

PROCEDURE LoadApproximateFont*(fi : WMFontManager.FontInfo) : WMGraphics.Font;
VAR exactName : ARRAY 256 OF CHAR; f : WMGraphics.Font;
BEGIN
	COPY(fi.name^, exactName);
	Strings.Append(exactName, ".ttf");
	f := LoadFont(exactName, fi.size);
	IF f # NIL THEN
		f.size := fi.size;
		f.style := fi.style
	END;
	RETURN f
END LoadApproximateFont;

PROCEDURE MultiTest*;
VAR name : ARRAY 256 OF CHAR; flags : SET; time, date, size : LONGINT;
	enumerator : Files.Enumerator;
	f : WMGraphics.Font;
BEGIN
	NEW(enumerator);
	enumerator.Open("*.ttf", {});
	KernelLog.String("*** TrueType MultiTester v0.1 ***"); KernelLog.Ln;
	WHILE enumerator.HasMoreEntries() DO
		IF enumerator.GetEntry(name, flags, time, date, size) THEN
			KernelLog.String("    Testing File: "); KernelLog.String(name);
			f := LoadFont(name, 40);
			IF f # NIL THEN
				KernelLog.String("            all ok")
			ELSE
				KernelLog.String("            failed")
			END;
			KernelLog.Ln
		END
	END;
	KernelLog.String("*** all done ***"); KernelLog.Ln;
	enumerator.Close;
END MultiTest;


BEGIN
	InitBitTable
END WMOTFonts.


--------------------------------------------

SystemTools.Free WMOTFonts~
WMOTFonts.MultiTest~
