INTERFACE SnapshotOutput;
	IN Start { IN CarPosition(time, carId, linkId, fromNode: INTEGER; fromX, fromY, toX, toY, distance: REAL) } IN Stop
END SnapshotOutput;

COMPONENT SnapshotWriter OFFERS SnapshotOutput, WriterControl REQUIRES FileSystem;
	CONSTANT FileSuffix = ".txt"; TAB = 09X; CR = 0DX;
	
	VARIABLE open: BOOLEAN; nofUsers: INTEGER; trans: TextTransformer;
	
	PROCEDURE IntegerToText(int: INTEGER): TEXT;
	VARIABLE text: TEXT;
	BEGIN TextGenerator(trans)!MakeInteger(int); TextGenerator(trans)?Text(text); RETURN text
	END IntegerToText;
	
	PROCEDURE RealToText(real: REAL): TEXT;
	VARIABLE text: TEXT;
	BEGIN TextGenerator(trans)!MakeReal(real); TextGenerator(trans)?Text(text); RETURN text
	END RealToText;
	
	PROCEDURE MakeFileName(prefix: TEXT; version: INTEGER; VARIABLE filename: TEXT);
	VARIABLE x: TEXT; 
	BEGIN 
		x := IntegerToText(version);
		TextGenerator(trans)!Append(prefix, x); TextGenerator(trans)?Text(filename);
		TextGenerator(trans)!Append(filename, FileSuffix); TextGenerator(trans)?Text(filename)
	END MakeFileName;
			
	IMPLEMENTATION WriterControl;
	VARIABLE prefix, filename: TEXT; version: INTEGER;
	BEGIN
		WHILE ?Start DO
			?Start(prefix, version);
			BEGIN {EXCLUSIVE}
				MakeFileName(prefix, version, filename); 
				FileSystem!New(filename); FileSystem?Done;
				FileSystem!WriteText("VEHICLE"); FileSystem!Write(TAB);
				FileSystem!WriteText("TIME"); FileSystem!Write(TAB);
				FileSystem!WriteText("LINK"); FileSystem!Write(TAB);
				FileSystem!WriteText("NODE"); FileSystem!Write(TAB);
				FileSystem!WriteText("LANE"); FileSystem!Write(TAB);
				FileSystem!WriteText("DISTANCE"); FileSystem!Write(TAB);
				FileSystem!WriteText("VELOCITY"); FileSystem!Write(TAB);
				FileSystem!WriteText("VEHTYPE"); FileSystem!Write(TAB);
				FileSystem!WriteText("ACCELER"); FileSystem!Write(TAB);
				FileSystem!WriteText("DRIVER"); FileSystem!Write(TAB);
				FileSystem!WriteText("PASSENGERS"); FileSystem!Write(TAB);
				FileSystem!WriteText("EASTING"); FileSystem!Write(TAB);
				FileSystem!WriteText("NORTHING"); FileSystem!Write(TAB);
				FileSystem!WriteText("ELEVATION"); FileSystem!Write(TAB);
				FileSystem!WriteText("AZIMUTH"); FileSystem!Write(TAB);
				FileSystem!WriteText("USER"); FileSystem!Write(CR);
				open := TRUE;
				AWAIT(nofUsers > 0)
			END;
			?Stop;
			BEGIN {EXCLUSIVE}
				AWAIT(nofUsers = 0);
				FileSystem!Close;
				WRITE("Snapshots written"); WRITELINE;
				open := FALSE
			END;
			!Done
		END
	END WriterControl;
	
	IMPLEMENTATION SnapshotOutput;
	CONSTANT LaneWidth = 3.75; (* m *)
	VARIABLE time, car, link, node: INTEGER; fromX, fromY, toX, toY, distance, xd, yd, x, y, theta, azimuth: REAL;
	BEGIN
		?Start;
		BEGIN {EXCLUSIVE} INC(nofUsers); AWAIT(open) END;
		WHILE ?CarPosition DO {EXCLUSIVE}
			?CarPosition(time, car, link, node, fromX, fromY, toX, toY, distance);
			xd := toX - fromX; yd := toY - fromY;
			IF xd > 0 THEN theta := ARCTAN(yd / xd)
			ELSIF xd < 0 THEN theta := PI + ARCTAN(yd / xd)
			ELSIF yd > 0 THEN theta := PI / 2
			ELSE theta := PI * 3 / 2
			END;
			x := fromX + distance * COS(theta) - LaneWidth * SIN(theta); IF x < 0.0 THEN x := 0.0 END;
			y := fromY + distance * SIN(theta) + LaneWidth * COS(theta); IF y < 0.0 THEN y := 0.0 END;
			azimuth := theta / (2*PI) * 360;
			FileSystem!WriteText(IntegerToText(car)); FileSystem!Write(TAB);
			FileSystem!WriteText(IntegerToText(time)); FileSystem!Write(TAB);
			FileSystem!WriteText(IntegerToText(link)); FileSystem!Write(TAB);
			FileSystem!WriteText(IntegerToText(node)); FileSystem!Write(TAB);
			FileSystem!WriteText("1"); FileSystem!Write(TAB); (* lane *)
			FileSystem!WriteText(RealToText(distance)); FileSystem!Write(TAB);
			FileSystem!WriteText("7.5"); FileSystem!Write(TAB); (* velocity *)
			FileSystem!WriteText("1"); FileSystem!Write(TAB); (* vehtype *)
			FileSystem!WriteText("0"); FileSystem!Write(TAB); (* acceleration *)
			FileSystem!WriteText(IntegerToText(car)); FileSystem!Write(TAB); (* driver *)
			FileSystem!WriteText("1"); FileSystem!Write(TAB); (* passengers *)
			FileSystem!WriteText(RealToText(x)); FileSystem!Write(TAB);
			FileSystem!WriteText(RealToText(y)); FileSystem!Write(TAB); 
			FileSystem!WriteText("0"); FileSystem!Write(TAB); (* elevation *)
			FileSystem!WriteText(RealToText(azimuth)); FileSystem!Write(TAB); 
			FileSystem!WriteText("0"); FileSystem!Write(CR) (* user-defined *)
		END;
		BEGIN {EXCLUSIVE} DEC(nofUsers); AWAIT(~open) END;
		?Stop
	END SnapshotOutput;
	
	BEGIN NEW(trans); open := FALSE; nofUsers := 0
END SnapshotWriter;

