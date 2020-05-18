INTERFACE PlanData;
	IN Read(filename: TEXT)
	{ 
		OUT BeginPlan(carId: INTEGER)
		{ 
			OUT BeginLeg(startLinkId, departTime: INTEGER)  
			{ OUT RouteNode(nodeId: INTEGER) } 
			OUT EndLeg(endLinkId: INTEGER) 
		}
		OUT EndPlan
	}
	OUT Finish
END PlanData;

COMPONENT PlanReader OFFERS PlanData REQUIRES FileSystem;
	VARIABLE reader: XMLParser; trans: TextTransformer;
	
	PROCEDURE SkipAttributes;
	VARIABLE a, b: TEXT;
	BEGIN WHILE XMLReader(reader)?Attribute DO XMLReader(reader)?Attribute(a, b) END
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
	
	PROCEDURE SkipSubContent;
	VARIABLE x: TEXT;
	BEGIN
		WHILE XMLReader(reader)?BeginElement OR XMLReader(reader)?Text DO
			IF XMLReader(reader)?BeginElement THEN
				XMLReader(reader)?BeginElement(x);
				SkipAttributes; SkipSubContent
			ELSE XMLReader(reader)?Text(x)
			END
		END;
		XMLReader(reader)?EndElement
	END SkipSubContent;

	PROCEDURE ReadPart(route: TEXT; VARIABLE k: INTEGER): INTEGER;
	VARIABLE point: TEXT; i: INTEGER;
	BEGIN
		NEW(point, 16); i := 0;
		WHILE (k < LENGTH(route)) AND (route[k] # 0X) AND (route[k] # " ") DO
			IF i < LENGTH(point) THEN point[i] := route[k]; INC(i)
			ELSE WRITE("node id too long in route description"); WRITELINE END;
			INC(k)
		END;
		point[i] := 0X;
		WHILE (k < LENGTH(route)) AND (route[k] # 0X) AND (route[k] <= " ") DO INC(k) END;
		RETURN ParseInteger(point)
	END ReadPart;

	IMPLEMENTATION PlanData;
	VARIABLE filename, name, key, value, mode, route, error: TEXT; id, startLink, depart, pos, k, node: INTEGER; 
		endLeg: BOOLEAN;
	BEGIN {EXCLUSIVE}
		?Read(filename); error := ""; 
		XMLReader(reader)!Parse(filename);
		IF XMLReader(reader)?BeginElement THEN
			XMLReader(reader)?BeginElement(name);
			IF name = "plans" THEN
				SkipAttributes;
				WHILE XMLReader(reader)?BeginElement DO
					XMLReader(reader)?BeginElement(name);
					IF name = "person" THEN
						id := 0; depart := 0; mode := "";
						WHILE XMLReader(reader)?Attribute DO 
							XMLReader(reader)?Attribute(key, value);
							IF key = "id" THEN id := ParseInteger(value) END
						END;
						WHILE XMLReader(reader)?BeginElement DO
							XMLReader(reader)?BeginElement(name);
							IF name = "plan" THEN
								!BeginPlan(id);
								SkipAttributes; endLeg := FALSE;						
								WHILE XMLReader(reader)?BeginElement DO
									XMLReader(reader)?BeginElement(name);
									IF name = "act" THEN
										WHILE XMLReader(reader)?Attribute DO
											XMLReader(reader)?Attribute(key, value);
											IF key = "link" THEN startLink := ParseInteger(value) END
										END;
										SkipSubContent;
										IF endLeg THEN !EndLeg(startLink); endLeg := FALSE END
									ELSIF name = "leg" THEN
										WHILE XMLReader(reader)?Attribute DO
											XMLReader(reader)?Attribute(key, value);
											IF key = "dep_time" THEN depart := ParseTime(value) 
											ELSIF key = "mode" THEN mode := value
											END
										END;
										IF mode = "car" THEN
											!BeginLeg(startLink, depart); 
											WHILE XMLReader(reader)?BeginElement DO
												XMLReader(reader)?BeginElement(name);
												IF name = "route" THEN
													SkipAttributes;
													IF XMLReader(reader)?Text THEN
														XMLReader(reader)?Text(route); k := 0;
														WHILE (k < LENGTH(route)) AND (route[k] # 0X) AND (route[k] <= " ") DO INC(k) END;
														WHILE (k < LENGTH(route)) AND (route[k] # 0X) DO
															node := ReadPart(route, k); !RouteNode(node)
														END
													END;
													IF XMLReader(reader)?EndElement THEN 
														XMLReader(reader)?EndElement
													ELSE Error("</route> missing")
													END
												ELSE SkipAttributes; SkipSubContent
												END
											END;
											endLeg := TRUE; (* end plan follows after next act *)
											IF XMLReader(reader)?EndElement THEN 
												XMLReader(reader)?EndElement
											ELSE Error("</leg> missing")
											END
										ELSE SkipAttributes; SkipSubContent
										END
									ELSE SkipAttributes; SkipSubContent
									END
								END;
								IF XMLReader(reader)?EndElement THEN XMLReader(reader)?EndElement
								ELSE Error("</plan> missing")
								END;
								IF endLeg THEN !EndLeg(startLink) END;
								!EndPlan
							ELSE SkipAttributes; SkipSubContent
							END
						END;
						IF XMLReader(reader)?EndElement THEN XMLReader(reader)?EndElement
						ELSE Error("</person> missing")
						END
					ELSE SkipAttributes; SkipSubContent
					END;
				END
			ELSE Error("<plans> expected")
			END;
			IF XMLReader(reader)?EndElement THEN XMLReader(reader)?EndElement
			ELSE Error("</plans> expected")
			END
		ELSE Error("<plans> expected")
		END;
		IF XMLReader(reader)?Error THEN
			XMLReader(reader)?Error(pos, error);
			WRITE("XML Error pos "); WRITE(pos); WRITE(" "); WRITE(error); WRITELINE
		ELSE XMLReader(reader)?Finish
		END;
		!Finish
	END PlanData;
	
	BEGIN NEW(reader); CONNECT(FileSystem(reader), FileSystem); NEW(trans)
END PlanReader;

