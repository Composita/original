INTERFACE EventOutput;
	IN Initialize(carId: INTEGER)
	{
		{ IN Departure(time, linkId: INTEGER) 
		| IN Arrival(time, linkId: INTEGER)
		| IN StuckAndAbort(time, linkId: INTEGER) }
		IN EndOfDay
	}
END EventOutput;

INTERFACE WriterControl;
	{ IN Start(filenamePrefix: TEXT; version: INTEGER) IN Stop OUT Done }
END WriterControl;

COMPONENT BufferedEventWriter OFFERS EventOutput, WriterControl REQUIRES XMLWriter;
	CONSTANT FileSuffix = ".xml"; DTD = "events_v1.dtd"; Capacity = 10000;
		DepartureType = 1; ArrivalType = 2; StuckType = 3;
	VARIABLE trans: TextTransformer; nofUsers: INTEGER; running, closed: BOOLEAN; first, last: INTEGER;
		eventType[pos: INTEGER]: INTEGER; time[pos: INTEGER]: INTEGER; 
		carId[pos: INTEGER]: INTEGER; linkId[pos: INTEGER]: INTEGER;
		
	PROCEDURE IntegerToText(int: INTEGER): TEXT;
	VARIABLE text: TEXT;
	BEGIN TextGenerator(trans)!MakeInteger(int); TextGenerator(trans)?Text(text); RETURN text
	END IntegerToText;
	
	PROCEDURE TimeToText(int: INTEGER): TEXT;
	VARIABLE text: TEXT;
	BEGIN TextGenerator(trans)!MakeTime(int); TextGenerator(trans)?Text(text); RETURN text
	END TimeToText;
	
	IMPLEMENTATION EventOutput;
	VARIABLE eventCar, eventLink, eventTime: INTEGER; type: TEXT;
	BEGIN 
		?Initialize(eventCar);
		WHILE ?Departure OR ?Arrival OR ?StuckAndAbort OR ?EndOfDay DO
			BEGIN {EXCLUSIVE} INC(nofUsers); AWAIT(running) END;
			WHILE ?Departure OR ?Arrival OR ?StuckAndAbort DO {EXCLUSIVE}
				IF ?Departure THEN ?Departure(eventTime, eventLink); eventType[last] := DepartureType
				ELSIF ?Arrival THEN ?Arrival(eventTime, eventLink); eventType[last] := ArrivalType
				ELSE ?StuckAndAbort(eventTime, eventLink); eventType[last] := StuckType
				END;
				time[last] := eventTime; carId[last] := eventCar; linkId[last] := eventLink;
				INC(last);
				IF last - first > Capacity THEN Flush END
			END;
			?EndOfDay;
			BEGIN {EXCLUSIVE} DEC(nofUsers); AWAIT(closed) END
		END
	END EventOutput;
	
	PROCEDURE MakeFileName(prefix: TEXT; version: INTEGER; VARIABLE filename: TEXT);
	VARIABLE x: TEXT; 
	BEGIN 
		x := IntegerToText(version);
		TextGenerator(trans)!Append(prefix, x); TextGenerator(trans)?Text(filename);
		TextGenerator(trans)!Append(filename, FileSuffix); TextGenerator(trans)?Text(filename)
	END MakeFileName;
	
	PROCEDURE Flush;
	BEGIN
		WHILE first < last DO
			XMLWriter!BeginElement("event"); 
			XMLWriter!Attribute("time", TimeToText(time[first]));
			IF eventType[first] = DepartureType THEN
				XMLWriter!Attribute("type", "departure")
			ELSIF eventType[first] = ArrivalType THEN
				XMLWriter!Attribute("type", "arrival")
			ELSIF eventType[first] = StuckType THEN
				XMLWriter!Attribute("type", "stuckAndAbort")
			ELSE HALT(111)
			END;
			XMLWriter!Attribute("agentId", IntegerToText(carId[first]));
			XMLWriter!Attribute("link", IntegerToText(linkId[first]));
			XMLWriter!EndElement;
			INC(first)
		END;
		first := 0; last := 0
	END Flush;
	
	IMPLEMENTATION WriterControl;
	VARIABLE prefix, filename: TEXT; version: INTEGER; 
	BEGIN 
		WHILE ?Start DO
			?Start(prefix, version);  
			BEGIN {EXCLUSIVE}
				MakeFileName(prefix, version, filename); 
				XMLWriter!New(filename, DTD); 
				XMLWriter!BeginElement("events");
				running := TRUE; closed := FALSE; first := 0; last := 0;
				AWAIT(nofUsers > 0)
			END;
			?Stop;
			BEGIN {EXCLUSIVE}
				AWAIT(nofUsers = 0);
				Flush;
				XMLWriter!EndElement; XMLWriter!Close;
				WRITE("Events written "); WRITELINE;
				running := FALSE; closed := TRUE
			END;
			!Done
		END
	END WriterControl;
	
	BEGIN NEW(trans); running := FALSE; nofUsers := 0;
END BufferedEventWriter;

COMPONENT NormalEventWriter OFFERS EventOutput, WriterControl REQUIRES XMLWriter;
	CONSTANT FileSuffix = ".xml"; DTD = "events_v1.dtd"; 
	VARIABLE trans: TextTransformer; open: BOOLEAN; nofUsers: INTEGER;
		
	PROCEDURE IntegerToText(int: INTEGER): TEXT;
	VARIABLE text: TEXT;
	BEGIN TextGenerator(trans)!MakeInteger(int); TextGenerator(trans)?Text(text); RETURN text
	END IntegerToText;
	
	PROCEDURE TimeToText(int: INTEGER): TEXT;
	VARIABLE text: TEXT;
	BEGIN TextGenerator(trans)!MakeTime(int); TextGenerator(trans)?Text(text); RETURN text
	END TimeToText;
	
	IMPLEMENTATION EventOutput;
	VARIABLE car, time, link: INTEGER; type: TEXT;
	BEGIN 
		?Initialize(car);
		WHILE ?Departure OR ?Arrival OR ?StuckAndAbort OR ?EndOfDay DO
			BEGIN {EXCLUSIVE} INC(nofUsers); AWAIT(open) END;
			WHILE ?Departure OR ?Arrival OR ?StuckAndAbort DO
				IF ?Departure THEN ?Departure(time, link); type := "departure"
				ELSIF ?Arrival THEN ?Arrival(time, link); type := "arrival"
				ELSE ?StuckAndAbort(time, link); type := "stuckAndAbort"
				END;
				BEGIN {EXCLUSIVE}
					XMLWriter!BeginElement("event"); 
					XMLWriter!Attribute("time", TimeToText(time));
					XMLWriter!Attribute("type", type);
					XMLWriter!Attribute("agentId", IntegerToText(car));
					XMLWriter!Attribute("link", IntegerToText(link));
					XMLWriter!EndElement
				END
			END;
			?EndOfDay;
			BEGIN {EXCLUSIVE} DEC(nofUsers); AWAIT(~open) END
		END
	END EventOutput;
	
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
				XMLWriter!New(filename, DTD); 
				XMLWriter!BeginElement("events");
				open := TRUE;
				AWAIT(nofUsers > 0)
			END;
			?Stop;
			BEGIN {EXCLUSIVE}
				AWAIT(nofUsers = 0);
				XMLWriter!EndElement; XMLWriter!Close;
				WRITE("Events written"); WRITELINE;
				open := FALSE
			END;
			!Done
		END
	END WriterControl;
	
	BEGIN NEW(trans); open := FALSE; nofUsers := 0
END NormalEventWriter;

