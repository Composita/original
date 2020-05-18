INTERFACE TextReader;
	IN Open(filename: TEXT) 
	(  { OUT Text(x: TEXT) | OUT NewLine } OUT End
	|   OUT Failed )
END TextReader;

COMPONENT TextInput OFFERS TextReader REQUIRES FileSystem;
	CONSTANT TAB = 09X; 

	IMPLEMENTATION TextReader;
	VARIABLE filename, line, value: TEXT; i, k, p: INTEGER; eof: BOOLEAN; 
	BEGIN {EXCLUSIVE}
		?Open(filename); FileSystem!Open(filename);
		IF FileSystem?Done THEN
			FileSystem?Done; eof := FALSE;
			REPEAT
				FileSystem!ReadLine;
				IF FileSystem?Line THEN
				FileSystem?Line(line);
					i := 0; k := 0;
					WHILE (i < LENGTH(line)) AND (line[i] # 0X) DO
						WHILE (k < LENGTH(line)) AND (line[k] # 0X) AND (line[k] # TAB) DO INC(k) END;
						NEW(value, k-i+1); 
						p := 0; WHILE p < k-i DO value[p] := line[i+p]; INC(p) END; value[p] := 0X;
						!Text(value);
						IF (k < LENGTH(line)) AND (line[k] = TAB) THEN INC(k) END;
						i := k
					END;
					!NewLine
				ELSE
					FileSystem?EOF; eof := TRUE
				END
			UNTIL eof;
			FileSystem!Close; !End
		ELSE
			FileSystem?Failed; !Failed
		END
	END TextReader;
END TextInput;

