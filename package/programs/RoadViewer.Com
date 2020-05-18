COMPONENT RoadViewer REQUIRES FileSystem, GraphicView;
	CONSTANT 
		NetworkFile = "ch_net.xml";
		Black = 0000000H; 

	VARIABLE 
		nodeX[id: INTEGER]: INTEGER; nodeY[id: INTEGER]: INTEGER;
		linkFrom[id: INTEGER]: INTEGER; linkTo[id: INTEGER]: INTEGER;
		minX, minY: INTEGER; maxX, maxY: INTEGER; scale: INTEGER;
	
	PROCEDURE ReadNetwork;
	VARIABLE reader: RoadNetworkReader; id, x, y, from, to: INTEGER; len, cap, speed: REAL; lanes: INTEGER; t: BOOLEAN;
	BEGIN
		minX := MAX(INTEGER); minY := MAX(INTEGER); maxX := MIN(INTEGER); maxY := MIN(INTEGER);
		NEW(reader); CONNECT(FileSystem(reader), FileSystem);
		RoadData(reader)!Read(NetworkFile);
		WHILE RoadData(reader)?Node DO
			RoadData(reader)?Node(id, x, y); nodeX[id] := x; nodeY[id] := y;
			IF x < minX THEN minX := x END; IF y < minY THEN minY := y END;
			IF x > maxX THEN maxX := x END; IF y > maxY THEN maxY := y END
		END;
		WHILE RoadData(reader)?Link DO
			RoadData(reader)?Link(id, from, to, len, cap, lanes, speed, t); linkFrom[id] := from; linkTo[id] := to
		END;
		RoadData(reader)?Finish
	END ReadNetwork;
	
	PROCEDURE ScaleGraphic;
	VARIABLE W, H, w, h, c: INTEGER;
	BEGIN
		w := maxX - minX; h := maxY - minY;
		GraphicView!GetSize; GraphicView?Size(W, H, c);
		IF (W > 0) AND (H > 0) THEN
			IF w / W > h / H THEN scale := INTEGER(w / W) ELSE scale := INTEGER(h / H) END
		ELSE
			scale := 1
		END;
		WRITE("("); WRITE(minX); WRITE(","); WRITE(minY); WRITE(") -> ("); 
		WRITE(maxX); WRITE(", "); WRITE(maxY); WRITE(") scale "); 
		WRITE(scale); WRITELINE
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

	PROCEDURE DrawNetwork;
	VARIABLE id, from, to, x1, y1, x2, y2: INTEGER;
	BEGIN
		GraphicView!Clear;
		FOREACH id OF linkFrom DO
			from := linkFrom[id]; to := linkTo[id];
			x1 := nodeX[from]; y1 := nodeY[from];
			x2 := nodeX[to]; y2 := nodeY[to];
			DrawLine(x1, y1, x2, y2)
		END
	END DrawNetwork;
			
	BEGIN
		ReadNetwork;
		ScaleGraphic;
		DrawNetwork
END RoadViewer;

