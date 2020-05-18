INTERFACE RoadData;
	IN Read(xmlFilename: TEXT)
	{ OUT Node(id, x, y: INTEGER) }
	{ OUT Link(id, from, to: INTEGER; length, capacity: REAL; lanes: INTEGER; freeSpeed: REAL; transport: BOOLEAN) }
	OUT Finish
END RoadData;

COMPONENT RoadNetworkReader OFFERS RoadData REQUIRES FileSystem;
	VARIABLE reader: XMLParser; trans: TextTransformer;
	
	PROCEDURE SkipAttributes;
	VARIABLE a, b: TEXT;
	BEGIN  WHILE XMLReader(reader)?Attribute DO XMLReader(reader)?Attribute(a, b) END
	END SkipAttributes;
	
	PROCEDURE ParseInteger(x: TEXT): INTEGER;
	VARIABLE i: INTEGER;
	BEGIN TextParser(trans)!ParseInteger(x); TextParser(trans)?Integer(i); RETURN i
	END ParseInteger;
	
	PROCEDURE ParseReal(x: TEXT): REAL;
	VARIABLE r: REAL;
	BEGIN TextParser(trans)!ParseReal(x); TextParser(trans)?Real(r); RETURN r
	END ParseReal;
	
	PROCEDURE ParseTime(x: TEXT): INTEGER;
	VARIABLE i: INTEGER;
	BEGIN TextParser(trans)!ParseTime(x); TextParser(trans)?Time(i); RETURN i
	END ParseTime;

	PROCEDURE Error(x: TEXT);
	BEGIN WRITE(x); WRITELINE; SkipAll
	END Error;
	
	PROCEDURE SkipAll;
	VARIABLE x, y: TEXT;
	BEGIN
		WHILE XMLReader(reader)?BeginElement OR XMLReader(reader)?Attribute OR 
				XMLReader(reader)?EndElement OR XMLReader(reader)?Text DO
			IF XMLReader(reader)?BeginElement THEN XMLReader(reader)?BeginElement(x)
			ELSIF XMLReader(reader)?Attribute THEN XMLReader(reader)?Attribute(x, y)
			ELSIF XMLReader(reader)?EndElement THEN XMLReader(reader)?EndElement
			ELSE XMLReader(reader)?Text(x)
			END
		END
	END SkipAll;

	IMPLEMENTATION RoadData;
	VARIABLE filename, name, key, value, error: TEXT; id, x, y, from, to, lanes, pos, capperiod: INTEGER; 
		capacity, length, freeSpeed: REAL; transport: BOOLEAN;
	BEGIN {EXCLUSIVE}
		?Read(filename); error := "";
		XMLReader(reader)!Parse(filename);
		IF XMLReader(reader)?BeginElement THEN
			XMLReader(reader)?BeginElement(name);
			IF name = "network" THEN
				SkipAttributes; 
				IF XMLReader(reader)?BeginElement THEN
					XMLReader(reader)?BeginElement(name);
					IF name = "nodes" THEN
						SkipAttributes;
						WHILE XMLReader(reader)?BeginElement DO
							XMLReader(reader)?BeginElement(name);
							IF name = "node" THEN
								id := 0; x:= 0; y := 0;
								WHILE XMLReader(reader)?Attribute DO
									XMLReader(reader)?Attribute(key, value);
									IF key = "id" THEN id := ParseInteger(value)
									ELSIF key = "x" THEN x := ParseInteger(value)
									ELSIF key = "y" THEN y := ParseInteger(value)
									END
								END;
								!Node(id, x, y)
							ELSE Error("<node> expected")
							END;
							IF XMLReader(reader)?EndElement THEN XMLReader(reader)?EndElement
							ELSE Error("</node> expected")
							END
						END
					ELSE Error("<nodes> expected")
					END;
					IF XMLReader(reader)?EndElement THEN XMLReader(reader)?EndElement
					ELSE Error("</nodes> expected")
					END
				END;
				IF XMLReader(reader)?BeginElement THEN
					XMLReader(reader)?BeginElement(name);
					IF name = "links" THEN
						capperiod := 12*3600;
						WHILE XMLReader(reader)?Attribute DO
							XMLReader(reader)?Attribute(key, value);
							IF key = "capperiod" THEN capperiod := ParseTime(value) END
						END;
						WHILE XMLReader(reader)?BeginElement DO
							XMLReader(reader)?BeginElement(name);
							IF name = "link" THEN
								id := 0; from := 0; to := 0; length := 0.0; capacity := 0; lanes := 1; transport := FALSE;
								WHILE XMLReader(reader)?Attribute DO
									XMLReader(reader)?Attribute(key, value);
									IF key = "id" THEN id := ParseInteger(value)
									ELSIF key = "from" THEN from := ParseInteger(value)
									ELSIF key = "to" THEN to := ParseInteger(value)
									ELSIF key = "length" THEN length := ParseReal(value)
									ELSIF key = "capacity" THEN capacity := ParseInteger(value) / capperiod
									ELSIF key = "freespeed" THEN freeSpeed := ParseReal(value)
									ELSIF key = "permlanes" THEN lanes := ParseInteger(value)
									ELSIF (key = "transport") AND ((value = "true") OR (value = "TRUE")) THEN transport := TRUE
									END
								END;
								!Link(id, from, to, length, capacity, lanes, freeSpeed, transport)
							ELSE Error("<node> expected")
							END;
							IF XMLReader(reader)?EndElement THEN XMLReader(reader)?EndElement
							ELSE Error("</node> expected")
							END
						END
					ELSE Error("<nodes> expected")
					END;
					IF XMLReader(reader)?EndElement THEN XMLReader(reader)?EndElement
					ELSE Error("</nodes> expected")
					END
				END
			ELSE Error("<network> expected")
			END;
			IF XMLReader(reader)?EndElement THEN XMLReader(reader)?EndElement
			ELSE Error("</network> expected")
			END
		ELSE Error("<network> expected")
		END;
		IF XMLReader(reader)?Error THEN
			XMLReader(reader)?Error(pos, error);
			WRITE("XML Error pos "); WRITE(pos); WRITE(" "); WRITE(error); WRITELINE
		ELSE XMLReader(reader)?Finish
		END;
		!Finish
	END RoadData;

	BEGIN NEW(reader); CONNECT(FileSystem(reader), FileSystem); NEW(trans)	
END RoadNetworkReader;

