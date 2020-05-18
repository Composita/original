COMPONENT RoadAnimator REQUIRES FileSystem, SystemTime, GraphicView;
	CONSTANT 
		NetworkFile = "zurich_network.xml";
		SnapshotFile = "snapshot1.txt";
		TimeIntervall = 500; (* ms *)
		EndTime = 86400;
		Black = 0000000H; Red = 0FF0000H;
		Zoom = FALSE; 
		ZoomX = 660000; ZoomY = 250000; 
		ZoomRadius = 50000;

	VARIABLE 
		nodeX[id: INTEGER]: INTEGER; nodeY[id: INTEGER]: INTEGER;
		linkFrom[id: INTEGER]: INTEGER; linkTo[id: INTEGER]: INTEGER;
		minX, minY: INTEGER; maxX, maxY: INTEGER; scale: REAL;
		trans: TextTransformer; background: INTEGER;
		Width, Height: INTEGER;
	
	PROCEDURE ReadNetwork;
	VARIABLE reader: RoadNetworkReader; id, x, y, from, to, k: INTEGER; len, cap, speed: REAL; lanes: INTEGER; t: BOOLEAN;
	BEGIN
		minX := MAX(INTEGER); minY := MAX(INTEGER); maxX := MIN(INTEGER); maxY := MIN(INTEGER);
		NEW(reader); CONNECT(FileSystem(reader), FileSystem);
		RoadData(reader)!Read(NetworkFile);
		WHILE RoadData(reader)?Node DO
			RoadData(reader)?Node(id, x, y); nodeX[id] := x; nodeY[id] := y;
			IF x < minX THEN minX := x END; IF y < minY THEN minY := y END;
			IF x > maxX THEN maxX := x END; IF y > maxY THEN maxY := y END
		END;
		IF Zoom THEN
			minX := ZoomX - ZoomRadius; minY := ZoomY - ZoomRadius;
			maxX := ZoomX + ZoomRadius; maxY := ZoomY + ZoomRadius
		END;
		WRITE("Scale "); WRITE(minX); WRITE(", "); WRITE(minY); WRITE(" "); 
		WRITE(maxX); WRITE(", "); WRITE(maxY); WRITELINE;
		k := 0;
		WHILE RoadData(reader)?Link DO
			RoadData(reader)?Link(id, from, to, len, cap, lanes, speed, t); linkFrom[id] := from; linkTo[id] := to;
			INC(k); IF k MOD 1000 = 0 THEN WRITE("Link "); WRITE(k); WRITE(" read"); WRITELINE END
		END;
		RoadData(reader)?Finish
	END ReadNetwork;
	
	PROCEDURE ScaleGraphic;
	VARIABLE w, h: INTEGER;
	BEGIN
		w := maxX - minX; h := maxY - minY;
		GraphicView!GetSize; GraphicView?Size(Width, Height, background);
		IF (Width > 0) AND (Height > 0) THEN
			IF w / Width > h / Height THEN scale := w / Width ELSE scale := h / Height END
		ELSE
			scale := 1.0
		END
	END ScaleGraphic;
	
	PROCEDURE ABS(x: REAL): REAL;
	BEGIN IF x < 0 THEN RETURN -x ELSE RETURN x END
	END ABS;
	
	PROCEDURE DrawLine(x1, y1, x2, y2: INTEGER);
	VARIABLE xd, yd, theta, distance, d, x, y: REAL; xp, yp: INTEGER;
	BEGIN
		xd := x2 - x1; yd := y2 - y1;
		IF xd > 0 THEN theta := ARCTAN(yd / xd)
		ELSIF xd < 0 THEN theta := PI + ARCTAN(yd / xd)
		ELSIF yd > 0 THEN theta := PI / 2
		ELSE theta := PI * 3 / 2
		END;
		distance := SQRT(xd * xd + yd * yd); d := 0.0;
		WHILE d < distance DO
			x := x1 + d * COS(theta); y := y1 + d * SIN(theta); 
			xp := INTEGER((x - minX) / scale);
			yp := INTEGER((maxY - y) / scale);
			GraphicView!Pixel(xp, yp, Black);
			d := d + scale
		END
	END DrawLine;
	
	PROCEDURE DrawScale;
	VARIABLE t: TEXT; y, x, d, p: INTEGER;
	BEGIN
		d := INTEGER(50 * scale); p := INTEGER(2 * scale);
		x := minX + INTEGER(400 * scale); y := maxY - d;
		DrawLine(x, y, x + d, y);
		DrawLine(x, y - p, x, y + p);
		DrawLine(x + d, y - p, x + d, y + p);
		IF d > 10000 THEN 
			d := d DIV 1000;
			TextGenerator(trans)!MakeInteger(d); TextGenerator(trans)?Text(t);
			TextGenerator(trans)!Append(t, " km"); TextGenerator(trans)?Text(t)
		ELSE
			TextGenerator(trans)!MakeInteger(d); TextGenerator(trans)?Text(t);
			TextGenerator(trans)!Append(t, " m"); TextGenerator(trans)?Text(t)
		END;
		DrawText(x + p, y + 5 * p, t)
	END DrawScale;
	
	PROCEDURE DrawText(x, y: INTEGER; t: TEXT);
	VARIABLE i, xp, yp: INTEGER;
	BEGIN
		xp := INTEGER((x - minX) / scale); yp := INTEGER((maxY - y) / scale); i := 0; 
		WHILE t[i] # 0X DO GraphicView!Font(xp + i * 8, yp, t[i], Black); INC(i) END
	END DrawText;

	PROCEDURE DrawNetwork;
	VARIABLE id, from, to, x1, y1, x2, y2: INTEGER;
	BEGIN
		GraphicView!SetLayer(0);
		GraphicView!Clear;
		FOREACH id OF linkFrom DO
			from := linkFrom[id]; to := linkTo[id];
			x1 := nodeX[from]; y1 := nodeY[from];
			x2 := nodeX[to]; y2 := nodeY[to];
			DrawLine(x1, y1, x2, y2)
		END;
		DrawScale;
		GraphicView!DrawLayers
	END DrawNetwork;
			
	PROCEDURE DrawCars;
	VARIABLE reader: SnapshotReader; lastTime, carId, time: INTEGER; x, y: REAL; xp, yp: INTEGER;
	BEGIN
		NEW(reader); CONNECT(FileSystem(reader), FileSystem);
		SnapshotInput(reader)!Read(SnapshotFile); lastTime := 0;
		GraphicView!SetLayer(1);
		WHILE SnapshotInput(reader)?CarLocation DO
			SnapshotInput(reader)?CarLocation(carId, time, x, y);
			IF (time # lastTime) AND (time <= EndTime) THEN
				GraphicView!DrawLayers;
				SystemTime!Wait(TimeIntervall); SystemTime?Passed;
				GraphicView!Clear; lastTime := time; 
				IF time MOD 15 * 60 = 0 THEN
					WRITE("TIME="); WRITE(time DIV 3600); WRITE(":");
					IF time DIV 60 MOD 60 < 10 THEN WRITE(0) END;
					WRITE(time DIV 60 MOD 60); WRITELINE
				END
			END;
			xp := INTEGER((x - minX) / scale);
			yp := INTEGER((maxY - y) / scale);
			GraphicView!Fill(xp-1, yp-1, 2, 2, Red)
		END;
		SnapshotInput(reader)?Finish;
		SystemTime!Wait(TimeIntervall); SystemTime?Passed;
		(* GraphicView!Clear; GraphicView!DrawLayers *)
	END DrawCars;

	BEGIN
		NEW(trans);
		ReadNetwork;
		ScaleGraphic;
		DrawNetwork;
		DrawCars
END RoadAnimator;

