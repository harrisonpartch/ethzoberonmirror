MODULE WMFigures; (** AUTHOR "staubesv, modif PH"; PURPOSE "Geometric shapes"; *)

IMPORT
	KernelLog, Streams,
	Math, Strings, XML, XMLObjects,
	WMRectangles, WMGraphics, WMGraphicUtilities, WMProperties, WMComponents;

CONST
	(* Figure.state *)
	Filled* = 0;
	Closed* = 1;
	EditPoints* = 2;
	Reshape*=3;

	PointOffset = 2; PointSize = 6; (* size of the control points. Currently not related to Effects.gravity *)

TYPE

	Point* = POINTER TO RECORD
		x, y : LONGINT;
		previous, next : Point;
		END;

TYPE

	Figure* = OBJECT(WMComponents.VisualComponent)
	VAR
		width- : WMProperties.Int32Property;
		color-, clHover- : WMProperties.ColorProperty;
		closed-: WMProperties.BooleanProperty;
		filled-: WMProperties.BooleanProperty;
		reshape-: WMProperties.BooleanProperty;

		points : Point;
		nofPoints : LONGINT;

		hover, selected : Point;
		mouseOver:BOOLEAN;

		lastKeys, state : SET;

		PROCEDURE &Init*;
		BEGIN
			Init^;
			SetNameAsString(StrFigure);
			NEW(width, PrototypeWidth, NIL, NIL); properties.Add(width);
			NEW(color, PrototypeColor, NIL, NIL); properties.Add(color);
			NEW(reshape, PrototypeReshape, NIL, NIL); properties.Add(reshape);
			NEW(closed, PrototypeClosed, NIL, NIL); properties.Add(closed);
			NEW(filled, PrototypeFilled, NIL, NIL); properties.Add(filled);
			NEW(clHover, PrototypeclHover, NIL, NIL); properties.Add(clHover);
			points := NIL;
			nofPoints := 0;
			hover := NIL;
			selected := NIL;
			state := {};
			lastKeys := {};
		END Init;
		
		PROCEDURE PropertyChanged(sender, property : ANY);
		VAR bool: BOOLEAN;
		BEGIN
			IF (property = color) THEN Invalidate;
			ELSIF (property = width) THEN Invalidate;
			ELSIF (property = clHover) THEN Invalidate;
			ELSIF (property = closed) THEN IF closed.Get() THEN INCL(state,Closed) ELSE EXCL(state,Closed); Invalidate; END;
			ELSIF (property = filled) THEN	IF filled.Get() THEN INCL(state,Filled) ELSE EXCL(state,Filled); Invalidate; END;
			ELSIF (property = reshape) THEN IF reshape.Get() THEN INCL(state,Reshape) ELSE EXCL(state,Reshape); Invalidate; END;
			ELSE 	PropertyChanged^(sender, property);
			END;
		END PropertyChanged;

		PROCEDURE Normalize(VAR newBounds : WMRectangles.Rectangle);
		END Normalize;

		PROCEDURE Scale;
		END Scale;

		PROCEDURE AddControlPoint(x, y : LONGINT);
		VAR point, p : Point; 
		BEGIN
			NEW(point);
			point.x := x; point.y := y;
			point.previous := NIL; point.next := NIL;
			Acquire;
			IF (points = NIL) THEN
				points := point;
			ELSE
				p := points;
				WHILE (p.next # NIL) DO p := p.next; END;
				p.next := point;
				point.previous := p;
			END;
			INC(nofPoints);
			Release;
		END AddControlPoint;

		PROCEDURE RemoveControlPoint(point : Point);
		BEGIN
			ASSERT(point # NIL);
			Acquire;
			IF (point.previous # NIL) THEN point.previous.next := point.next; END;
			IF (point.next # NIL) THEN point.next.previous := point.previous; END;
			point.next := NIL; point.previous := NIL;
			Release;
		END RemoveControlPoint;

		PROCEDURE Resized;
		BEGIN
			Resized^;
		END Resized;

		PROCEDURE PointerDown(x, y : LONGINT; keys : SET);
		BEGIN
			PointerDown^(x, y, keys);
			lastKeys := keys;
			IF (0 IN keys) & (selected = NIL) THEN
				selected := ThisPoint(x, y);
				IF (selected # NIL) THEN Invalidate; END;
			END;
		END PointerDown;

		PROCEDURE PointerUp(x, y : LONGINT; keys : SET);
		VAR newBounds : WMRectangles.Rectangle; point : Point;
		BEGIN
			PointerUp^(x, y, keys);
			IF ~(0 IN keys) & (selected # NIL) THEN selected := NIL; Invalidate; END;
			IF (2 IN lastKeys) & ~(2 IN keys) THEN
				IF reshape.Get() THEN EXCL(state, Reshape); ELSE INCL(state, Reshape); END;
				Invalidate;
			ELSIF (EditPoints IN state) & (1 IN lastKeys) & ~(1 IN keys) & (Reshape IN state) THEN
				AddControlPoint(x, y);
				Normalize(newBounds); bounds.Set(newBounds);
				Invalidate;
			ELSIF (EditPoints IN state) & (0 IN keys) & (0 IN lastKeys) & (2 IN lastKeys) & ~(2 IN keys) THEN
				KernelLog.String("Delete");
				point := ThisPoint(x, y);
				IF (point # NIL) THEN
					RemoveControlPoint(point);
				END;
				Normalize(newBounds); bounds.Set(newBounds);
				Invalidate;
			END;
		END PointerUp;
		
		PROCEDURE PointerMove(x, y : LONGINT; keys : SET);
		VAR p : Point; oldBounds, newBounds : WMRectangles.Rectangle;
		BEGIN
			PointerMove^(x, y, keys);
			IF (Reshape IN state) & (selected # NIL) THEN
				selected.x := x;
				selected.y := y;
				oldBounds := bounds.Get();
				Normalize(newBounds);
				IF ~WMRectangles.IsEqual(newBounds, oldBounds) THEN
					bounds.Set(newBounds);
				END;
				Invalidate;
			ELSE
				p := ThisPoint(x, y);
				IF (p # hover) THEN
					hover := p;
					Invalidate; (*? optimize *)
				END;
				IF (p=NIL) THEN
					IF HitTestLine(x,y) THEN
						IF ~mouseOver THEN mouseOver := TRUE; Invalidate END
					ELSE
						IF mouseOver THEN mouseOver := FALSE; Invalidate END
					END;
				END;
			END;
		END PointerMove;

		PROCEDURE MovePoints(dx, dy : LONGINT);
		VAR p : Point;
		BEGIN
			p := points;
			WHILE (p # NIL) DO
				p.x := p.x + dx;
				p.y := p.y + dy;
				p := p.next;
			END;
		END MovePoints;

		(* Is X, Y somewhere inside the polygon defined by p ? *)
		PROCEDURE Inside(X, Y: LONGINT): BOOLEAN;
		VAR c, q, p: LONGINT;
		BEGIN
			c := 0;
			IF (points # NIL) THEN
	(*			q := points;
				FOR i := 0 TO nofPoints - 2 DO
					IF Intersect(X, Y, points[i].x + x, points[i].y + y, points[i + 1].x + x, points[i + 1].y + y) THEN INC(c) END;
				END;
				IF (nofPoints > 1) & Intersect(X, Y, points[nofPoints-1].x + x, points[nofPoints-1].y + y, points[0].x + x, points[0].y + y) THEN INC(c) END; *)
			END;
			RETURN ODD(c);
		END Inside;

		(** Return point located at mouse position mx. my (NIL if no point at location). *)
		PROCEDURE ThisPoint*(x, y : LONGINT): Point;
		VAR p : Point;
		BEGIN
			p := points;
			WHILE (p # NIL) DO
				IF Invicinity(x, y, p.x, p.y) THEN RETURN p; END;
				p := p.next;
			END;
			RETURN NIL;
		END ThisPoint;
		
		PROCEDURE HitTestLine*(mx, my: LONGINT): BOOLEAN;
		BEGIN RETURN FALSE
		END HitTestLine;

		PROCEDURE GetBoundingBox() : WMRectangles.Rectangle;
		VAR p : Point; rect : WMRectangles.Rectangle;
		BEGIN
			rect.l := MAX(LONGINT); rect.t := MAX(LONGINT);
			rect.r := MIN(LONGINT); rect.b := MIN(LONGINT);
			Acquire;
			p := points;
			WHILE (p # NIL) DO
				IF (p.x < rect.l) THEN rect.l := p.x; END;
				IF (p.y < rect.t) THEN rect.t := p.y; END;
				IF (p.x > rect.r) THEN rect.r := p.x; END;
				IF (p.y > rect.b) THEN rect.b := p.y; END;
				p := p.next;
			END;
			Release;
			RETURN rect;
		END GetBoundingBox;

			PROCEDURE DrawControlPoint(canvas : WMGraphics.Canvas; p : Point);
			VAR rect : WMRectangles.Rectangle; color : LONGINT;
			BEGIN
				ASSERT(p # NIL);
				IF (p = selected) THEN color := WMGraphics.Yellow;
				ELSIF (p = hover) THEN color := WMGraphics.Blue;
				ELSE color := WMGraphics.White;
				END;
				rect := WMRectangles.MakeRect(p.x - PointSize DIV 2, p.y - PointSize DIV 2, p.x + PointSize DIV 2, p.y + PointSize DIV 2);
				canvas.Fill(rect, WMGraphics.White, WMGraphics.ModeSrcOverDst);
				WMGraphicUtilities.DrawRect(canvas, rect, WMGraphics.Black, WMGraphics.ModeSrcOverDst);
			END DrawControlPoint;

		PROCEDURE DrawForeground(canvas : WMGraphics.Canvas);
		VAR p : Point;
		BEGIN
			DrawForeground^(canvas);
			IF reshape.Get() THEN
				p := points;
				WHILE (p # NIL) DO
					DrawControlPoint(canvas, p);
					p := p.next;
				END;
			END;
		END DrawForeground;

		PROCEDURE ToXML;
		VAR xmlpoint, pointlist: XML.Element; 
			p:Point;
			string: ARRAY 16 OF CHAR;
		BEGIN
			RemoveContent(GetFirstChild()); (* remove old pointlist, if existing*)
			NEW(pointlist); pointlist.SetName("PointList");
			p := points;
			WHILE (p # NIL) DO
				NEW(xmlpoint); xmlpoint.SetName("Point");
				Strings.IntToStr(p.x,string); xmlpoint.SetAttributeValue("x", string);
				Strings.IntToStr(p.y,string); xmlpoint.SetAttributeValue("y", string);
				pointlist.AddContent(xmlpoint);
				p := p.next;
		END;
			AddContent(pointlist);
		END ToXML;
		
		PROCEDURE FromXML*(xml: XML.Element);
		VAR pointlist, xmlpoint: XML.Element; 
			name:Strings.String; 
			xstring, ystring: Strings.String;
			x, y: LONGINT;
		BEGIN
			FromXML^(xml);
			nofPoints := 0;
			points:=NIL;
			pointlist := xml.GetFirstChild();
			LOOP
				IF pointlist=NIL THEN RETURN END;
				name:=pointlist.GetName();	
				IF name^="PointList" THEN EXIT END;
				pointlist:=pointlist.GetNextSibling();
			END;
			
			xmlpoint:=pointlist.GetFirstChild();
			WHILE xmlpoint#NIL DO
				name:=xmlpoint.GetName();
				IF name^ = "Point" THEN
					xstring:=xmlpoint.GetAttributeValue("x"); Strings.StrToInt(xstring^, x);
					ystring:=xmlpoint.GetAttributeValue("y"); Strings.StrToInt(ystring^, y);
					AddControlPoint(x,y);
				END;
				xmlpoint := xmlpoint.GetNextSibling();
			END;
		END FromXML;
		
		PROCEDURE Write*(w : Streams.Writer;context: ANY; level : LONGINT);
		BEGIN
			ToXML;
			Write^(w, context, level);
		END Write;
		
	END Figure;

TYPE

	PointArray = POINTER TO ARRAY OF WMGraphics.Point2d;

	Line* = OBJECT(Figure)
	VAR
		pointArray : PointArray; (* {pointArray # NIL} *)

		PROCEDURE &Init*;
		BEGIN
			Init^;
			SetGenerator("WMFigures.GenLine");
			SetNameAsString(StrLine);
			IF nofPoints=0 THEN (* prototype *)
				AddControlPoint(10, 10);
				AddControlPoint(20, 20);
			END;
			INCL(state, EditPoints);
			NEW(pointArray, nofPoints);
		END Init;

		PROCEDURE Normalize(VAR newBounds : WMRectangles.Rectangle);
		VAR bounds, box : WMRectangles.Rectangle; n : LONGINT;
		BEGIN
			Acquire;
			bounds := SELF.bounds.Get();
			box := GetBoundingBox();
			n := (PointSize DIV 2) + (width.Get() DIV 2) + 1;
			box.l := box.l - n;
			box.r := box.r + n;
			box.t := box.t - n;
			box.b := box.b + n;
			newBounds.l := bounds.l + box.l;
			newBounds.t := bounds.t + box.t;
			newBounds.r := bounds.l + (box.r - box.l);
			newBounds.b := bounds.t + (box.b - box.t);
			IF (box.l # 0) OR (box.t # 0) THEN
				MovePoints(-box.l, -box.t);
			END;
			Release;
		END Normalize;

		PROCEDURE Scale;
		VAR p : Point; bounds, box : WMRectangles.Rectangle; oldWidth, oldHeight, newWidth, newHeight, n : LONGINT;
		BEGIN
			Acquire;
			bounds := SELF.bounds.Get();
			box := GetBoundingBox();
			oldWidth := box.r - box.l;
			oldHeight := box.b - box.t;
			n := (PointSize DIV 2) + (width.Get() DIV 2) + 1;
			newWidth := bounds.r - bounds.l - 2*n;
			newHeight := bounds.b - bounds.t - 2*n;
			IF (oldWidth # 0) & (oldHeight # 0) THEN
				p := points;
				WHILE (p # NIL) DO
					p.x := (p.x - box.l) * newWidth DIV oldWidth + box.l;
					p.y := (p.y - box.t) * newHeight DIV oldHeight + box.t;
					p := p.next;
				END;
			END;
			Release;
		END Scale;

		(* Is X, Y somewhere inside the polygon defined by p ? *)
		PROCEDURE Inside(X, Y: LONGINT): BOOLEAN;
		VAR c: LONGINT; p, q: Point;
		BEGIN
			c := 0;
			IF (points # NIL) THEN
				p := points; q:=p.next;
				WHILE q#NIL DO
					IF Intersect(X, Y, p.x, p.y, q.x, q.y) THEN INC(c) END;
					p:=q; q:=q.next; 
				END;
				IF (nofPoints > 1) & Intersect(X, Y, p.x, p.y, points.x, points.y) THEN INC(c) END; 
			END;
			RETURN ODD(c);
		END Inside;

		PROCEDURE HitTestLine*(mx, my: LONGINT): BOOLEAN;
		VAR p, q: Point; i : LONGINT;
		BEGIN
			IF (points = NIL) OR (points.next = NIL) THEN RETURN FALSE; END;
			IF Filled IN state THEN
				IF Inside(mx, my) THEN RETURN TRUE END;
			END;
			p := points; q := points.next;
			WHILE (q # NIL) DO
				IF InLineVicinity(mx, my, p.x, p.y, q.x, q.y) THEN RETURN TRUE END;
				p:=q; q:=q.next;
				INC(i);
			END;
			IF (Closed IN state) OR (Filled IN state) THEN
				IF InLineVicinity(mx, my, p.x, p.y, points.x, points.y) THEN RETURN TRUE END;
			END;
			RETURN FALSE
		END HitTestLine;

		PROCEDURE DrawBackground(canvas : WMGraphics.Canvas);
		VAR p : Point; i : LONGINT;
		BEGIN
			DrawBackground^(canvas);
			IF (nofPoints # LEN(pointArray)) THEN
				NEW(pointArray, nofPoints);
			END;
			p := points; i := 0;
			WHILE (p # NIL) DO
				pointArray[i].x := p.x;
				pointArray[i].y := p.y;
				INC(i);
				p := p.next;
			END;
			IF filled.Get() THEN
				canvas.FillPolygonFlat(pointArray^, nofPoints, color.Get(), WMGraphics.ModeSrcOverDst);
			ELSE
				canvas.PolyLine(pointArray^, nofPoints, closed.Get(), color.Get(), WMGraphics.ModeSrcOverDst);
			END;
		END DrawBackground;

	END Line;

TYPE

	Circle* = OBJECT(Figure)

		PROCEDURE &Init*;
		BEGIN
			Init^;
			SetGenerator("WMFigures.GenCircle");
			SetNameAsString(StrCircle);
			AddControlPoint(10, 10);
			AddControlPoint(20, 20);
			INCL(state, EditPoints);
		END Init;

		PROCEDURE Normalize(VAR newBounds : WMRectangles.Rectangle);
		VAR bounds : WMRectangles.Rectangle; p, q : Point; r, n : LONGINT;
		BEGIN
			Acquire;
			bounds := SELF.bounds.Get();
			p := points; q := p.next;
			r := Distance(p.x, p.y, q.x, q.y);
			n := r + (PointSize DIV 2) + (width.Get() DIV 2) + 1;
			newBounds.l := bounds.l + p.x - n;
			newBounds.r := bounds.l + 2*n;
			newBounds.t := bounds.t + p.y - n;
			newBounds.b := bounds.t + 2*n;
			MovePoints(-(p.x - n), -(p.y - n));
			Release;
		END Normalize;

		PROCEDURE DrawBackground(canvas : WMGraphics.Canvas);
		VAR p, q : Point;
		BEGIN
			DrawBackground^(canvas);
			p := points;
			q := points.next;
			canvas.SetColor(color.Get());
			WMGraphicUtilities.Circle(canvas, p.x, p.y, Distance(p.x, p.y, q.x, q.y));
		END DrawBackground;

	END Circle;

TYPE

	Rectangle* = OBJECT(Figure)

		PROCEDURE &Init*;
		BEGIN
			Init^;
			SetGenerator("WMFigures.GenRectangle");
			SetNameAsString(StrRectangle);
			AddControlPoint(10, 10);
			AddControlPoint(20, 20);
			INCL(state, EditPoints);
		END Init;

		PROCEDURE Normalize(VAR newBounds : WMRectangles.Rectangle);
		VAR p, q : Point; bounds, box : WMRectangles.Rectangle; n : LONGINT;
		BEGIN
			Acquire;
			p := points;
			q := p.next;
			bounds := SELF.bounds.Get();
			n := (PointSize DIV 2) + (width.Get() DIV 2) + 1;
			box.l := Min(p.x, q.x) - n;
			box.r := Max(p.x, q.x) + n;
			box.t := Min(p.y, q.y) - n;
			box.b := Max(p.y, q.y) + n;
			newBounds.l := bounds.l + box.l;
			newBounds.t := bounds.t + box.t;
			newBounds.r := bounds.l + (box.r - box.l);
			newBounds.b := bounds.t + (box.b - box.t);
			MovePoints(-box.l, -box.t);
			Release;
		END Normalize;

		PROCEDURE DrawBackground(canvas : WMGraphics.Canvas);
		VAR p, q : Point; rect : WMRectangles.Rectangle;
		BEGIN
			DrawBackground^(canvas);
			p := points;
			q := points.next;
			rect.l := Min(p.x, q.x);
			rect.r := Max(p.x, q.x);
			rect.t := Min(p.y, q.y);
			rect.b := Max(p.x, q.x);
			WMGraphicUtilities.DrawRect(canvas, rect, color.Get(), WMGraphics.ModeSrcOverDst);
		END DrawBackground;

	END Rectangle;

TYPE

	Spline* = OBJECT(Figure)
	VAR
		pointArray : ARRAY 2048 OF WMGraphics.Point2d;

		PROCEDURE &Init*;
		BEGIN
			Init^;
			SetGenerator("WMFigures.GenSpline");
			SetNameAsString(StrSpline);
			INCL(state, EditPoints);
			IF nofPoints=0 THEN (* prototype*)
				AddControlPoint(0, 20);
				AddControlPoint(20, 0);
				AddControlPoint(20, 20);
				AddControlPoint(30, 30);
			END;
		END Init;
		
				(* Is X, Y somewhere inside the polygon defined by p ? *) (*! to be implemented for pointarray; eliminate bias*)
		PROCEDURE Inside(X, Y: LONGINT): BOOLEAN;
		VAR c: LONGINT; p,q: Point;
		BEGIN
			c := 0;
			IF (points # NIL) THEN
				p := points; q := p.next;
				WHILE q#NIL DO
					IF Intersect(X, Y, p.x, p.y, q.x, q.y) THEN INC(c) END;
					p:=q; q:=q.next;
				END;
				IF (nofPoints > 1) & Intersect(X, Y, p.x, p.y, points.x, points.y) THEN INC(c) END; 
			END;
			RETURN ODD(c);
		END Inside;
		
		(*! to be implemented for full pointarray, not only for control points  with straight connections, eliminate bias*)
		PROCEDURE HitTestLine*(mx, my: LONGINT): BOOLEAN;
		VAR p, q: Point; i : LONGINT;
		BEGIN
			IF (points = NIL) OR (points.next = NIL) THEN RETURN FALSE; END;
			IF Filled IN state THEN
				IF Inside(mx, my) THEN RETURN TRUE END;
			END;
			p := points; q := points.next;
			WHILE (q # NIL) DO
				IF InLineVicinity(mx, my, p.x, p.y, q.x, q.y) THEN RETURN TRUE END;
				p:=q; q:=q.next; INC(i);
			END;
			IF (Closed IN state) OR (Filled IN state) THEN
				IF InLineVicinity(mx, my, p.x, p.y, points.x, points.y) THEN RETURN TRUE END;
			END;
			RETURN FALSE
		END HitTestLine;

		PROCEDURE Normalize(VAR newBounds : WMRectangles.Rectangle);
		VAR bounds, box : WMRectangles.Rectangle; i, n : LONGINT;
		BEGIN
			bounds := SELF.bounds.Get();
			Acquire;
			SplineToPoly(points, closed.Get(), pointArray, n);
			box.l := MAX(LONGINT); box.r := MIN(LONGINT);
			box.t := MAX(LONGINT); box.b := MIN(LONGINT);
			FOR i := 0 TO n - 1 DO
				IF (pointArray[i].x < box.l) THEN box.l := pointArray[i].x; END;
				IF (pointArray[i].x > box.r) THEN box.r := pointArray[i].x; END;
				IF (pointArray[i].y < box.t) THEN box.t := pointArray[i].y; END;
				IF (pointArray[i].y > box.b) THEN box.b := pointArray[i].y; END;
			END;
			n := (PointSize DIV 2) + (width.Get() DIV 2) + 1;
			box.l := box.l - n;
			box.r := box.r + n;
			box.t := box.t - n;
			box.b := box.b + n;
			MovePoints(-box.l, -box.t);
			newBounds.l := bounds.l + box.l;
			newBounds.r := bounds.l + (box.r - box.l);
			newBounds.t := bounds.t + box.t;
			newBounds.b := bounds.t + (box.b - box.t);
			Release;
		END Normalize;

		PROCEDURE DrawBackground(canvas : WMGraphics.Canvas);
		VAR n : LONGINT; p: Point; col: LONGINT;
		BEGIN
			DrawBackground^(canvas);
			SplineToPoly(points, Closed IN state, pointArray, n);
			IF mouseOver THEN col:=clHover.Get() ELSE col:=color.Get() END;
			IF filled.Get() THEN
				canvas.FillPolygonFlat(pointArray, n, col, WMGraphics.ModeSrcOverDst);
			ELSE
				canvas.PolyLine(pointArray, n, closed.Get(), col, WMGraphics.ModeSrcOverDst);
			END;
		END DrawBackground;

	END Spline;



VAR
	(* Size of gravity spot used for "snapping" the cursor *)
	gravity : LONGINT;

	PrototypeWidth : WMProperties.Int32Property;
	PrototypeColor, PrototypeclHover : WMProperties.ColorProperty;
	PrototypeClosed: WMProperties.BooleanProperty;
	PrototypeFilled: WMProperties.BooleanProperty;
	PrototypeReshape: WMProperties.BooleanProperty;

	StrFigure, StrLine, StrCircle, StrRectangle, StrSpline : Strings.String;

(* start of Rege code *)

PROCEDURE MakePoly(CONST RX, RY, RXstrich, RYstrich, RS: ARRAY OF REAL; n: LONGINT; VAR points : ARRAY OF WMGraphics.Point2d; VAR k: LONGINT);
 TYPE
 	Polynom = RECORD A, B, C, D: REAL END;
 VAR
 	i, cs, smax, k1: LONGINT; px, py: Polynom;
	x, dx1, dx2, dx3, y, dy1, dy2, dy3: REAL; L, B, R, T,dW  : LONGINT;

	PROCEDURE GetPolynom((* VAR *) y1, y2, y1s, y2s: REAL; VAR p: Polynom);
		VAR dx1, dyx: REAL;
	BEGIN
		IF RS[i] # RS[i+1] THEN dx1 := 1.0/(RS[i + 1] - RS[i]) ELSE dx1 := 1.0 END;
		dyx := (y2 - y1)*dx1;
		p.A := dx1*dx1*(-2.0*dyx + y1s + y2s);
		p.B := dx1*(3.0*dyx - 2.0*y1s - y2s);
		p.C := y1s;
		p.D := y1
	END GetPolynom;

BEGIN
	points[0].x := SHORT(ENTIER(RX[1])); points[0].y := SHORT(ENTIER(RY[1]));
	L := MAX(LONGINT);  B := MAX(LONGINT); R := MIN(LONGINT); T := MIN(LONGINT);
	i := 1; WHILE i <= n DO
		L := Min(L,SHORT(ENTIER(RX[i]))); B := Min(B,SHORT(ENTIER(RY[i])));
		R := Max(R,SHORT(ENTIER(RX[i]))); T := Max(T,SHORT(ENTIER(RY[i])));
		INC(i);
	END;

	dW := Max(1,Min((Max(R-L ,T-B)  * 3 DIV n DIV 20),4));
	i := 1; k := 1;
	WHILE i < n DO
		GetPolynom(RX[i], RX[i+1], RXstrich[i], RXstrich[i+1], px);
		x := px.D;
		dx1 := px.A + px.B + px.C;
		dx3 := 6.0*px.A;
		dx2 := dx3 + 2.0*px.B;
		GetPolynom(RY[i], RY[i+1], RYstrich[i], RYstrich[i+1], py);
		y := py.D;
		dy1 := py.A + py.B + py.C;
		dy3 := 6.0*py.A;
		dy2 := dy3 + 2.0*py.B;
		smax := SHORT(ENTIER(RS[i+1]-RS[i]));
		cs := 0;
		WHILE cs <= smax DO
			points[k].x := SHORT(ENTIER(x)); points[k].y := SHORT(ENTIER(y));
			k1 := k-1;
			IF (ABS(points[k].x - points[k1].x) > dW) OR (ABS(points[k].y - points[k1].y) > dW) THEN INC(k) END;
			x   := x + dx1;    y   := y + dy1;
			dx1 := dx1 + dx2;  dy1 := dy1 + dy2;
			dx2 := dx2 + dx3;  dy2 := dy2 + dy3;
			INC(cs);
		END;
		INC(i);
	END; (* FOR i *)
	points[k].x := SHORT(ENTIER(RX[n])); points[k].y := SHORT(ENTIER(RY[n])); INC(k);
END MakePoly;

PROCEDURE SplineToPoly(c: Point; closed: BOOLEAN; VAR points : ARRAY OF WMGraphics.Point2d; VAR k: LONGINT);
TYPE
	RealVect = ARRAY 256 OF REAL;
VAR
	n, i: LONGINT; RS, RX, RY ,RXstrich, RYstrich : RealVect; dx, dy: REAL;
	helpR: REAL;

	PROCEDURE NatSplineDerivates(VAR x, y, d: ARRAY OF REAL; n: LONGINT);
	VAR i: LONGINT; d1, d2: REAL; a, b, c: RealVect;

		PROCEDURE SolveTriDiag(VAR a, b, c: ARRAY OF REAL; n: LONGINT; VAR y: ARRAY OF REAL);
		VAR i: LONGINT; t: REAL;
		BEGIN i := 1;
			WHILE i < n DO t := a[i]; c[i] := c[i]/t; helpR := c[i]*b[i]; a[i+1] := a[i+1] -  helpR; INC(i); END;
			i := 2;
			WHILE i <= n DO helpR := c[i-1]*y[i-1]; y[i] := y[i] - helpR; INC(i); END;
			t := a[n]; y[n] := y[n]/t; i := n-1;
			WHILE i > 0 DO  t := y[i+1]; helpR :=y[i] - b[i]*t; y[i] := helpR/a[i]; DEC(i) END
		END SolveTriDiag;

		BEGIN  (* NatSplineDerivates *)
			IF x[1] # x[2] THEN b[1] := 1.0/(x[2] - x[1]); ELSE b[1] := 1.0 END;
			a[1] := 2.0*b[1]; c[1] := b[1];
			d1 := (y[2] - y[1])*3.0*b[1]*b[1];
			d[1] := d1;
			i :=2;
			WHILE i < n DO
				IF x[i] # x[i+1] THEN b[i] := 1.0 /(x[i+1] - x[i]) ELSE b[i] := 1.0 END;
				a[i] := 2.0*(c[i-1] + b[i]); c[i] := b[i];
				d2 := (y[i+1] - y[i])*3.0*b[i]*b[i];
				d[i] := d1 + d2; d1 := d2;
				INC(i);
			END;
			a[n] := 2.0*b[n-1]; d[n] := d1;
			SolveTriDiag(a, b, c, n, d)
		END NatSplineDerivates;

	PROCEDURE ClSplineDerivates(VAR x, y, d: ARRAY OF REAL; n: LONGINT);
		VAR i: LONGINT; hn1, dn1, d1, d2: REAL; a, b, c, u: RealVect;

		PROCEDURE SolveTriDiag2(VAR a, b, c: ARRAY OF REAL; n:LONGINT; VAR y1, y2: ARRAY OF REAL);
		VAR i: LONGINT; t: REAL;
		BEGIN
			i := 1;
			WHILE i < n DO
				t := a[i]; c[i] := c[i]/t;
				helpR := c[i]*b[i]; a[i+1] := a[i+1] - helpR;
				INC(i)
			END;
			i :=2;
			WHILE i <= n DO
				helpR := c[i-1]*y1[i-1];  y1[i] := y1[i] - helpR;
				helpR :=  c[i-1]*y2[i-1]; y2[i] := y2[i] - helpR;
				INC(i);
			END;
			t := a[n]; y1[n] := y1[n]/t; t := a[n]; y2[n] := y2[n]/t;
			i := n-1;
			WHILE i > 0 DO
				t := y1[i+1]; helpR := y1[i] - b[i]* t; y1[i] := helpR/a[i];
				t := y2[i+1]; helpR :=y2[i] - b[i]*t; y2[i] := helpR/a[i];
				DEC(i)
			END
		END SolveTriDiag2;

	BEGIN  (* ClSplineDerivates *)
		hn1 := 1.0/(x[n] - x[n-1]);
		dn1 := (y[n] - y[n-1])*3.0*hn1*hn1;
		IF x[2] # x[1] THEN
			b[1] := 1.0/(x[2] - x[1]);
		ELSE
			b[1] := 0
		END;
		a[1] := hn1 + 2.0*b[1];
		c[1] := b[1];
		d1 := (y[2] - y[1])*3.0*b[1]*b[1];
		d[1] := dn1 + d1;
		u[1] := 1.0;
		i := 2;
		WHILE i < n-1 DO
			IF x[i+1] # x[i] THEN b[i] := 1.0/(x[i+1] - x[i]) ELSE b[i] := 0 END;
			a[i] := 2.0*(c[i-1] + b[i]);
			c[i] := b[i];
			d2 := (y[i+1] - y[i])*3.0*b[i]*b[i];
			d[i] := d1 + d2;
			d1 := d2;
			u[i] := 0.0;
			INC(i)
		END;
		a[n-1] := 2.0*b[n-2] + hn1;
		d[n-1] := d1 + dn1;
		u[n-1] := 1.0;
		SolveTriDiag2(a, b, c, n-1, u, d);
		helpR := u[1] + u[n-1] + x[n] - x[n-1];
		d1 := (d[1] + d[n-1])/helpR;
		i := 1;
		WHILE i < n DO
			d[i] := d[i] - d1*u[i];
			INC(i)
		END;
		d[n] := d[1]
	END ClSplineDerivates;

BEGIN
	n := 0; WHILE c # NIL DO RX[n+1] := c.x ; RY[n+1] := c.y; INC(n); c := c.next END;
	IF closed THEN RX[n+1] := RX[1]; RY[n+1] := RY[1]; INC(n) ; END;
	RS[1] := 0.0; i := 2;
	WHILE i <= n DO
		dx := RX[i] - RX[i-1];  dy := RY[i] - RY[i-1];
		RS[i] := RS[i-1] + Math.sqrt(dx*dx + dy*dy);
		INC(i);
	END;
	IF ~closed THEN
		NatSplineDerivates(RS, RX, RXstrich, n);
		NatSplineDerivates(RS, RY, RYstrich, n);
	ELSE
		ClSplineDerivates(RS, RX, RXstrich, n);
		ClSplineDerivates(RS, RY, RYstrich, n)
	END;
	MakePoly(RX, RY, RXstrich, RYstrich, RS, n, points, k);
END SplineToPoly;

(* end of Rege code *)


(** Returns TRUE if mx, my is within gravity pixels from X, Y. *)
PROCEDURE Invicinity(mx, my, X, Y: LONGINT): BOOLEAN;
BEGIN RETURN (mx - X) * (mx - X) + (my - Y) * (my - Y) < gravity * gravity
END Invicinity;

(** Returns TRUE if mx, my is within gravity pixels of the line from X, Y to X1, Y1. *)
PROCEDURE InLineVicinity(mx, my, X, Y, X1, Y1: LONGINT): BOOLEAN;
VAR  w, h, pw, ph, det,len : LONGINT;

	PROCEDURE Between(x, a, b: LONGINT): BOOLEAN;
	VAR min, max: LONGINT;
	BEGIN
		min := Min(a, b); max := Max(a, b);
		RETURN (min - gravity <= x) & (x <= max + gravity);
	END Between;

BEGIN
	IF ABS(X - X1) > gravity  THEN
		IF ABS(Y - Y1) > gravity THEN
			IF Invicinity(mx, my,X, Y) OR Invicinity(mx, my,X1, Y1) THEN RETURN TRUE END;
			pw := mx - X; ph := my - Y; w := X1 -X;  h := Y1 - Y;
			det := pw * h - ph * w; len := w * w + h * h;
			RETURN  Between(mx, X, X1) & Between(my, Y, Y1) & (det / len * det < gravity * gravity)
		ELSE
			RETURN Between(mx, X, X1) & (ABS(my - Y) < gravity)
		END
	ELSE
		RETURN Between(my, Y, Y1) & (ABS(mx - X) < gravity)
	END
END InLineVicinity;

PROCEDURE Intersect(X, Y, x0,y0,x1,y1 : LONGINT) : BOOLEAN;
BEGIN
	IF ((Y >= y0) & (Y < y1)) OR ((Y >= y1) & (Y < y0)) THEN
		IF y1 > y0 THEN RETURN x0 + (Y - y0) * (x1 -x0) DIV (y1 - y0) - X >= 0
		ELSIF y1 <  y0 THEN RETURN x0 + (Y - y0) * (x0 -x1) DIV (y0 - y1) - X >= 0
		ELSE RETURN (x0 > X) OR (x1 > X)
		END
	ELSE RETURN FALSE
	END
END Intersect;

PROCEDURE Distance(x, y, x0, y0: LONGINT): LONGINT;
VAR dx, dy: LONGINT;
BEGIN dx := x - x0; dy := y - y0;
	RETURN SHORT(ENTIER(Math.sqrt(dx * dx + dy * dy)))
END Distance;

PROCEDURE Min(x, y: LONGINT): LONGINT;
BEGIN IF x < y THEN RETURN x ELSE RETURN y END
END Min;

PROCEDURE Max(x, y: LONGINT): LONGINT;
BEGIN IF x > y THEN RETURN x ELSE RETURN y END
END Max;

PROCEDURE GenLine*() : XML.Element;
VAR line : Line;
BEGIN
	NEW(line); RETURN line;
END GenLine;

PROCEDURE GenCircle*() : XML.Element;
VAR circle : Circle;
BEGIN
	NEW(circle); RETURN circle;
END GenCircle;

PROCEDURE GenRectangle*() : XML.Element;
VAR rectangle : Rectangle;
BEGIN
	NEW(rectangle); RETURN rectangle;
END GenRectangle;

PROCEDURE GenSpline*() : XML.Element;
VAR spline : Spline;
BEGIN
	NEW(spline); RETURN spline;
END GenSpline;

PROCEDURE InitPrototypes;
BEGIN
	NEW(PrototypeWidth, NIL, Strings.NewString("width"), Strings.NewString("Width of stroke"));
	PrototypeWidth.Set(1);
	NEW(PrototypeColor, NIL, Strings.NewString("color"), Strings.NewString("Color"));
	PrototypeColor.Set(WMGraphics.Red);
	NEW(PrototypeclHover, NIL, Strings.NewString("clHover"), Strings.NewString("Color HOver"));
	PrototypeColor.Set(WMGraphics.Yellow);
	NEW(PrototypeClosed, NIL, Strings.NewString("closed"), Strings.NewString("Figure is closed"));
	PrototypeClosed.Set(FALSE);
	NEW(PrototypeFilled, NIL, Strings.NewString("filled"), Strings.NewString("Figure is filled"));
	PrototypeFilled.Set(FALSE);
	NEW(PrototypeReshape, NIL, Strings.NewString("reshape"), Strings.NewString("Control Points can be individually moved"));
	PrototypeReshape.Set(TRUE);
END InitPrototypes;

PROCEDURE InitStrings;
BEGIN
	StrFigure := Strings.NewString("Figure");
	StrLine := Strings.NewString("Line");
	StrCircle := Strings.NewString("Circle");
	StrRectangle := Strings.NewString("Rectangle");
	StrSpline := Strings.NewString("Spline");
END InitStrings;

BEGIN
	gravity := 6;
	InitStrings;
	InitPrototypes;
END WMFigures.

SystemTools.FreeDownTo WMFigures ~
