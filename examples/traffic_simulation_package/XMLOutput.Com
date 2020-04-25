INTERFACE XMLWriter;
	IN New(filename, dtd: TEXT) 
	{ IN BeginElement(name: TEXT) { IN Attribute(key, value: TEXT) } 
	| IN Text(x: TEXT)
	| IN EndElement }
	IN Close
END XMLWriter;

COMPONENT XMLOutput OFFERS XMLWriter REQUIRES FileSystem;
	PROCEDURE Indent(length: INTEGER);
	BEGIN WHILE length > 0 DO FileSystem!Write(09X); DEC(length) END
	END Indent;
	
	PROCEDURE NewLine;
	BEGIN FileSystem!Write(0DX); FileSystem!Write(0AX)
	END NewLine;
	
	IMPLEMENTATION XMLWriter;
	VARIABLE filename, dtd, text, name,  key, value: TEXT; 
		depth: INTEGER; element[depth: INTEGER]: TEXT;
	BEGIN {EXCLUSIVE}
		?New(filename, dtd); FileSystem!New(filename); FileSystem?Done;
		FileSystem!WriteText("<?xml version="); FileSystem!Write(22X); FileSystem!WriteText("1.0");
		FileSystem!Write(22X); FileSystem!WriteText(" encoding="); FileSystem!Write(22X);
		FileSystem!WriteText("utf-8"); FileSystem!Write(22X); FileSystem!WriteText(" ?>"); NewLine;
		IF dtd # "" THEN
			FileSystem!WriteText("<!DOCTYPE events SYSTEM "); FileSystem!Write(22X);
			FileSystem!WriteText(dtd); FileSystem!Write(22X); FileSystem!Write(">"); NewLine
		END;
		depth := 0;
		WHILE ?BeginElement OR ?Text OR ?EndElement DO
			IF ?BeginElement THEN 
				Indent(depth);
				?BeginElement(name); INC(depth); element[depth] := name;
				FileSystem!Write("<"); FileSystem!WriteText(name);
				WHILE ?Attribute DO
					?Attribute(key, value);
					FileSystem!Write(" "); FileSystem!WriteText(key); 
					FileSystem!Write("="); FileSystem!Write(22X);
					FileSystem!WriteText(value); FileSystem!Write(22X)
				END;
				IF ?EndElement THEN 
					?EndElement; DEC(depth); FileSystem!Write("/")
				END;
				FileSystem!Write(">"); NewLine
			ELSIF ?Text THEN	
				?Text(text); FileSystem!WriteText(text)
			ELSE
				?EndElement; 
				IF depth > 0 THEN
					Indent(depth-1);
					FileSystem!Write("<"); FileSystem!Write("/"); 
					FileSystem!WriteText(element[depth]); DEC(depth);
					FileSystem!Write(">"); NewLine
				ELSE WRITE("XMLOutput error: EndElement with open BeginElement"); WRITELINE
				END
			END
		END;
		?Close; FileSystem!Close
	END XMLWriter;
END XMLOutput;

