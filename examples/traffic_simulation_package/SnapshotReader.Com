INTERFACE SnapshotInput;
	IN Read(filename: TEXT)
	{ OUT CarLocation(carId, time: INTEGER; x, y: REAL) }
	OUT Finish
END SnapshotInput;

COMPONENT SnapshotReader OFFERS SnapshotInput REQUIRES FileSystem;
	VARIABLE reader: TextInput; trans: TextTransformer; error: BOOLEAN;
	
	PROCEDURE ReadHeaderField(name: TEXT);
	VARIABLE x: TEXT;
	BEGIN
		IF TextReader(reader)?Text THEN 
			TextReader(reader)?Text(x);
			IF x # name THEN error := TRUE; WRITE(name); WRITE(" missing in header line") END
		END
	END ReadHeaderField; 
	
	PROCEDURE ReadInteger(VARIABLE int: INTEGER);
	VARIABLE x: TEXT;
	BEGIN
		IF TextReader(reader)?Text THEN
			TextReader(reader)?Text(x); 
			TextParser(trans)!ParseInteger(x); TextParser(trans)?Integer(int)
		ELSE error := TRUE; WRITE("Text value expected"); WRITELINE
		END
	END ReadInteger;
	
	PROCEDURE ReadReal(VARIABLE real: REAL);
	VARIABLE x: TEXT;
	BEGIN
		IF TextReader(reader)?Text THEN
			TextReader(reader)?Text(x); 
			TextParser(trans)!ParseReal(x); TextParser(trans)?Real(real)
		ELSE error := TRUE; WRITE("Text value expected"); WRITELINE
		END
	END ReadReal;
	
	PROCEDURE ReadText(VARIABLE text: TEXT);
	BEGIN
		IF TextReader(reader)?Text THEN
			TextReader(reader)?Text(text)
		ELSE error := TRUE; text := ""; WRITE("Text expected"); WRITELINE
		END
	END ReadText;
		
	PROCEDURE SkipAll;
	VARIABLE x: TEXT;
	BEGIN
		WHILE TextReader(reader)?Text OR TextReader(reader)?NewLine DO
			IF TextReader(reader)?Text THEN TextReader(reader)?Text(x)
			ELSE TextReader(reader)?NewLine
			END
		END;
		TextReader(reader)?End
	END SkipAll;
	
	PROCEDURE SkipToLineEnd;
	VARIABLE x: TEXT;
	BEGIN WHILE TextReader(reader)?Text DO TextReader(reader)?Text(x) END
	END SkipToLineEnd;
	
	IMPLEMENTATION SnapshotInput;
	VARIABLE filename: TEXT; carId, time, link, node, lane: INTEGER; distance, velocity, x, y: REAL; ignore: TEXT;
	BEGIN {EXCLUSIVE}
		error := FALSE;
		?Read(filename); TextReader(reader)!Open(filename);
		IF TextReader(reader)?Failed THEN
			TextReader(reader)?Failed;
			WRITE("Cannot open snapshot file "); WRITE(filename); WRITELINE
		ELSE
			ReadHeaderField("VEHICLE"); ReadHeaderField("TIME"); 
			ReadHeaderField("LINK"); ReadHeaderField("NODE");
			ReadHeaderField("LANE"); ReadHeaderField("DISTANCE");
			ReadHeaderField("VELOCITY"); ReadHeaderField("VEHTYPE");
			ReadHeaderField("ACCELER"); ReadHeaderField("DRIVER");
			ReadHeaderField("PASSENGERS"); ReadHeaderField("EASTING");
			ReadHeaderField("NORTHING"); ReadHeaderField("ELEVATION");
			ReadHeaderField("AZIMUTH"); ReadHeaderField("USER");
			WHILE TextReader(reader)?NewLine AND ~error DO
				TextReader(reader)?NewLine;
				IF TextReader(reader)?Text THEN
					ReadInteger(carId); ReadInteger(time); ReadInteger(link);
					ReadInteger(node); ReadInteger(lane); ReadReal(distance);
					ReadReal(velocity); ReadText(ignore); ReadText(ignore);
					ReadText(ignore); ReadText(ignore); ReadReal(x); ReadReal(y);
					SkipToLineEnd;
					!CarLocation(carId, time, x, y)
				END
			END;
			IF ~error AND TextReader(reader)?End THEN TextReader(reader)?End ELSE SkipAll END
		END;
		!Finish
	END SnapshotInput;
	
	BEGIN NEW(reader); CONNECT(FileSystem(reader), FileSystem); NEW(trans)
END SnapshotReader;
