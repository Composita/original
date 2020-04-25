MODULE ComponentCompiler; (* 2005-2007 by Luc Blaeser *)
	IMPORT CCGenerator, CCChecker, CCImporter, CCParser, CCIR, CCScanner, CCBasic, 
		AosIO, Texts, In, Oberon, Display, Fonts;
	
	CONST NoBreakPosition = -1;
	
TYPE 
	TextReader = OBJECT
		VAR r: Texts.Reader; pos: LONGINT;

		PROCEDURE Receive(VAR buf: ARRAY OF CHAR; ofs, size, min: LONGINT; VAR len, res: LONGINT);
		VAR ch: CHAR;
		BEGIN
			len := 0;
			IF r.eot THEN res := AosIO.EOF
			ELSE
				WHILE ~r.eot & (len < size) & (pos < Texts.Pos(r)) DO
					buf[ofs+len] := 20X; INC(len); INC(pos)
				END;
				WHILE ~r.eot & (len < size) DO
					Texts.Read(r, ch);
					IF ((r.lib = NIL) OR ~(r.lib IS Fonts.Font)) THEN
						WHILE (len < size) & (pos < Texts.Pos(r)) DO
							buf[ofs+len] := 20X; INC(len); INC(pos)
						END
					ELSE buf[ofs+len] := ch; INC(len); INC(pos)
					END
				END;
				res := 0
			END
		END Receive;
	END TextReader;

	PROCEDURE TestScanner*;
	VAR name: ARRAY 64 OF CHAR; r: TextReader; t: Texts.Text; b: AosIO.Reader; s: CCScanner.Symbol;
	BEGIN {EXCLUSIVE}
		In.Open; In.String(name); CCBasic.OutText(name);
		NEW(r);
		GetReader(name, r.r, t);
		AosIO.OpenReader(b, r.Receive);
		CCScanner.InitializeScanner(b, t.len);
		REPEAT
			s := CCScanner.NextSymbol();
			IF s IS CCScanner.Identifier THEN
				CCBasic.OutText("IDENTIFIER: "); CCBasic.OutText(s(CCScanner.Identifier).s^)
			ELSIF s IS CCScanner.TextValue THEN
				CCBasic.OutText("TEXT VALUE: "); CCBasic.OutText(s(CCScanner.TextValue).s^)
			ELSIF s IS CCScanner.CharacterValue THEN
				CCBasic.OutText("CHARACTER VALUE: "); CCBasic.OutCharacter(s(CCScanner.CharacterValue).c)
			ELSIF s IS CCScanner.IntegerValue THEN
				CCBasic.OutText("INTEGER: "); CCBasic.OutInteger(s(CCScanner.IntegerValue).i)
			ELSIF s IS CCScanner.RealValue THEN
				CCBasic.OutText("REAL: "); CCBasic.OutReal(s(CCScanner.RealValue).r)
			ELSIF s IS CCScanner.Token THEN
				CCBasic.OutText("TOKEN: "); CCBasic.OutInteger(s(CCScanner.Token).type)
			ELSE HALT(111)
			END;
			CCBasic.OutLine
		UNTIL (s IS CCScanner.Token) & (s(CCScanner.Token).type = CCScanner.EndOfText);
	END TestScanner;
	
	PROCEDURE TestParser*;
	VAR name: ARRAY 64 OF CHAR; r: TextReader; t: Texts.Text; b: AosIO.Reader;
	BEGIN {EXCLUSIVE}
		In.Open; In.String(name); CCBasic.OutText(name);
		NEW(r);
		GetReader(name, r.r, t);
		AosIO.OpenReader(b, r.Receive);
		CCParser.Parse(b, t.len); CCBasic.OutLine;
		CCIR.Print		
	END TestParser;

	PROCEDURE TestChecker*;
	VAR name: ARRAY 64 OF CHAR; r: TextReader; t: Texts.Text; b: AosIO.Reader;
	BEGIN {EXCLUSIVE}
		In.Open; In.String(name); CCBasic.OutText(name);
		NEW(r);
		GetReader(name, r.r, t);
		AosIO.OpenReader(b, r.Receive);
		CCParser.Parse(b, t.len);
		CCChecker.Check;
		CCBasic.OutText(" checked"); CCBasic.OutLine
	END TestChecker;

	PROCEDURE CompileWithReader(r: AosIO.Reader; length: LONGINT; outPartition: ARRAY OF CHAR;
		break: BOOLEAN; breakComponent: ARRAY OF CHAR; breakCILPos: LONGINT; 
		VAR error: BOOLEAN; VAR sourceBreakPos: LONGINT);
	BEGIN {EXCLUSIVE}
		CCParser.Parse(r, length);
		IF ~CCScanner.error & ~CCParser.error THEN 
			CCChecker.Check;
			IF ~CCImporter.error & ~CCChecker.error THEN 
				CCGenerator.Generate(outPartition, break, breakComponent, breakCILPos, sourceBreakPos)
			ELSE error := TRUE
			END
		ELSE error := TRUE
		END;
		CCImporter.Free; CCIR.Free
	END CompileWithReader;
	
	PROCEDURE CompileText*(t: Texts.Text; outPartition: ARRAY OF CHAR; pos: LONGINT; 
		frame: Display.Frame; opt: ARRAY OF CHAR; VAR error: BOOLEAN);
	VAR f: BOOLEAN; breakPos, sourcePos: LONGINT; r: TextReader; b: AosIO.Reader; breakName: ARRAY 128 OF CHAR;
	BEGIN
		IF t = NIL THEN
			CCBasic.OutText("No text marked"); CCBasic.OutLine; 
			RETURN
		END;
		f := InOptions(opt, "f");
		IF f THEN
			GetBreakPosition(breakName, breakPos);
			IF breakPos = NoBreakPosition THEN RETURN END
		END;
		NEW(r);
		Texts.OpenReader(r.r, t, pos);
		AosIO.OpenReader(b, r.Receive);
		CompileWithReader(b, t.len - pos, outPartition, f, breakName, breakPos, error, sourcePos);
		IF f THEN
			Locate(frame, t, sourcePos)
		END
	END CompileText;
	
	PROCEDURE CompileFile*(name: ARRAY OF CHAR; outPartition, opt: ARRAY OF CHAR; VAR error: BOOLEAN);
	VAR f: BOOLEAN; breakPos, sourcePos: LONGINT; r: TextReader; t: Texts.Text; b: AosIO.Reader; 
		breakName: ARRAY 128 OF CHAR; 
	BEGIN
		CCBasic.OutText(name); CCBasic.OutText(" compiling "); CCBasic.OutLine;
		NEW(r);
		f := InOptions(opt, "f");
		IF f THEN
			GetBreakPosition(breakName, breakPos);
			IF breakPos = NoBreakPosition THEN RETURN END
		END;
		GetReader(name, r.r, t);
		AosIO.OpenReader(b, r.Receive);
		CompileWithReader(b, t.len, outPartition, f, breakName, breakPos, error, sourcePos)
	END CompileFile;
	
	PROCEDURE Compile*;
	VAR S: Texts.Scanner;  t: Texts.Text; pos, end, time, count: LONGINT; frame: Display.Frame; name: ARRAY 128 OF CHAR; 
		error: BOOLEAN; globalOpt, localOpt, outPartition: ARRAY 32 OF CHAR;
	BEGIN
		error := FALSE;
		Texts.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos);  Texts.Scan(S);
		globalOpt := ""; GetOptions(S, globalOpt);
		ExtractPartition(globalOpt, outPartition);
		IF (S.class = Texts.Char) & ((S.c = "*") OR (S.c = "@")) THEN
			IF S.c = "*" THEN
				t := Oberon.MarkedText(); pos := 0; frame := Oberon.MarkedFrame()
			ELSE (* S.c = "@" *)
				Oberon.GetSelection(t, pos, end, time); frame := NIL;
				IF time < 0 THEN RETURN END
			END;
			Texts.Scan(S);
			GetOptions(S, globalOpt);
			IF outPartition = "" THEN ExtractPartition(globalOpt, outPartition) END;
			CompileText(t, outPartition, pos, frame, globalOpt, error);
		ELSIF ((S.class = Texts.Char) & (S.c = "^")) OR (S.class = Texts.Name) THEN
			IF S.c = "^" THEN
				Oberon.GetSelection(t, pos, end, time);
				Texts.OpenScanner(S, t, pos); Texts.Scan(S)
			ELSE
				end := MAX(LONGINT)
			END;
			count := 0; error := FALSE;
			WHILE (S.class = Texts.Name) & (Texts.Pos(S) - S.len <= end) & ~error DO
				INC(count);
				COPY(S.s, name); COPY(globalOpt, localOpt);
				Texts.Scan(S);  GetOptions(S, localOpt);
				CompileFile(name, outPartition, localOpt, error)
			END
		END
	END Compile;
	
	PROCEDURE GetOptions(VAR S: Texts.Scanner; VAR opts: ARRAY OF CHAR);
		VAR i: LONGINT; ch: CHAR;
	BEGIN
		i := 0;
		WHILE opts[i] # 0X DO  INC(i)  END;
		WHILE (S.class = Texts.Char) & (S.c = Oberon.OptionChar) DO
			ch := S.nextCh;
			WHILE ch > " " DO
				opts[i] := ch;  INC(i);  Texts.Read(S, ch)
			END;
			opts[i] := " "; INC(i);
			S.nextCh := ch; Texts.Scan(S)
		END;
		opts[i] := 0X
	END GetOptions;

	PROCEDURE InOptions(VAR opt: ARRAY OF CHAR; ch: CHAR): BOOLEAN;
		VAR i: LONGINT;
	BEGIN
		i := 0;
		WHILE (opt[i] # 0X) & (opt[i] # ch) DO
			IF (opt[i] = ".") OR (opt[i] = "P") OR (opt[i] = "d") THEN
				REPEAT  INC(i)   UNTIL (opt[i] = 0X) OR (opt[i] = " ")
			ELSE INC(i) END
		END;
		RETURN opt[i] # 0X
	END InOptions;
	
	PROCEDURE ExtractPartition(VAR opt, part: ARRAY OF CHAR);
	VAR i, k: LONGINT;
	BEGIN
		i := 0; k := 0;
		WHILE (opt[i] # 0X) & (opt[i] # "P") DO INC(i) END;
		IF opt[i] # 0X THEN
			INC(i);
			WHILE (opt[i] # 0X) & (opt[i] # " ") DO part[k] := opt[i]; INC(k); INC(i) END
		END;
		part[k] := 0X
	END ExtractPartition;

	PROCEDURE ExtractPrefix(VAR from, to: ARRAY OF CHAR);
	VAR i: LONGINT;
	BEGIN
		i := 0; WHILE (i < LEN(from)) & (i < LEN(to)) & (from[i] # ".") & (from[i] # 0X) DO to[i] := from[i]; INC(i) END;
		IF i < LEN(to) THEN to[i] := 0X END
	END ExtractPrefix;
			
	PROCEDURE GetBreakPosition(VAR name: ARRAY OF CHAR; VAR pos: LONGINT);
		VAR S: Texts.Scanner; t: Texts.Text;  beg, end, time: LONGINT; 
	BEGIN
		Oberon.GetSelection(t, beg, end, time);
		name := ""; pos := NoBreakPosition;
		IF time >= 0 THEN
			Texts.OpenScanner(S, t, beg); Texts.Scan(S);
			end := S.line;
			WHILE (S.class # Texts.Name) & (S.line = end) & (S.s # "TRAP") DO Texts.Scan(S) END;
			IF (S.class = Texts.Name) & (S.s = "TRAP") THEN
				Texts.Scan(S);
				IF S.class = Texts.Name THEN
					ExtractPrefix(S.s, name);
					WHILE (S.class # Texts.Int) & (S.line = end) DO Texts.Scan(S) END;
					IF S.class = Texts.Int THEN pos := S.i END
				END
			END
		END;
		IF pos = NoBreakPosition THEN
			CCBasic.OutText(" trap not selected"); CCBasic.OutLine
		END
	END GetBreakPosition;
	
	PROCEDURE Locate(F: Display.Frame;  T: Texts.Text;  pos: LONGINT);
	VAR M: Oberon.CaretMsg;  N: Oberon.ControlMsg;
	BEGIN
		IF pos < 0 THEN pos := 0
		ELSIF pos > T.len THEN pos := T.len
		END;
		N.F := NIL; N.id := Oberon.neutralize; Display.Broadcast(N);
		Oberon.FadeCursor(Oberon.Pointer);
		M.id := Oberon.set; M.F := F; M.car := F; M.text := T; M.pos := pos; Display.Broadcast(M)
	END Locate;
	
	PROCEDURE GetReader(filename: ARRAY OF CHAR; VAR r: Texts.Reader; VAR t: Texts.Text);
	BEGIN NEW(t); Texts.Open(t, filename); Texts.OpenReader(r, t, 0)
	END GetReader;
END ComponentCompiler.

System.Free ComponentCompiler CCGenerator CCChecker CCImporter CCParser CCIR CCScanner Basic ~
PC.Compile \s CCBasic.Mod CCScanner.Mod CCIR.Mod CCParser.Mod CCImporter.Mod CCChecker.Mod CCGenerator.Mod ComponentCompiler.Mod ~

ComponentCompiler.Compile Hello1.Com ~
ComponentCompiler.Compile ^
ComponentCompiler.Compile *

ComponentCompiler.TestScanner HelloWorld.Com ~
ComponentCompiler.TestParser HelloWorld.Com ~
ComponentCompiler.TestChecker HelloWorld.Com ~


