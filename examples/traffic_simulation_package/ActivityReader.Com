INTERFACE ActivityData;
	IN Read(filename: TEXT) 
	{ OUT Activity(carId: INTEGER; type: TEXT; linkId, desiredArrivalTime: INTEGER) }
	OUT Finish
END ActivityData;

COMPONENT ActivityReader OFFERS ActivityData REQUIRES FileSystem;
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
	
	IMPLEMENTATION ActivityData;
	VARIABLE filename, type: TEXT; carId, linkId, desArrTime: INTEGER;
	BEGIN {EXCLUSIVE}
		error := FALSE;
		?Read(filename); TextReader(reader)!Open(filename);
		IF TextReader(reader)?Failed THEN
			TextReader(reader)?Failed;
			WRITE("Cannot open activity file "); WRITE(filename); WRITELINE
		ELSE
			ReadHeaderField("TRAV_ID"); ReadHeaderField("ACT_TYPE"); 
			ReadHeaderField("LINK"); ReadHeaderField("DES_ARR_TIME"); 
			ReadHeaderField("NOTES");
			WHILE (TextReader(reader)?NewLine) AND ~error DO
				TextReader(reader)?NewLine;
				IF TextReader(reader)?Text THEN
					ReadInteger(carId); ReadText(type); ReadInteger(linkId); 
					ReadInteger(desArrTime); SkipToLineEnd;
					!Activity(carId, type, linkId, desArrTime)
				END
			END;
			IF ~error AND TextReader(reader)?End THEN TextReader(reader)?End ELSE SkipAll END
		END;
		!Finish
	END ActivityData;
	
	BEGIN NEW(reader); CONNECT(FileSystem(reader), FileSystem); NEW(trans)
END ActivityReader;
