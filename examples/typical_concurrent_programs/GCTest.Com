COMPONENT GCTest REQUIRES SystemTime, FileSystem;				
	PROCEDURE SystemTime(): INTEGER;
	VARIABLE t: INTEGER;
	BEGIN SystemTime!GetSystemTime; SystemTime?SystemTime(t); RETURN t
	END SystemTime;
	
	PROCEDURE MakeInteger(x: INTEGER): TEXT;
	VARIABLE k, d, i: INTEGER; a[i: INTEGER]: CHARACTER; t: TEXT;
	BEGIN
		i := 0;
		IF x < 0 THEN a[i] := "-"; INC(i); x := -x END;
		k := 10; WHILE k <= x DO k := k * 10 END;
		REPEAT
			k := k DIV 10;
			d := (x DIV k) MOD 10;
			a[i] := CHARACTER(INTEGER("0") + d); INC(i)
		UNTIL k = 1;
		NEW(t, i+1);
		FOR k := 0 TO i-1 DO t[k] := a[k] END; t[i] := 0X;
		RETURN t
	END MakeInteger;
	
	CONSTANT Runs = 1000;
	VARIABLE k, startTime: INTEGER; test: TokenRing;
		time[x: INTEGER]: INTEGER;
	BEGIN
		FOR k := 1 TO Runs DO 
			startTime := SystemTime();
			NEW(test); CONNECT(SystemTime(test), SystemTime);
			DELETE(test);
			time[k] := SystemTime()-startTime
		END;
		WRITE("Write results"); WRITELINE;
		FileSystem!New("GCTest.txt"); FileSystem?Done;
		FOR k := 1 TO Runs DO
			FileSystem!WriteText(MakeInteger(time[k]));
			FileSystem!Write(0DX);
			WRITE(time[k]); WRITE("ms ")
		END;
		WRITE("DONE"); WRITELINE;
		FileSystem!Close
END GCTest;

