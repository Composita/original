INTERFACE XMLReader;
	IN Parse(filename: TEXT)
	{ OUT BeginElement(name: TEXT) { OUT Attribute(key, value: TEXT) }
	| OUT EndElement 
	| OUT Text(x: TEXT)  }
	( OUT Finish | OUT Error(position: INTEGER; description: TEXT) )
END XMLReader;

COMPONENT XMLParser OFFERS XMLReader REQUIRES FileSystem;
	CONSTANT MaxIdentLen = 128;
	VARIABLE line, sym, error: TEXT; p: INTEGER; c: CHARACTER; eof: BOOLEAN; 
	
	PROCEDURE NextCharacter;
	BEGIN
		IF ~eof THEN INC(p) END;
		WHILE ~eof AND ((p >= LENGTH(line)) OR (line[p] = 0X)) DO
			FileSystem!ReadLine; 
			IF FileSystem?Line THEN FileSystem?Line(line); p := 0
			ELSE FileSystem?EOF; eof := TRUE; c := 0X
			END
		END;
		IF ~eof THEN c := line[p] END
	END NextCharacter;
	
	PROCEDURE IsLetter(c: CHARACTER): BOOLEAN;
	BEGIN RETURN ((c >= "A") AND (c <= "Z")) OR ((c >= "a") AND (c <= "z"))
	END IsLetter;
	
	PROCEDURE IsDigit(c: CHARACTER): BOOLEAN;
	BEGIN RETURN (c >= "0") AND (c <= "9")
	END IsDigit;
	
	PROCEDURE AllowedCharacter(c: CHARACTER): BOOLEAN;
	BEGIN RETURN (c = ":") OR (c = "-") OR (c = "_")
	END AllowedCharacter;
	
	PROCEDURE NextSymbol;
	VARIABLE i: INTEGER;
	BEGIN
		WHILE ~eof AND (INTEGER(c) <= INTEGER(" ")) DO NextCharacter END; (* skip blanks *)
		IF ~eof THEN
			IF IsLetter(c) THEN
				NEW(sym, MaxIdentLen); i := 0;
				REPEAT
					sym[i] := c; NextCharacter; INC(i)
				UNTIL eof OR (i >= MaxIdentLen-1) OR (~IsLetter(c) AND ~IsDigit(c) AND ~AllowedCharacter(c));
				IF i >= MaxIdentLen-1 THEN error := "Too long identifier" END;
				sym[i] := 0X
			ELSE
				sym := TEXT(c); NextCharacter
			END
		ELSE eof := TRUE; sym := ""
		END
	END NextSymbol;
	
	PROCEDURE IsIdentifier(): BOOLEAN;
	BEGIN RETURN (LENGTH(sym) > 0) AND IsLetter(sym[0])
	END IsIdentifier;
	
	PROCEDURE InitReader;
	BEGIN line :=""; p := -1; eof := FALSE; error := ""; NextCharacter; NextSymbol
	END InitReader;
	
	PROCEDURE IsTag(): BOOLEAN;
	BEGIN RETURN sym = "<"
	END IsTag;
	
	PROCEDURE ReadText(VARIABLE x: TEXT; end: CHARACTER);
	VARIABLE a[i: INTEGER]: CHARACTER; len, i: INTEGER;
	BEGIN
		len := 0;
		IF ~eof THEN 
			WHILE (len < LENGTH(sym)) AND (sym[len] # 0X) DO
				a[len] := sym[len]; INC(len)
			END
		END;
		WHILE ~eof AND (c # end) DO 
			a[len] := c; NextCharacter; INC(len)
		END;
		NEW(x, len+1);
		FOR i := 0 TO len-1 DO x[i] := a[i] END;
		x[len] := 0X
	END ReadText;
	
	PROCEDURE ReadContent(VARIABLE content: TEXT);
	BEGIN ReadText(content, "<"); NextSymbol
	END ReadContent;
	
	PROCEDURE BeginTag;
	BEGIN
		IF sym = "<" THEN NextSymbol
		ELSE error := "'<' missing"
		END;
		WHILE (sym = "?") OR (sym = "!")  DO 
			SkipDirective;
			IF sym = "<" THEN NextSymbol
			ELSE error := "'<' missing"
			END
		END
	END BeginTag;
	
	PROCEDURE SkipDirective;
	VARIABLE ignore: TEXT;
	BEGIN ReadText(ignore, ">"); NextSymbol; NextSymbol
	END SkipDirective;
	
	PROCEDURE BeginElement(VARIABLE name: TEXT);
	BEGIN
		name := sym;
		NextSymbol
	END BeginElement;
	
	PROCEDURE ReadAttribute(VARIABLE key, value: TEXT);
	BEGIN
		IF IsIdentifier() THEN
			key := sym;
			NextSymbol;
			IF sym = "=" THEN 
				NextSymbol;
				IF sym = 22X THEN
					NextSymbol;
					ReadText(value, 22X);
					NextSymbol;
					IF sym = 22X THEN NextSymbol 
					ELSE error := "double quote missing" 
					END
				END
			ELSE error := "'=' missing"
			END
		ELSE error := "attribute expected"
		END
	END ReadAttribute;
	
	PROCEDURE IsAttribute(): BOOLEAN;
	BEGIN RETURN IsIdentifier()
	END IsAttribute;
	
	PROCEDURE BeginBody(VARIABLE hasBody: BOOLEAN);
	BEGIN
		hasBody := TRUE;
		IF sym = "/" THEN 
			hasBody := FALSE; NextSymbol
		END;
		IF sym = ">" THEN NextSymbol
		ELSE error := "'>' missing" 
		END
	END BeginBody;
	
	PROCEDURE IsEndBody(): BOOLEAN;
	BEGIN RETURN sym = "/"
	END IsEndBody;
	
	PROCEDURE EndBody(name: TEXT);
	BEGIN
		IF sym = "/" THEN
			NextSymbol;
			IF sym = name THEN 
				NextSymbol;
				IF sym = ">" THEN NextSymbol
				ELSE error := "'>' missing"
				END
			ELSE error := "end tag does not match"
			END
		ELSE error := "'/' missing"
		END
	END EndBody;
					
	IMPLEMENTATION XMLReader;
	VARIABLE 
		filename: TEXT; depth: INTEGER; name: TEXT; element[depth: INTEGER]: TEXT; 
		key, value: TEXT; hasBody: BOOLEAN; content: TEXT; pos: INTEGER; hasRoot: BOOLEAN;
	BEGIN {EXCLUSIVE}
		?Parse(filename);
		FileSystem!Open(filename); 
		IF FileSystem?Done THEN
			FileSystem?Done;
			InitReader; depth := 0; hasRoot := FALSE;
			WHILE (sym # "") AND (error = "") DO
				IF IsTag() THEN
					IF depth = 0 THEN 
						IF hasRoot THEN error := "only one root element allowed"
						ELSE hasRoot := TRUE
						END
					END;
					IF error = "" THEN BeginTag END;
					IF ~IsEndBody() THEN
						IF error = "" THEN BeginElement(name) END;
						IF error = "" THEN !BeginElement(name) END;
						element[depth] := name;
						WHILE IsAttribute() DO
							IF error = "" THEN ReadAttribute(key, value) END;
							IF error = "" THEN !Attribute(key, value) END
						END;
						IF error = "" THEN BeginBody(hasBody) END;
						IF hasBody THEN
							INC(depth)
						ELSE 
							IF error = "" THEN !EndElement END
						END
					ELSE
						DEC(depth);
						IF depth >= 0 THEN
							IF error = "" THEN EndBody(element[depth]) END;
							IF error = "" THEN !EndElement END
						ELSE error := "invalid closing tag"
						END
					END 
				ELSE
					IF depth > 0 THEN 
						IF error = "" THEN ReadContent(content) END;
						IF error = "" THEN !Text(content) END
					ELSE error := "text not allowed at topmost level"
					END
				END
			END;
			IF error = "" THEN !Finish 
			ELSE
				FileSystem!GetPosition; FileSystem?Position(pos);
				!Error(pos, error) 
			END;
			FileSystem!Close
		ELSE
			FileSystem?Failed;
			!Error(0, "File not present")
		END
	END XMLReader;
END XMLParser;

