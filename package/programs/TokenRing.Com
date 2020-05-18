COMPONENT TokenRing REQUIRES SystemTime;
	CONSTANT 
		N = 1000; (* nodes *)
		K = 1000; (* circulations *)
		Output = FALSE;
		TimeOutput = TRUE;
		
	INTERFACE Neighbour;
		{ IN PassToken } IN Finish
	END Neighbour;
	
	INTERFACE Control;
		IN InjectToken OUT ReturnToken
	END Control;

	COMPONENT Node OFFERS Neighbour, Control REQUIRES Neighbour;
		VARIABLE k: INTEGER;
		
		IMPLEMENTATION Control;
		BEGIN {EXCLUSIVE}
			?InjectToken; Neighbour!PassToken; INC(k);
			AWAIT(k > K);
			!ReturnToken
		END Control;
		
		IMPLEMENTATION Neighbour;
		BEGIN {EXCLUSIVE}
			WHILE k <= K DO 
				?PassToken; Neighbour!PassToken; INC(k);
				IF Output THEN WRITE(".") END
			END;
			IF ?PassToken THEN ?PassToken END;
			Neighbour!Finish; ?Finish
		END Neighbour;
		
		BEGIN k := 0
	END Node;
	
	PROCEDURE SystemTime(): INTEGER;
	VARIABLE t: INTEGER;
	BEGIN SystemTime!GetSystemTime; SystemTime?SystemTime(t); RETURN t
	END SystemTime;
	
	VARIABLE 
		node[number: INTEGER]: Node;
		i, start: INTEGER;
	BEGIN
		start := SystemTime();
		FOR i := 1 TO N DO NEW(node[i]) END;
		FOR i := 1 TO N DO
			CONNECT(Neighbour(node[i]), node[i MOD N + 1])
		END;
	    Control(node[1])!InjectToken; Control(node[1])?ReturnToken;
	    IF TimeOutput THEN
	    	WRITE(SystemTime()-start); WRITE("ms"); WRITELINE
	    END
END TokenRing;

