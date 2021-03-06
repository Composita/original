��   Oberon10.Scn.Fnt  �   	    �   -    5        :    �    L    �      Oberon10b.Scn.Fnt  B    �   � 
MODULE ComponentCompiler; (* 2005-2010 by Luc Blaeser *)
	IMPORT CCGenerator, CCChecker, CCImporter, CCParser, CCIR, CCScanner, CCBasic, 
	Streams, Commands, Texts, TextUtilities;
		
	PROCEDURE CompileWithReader(r: Streams.Reader; length: LONGINT; outPartition: ARRAY OF CHAR;
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
	
	PROCEDURE CompileFile*(name: ARRAY OF CHAR; outPartition, opt: ARRAY OF CHAR; VAR error: BOOLEAN);
	VAR f: BOOLEAN; breakPos, sourcePos: LONGINT; r: TextUtilities.TextReader; t: Texts.Text; b: Streams.Reader; 
		breakName: ARRAY 128 OF CHAR; format, res: LONGINT;
	BEGIN
		NEW(t);
		TextUtilities.LoadAuto(t, name, format, res);
		CCBasic.OutText(name); 
		IF res # 0 THEN
			CCBasic.OutText(" not present"); CCBasic.OutLine;
			error := TRUE
		ELSE
			CCBasic.OutText(" compiling ");
			NEW(r, t);
			t.AcquireRead;
			CompileWithReader(r, t.GetLength(), outPartition, f, breakName, breakPos, error, sourcePos);
			t.ReleaseRead
		END
	END CompileFile;
	
	PROCEDURE Compile*(context: Commands.Context);
	VAR name: ARRAY 128 OF CHAR; error: BOOLEAN; globalOpt, localOpt, outPartition: ARRAY 32 OF CHAR;
	BEGIN
		error := FALSE;
		globalOpt := ""; GetOptions(context.arg, globalOpt);
		ExtractPartition(globalOpt, outPartition);
		WHILE ~context.arg.EOLN() & ~error DO
			context.arg.String(name);
			IF name # "" THEN
				context.arg.SkipWhitespace;
	   		       COPY(globalOpt, localOpt);
				CompileFile(name, outPartition, localOpt, error)
			END
		END
	END Compile;

	PROCEDURE GetOptions(r: Streams.Reader; VAR opts: ARRAY OF CHAR);
	VAR i: LONGINT; ch: CHAR;
	BEGIN
		i := 0;
		WHILE opts[i] # 0X DO INC(i) END;
		r.SkipWhitespace;
		ch := r.Peek();
		WHILE (ch = "\") DO
			r.Char(ch); (* skip \ *)
			r.Char(ch);
			WHILE (ch > " ") DO
				opts[i] := ch;  INC(i); r.Char(ch)
			END;
			opts[i] := " "; INC(i);
			r.SkipWhitespace;
			ch := r.Peek()
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
END ComponentCompiler.

SystemTools.Free ComponentCompiler ~

