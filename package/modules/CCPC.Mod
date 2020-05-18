(* Paco, Copyright 2000 - 2002, Patrik Reali, ETH Zurich *)

MODULE CCPC; (** AUTHOR "prk / be"; PURPOSE "Parallel Compiler: main module"; *)
	
IMPORT
		AosCommands := Commands, AosModules := Modules, AosIO := Streams, 
		AosFS := Files, AosTexts := Texts, AosConfig := Configuration,
		TextUtilities, XMLObjects, XML, XMLScanner, XMLParser, Strings, 
		UTF8Strings, DynamicStrings, 
		StringPool, PCM := CCPCM, PCS := CCPCS, PCT := CCPCT, PCP := CCPCP, PCLIR := CCPCLIR, PCBT := CCPCBT, 
		PCOF := CCPCOF, PCOM := CCPCOM, PCV := CCPCV, PCC := CCPCC;

	CONST
		ErrorTag = "Error";
		DefaultErrorFile = "Errors.XML";
		ErrCodeAttr = "code";
		
		Trace = FALSE;
		Debug = TRUE;
		
		NoBreakPC = -1;
		
		(* compiler options: -> PCM *)
		DefCodeOpt = {PCM.ArrayCheck, PCM.AssertCheck, PCM.TypeCheck, PCM.PtrInit, PCM.FullStackInit};
		DefParserOpt = {};
		DefDest = "386";
		
	VAR
		ErrorFile: ARRAY 256 OF CHAR;
		
	TYPE
		StringBuf = ARRAY 256 OF CHAR;

	VAR
		LastDest: ARRAY 16 OF CHAR;	(*last code generator loaded*)
	
	PROCEDURE ReportError(pos, err: LONGINT; msg: ARRAY OF CHAR);
	BEGIN
		PCM.LogWLn;
		PCM.LogW(9X);
		IF err = -1 THEN
			PCM.LogWStr("pos "); PCM.LogWNum(pos);
		ELSIF (err <= 400) OR (err >= 404) THEN
			PCM.LogWStr("pos  "); PCM.LogWNum(pos);
			PCM.LogWStr("  err  "); PCM.LogWNum(err)
		END;
		PCM.LogW(9X);
		PCM.LogWStr(msg)
	END ReportError;
	
	PROCEDURE OutMsg(scanner: PCS.Scanner);
		VAR s: PCS.Scanner;  t: PCS.Token; name: StringBuf;
	BEGIN
		s := PCS.ForkScanner(scanner);
		s.Get(t);
		IF t = PCS.module THEN
			s.Get(t);
			IF t = PCS.ident THEN
				StringPool.GetString(s.name, name);
				PCM.LogWStr(" compiling "); PCM.LogWStr(PCM.prefix); PCM.LogWStr(name);
				IF PCM.suffix # AosModules.extension[0] THEN
					PCM.LogWStr(PCM.suffix)
				ELSIF AosModules.ModuleByName(name) # NIL THEN
					PCM.LogWStr(" (in use) ")
				END
			END
		END;
	END OutMsg;
	
	PROCEDURE Configure(CONST base, dest: ARRAY OF CHAR;  errorIsFatal: BOOLEAN);
	VAR name: ARRAY 32 OF CHAR;  i, j: LONGINT;  p: PROCEDURE;
	BEGIN
		i := 0;
		WHILE (base[i] # 0X) DO  name[i] := base[i]; INC(i)  END; 
		j := 0;
		WHILE dest[j] # 0X DO  name[i] := dest[j]; INC(i); INC(j)  END;
		name[i] := 0X;
		GETPROCEDURE (name, "Install", p);
		IF p # NIL THEN
			p; (*call Install*)
			(* PCV.SetBasicSizes *)
		ELSIF errorIsFatal THEN
			PCM.LogWStr("Cannot install code-generator (no Install procedure)");
			PCM.LogWLn;
			PCM.error := TRUE
		END
	END Configure;

	PROCEDURE LoadBackEnd(CONST dest: ARRAY OF CHAR);
	BEGIN
		COPY(dest, LastDest);
		Configure("CCPCG", dest, TRUE);
		IF ~PCM.error THEN
			PCP.Assemble := NIL;	(*default = no assembler*)
			Configure("CCPCA", dest, FALSE)
		END;
	END LoadBackEnd;
	
	PROCEDURE GetOptions(S: AosIO.Reader; VAR opts: ARRAY OF CHAR);
		VAR i: LONGINT; ch: CHAR;
	BEGIN
		i := 0;
		WHILE opts[i] # 0X DO  INC(i)  END;
		S.SkipWhitespace;
		ch := S.Peek();
		WHILE (ch = "\") DO
			S.Char(ch);	(* skip \ *)
			S.Char(ch);
			WHILE ch > " " DO
				opts[i] := ch;  INC(i);  S.Char(ch)
			END;
			opts[i] := " "; INC(i);
			S.SkipWhitespace;
			ch := S.Peek()
		END;
		opts[i] := 0X
	END GetOptions;
	
	(** Extract input file prefix from global options string, exported for PC.Mod *)
		PROCEDURE GetSourcePrefix*(CONST options : ARRAY OF CHAR; VAR prefix : ARRAY OF CHAR);
		VAR ch, lastCh : CHAR; i : LONGINT;
		BEGIN
			prefix := "";
			i := 0; ch := 0X;
			LOOP
				lastCh := ch;
				ch := options[i]; INC(i);
				IF (ch = 0X) OR (i >= LEN(options)) THEN EXIT; END;
				IF (ch = "p") THEN
					IF (i = 0) OR (lastCh = " ") THEN (* be sure that "p" is the first character of an option *)
						SubString(options, i, prefix);
					END;
				END;
			END;
		END GetSourcePrefix;
		
		PROCEDURE SubString(CONST options : ARRAY OF CHAR; VAR from : LONGINT; VAR str: ARRAY OF CHAR);
		VAR ch: CHAR;  j: LONGINT;
		BEGIN
			ASSERT(from < LEN(options));
			ch := options[from]; INC(from); j := 0;
			WHILE (ch # 0X) & (ch # " ") & (from < LEN(options)) & (j < LEN(str)-1) DO
				str[j] := ch; ch := options[from]; INC(j); INC(from);
			END;
			str[j] := 0X;
		END SubString;
	
	PROCEDURE ParseOptions(VAR options, prefix, extension, dest, dump, objF: ARRAY OF CHAR;  VAR cOpt, pOpt: SET);
	VAR  i: LONGINT;  ch: CHAR;
	
		PROCEDURE SubString(VAR str: ARRAY OF CHAR);
		VAR ch: CHAR;  j: LONGINT;
		BEGIN
			ch := options[i]; INC(i); j := 0;
			WHILE (ch # 0X) & (ch # " ") DO
				str[j] := ch; ch := options[i]; INC(j); INC(i)
			END;
			str[j] := 0X
		END SubString;
		
	BEGIN
		(*defaults*)
		cOpt := DefCodeOpt;
		pOpt := DefParserOpt;
		prefix[0] := 0X;
		COPY(AosModules.extension[0], extension);
		COPY(DefDest, dest);
		COPY("", dump);
		(*parse*)
		i := 0;
		REPEAT
			ch := options[i]; INC(i);
			IF ch = "s" THEN pOpt := pOpt / {PCM.NewSF}
			ELSIF ch = "e" THEN pOpt := pOpt / {PCM.ExtSF}
			ELSIF ch = "n" THEN pOpt := pOpt / {PCM.NoFiles}
			ELSIF ch = "f" THEN pOpt := pOpt / {PCM.Breakpoint}
			ELSIF ch = "o" THEN pOpt := pOpt / {PCM.NoOpOverloading}	(* do NOT allow operator overloading *)
			ELSIF ch = "N" THEN cOpt := cOpt / {PCM.NilCheck}
			ELSIF ch = "c" THEN pOpt := pOpt / {PCM.CacheImports}
			ELSIF ch = "x" THEN cOpt := cOpt / {PCM.ArrayCheck}
			ELSIF ch = "a" THEN cOpt := cOpt / {PCM.AssertCheck}
			ELSIF ch = "z" THEN cOpt := cOpt / {PCM.FullStackInit}
			ELSIF ch = "b" THEN pOpt := pOpt / {PCM.BigEndian}
			ELSIF ch = "." THEN DEC(i); SubString(extension)
			ELSIF ch = "P" THEN SubString(prefix)
			ELSIF ch = "d" THEN SubString(dest)
			ELSIF ch = "D" THEN SubString(dump)
			ELSIF ch = "O" THEN cOpt := cOpt + {PCM.Optimize}
			ELSIF ch = "F" THEN SubString(objF)
			ELSIF ch = "W" THEN pOpt := pOpt + {PCM.Warnings}
			ELSIF ch = "K" THEN 
				cOpt := cOpt + {PCM.KernelOberon, PCM.CardinalRequired
					, PCM.StackOverflowChecks
					(* , PCM.ReferenceCounting *) };
				PCM.LogWStr(" (Oberon-K)"); PCM.LogWLn
			END
		UNTIL ch = 0X;
	END ParseOptions;
	
	PROCEDURE EmitScope(scope: PCT.Scope);
	VAR name: StringBuf;
	BEGIN
		IF (scope.code # NIL) & (scope.code IS PCLIR.Code) THEN
			IF Debug THEN PCT.GetScopeName(scope, name) END;
			PCLIR.Emit(scope.code(PCLIR.Code));
			scope.code := NIL
		END
	END EmitScope;
	
	PROCEDURE Module*(scanner: PCS.Scanner; options: ARRAY OF CHAR; breakpc: LONGINT; log: AosIO.Writer; 
		errlist: PCM.ErrorList; VAR error: BOOLEAN);
		VAR scope: PCT.ModScope; dest, objF: ARRAY 16 OF CHAR;
			size: LONGINT; R: PCM.Rider; new, extend, nofile: BOOLEAN;
			version: CHAR; res: LONGINT;
			str: StringBuf;
			msg: ARRAY 32 OF CHAR;
	BEGIN {EXCLUSIVE}
		PCM.log := log;
		PCM.Init(ReportError);		(*also resets PCM.count!!*)
		ParseOptions(options, PCM.prefix, PCM.suffix, dest, PCM.dump, objF, PCM.codeOptions, PCM.parserOptions);
		IF dest # LastDest THEN LoadBackEnd(dest) END;
		OutMsg(scanner);
		new := PCM.NewSF IN PCM.parserOptions;
		extend := PCM.ExtSF IN PCM.parserOptions;
		nofile := PCM.NoFiles IN PCM.parserOptions;
		PCM.bigEndian := PCM.BigEndian IN PCM.parserOptions;
		PCM.breakpc := MAX(LONGINT);
		IF PCM.Breakpoint IN PCM.parserOptions THEN
			IF breakpc = NoBreakPC THEN
				PCM.LogWLn; PCM.LogWStr("No PC Selected");
				RETURN
			END;
			PCM.breakpc := breakpc
		END;
		
		IF PCLIR.CG.Init() THEN
			NEW(scope); PCT.InitScope(scope, NIL, {}, FALSE);
			PCP.ParseModule(scope, scanner);
			IF ~PCM.error & ~nofile THEN
				IF PCM.OldFileFormat THEN
					version := PCM.OldFileVersion
				ELSE
					version := PCM.NewFileVersion
				END;
				StringPool.GetString(scope.owner.name, str);
				PCM.Open(str, R, version);
				IF ~(PCM.Breakpoint IN PCM.parserOptions) THEN
					IF PCM.CacheImports IN PCM.parserOptions THEN
						PCT.Unregister(PCT.database, scope.owner.name);
(*
						PCT.Register(PCT.database, scope.owner)
*)
					END;
					PCOM.Export(R, scope.owner, new, extend, msg);
					PCM.LogWStr(msg)
				END;
				IF ~PCM.error THEN
					PCT.TraverseScopes(scope, EmitScope);
					IF objF # "" THEN
						Configure("PCOF", objF, TRUE)
					ELSE
						PCOF.Install
					END;
					IF ~PCM.error & ~(PCM.Breakpoint IN PCM.parserOptions) THEN  PCBT.generate(R, scope, size)  END;
				END
			END;
			PCM.MakeErrorList(errlist);
			PCM.FlushErrors;
			IF ~PCM.error THEN
				PCM.LogWStr("  "); PCM.LogWNum(size); PCM.LogWStr(" done ");
				IF PCM.bigEndian THEN  PCM.LogWStr("(BigEndian Mode)") END;
				PCM.LogWLn
			ELSE
				PCM.LogWStr(" not done"); PCM.LogWLn
			END;
			PCLIR.CG.Done(res); (* ignore res ? *)
		ELSE 
			PCM.LogWLn; PCM.LogWStr("  Code generator not installed"); 
			PCM.LogWLn; PCM.error := TRUE
		END;
		PCC.Cleanup;
		error := PCM.error;
		PCM.Reset;
		PCBT.context := NIL;
		PCM.LogFlush;
	END Module;

	(** Compile code contained in t, beginning at position pos *)

	PROCEDURE CompileText*(t: AosTexts.Text; pos, pc: LONGINT; opt: ARRAY OF CHAR; log: AosIO.Writer; 
	errlist: PCM.ErrorList; VAR error: BOOLEAN);
	BEGIN
		PCM.log := log;
		IF t = NIL THEN
			PCM.LogWStr("No text available"); PCM.LogWLn; PCM.LogFlush;
			error := TRUE; RETURN
		END;
		Module(PCS.InitWithText(t, pos), opt, pc, log, errlist, error);
	END CompileText;

	(** Compile file *)
	
	PROCEDURE CompileFile*(name, opt: ARRAY OF CHAR; pc: LONGINT; log: AosIO.Writer;
		errlist: PCM.ErrorList; VAR error: BOOLEAN);
		VAR atu: AosTexts.Text; format, res: LONGINT;
	BEGIN
		PCM.log := log;
		NEW(atu);
		TextUtilities.LoadAuto(atu, name, format, res);
		IF res # 0 THEN
			PCM.LogWStr(name); PCM.LogWStr(" not found"); PCM.LogWLn; PCM.LogFlush;
			error := TRUE; RETURN
		END;
		PCM.LogWStr(name);
		Module(PCS.InitWithText(atu, 0), opt, pc, log, errlist, error);
	END CompileFile;
	
	(** Compile ascii file *)

	PROCEDURE CompileAsciiFile*(name, opt: ARRAY OF CHAR; pc: LONGINT; log: AosIO.Writer; 
	errlist: PCM.ErrorList; VAR error: BOOLEAN);
		VAR f: AosFS.File; r: AosFS.Reader;
	BEGIN
		PCM.log := log;
		f := AosFS.Old(name);
		IF f = NIL THEN
			PCM.LogWStr(name); PCM.LogWStr(" not found");
			PCM.LogWLn; PCM.LogFlush;
			error := TRUE; RETURN
		END;
		PCM.LogWStr(name);
		AosFS.OpenReader(r, f, 0);
		Module(PCS.InitWithReader(r, f.Length()), opt, pc, log, errlist, error);
	END CompileAsciiFile;

	PROCEDURE Compile*(context : AosCommands.Context);
		VAR 
		globalOpt, localOpt: ARRAY 256 OF CHAR;
		fullname, prefix, filename: ARRAY 256 OF CHAR;
		count: LONGINT;
		error: BOOLEAN;
		breakPC: LONGINT;
		BEGIN
		PCT.InitDB(PCT.database);
		error := FALSE;
		globalOpt := ""; GetOptions(context.arg, globalOpt);
		breakPC := MAX(LONGINT);
		IF Strings.ContainsChar(globalOpt, "f", FALSE) THEN
		   IF ~context.arg.EOLN() THEN
		      context.arg.GetInteger(breakPC, FALSE)
		   END;
		   PCM.LogWStr("Breakpoint set "); 
		   PCM.LogWNum(breakPC)
		END;
		GetSourcePrefix(globalOpt, prefix);
		count := 0;
		PCM.LogWStr("Files");
		WHILE  ~context.arg.EOLN() & ~error DO
			context.arg.String(filename);
			PCM.LogWStr(filename);
		       IF filename # "" THEN
				INC(count);
				COPY(globalOpt, localOpt);
				GetOptions(context.arg, localOpt);
				COPY(prefix, fullname); Strings.Append(fullname, filename);
				CompileFile(fullname, localOpt, breakPC, context.out, NIL, error);
				PCM.LogFlush;
				IF count MOD 32 = 0 THEN PCT.InitDB(PCT.database) END;
			END
		END;
		PCT.InitDB(PCT.database)
	END Compile;

	PROCEDURE TrapHandler(pos, line, row: LONGINT; CONST msg: ARRAY OF CHAR);
	BEGIN
		PCM.LogWStr("could not load error messages: "); PCM.LogWLn;
		PCM.LogWStr(ErrorFile); PCM.LogWStr(" invalid (pos ");
		PCM.LogWNum(pos); PCM.LogWStr(", line ");
		PCM.LogWNum(line); PCM.LogWStr(", row ");
		PCM.LogWNum(row); PCM.LogWStr("   ");
		PCM.LogWStr(msg); PCM.LogWStr(")"); PCM.LogWLn;
	END TrapHandler;
		
	PROCEDURE InitErrMsg*;
	VAR
		f: AosFS.File; scanner: XMLScanner.Scanner; parser: XMLParser.Parser; errors: XML.Document;
		e: XML.Element; enum, msgEnum: XMLObjects.Enumerator; p: ANY;
		code, i: LONGINT; str: XML.String;
		dynStr: DynamicStrings.DynamicString;		
		r : AosFS.Reader;
		res: LONGINT;
	BEGIN
		AosConfig.Get("Paco.ErrorMessages", ErrorFile, res);
		IF ErrorFile = "" THEN ErrorFile := DefaultErrorFile END;
		f := AosFS.Old(ErrorFile);
		IF f = NIL THEN
			PCM.LogWStr("could not load error messages: ");
			PCM.LogWStr(ErrorFile); PCM.LogWStr(" not found"); PCM.LogWLn;
			RETURN;
		END;
		(* f # NIL *)
		AosFS.OpenReader(r, f, 0);
		NEW(scanner, r);
		NEW(parser, scanner); parser.reportError := TrapHandler;
		errors := parser.Parse();
		e := errors.GetRoot();
		enum := e.GetContents();
		WHILE enum.HasMoreElements() DO
			p := enum.GetNext();
			IF p IS XML.Element THEN
				e := p(XML.Element);
				str := e.GetName();
				IF str^ = ErrorTag THEN
						(* extract error code *)
					str := e.GetAttributeValue(ErrCodeAttr);
					Strings.StrToInt(str^, code);
						(* extract error message *)
					msgEnum := e.GetContents();
					NEW(dynStr);
					WHILE msgEnum.HasMoreElements() DO
						p := msgEnum.GetNext();
						IF p IS XML.Chars THEN
							str := p(XML.Chars).GetStr();
							dynStr.Append(str^);
						ELSIF p IS XML.CDataSect THEN
							str := p(XML.CDataSect).GetStr();
							dynStr.Append(str^);
						ELSIF p IS XML.CharReference THEN
							NEW(str, 5);
							i := 0;
							IF UTF8Strings.EncodeChar(p(XML.CharReference).GetCode(), str^, i) THEN
								dynStr.Append(str^);
							END;
						ELSE
							(* ignore *)
						END;
					END;
					str := dynStr.ToArrOfChar();
					PCM.SetErrorMsg(code, str^);
					dynStr.Init();
				END;
			END;
		END;
	END InitErrMsg;

BEGIN
	LastDest := "";
	PCM.LogWStr("Parallel Compiler / prk"); PCM.LogWLn;
	PCV.Install;
	InitErrMsg;
	IF Trace THEN PCM.LogWStr("PCCompiler.Trace on"); PCM.LogWLn END;
END CCPC.

(*
	25.11.03	mb	added InitErrMsg: read error messages from XML file
	20.09.03	prk	"/Dcode" compiler option added
	24.06.03	prk	Check that name after END is the same as declared after MODULE
	25.02.03	prk	PC split into PC0 (Aos pure) and PC (Oberon dependent)
	09.03.06	lb	  add support for Reduced Oberon (for new kernel construction)
*)
