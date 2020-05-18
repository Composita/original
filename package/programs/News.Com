COMPONENT News REQUIRES SystemTime;
	CONSTANT 
		N = 1000; (* customers *)
		M = 10; (* reporters *)
		K = 10; (* news per reporter *)
		Output = FALSE;

	INTERFACE Broadcasting;
		{ OUT News(x: TEXT) } OUT Finished
	END Broadcasting;
	
	INTERFACE Editorial;
		{ IN News(x: TEXT) } IN Finished
	END Editorial;
	
	COMPONENT NewsCenter OFFERS Broadcasting, Editorial;
		VARIABLE news[pos: INTEGER]: TEXT; lastPos, finishedRep: INTEGER;  
		
		IMPLEMENTATION Broadcasting;
		VARIABLE i: INTEGER;
		BEGIN {SHARED}
			i := 0;
			REPEAT
				AWAIT((i < lastPos) OR (finishedRep = M));
				IF i < lastPos THEN !News(news[i]); INC(i) END
			UNTIL (i = lastPos) AND (finishedRep = M);
			!Finished
		END Broadcasting;
		
		IMPLEMENTATION Editorial;
		BEGIN
			WHILE ?News DO {EXCLUSIVE}
				?News(news[lastPos]); INC(lastPos)
			END;
			?Finished; 
			BEGIN {EXCLUSIVE} INC(finishedRep) END
		END Editorial;
		
		BEGIN lastPos := 0; finishedRep := 0
	END NewsCenter;

	COMPONENT Reporter REQUIRES Editorial;
	VARIABLE i: INTEGER;
	BEGIN
		FOR i := 1 TO K DO
			IF i MOD 2 = 0 THEN Editorial!News("News from white house") 
			ELSE Editorial!News("News from houses of parliaments")
			END
		END;
		Editorial!Finished
	END Reporter;
	
	COMPONENT Customer REQUIRES Broadcasting;
	VARIABLE x: TEXT;
	BEGIN
		WHILE Broadcasting?News DO
			Broadcasting?News(x); 
			IF Output THEN WRITE(x); WRITELINE END
		END;
		Broadcasting?Finished
	END Customer;
	
	PROCEDURE SystemTime(): INTEGER;
	VARIABLE t: INTEGER;
	BEGIN SystemTime!GetSystemTime; SystemTime?SystemTime(t); RETURN t
	END SystemTime;

	VARIABLE 
		center: NewsCenter;
		customer[number: INTEGER]: Customer; 
		reporter[number: INTEGER]: Reporter; 
		i, startTime: INTEGER;
	BEGIN
		startTime := SystemTime();
		NEW(center);
		FOR i := 1 TO N DO
			NEW(customer[i]); CONNECT(Broadcasting(customer[i]), center)
		END;
		FOR i := 1 TO M DO
			NEW(reporter[i]); CONNECT(Editorial(reporter[i]), center)
		END;
		FOR i := 1 TO N DO
			DELETE(customer[i])
		END;
		WRITE(SystemTime()-startTime); WRITE("ms"); WRITELINE
END News;

