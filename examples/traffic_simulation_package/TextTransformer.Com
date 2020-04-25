INTERFACE TextParser;
	{ IN ParseInteger(x: TEXT) OUT Integer(x: INTEGER) 
	| IN ParseReal(x: TEXT) OUT Real(x: REAL) 
	| IN ParseTime(x: TEXT) OUT Time(i: INTEGER) }
END TextParser;

INTERFACE TextGenerator;
	{  ( IN MakeInteger(x: INTEGER) | IN MakeReal(x: REAL) 
	   | IN MakeTime(x: INTEGER) | IN Append(x, y: TEXT) ) 
	   OUT Text(x: TEXT) }
END TextGenerator;

COMPONENT TextTransformer OFFERS TextParser, TextGenerator;
	PROCEDURE ParseInteger(x: TEXT): INTEGER;
	VARIABLE i, n: INTEGER; neg: BOOLEAN;
	BEGIN
		i := 0; n := 0;
		IF (LENGTH(x) > 0) AND (x[0] = "-") THEN neg := TRUE; INC(i) ELSE neg := FALSE END;
		WHILE (i < LENGTH(x)) AND (x[i] >= "0") AND (x[i] <= "9") DO
			n := n * 10 + INTEGER(x[i])-INTEGER("0"); INC(i)
		END;
		IF neg THEN n := -n END;
		RETURN n
	END ParseInteger;
	
	PROCEDURE ParseReal(x: TEXT): REAL;
	VARIABLE i: INTEGER; n, d: REAL;
	BEGIN 
		n := REAL(ParseInteger(x));
		i := 0; WHILE (i < LENGTH(x)) AND (x[i] # ".") DO INC(i) END;
		d := 0.1;
		WHILE (i < LENGTH(x)) AND (x[i] >= "0") AND (x[i] <= "9") DO
			n := n + d * INTEGER(x[i])-INTEGER("0"); INC(i); d := d/10
		END;
		RETURN n
	END ParseReal;
	
	PROCEDURE ParseTime(x: TEXT): INTEGER;
	VARIABLE h, m, s: INTEGER; t: TEXT;
	BEGIN
		IF LENGTH(x) < 5 THEN WRITE("Invalid time format, too short"); WRITELINE; RETURN -1 END;
		h := 0; m := 0; s := 0;
		NEW(t, 3); t[0] := x[0]; t[1] := x[1]; t[2] := 0X; h := ParseInteger(t);
		IF x[2] # ":" THEN WRITE("Invalid time format, ':' missing in "); WRITE(x); WRITELINE END;
		NEW(t, 3); t[0] := x[3]; t[1] := x[4]; t[2] := 0X; m := ParseInteger(t);
		IF LENGTH(x) >= 8 THEN
			IF x[5] # ":" THEN WRITE("Invalid time format, ':' missing in "); WRITE(x); WRITELINE END;
			NEW(t, 3); t[0] := x[6]; t[1] := x[7]; t[2] := 0X; s := ParseInteger(t)
		END;
		RETURN ((h * 60) + m) * 60 + s
	END ParseTime;

	IMPLEMENTATION TextParser;
	VARIABLE t: TEXT;
	BEGIN 
		WHILE ?ParseInteger OR ?ParseReal OR ?ParseTime DO
			IF ?ParseInteger THEN ?ParseInteger(t); !Integer(ParseInteger(t))
			ELSIF ?ParseReal THEN ?ParseReal(t); !Real(ParseReal(t))
			ELSE ?ParseTime(t); !Time(ParseTime(t))
			END
		END
	END TextParser;
	
	PROCEDURE GenerateInteger(x: INTEGER): TEXT;
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
	END GenerateInteger;
	
	PROCEDURE GenerateReal(x: REAL): TEXT;
	VARIABLE y, d, i, k: INTEGER; a[i: INTEGER]: CHARACTER; t: TEXT;
	BEGIN
		i := 0; 
		IF x < 0.0 THEN a[i] := "-"; INC(i); x := -x END;
		y := INTEGER(x); t := GenerateInteger(y);
		k := 0; WHILE (k < LENGTH(t)) AND (t[k] # 0X) DO a[i] := t[k]; INC(i); INC(k) END;
		a[i] := "."; INC(i);
		x := x - y; d := 0;
		REPEAT
			x := x * 10; y := INTEGER(x); x := x - y;
			a[i] := CHARACTER(INTEGER("0") + y); INC(i);
			INC(d)
		UNTIL (x = 0) OR (d > 10);
		NEW(t, i+1);
		FOR k := 0 TO i-1 DO t[k] := a[k] END; t[i] := 0X;
		RETURN t
	END GenerateReal;
	
	PROCEDURE GenerateTime(i: INTEGER): TEXT;
	VARIABLE h, m, s, k, n: INTEGER; t: TEXT; a[k: INTEGER]: CHARACTER;
	BEGIN
		s := i MOD 60; m := (i DIV 60) MOD 60; h := i DIV 3600;
		IF h >= 100 THEN WRITE("Time too long to be generated in text format"); WRITELINE END;
		h := h MOD 100;
		k := 0; IF h >= 10 THEN a[k] := CHARACTER(INTEGER("0") + (h DIV 10)) ELSE a[k] := "0" END;
		INC(k); a[k] := CHARACTER(INTEGER("0") + (h MOD 10));
		INC(k); a[k] := ":";
		INC(k); IF m >= 10 THEN a[k] := CHARACTER(INTEGER("0") + (m DIV 10)) ELSE a[k] := "0" END;
		INC(k); a[k] := CHARACTER(INTEGER("0") + (m MOD 10));
		IF s # 0 THEN
			INC(k); a[k] := ":";
			INC(k); IF s >= 10 THEN a[k] := CHARACTER(INTEGER("0") + (s DIV 10)) ELSE a[k] := "0" END;
			INC(k); a[k] := CHARACTER(INTEGER("0") + (m MOD 10))
		END;
		INC(k); a[k] := 0X;
		NEW(t, k+1); FOR n := 0 TO k DO t[n] := a[n] END;
		RETURN t
	END GenerateTime;
	
	PROCEDURE Append(x, y: TEXT): TEXT;
	VARIABLE z: TEXT; i, k: INTEGER; 
	BEGIN
		NEW(z, LENGTH(x) + LENGTH(y) + 1); k := 0; 
		i := 0; WHILE (i < LENGTH(x)) AND (x[i] # 0X) DO z[k] := x[i]; INC(i); INC(k) END;
		i := 0; WHILE (i < LENGTH(y)) AND (y[i] # 0X) DO z[k] := y[i]; INC(i); INC(k) END;
		z[k] := 0X; 
		RETURN z
	END Append;
	
	IMPLEMENTATION TextGenerator;
	VARIABLE i: INTEGER; r: REAL; x, y: TEXT;
	BEGIN
		WHILE ?MakeInteger OR ?MakeReal OR ?MakeTime OR ?Append DO
			IF ?MakeInteger THEN ?MakeInteger(i); !Text(GenerateInteger(i))
			ELSIF ?MakeReal THEN ?MakeReal(r); !Text(GenerateReal(r))
			ELSIF ?MakeTime THEN ?MakeTime(i); !Text(GenerateTime(i))
			ELSE ?Append(x, y); !Text(Append(x, y))
			END
		END
	END TextGenerator;
END TextTransformer;

