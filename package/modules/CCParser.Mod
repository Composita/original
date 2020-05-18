MODULE CCParser; (** Component Compiler, Syntax Parser, 2005-2007 by Luc Blaeser *)
	IMPORT CCIR, CCScanner, CCBasic, AosIO := Streams;
	
	VAR scannerSymbol: CCScanner.Symbol; error-: BOOLEAN;
	
	PROCEDURE Parse*(r: AosIO.Reader; length: LONGINT);
	BEGIN
		CCScanner.InitializeScanner(r, length);
		CCIR.Initialize;
		error := FALSE;
		scannerSymbol := CCScanner.NextSymbol();
		WHILE IsToken(CCScanner.Component) OR IsToken(CCScanner.Interface) DO
			IF IsToken(CCScanner.Component) THEN ParseComponent(NIL) ELSE ParseInterface(NIL) END
		END;
		IF ~EOT() THEN Error("COMPONENT or INTERFACE missing") END
	END Parse;
		
	PROCEDURE ParseInterface(scope: CCIR.Node);
	VAR interface: CCIR.Interface; id: CCIR.Identifier; pos: LONGINT; 
	BEGIN
		pos := Pos();
		CheckToken(CCScanner.Interface, "INTERFACE missing");
		id := ParseIdentifier();
		interface := CCIR.NewInterface(pos, scope, id);
		CheckToken(CCScanner.Semicolon, "';' missing");
		IF ~IsToken(CCScanner.End) THEN interface.SetProtocol(ParseProtocolExpression()) END;
		CheckToken(CCScanner.End, "END expected");
		id := ParseIdentifier();
		IF ~id.Equal(interface.name) THEN Error("Identifier mismatch") END;
		CheckToken(CCScanner.Semicolon, "';' missing")
	END ParseInterface;
	
	PROCEDURE ParseProtocolExpression(): CCIR.Protocol;
	VAR pos: LONGINT; result, next: CCIR.Protocol; alt: CCIR.ProtocolAlternative;
	BEGIN
		pos := Pos();
		result := ParseProtocolTerm();
		IF result # NIL THEN
			WHILE IsToken(CCScanner.VerticalLine) DO
				NextSymbol;
				next := ParseProtocolTerm();
				IF next # NIL THEN
					NEW(alt, pos, result, next); result := alt
				END
			END
		END;
		RETURN result
	END ParseProtocolExpression;
	
	PROCEDURE ParseProtocolTerm(): CCIR.Protocol;
	VAR pos: LONGINT; result, next: CCIR.Protocol; seq: CCIR.ProtocolSequence;
	BEGIN
		pos := Pos();
		result := ParseProtocolFactor();
		IF result # NIL THEN
			WHILE IsToken(CCScanner.In) OR IsToken(CCScanner.Out) OR IsToken(CCScanner.LeftBracket) OR 
					IsToken(CCScanner.LeftBrace) OR IsToken(CCScanner.LeftParenthesis) DO
				next := ParseProtocolFactor();
				IF next # NIL THEN
					NEW(seq, pos, result, next); result := seq
				END
			END
		END;
		RETURN result
	END ParseProtocolTerm;
	
	PROCEDURE ParseProtocolFactor(): CCIR.Protocol;
	VAR result: CCIR.Protocol; option: CCIR.ProtocolOption; rep: CCIR.ProtocolRepetition; pos: LONGINT; 
		leftOpen: BOOLEAN; next: CCIR.Protocol; seq: CCIR.ProtocolSequence;
	BEGIN
		pos := Pos();
		IF IsToken(CCScanner.In) OR IsToken(CCScanner.Out) THEN 
			result := ParseMessageDeclaration(leftOpen); 
			IF leftOpen THEN
				pos := Pos();
				next := ParseProtocolExpression();
				NEW(seq, pos, result, next); result := seq;
				CheckToken(CCScanner.RightParenthesis, "')' missing")
			END
		ELSIF IsToken(CCScanner.LeftBracket) THEN
			NextSymbol;
			result := ParseProtocolExpression();
			NEW(option, pos, result); result := option;
			CheckToken(CCScanner.RightBracket, "']' missing")
		ELSIF IsToken(CCScanner.LeftBrace) THEN
			NextSymbol;
			result := ParseProtocolExpression();
			NEW(rep, pos, result); result := rep;
			CheckToken(CCScanner.RightBrace, "'}' missing")
		ELSIF IsToken(CCScanner.LeftParenthesis) THEN
			NextSymbol;
			result := ParseProtocolExpression();
			CheckToken(CCScanner.RightParenthesis, "')' missing")
		ELSE
			Error("Missing protocol expression");
			result := NIL
		END;
		RETURN result
	END ParseProtocolFactor;
	
	(* leftOpen = '(' opened for sub-expression and not for message parameters *)
	PROCEDURE ParseMessageDeclaration(VAR leftOpen: BOOLEAN): CCIR.Protocol;
	VAR pos: LONGINT; m: CCIR.MessageDeclaration; input: BOOLEAN; id: CCIR.Identifier;
	BEGIN
		leftOpen := FALSE;
		pos := Pos();
		IF IsToken(CCScanner.In) OR IsToken(CCScanner.Out) THEN 
			input := IsToken(CCScanner.In); NextSymbol
		ELSE
			Error("IN or OUT expected")
		END;
		id := ParseIdentifier();
		NEW(m, pos, id, input);
		IF IsToken(CCScanner.LeftParenthesis) THEN
			NextSymbol;
			IF IsIdentifier() THEN
				ParseParameterList(m.parameters, CCScanner.RightParenthesis);
				CheckToken(CCScanner.RightParenthesis, "')' missing")
			ELSE
				leftOpen := TRUE
			END
		END;
		RETURN m
	END ParseMessageDeclaration;
	
	PROCEDURE ParseComponent(scope: CCIR.Node);
	VAR component: CCIR.Component; id: CCIR.Identifier; pos: LONGINT; ;
	BEGIN
		pos := Pos();
		CheckToken(CCScanner.Component, "COMPONENT expected");
		id := ParseIdentifier();
		component := CCIR.NewComponent(pos, scope, id);
		IF IsToken(CCScanner.Offers) THEN
			NextSymbol;
			ParseInterfaceDeclarationList(component.offeredInterfaces)
		END;
		IF IsToken(CCScanner.Requires) THEN
			NextSymbol;
			ParseInterfaceDeclarationList(component.requiredInterfaces)
		END;
		CheckToken(CCScanner.Semicolon, "';' missing");
		WHILE IsToken(CCScanner.Component) OR IsToken(CCScanner.Interface) OR IsToken(CCScanner.Constant) OR 
				IsToken(CCScanner.Variable) OR IsToken(CCScanner.Procedure) OR IsToken(CCScanner.Implementation) DO
			IF IsToken(CCScanner.Implementation) THEN
				ParseImplementation(component)
			ELSE
				ParseDeclarations(component)
			END
		END;
		IF IsToken(CCScanner.Begin) THEN 
			NextSymbol;
			ParseStatementSequence(component.initializer)
		END;
		IF IsToken(CCScanner.Activity) THEN
			NextSymbol;
			ParseStatementSequence(component.activity)
		END;
		IF IsToken(CCScanner.Finally) THEN
			NextSymbol;
			ParseStatementSequence(component.finalizer)
		END;
		CheckToken(CCScanner.End, "END missing");
		id := ParseIdentifier();
		IF ~id.Equal(component.name) THEN Error("Identifier mismatch") END;
		CheckToken(CCScanner.Semicolon, "';' missing")
	END ParseComponent;
	
	PROCEDURE ParseInterfaceDeclarationList(list: CCIR.InterfaceDeclarationList);
	BEGIN
		ParseInterfaceDeclaration(list);
		WHILE IsToken(CCScanner.Comma) DO
			NextSymbol;
			ParseInterfaceDeclaration(list)
		END
	END ParseInterfaceDeclarationList;
		
	PROCEDURE ParseInterfaceDeclaration(list: CCIR.InterfaceDeclarationList);
	VAR decl: CCIR.InterfaceDeclaration; name: CCIR.Identifier; min, max: LONGINT;
	BEGIN
		min := 1; max := 1; (* default *)
		name := ParseIdentifier();
		IF IsToken(CCScanner.LeftBracket) THEN
			NextSymbol;
			IF IsIntegerValue() THEN
				min := scannerSymbol(CCScanner.IntegerValue).i; max := min;
				NextSymbol
			ELSE Error("Integer expected")
			END;
			IF ~IsToken(CCScanner.RightBracket) THEN
				CheckToken(CCScanner.Dot, "'..' missing"); CheckToken(CCScanner.Dot, "'..' missing");
				IF IsIntegerValue() THEN 
					max := scannerSymbol(CCScanner.IntegerValue).i; 
					NextSymbol;
				ELSIF IsToken(CCScanner.Star) THEN 
					max := CCIR.Infinite; 
					NextSymbol
				ELSE Error("Integer or '*' expected")
				END
			END;
			CheckToken(CCScanner.RightBracket, "']' missing")
		END;
		NEW(decl, name.pos, name, min, max);
		list.Add(decl)
	END ParseInterfaceDeclaration;
	
	PROCEDURE ParseDeclarations(scope: CCIR.Node);
	BEGIN
		WHILE IsToken(CCScanner.Component) OR IsToken(CCScanner.Interface) OR IsToken(CCScanner.Variable) OR 
				IsToken(CCScanner.Constant) OR IsToken(CCScanner.Procedure) DO
			IF IsToken(CCScanner.Component) THEN
				ParseComponent(scope)
			ELSIF IsToken(CCScanner.Interface) THEN
				ParseInterface(scope)
			ELSIF IsToken(CCScanner.Variable) THEN 
				ParseVariableList(scope)
			ELSIF IsToken(CCScanner.Constant) THEN
				ParseConstantList(scope)
			ELSIF IsToken(CCScanner.Procedure) THEN
				ParseProcedure(scope)
			ELSE HALT(111) 
			END
		END
	END ParseDeclarations;
	
	PROCEDURE ParseProcedure(scope: CCIR.Node);
	VAR pos: LONGINT; name: CCIR.Identifier; procedure: CCIR.Procedure; type: CCIR.Type;
	BEGIN
		pos := Pos();
		CheckToken(CCScanner.Procedure, "PROCEDURE missing");
		name := ParseIdentifier();
		procedure := CCIR.NewProcedure(pos, scope, name);
		IF IsToken(CCScanner.LeftParenthesis) THEN
			NextSymbol;
			IF ~IsToken(CCScanner.RightParenthesis) THEN
				ParseProcedureParamList(procedure)
			END;
			CheckToken(CCScanner.RightParenthesis, "')' missing");
			IF IsToken(CCScanner.Colon) THEN
				NextSymbol;
				type := ParseType();
				procedure.SetType(type)
			END
		END;
		CheckToken(CCScanner.Semicolon, "';' missing");
		ParseDeclarations(procedure);
		IF IsToken(CCScanner.Begin) THEN
			NextSymbol;
			ParseStatementSequence(procedure.statements)
		END;
		CheckToken(CCScanner.End, "END missing");
		name := ParseIdentifier();
		IF ~procedure.name.Equal(name) THEN Error("Identifier mismatch") END;
		CheckToken(CCScanner.Semicolon, "';' missing")
	END ParseProcedure;
	
	PROCEDURE ParseProcedureParamList(proc: CCIR.Procedure);
	BEGIN
		ParseProcedureParamDecl(proc);
		WHILE IsToken(CCScanner.Semicolon) DO
			NextSymbol;
			ParseProcedureParamDecl(proc)
		END
	END ParseProcedureParamList;
	
PROCEDURE ParseProcedureParamDecl(proc: CCIR.Procedure);
	VAR isVar: BOOLEAN; nameList: CCIR.IdentifierList; type: CCIR.Type; i: LONGINT; name: CCIR.Identifier; 
		par: CCIR.ProcedureParameter;
	BEGIN
		IF IsToken(CCScanner.Variable) THEN
			NextSymbol; isVar := TRUE
		ELSE isVar := FALSE
		END;
		NEW(nameList); ParseIdentifierList(nameList);
		IF IsToken(CCScanner.Colon) THEN
			NextSymbol;
			type := ParseType();
			FOR i := 0 TO nameList.Length()-1 DO
				name := nameList.GetIdentifier(i);
				proc.AddParameter(name.pos, isVar, name, type.Copy())
			END
		ELSE Error("':' missing")
		END
	END ParseProcedureParamDecl;
	
	PROCEDURE ParseParameterList(list: CCIR.ParameterList; endToken: LONGINT);
	BEGIN
		ParseParameterDecl(list);
		WHILE IsToken(CCScanner.Semicolon) DO
			NextSymbol;
			ParseParameterDecl(list)
		END
	END ParseParameterList;
	
	PROCEDURE ParseParameterDecl(list: CCIR.ParameterList);
	VAR nameList: CCIR.IdentifierList; type: CCIR.Type; i: LONGINT; name: CCIR.Identifier; par: CCIR.Parameter;
	BEGIN
		NEW(nameList); ParseIdentifierList(nameList);
		IF IsToken(CCScanner.Colon) THEN
			NextSymbol;
			type := ParseType();
			FOR i := 0 TO nameList.Length()-1 DO
				name := nameList.GetIdentifier(i);
				NEW(par, name.pos, name, type.Copy());
				list.Add(par)
			END
		ELSE Error("':' missing")
		END
	END ParseParameterDecl;
						
	PROCEDURE ParseVariableList(scope: CCIR.Node);
	BEGIN
		CheckToken(CCScanner.Variable, "VARIABLE missing");
		WHILE IsIdentifier() DO
			ParseVariableDecl(scope);
			CheckToken(CCScanner.Semicolon, "';' missing")
		END
	END ParseVariableList;
	
	PROCEDURE ParseVariableDecl(scope: CCIR.Node);
	VAR i: LONGINT; v: CCIR.Variable; name: CCIR.Identifier; type: CCIR.Type; varList: CCIR.VariableList;
		attrList: CCIR.IdentifierList;
	BEGIN
		NEW(varList);
		REPEAT
			name := ParseIdentifier();
			v := CCIR.NewVariable(name.pos, scope, name); varList.Add(v);
			IF IsToken(CCScanner.LeftBracket) THEN
				NextSymbol;
				ParseParameterList(v.parameters, CCScanner.RightBracket);
				CheckToken(CCScanner.RightBracket, "']' missing")
			END;
			IF ~IsToken(CCScanner.Colon) THEN
				CheckToken(CCScanner.Comma, "',' expected")
			END
		UNTIL ~IsIdentifier();
		CheckToken(CCScanner.Colon, "':' missing");
		type := ParseType();
		attrList := ParseAttributeList();
		FOR i := 0 TO varList.Length()-1 DO
			v := varList.GetVariable(i);
			v.SetType(type.Copy());
			IF attrList # NIL THEN
				v.SetAttributeList(attrList.Copy())
			END
		END
	END ParseVariableDecl;
	
	PROCEDURE ParseConstantList(scope: CCIR.Node);
	BEGIN
		CheckToken(CCScanner.Constant, "CONSTANT missing");
		WHILE IsIdentifier() DO
			ParseConstant(scope)
		END
	END ParseConstantList;
	
	PROCEDURE ParseConstant(scope: CCIR.Node);
	VAR name: CCIR.Identifier; public: BOOLEAN; expr: CCIR.Expression; c: CCIR.Constant;
	BEGIN
		name := ParseIdentifier();
		CheckToken(CCScanner.Equal, "'=' missing");
		expr := ParseExpression();
		c := CCIR.NewConstant(name.pos, scope, name, expr);
		CheckToken(CCScanner.Semicolon, "';' missing")
	END ParseConstant;
		
	PROCEDURE ParseImplementation(scope: CCIR.Component);
	VAR pos: LONGINT; name: CCIR.Identifier; implementation: CCIR.Implementation;
	BEGIN
		pos := Pos();
		CheckToken(CCScanner.Implementation, "IMPLEMENTATION missing");
		name := ParseIdentifier();
		implementation := CCIR.NewImplementation(pos, scope, name);
		CheckToken(CCScanner.Semicolon, "';' missing");
		ParseDeclarations(implementation);
		IF IsToken(CCScanner.Begin) THEN
			NextSymbol;
			ParseStatementSequence(implementation.statements)
		END;
		CheckToken(CCScanner.End, "END missing");
		name := ParseIdentifier();
		IF ~implementation.name.Equal(name) THEN Error("Identifier mismatch") END;
		CheckToken(CCScanner.Semicolon, "';' missing")
	END ParseImplementation;
	
	PROCEDURE ParseType(): CCIR.Type;
	VAR pos: LONGINT; id: CCIR.Identifier; ct: CCIR.ComponentType; at: CCIR.AnyType;
	BEGIN
		pos := Pos();
		IF IsIdentifier() THEN
			id := ParseIdentifier();
			IF id.Equal(CCIR.integerType.name) THEN RETURN CCIR.integerType
			ELSIF id.Equal(CCIR.realType.name) THEN RETURN CCIR.realType
			ELSIF id.Equal(CCIR.booleanType.name) THEN RETURN CCIR.booleanType
			ELSIF id.Equal(CCIR.textType.name) THEN RETURN CCIR.textType
			ELSIF id.Equal(CCIR.characterType.name) THEN RETURN CCIR.characterType
			END;
			NEW(ct, id.pos, id); RETURN ct
		ELSIF IsToken(CCScanner.Any) THEN
			NextSymbol;
			NEW(at, pos); 
			IF IsToken(CCScanner.LeftParenthesis) THEN
				NextSymbol;
				IF ~IsToken(CCScanner.VerticalLine) THEN
					ParseInterfaceDeclarationList(at.offeredInterfaces)
				END;
				IF IsToken(CCScanner.VerticalLine) THEN
					NextSymbol;
					ParseInterfaceDeclarationList(at.requiredInterfaces)
				END;
				CheckToken(CCScanner.RightParenthesis, "')' missing")
			END;
			RETURN at
		ELSE 
			Error("Invalid component type");
			RETURN EmptyType()
		END
	END ParseType;
	
	PROCEDURE ParseStatementSequence(seq: CCIR.StatementSequence);
	VAR attributes: CCIR.IdentifierList;
	BEGIN
		attributes := ParseAttributeList();
		IF attributes # NIL THEN seq.SetAttributeList(attributes) END;
		WHILE ~IsStatementSequenceEnd() DO
			ParseStatement(seq);
			IF ~IsStatementSequenceEnd() THEN
				CheckToken(CCScanner.Semicolon, "';' missing")
			END
		END;
		seq.SetEndPosition(Pos())
	END ParseStatementSequence;
	
	PROCEDURE IsStatementSequenceEnd(): BOOLEAN;
	BEGIN 
		RETURN EOT() OR IsToken(CCScanner.End) OR IsToken(CCScanner.Elsif) OR IsToken(CCScanner.Else) OR 
			IsToken(CCScanner.Until) OR IsToken(CCScanner.Activity) OR IsToken(CCScanner.Finally)
	END IsStatementSequenceEnd;
		
	PROCEDURE ParseAttributeList(): CCIR.IdentifierList;
	VAR list: CCIR.IdentifierList;
	BEGIN
		list := NIL;
		IF IsToken(CCScanner.LeftBrace) THEN
			NextSymbol;
			NEW(list);
			ParseIdentifierList(list);
			CheckToken(CCScanner.RightBrace, "'}' missing")
		END;
		RETURN list
	END ParseAttributeList;
	
	PROCEDURE ParseStatement(seq: CCIR.StatementSequence);
	VAR d: CCIR.Designator; 
	BEGIN
		IF IsToken(CCScanner.Semicolon) THEN 
			(* Unnecessary semicolon *)
		ELSIF IsToken(CCScanner.If) THEN
			ParseIfStatement(seq)
		ELSIF IsToken(CCScanner.While) THEN
			ParseWhileStatement(seq)
		ELSIF IsToken(CCScanner.Repeat) THEN
			ParseRepeatStatement(seq)
		ELSIF IsToken(CCScanner.For) THEN
			ParseForStatement(seq)
		ELSIF IsToken(CCScanner.Foreach) THEN
			ParseForeachStatement(seq)
		ELSIF IsToken(CCScanner.Return) THEN
			ParseReturnStatement(seq)
		ELSIF IsIdentifier() THEN
			d := ParseDesignator();
			IF IsToken(CCScanner.ExclamationMark) THEN
				ParseSend(seq, d)
			ELSIF IsToken(CCScanner.QuestionMark) THEN
				ParseReceive(seq, d)
			ELSIF IsToken(CCScanner.Assign) THEN
				ParseAssignment(seq, d)
			ELSE
				ParseProcedureCall(seq, d)
			END
		ELSIF IsToken(CCScanner.ExclamationMark) THEN
			ParseSend(seq, EmptyDesignator())
		ELSIF IsToken(CCScanner.QuestionMark) THEN
			ParseReceive(seq, EmptyDesignator())
		ELSIF IsToken(CCScanner.Await) THEN
			ParseAwaitStatement(seq)
		ELSIF IsToken(CCScanner.New) THEN
			ParseNewStatement(seq)
		ELSIF IsToken(CCScanner.Connect) THEN
			ParseConnectStatement(seq)
		ELSIF IsToken(CCScanner.Disconnect) THEN
			ParseDisconnectStatement(seq)
		ELSIF IsToken(CCScanner.Begin) THEN
			ParseStatementBlock(seq)
		ELSE Error("Invalid statement, END expected")
		END
	END ParseStatement;
	
	PROCEDURE ParseStatementBlock(seq: CCIR.StatementSequence);
	VAR pos: LONGINT; newSeq: CCIR.StatementSequence;
	BEGIN
		pos := Pos();
		CheckToken(CCScanner.Begin, "BEGIN missing");
		newSeq := CCIR.NewStatementBlock(pos, seq);
		ParseStatementSequence(newSeq);
		CheckToken(CCScanner.End, "END missing")
	END ParseStatementBlock;
	
	PROCEDURE ParseProcedureCall(seq: CCIR.StatementSequence; des: CCIR.Designator);
	VAR left: CCIR.Designator; arguments: CCIR.ExpressionList; id: CCIR.Identifier; call: CCIR.ProcedureCall; i: LONGINT;
		expr: CCIR.Expression;
	BEGIN
		IF des IS CCIR.ParameterDesignator THEN
			left := des(CCIR.ParameterDesignator).left; arguments := des(CCIR.ParameterDesignator).arguments
		ELSE
			left := des; arguments := NIL
		END;
		IF left IS CCIR.IdentifierDesignator THEN
			id := left(CCIR.IdentifierDesignator).identifier;
			call := CCIR.NewProcedureCall(id.pos, seq, id);
			IF arguments # NIL THEN
				FOR i := 0 TO arguments.Length()-1 DO
					expr := arguments.GetExpression(i);
					expr.SetOuter(NIL);
					call.arguments.Add(expr)
				END
			END
		ELSE Error("Invalid procedure")
		END
	END ParseProcedureCall;
	
	PROCEDURE ParseIfStatement(seq: CCIR.StatementSequence);
	VAR cond: CCIR.Expression; if: CCIR.IfStatement; pos: LONGINT; cb: CCIR.ConditionalBlock;
	BEGIN
		pos := Pos();
		CheckToken(CCScanner.If, "IF missing");
		cond := ParseExpression();
		CheckToken(CCScanner.Then, "THEN missing");
		if := CCIR.NewIfStatement(pos, seq, cond, Pos());
		ParseStatementSequence(if.ifBlock.statements);
		WHILE IsToken(CCScanner.Elsif) DO
			pos := Pos(); NextSymbol;
			cond := ParseExpression();
			CheckToken(CCScanner.Then, "THEN missing");
			cb := if.AddElsifBlock(pos, Pos(), cond);
			ParseStatementSequence(cb.statements)
		END;
		IF IsToken(CCScanner.Else) THEN
			if.CreateElseBlock(Pos());
			NextSymbol;
			ParseStatementSequence(if.else)
		END;
		CheckToken(CCScanner.End, "END missing")
	END ParseIfStatement;
	
	PROCEDURE ParseWhileStatement(seq: CCIR.StatementSequence);
	VAR pos: LONGINT; cond: CCIR.Expression; while: CCIR.WhileStatement;
	BEGIN
		pos := Pos();
		CheckToken(CCScanner.While, "WHILE missing");
		cond := ParseExpression();
		CheckToken(CCScanner.Do, "DO missing");
		while := CCIR.NewWhileStatement(pos, seq, cond, Pos());
		ParseStatementSequence(while.statements);
		CheckToken(CCScanner.End, "END missing")
	END ParseWhileStatement;
			
	PROCEDURE ParseRepeatStatement(seq: CCIR.StatementSequence);
	VAR pos: LONGINT; cond: CCIR.Expression; repeat: CCIR.RepeatStatement;
	BEGIN
		pos := Pos();
		CheckToken(CCScanner.Repeat, "REPEAT missing");
		repeat := CCIR.NewRepeatStatement(pos, seq, Pos());
		ParseStatementSequence(repeat.statements);
		CheckToken(CCScanner.Until, "UNTIL missing");
		cond := ParseExpression();
		repeat.SetCondition(cond)
	END ParseRepeatStatement;
	
	PROCEDURE ParseForStatement(seq: CCIR.StatementSequence);
	VAR pos: LONGINT; des: CCIR.Designator; fromExp, toExp, byExp: CCIR.Expression; iv: CCIR.IntegerValue; 
		for: CCIR.ForStatement;
	BEGIN
		pos := Pos();
		CheckToken(CCScanner.For, "FOR missing");
		des := ParseDesignator();
		CheckToken(CCScanner.Assign, "':=' missing");
		fromExp := ParseExpression();
		CheckToken(CCScanner.To, "TO missing");
		toExp := ParseExpression();
		IF IsToken(CCScanner.By) THEN
			NextSymbol;
			byExp := ParseExpression()
		ELSE
			NEW(iv, Pos(), 1); byExp := iv
		END;
		CheckToken(CCScanner.Do, "DO missing");
		for := CCIR.NewForStatement(pos, seq, Pos(), des, fromExp, toExp, byExp);
		ParseStatementSequence(for.statements);
		CheckToken(CCScanner.End, "END missing")
	END ParseForStatement;
	
	PROCEDURE ParseForeachStatement(seq: CCIR.StatementSequence);
	VAR pos: LONGINT; of: CCIR.Designator; foreach: CCIR.ForeachStatement;
	BEGIN
		pos := Pos();
		CheckToken(CCScanner.Foreach, "FOREACH missing");
		foreach := CCIR.NewForeachStatement(pos, seq);
		ParseDesignatorList(foreach.varDesignators);
		CheckToken(CCScanner.Of, "OF missing");
		of := ParseDesignator();
		foreach.SetOf(of);
		CheckToken(CCScanner.Do, "DO missing");
		ParseStatementSequence(foreach.statements);
		CheckToken(CCScanner.End, "END missing")
	END ParseForeachStatement;
	
	PROCEDURE ParseReturnStatement(seq: CCIR.StatementSequence);
	VAR pos: LONGINT; expr: CCIR.Expression; return: CCIR.ReturnStatement;
	BEGIN 
		pos := Pos();
		CheckToken(CCScanner.Return, "RETURN missing");
		IF ~IsToken(CCScanner.Semicolon) & ~IsStatementSequenceEnd() & ~IsToken(CCScanner.Begin) & 
				~IsToken(CCScanner.If) & ~IsToken(CCScanner.While) & ~IsToken(CCScanner.Repeat) & 
				~IsToken(CCScanner.For) & ~IsToken(CCScanner.Foreach) & ~IsToken(CCScanner.Return) THEN
			expr := ParseExpression()
		ELSE expr := NIL
		END;
		return := CCIR.NewReturnStatement(pos, seq, expr)
	END ParseReturnStatement;
	
	PROCEDURE ParseAssignment(seq: CCIR.StatementSequence; leftDes: CCIR.Designator);
	VAR rightExp: CCIR.Expression; assign: CCIR.Assignment;
	BEGIN
		CheckToken(CCScanner.Assign, "':=' missing");
		rightExp := ParseExpression();
		assign := CCIR.NewAssignment(leftDes.pos, seq, leftDes, rightExp)
	END ParseAssignment;
	
	PROCEDURE ParseSend(seq: CCIR.StatementSequence; interface: CCIR.Designator);
	VAR message: CCIR.Identifier; send: CCIR.SendStatement; pos: LONGINT;
	BEGIN
		pos := Pos();
		CheckToken(CCScanner.ExclamationMark, "'!' missing");
		message := ParseIdentifier();
		send := CCIR.NewSendStatement(pos, seq, interface, message);
		IF IsToken(CCScanner.LeftParenthesis) THEN
			NextSymbol;
			ParseExpressionList(send.messageArguments);
			CheckToken(CCScanner.RightParenthesis, "')' missing")
		END
	END ParseSend;
	
	PROCEDURE ParseReceive(seq: CCIR.StatementSequence; interface: CCIR.Designator);
	VAR message: CCIR.Identifier; receive: CCIR.ReceiveStatement; pos: LONGINT;
	BEGIN
		pos := Pos();
		CheckToken(CCScanner.QuestionMark, "'?' missing");
		message := ParseIdentifier();
		receive := CCIR.NewReceiveStatement(pos, seq, interface, message);
		IF IsToken(CCScanner.LeftParenthesis) THEN
			NextSymbol;
			ParseExpressionList(receive.messageArguments);
			CheckToken(CCScanner.RightParenthesis, "')' missing")
		END
	END ParseReceive;

	PROCEDURE ParseAwaitStatement(seq: CCIR.StatementSequence);
	VAR pos: LONGINT; expr: CCIR.Expression; await: CCIR.AwaitStatement;
	BEGIN
		pos := Pos();
		CheckToken(CCScanner.Await, "AWAIT missing");
		CheckToken(CCScanner.LeftParenthesis, "'(' missing");
		expr := ParseExpression();
		CheckToken(CCScanner.RightParenthesis, "')' missing");
		await := CCIR.NewAwaitStatement(pos, seq, expr)
	END ParseAwaitStatement;
	
	PROCEDURE ParseNewStatement(seq: CCIR.StatementSequence);
	VAR pos: LONGINT; varDes: CCIR.Designator; new: CCIR.NewStatement; 
	BEGIN
		pos := Pos();
		CheckToken(CCScanner.New, "NEW missing");
		CheckToken(CCScanner.LeftParenthesis, "'(' missing");
		varDes := ParseDesignator();
		new := CCIR.NewNewStatement(pos, seq, varDes);
		IF IsToken(CCScanner.Comma) THEN
			NextSymbol;
			ParseExpressionList(new.additionalArguments)
		END;
		CheckToken(CCScanner.RightParenthesis, "')' missing")
	END ParseNewStatement;

	PROCEDURE ParseConnectStatement(seq: CCIR.StatementSequence);
	VAR pos: LONGINT; source, target: CCIR.Designator; connect: CCIR.ConnectStatement;
	BEGIN
		pos := Pos();
		CheckToken(CCScanner.Connect, "CONNECT missing");
		CheckToken(CCScanner.LeftParenthesis, "'(' missing");
		source := ParseDesignator();
		CheckToken(CCScanner.Comma, "',' missing");
		target := ParseDesignator();
		CheckToken(CCScanner.RightParenthesis, "')' missing");
		connect := CCIR.NewConnectStatement(pos, seq, source, target)
	END ParseConnectStatement;
	
	PROCEDURE ParseDisconnectStatement(seq: CCIR.StatementSequence);
	VAR pos: LONGINT; des: CCIR.Designator; disconnect: CCIR.DisconnectStatement;
	BEGIN
		pos := Pos();
		CheckToken(CCScanner.Disconnect, "DISCONNECT missing");
		CheckToken(CCScanner.LeftParenthesis, "'(' missing");
		des := ParseDesignator();
		CheckToken(CCScanner.RightParenthesis, "')' missing");
		disconnect := CCIR.NewDisconnectStatement(pos, seq, des)
	END ParseDisconnectStatement;
	
	PROCEDURE ParseIdentifierList(list: CCIR.IdentifierList);
	VAR id: CCIR.Identifier; 
	BEGIN
		id := ParseIdentifier(); list.Add(id); 
		WHILE IsToken(CCScanner.Comma) DO
			NextSymbol;
			id := ParseIdentifier(); list.Add(id)
		END
	END ParseIdentifierList;
	
	PROCEDURE ParseDesignatorList(list: CCIR.ExpressionList);
	VAR d: CCIR.Designator; 
	BEGIN
		d := ParseDesignator(); list.Add(d);
		WHILE IsToken(CCScanner.Comma) DO
			NextSymbol;
			d := ParseDesignator(); list.Add(d)
		END
	END ParseDesignatorList;
				
	PROCEDURE ParseDesignator(): CCIR.Designator;
	VAR id: CCIR.Identifier; des: CCIR.Designator; idDes: CCIR.IdentifierDesignator; indexDes: CCIR.IndexDesignator;
		type: CCIR.Type; guardDes: CCIR.GuardDesignator; args: CCIR.ExpressionList; parDes: CCIR.ParameterDesignator; 
		i: LONGINT;
	BEGIN
		id := ParseIdentifier();
		NEW(idDes, id.pos, id); des := idDes;
		WHILE IsToken(CCScanner.LeftParenthesis) OR IsToken(CCScanner.LeftBracket) DO
			IF IsToken(CCScanner.LeftBracket) THEN
				NextSymbol;
				NEW(indexDes, des.pos, des); des := indexDes;
				ParseExpressionList(indexDes.arguments);
				CheckToken(CCScanner.RightBracket, "']' missing")
			ELSIF IsToken(CCScanner.LeftParenthesis) THEN
				NextSymbol;
				(* if ANY(DeclaredInterfaces) then create CCIR.GuardDesignator *)
				(* resolution to function is later done by the semantic checker *)
				IF IsToken(CCScanner.Any) THEN
					type := ParseType();
					NEW(guardDes, des.pos, des, type); des := guardDes
				ELSE
					NEW(args, NIL);
					ParseExpressionList(args);
					NEW(parDes, des.pos, des); des := parDes;
					FOR i := 0 TO args.Length()-1 DO parDes.arguments.Add(args.GetExpression(i)) END
				END;
				CheckToken(CCScanner.RightParenthesis, "')' missing")
			ELSE HALT(111)
			END
		END;
		RETURN des
	END ParseDesignator;
		
	PROCEDURE ParseExpressionList(list: CCIR.ExpressionList);
	VAR e: CCIR.Expression;
	BEGIN
		IF ~IsToken(CCScanner.RightParenthesis) THEN
			e := ParseExpression(); list.Add(e);
			WHILE IsToken(CCScanner.Comma) DO
				NextSymbol;
				e := ParseExpression(); list.Add(e)
			END
		END
	END ParseExpressionList;
		
	PROCEDURE ParseExpression(): CCIR.Expression;
	VAR expr, right: CCIR.Expression; be: CCIR.BinaryExpression; isOffers: BOOLEAN; interfaceTest: CCIR.InterfaceTest; 
		pos: LONGINT; type: CCIR.Type; typeTest: CCIR.TypeTest; attributes: CCIR.IdentifierList;
	BEGIN
		attributes := ParseAttributeList();
		expr := ParseSimpleExpression();
		IF IsToken(CCScanner.Equal) OR IsToken(CCScanner.Unequal) OR IsToken(CCScanner.Less) OR 
				IsToken(CCScanner.LessEqual) OR IsToken(CCScanner.Greater) OR IsToken(CCScanner.GreaterEqual) THEN
			IF IsToken(CCScanner.Equal) THEN
				NextSymbol;
				right := ParseSimpleExpression();
				NEW(be, Pos(), CCIR.Equal, expr, right)
			ELSIF IsToken(CCScanner.Unequal) THEN
				NextSymbol;
				right := ParseSimpleExpression();
				NEW(be, Pos(), CCIR.Unequal, expr, right)
			ELSIF IsToken(CCScanner.Less) THEN
				NextSymbol;
				right := ParseSimpleExpression();
				NEW(be, Pos(), CCIR.Less, expr, right)
			ELSIF IsToken(CCScanner.LessEqual) THEN
				NextSymbol;
				right := ParseSimpleExpression();
				NEW(be, Pos(), CCIR.LessEqual, expr, right)
			ELSIF IsToken(CCScanner.Greater) THEN
				NextSymbol;
				right := ParseSimpleExpression();
				NEW(be, Pos(), CCIR.Greater, expr, right)
			ELSIF IsToken(CCScanner.GreaterEqual) THEN
				NextSymbol;
				right := ParseSimpleExpression();
				NEW(be, Pos(), CCIR.GreaterEqual, expr, right)
			ELSE HALT(101)
			END;
			expr := be
		ELSIF IsToken(CCScanner.Offers) OR IsToken(CCScanner.Requires) THEN
			pos := Pos();
			isOffers := IsToken(CCScanner.Offers);
			NextSymbol;
			NEW(interfaceTest, pos, isOffers, expr);
			ParseInterfaceDeclarationList(interfaceTest.interfaces);
			expr := interfaceTest
		ELSIF IsToken(CCScanner.Is) THEN
			pos := Pos();
			NextSymbol;
			type := ParseType();
			NEW(typeTest, pos, expr, type);
			expr := typeTest
		END;
		IF (attributes # NIL) & (expr # NIL) THEN expr.SetAttributeList(attributes) END;
		RETURN expr
	END ParseExpression;
	
	PROCEDURE ParseReceiveTestFunction(interface: CCIR.Designator): CCIR.Expression;
	VAR message: CCIR.Identifier; receiveTest: CCIR.ReceiveTestFunction;
	BEGIN
		CheckToken(CCScanner.QuestionMark, "'?' missing");
		message := ParseMessagePattern();
		NEW(receiveTest, interface.pos, interface, message);
		RETURN receiveTest
	END ParseReceiveTestFunction;
	
	PROCEDURE ParseInputFunction(): CCIR.Expression;
	VAR des: CCIR.Designator; message: CCIR.Identifier; pos: LONGINT; input: CCIR.InputFunction;
	BEGIN
		pos := Pos();
		CheckToken(CCScanner.Input, "INPUT missing");
		CheckToken(CCScanner.LeftParenthesis, "'(' missing");
		IF IsIdentifier() THEN 
			des := ParseDesignator();
			IF IsToken(CCScanner.Comma) THEN
				NextSymbol; 
				message := ParseMessagePattern()
			ELSE
				IF des IS CCIR.IdentifierDesignator THEN
					message := des(CCIR.IdentifierDesignator).identifier;
					des := EmptyDesignator()
				ELSE
					Error("Message identifier expected");
					des := EmptyDesignator(); message := CCIR.NewIdentifier(Pos(), "")
				END
			END
		ELSE
			des := EmptyDesignator();
			message := ParseMessagePattern()
		END;
		CheckToken(CCScanner.RightParenthesis, "')' missing");
		NEW(input, pos, des, message);
		RETURN input
	END ParseInputFunction;
	
	PROCEDURE ParseMessagePattern(): CCIR.Identifier;
	VAR pos: LONGINT; message: CCIR.Identifier;
	BEGIN
		pos := Pos();
		IF IsIdentifier() THEN
			message := ParseIdentifier()
		ELSIF IsToken(CCScanner.Any) THEN
			NextSymbol;
			message := CCIR.NewIdentifier(pos, CCIR.AnyMessage)
		ELSIF IsToken(CCScanner.Finish) THEN
			NextSymbol;
			message := CCIR.NewIdentifier(pos, CCIR.FinishMessage)
		ELSE 
			Error("Message identifier, ANY, or FINISH expected");
			message := EmptyIdentifier()
		END;
		RETURN message
	END ParseMessagePattern;
	
	PROCEDURE ParseSimpleExpression(): CCIR.Expression;
	VAR term, se: CCIR.Expression; unaryExpr: CCIR.UnaryExpression; binaryExpr: CCIR.BinaryExpression;
	BEGIN
		IF IsToken(CCScanner.Plus) THEN 
			NextSymbol;
			term := ParseTerm();
			NEW(unaryExpr, Pos(), CCIR.Plus, term); se := unaryExpr
		ELSIF IsToken(CCScanner.Minus) THEN 
			NextSymbol;
			term := ParseTerm();
			NEW(unaryExpr, Pos(), CCIR.Minus, term); se := unaryExpr
		ELSE
			se := ParseTerm()
		END;
		WHILE ~IsToken(CCScanner.EndOfText) & (IsToken(CCScanner.Plus) OR IsToken(CCScanner.Minus) OR
			IsToken(CCScanner.Or)) DO
			IF IsToken(CCScanner.Plus) THEN 
				NextSymbol;
				term := ParseTerm(); 
				NEW(binaryExpr, Pos(), CCIR.Plus, se, term)
			ELSIF IsToken(CCScanner.Minus) THEN
				NextSymbol;
				term := ParseTerm();
				NEW(binaryExpr, Pos(), CCIR.Minus, se, term)
			ELSIF IsToken(CCScanner.Or) THEN
				NextSymbol;
				term := ParseTerm();
				NEW(binaryExpr, Pos(), CCIR.Or, se, term)
			ELSE HALT(101) (* not supported *)
			END;
			se := binaryExpr
		END;
		RETURN se
	END ParseSimpleExpression;
	
	PROCEDURE ParseTerm(): CCIR.Expression;
	VAR factor, term: CCIR.Expression; be: CCIR.BinaryExpression;
	BEGIN
		term := ParseFactor();
		WHILE ~IsToken(CCScanner.EndOfText) & (IsToken(CCScanner.Star) OR IsToken(CCScanner.DivToken) OR 
				IsToken(CCScanner.Slash) OR IsToken(CCScanner.Mod) OR IsToken(CCScanner.And)) DO
			IF IsToken(CCScanner.Star) THEN
				NextSymbol;
				factor := ParseFactor();
				NEW(be, Pos(), CCIR.Times, term, factor)
			ELSIF IsToken(CCScanner.DivToken) THEN
				NextSymbol;
				factor := ParseFactor();
				NEW(be, Pos(), CCIR.IntegerDivision, term, factor)
			ELSIF IsToken(CCScanner.Slash) THEN
				NextSymbol;
				factor := ParseFactor();
				NEW(be, Pos(), CCIR.RealDivision, term, factor)
			ELSIF IsToken(CCScanner.Mod) THEN
				NextSymbol;
				factor := ParseFactor();
				NEW(be, Pos(), CCIR.Modulo, term, factor)
			ELSIF IsToken(CCScanner.And) THEN
				NextSymbol;
				factor := ParseFactor();
				NEW(be, Pos(), CCIR.And, term, factor)
			ELSE HALT(101) (* not supported *)
			END;
			term := be
		END;
		RETURN term
	END ParseTerm;
	
	PROCEDURE ParseFactor(): CCIR.Expression;
	VAR e: CCIR.Expression; tv: CCIR.TextValue; iv: CCIR.IntegerValue; bv: CCIR.BooleanValue; cv: CCIR.CharacterValue;
		rv: CCIR.RealValue; ue: CCIR.UnaryExpression; des: CCIR.Designator;
	BEGIN 
		IF IsTextValue() THEN
			NEW(tv, Pos(), scannerSymbol(CCScanner.TextValue).s^); e := tv; NextSymbol
		ELSIF IsIntegerValue() THEN
			NEW(iv, Pos(), scannerSymbol(CCScanner.IntegerValue).i); e := iv; NextSymbol
		ELSIF IsRealValue() THEN
			NEW(rv, Pos(), scannerSymbol(CCScanner.RealValue).r); e := rv; NextSymbol
		ELSIF IsCharacterValue() THEN
			NEW(cv, Pos(), scannerSymbol(CCScanner.CharacterValue).c); e := cv; NextSymbol
		ELSIF IsIdentifier() THEN
			des := ParseDesignator();
			IF IsToken(CCScanner.QuestionMark) THEN
				e := ParseReceiveTestFunction(des)
			ELSE
				e := des
			END
		ELSIF IsToken(CCScanner.True) THEN
			NEW(bv, Pos(), TRUE); e := bv; NextSymbol
		ELSIF IsToken(CCScanner.False) THEN
			NEW(bv, Pos(), FALSE); e := bv; NextSymbol
		ELSIF IsToken(CCScanner.Tilde) THEN
			NextSymbol;
			e := ParseFactor();
			NEW(ue, Pos(), CCIR.Not, e); e := ue
		ELSIF IsToken(CCScanner.LeftParenthesis) THEN
			NextSymbol;
			e := ParseExpression();
			IF IsToken(CCScanner.RightParenthesis) THEN
				NextSymbol
			ELSE
				Error("')' missing"); e := EmptyExpression()
			END
		ELSIF IsToken(CCScanner.Input) THEN
			e := ParseInputFunction()
		ELSIF IsToken(CCScanner.QuestionMark) THEN
			e := ParseReceiveTestFunction(EmptyDesignator())
		ELSE 
			Error("Invalid factor"); e := EmptyExpression()
		END;
		RETURN e
	END ParseFactor;
	
	PROCEDURE NextSymbol;
	BEGIN IF ~EOT() THEN scannerSymbol := CCScanner.NextSymbol() END
	END NextSymbol;
	
	PROCEDURE IsIdentifier(): BOOLEAN;
	BEGIN RETURN scannerSymbol IS CCScanner.Identifier
	END IsIdentifier;
	
	PROCEDURE IsTextValue(): BOOLEAN;
	BEGIN RETURN scannerSymbol IS CCScanner.TextValue
	END IsTextValue;
	
	PROCEDURE IsIntegerValue(): BOOLEAN;
	BEGIN RETURN scannerSymbol IS CCScanner.IntegerValue
	END IsIntegerValue;
	
	PROCEDURE IsRealValue(): BOOLEAN;
	BEGIN RETURN scannerSymbol IS CCScanner.RealValue
	END IsRealValue;
	
	PROCEDURE IsCharacterValue(): BOOLEAN;
	BEGIN RETURN scannerSymbol IS CCScanner.CharacterValue
	END IsCharacterValue;
	
	PROCEDURE IsToken(type: LONGINT): BOOLEAN;
	BEGIN RETURN (scannerSymbol IS CCScanner.Token) & (scannerSymbol(CCScanner.Token).type = type)
	END IsToken;
	
	PROCEDURE EOT(): BOOLEAN;
	BEGIN RETURN (scannerSymbol IS CCScanner.Token) & (scannerSymbol(CCScanner.Token).type = CCScanner.EndOfText)
	END EOT;
	
	PROCEDURE ParseIdentifier(): CCIR.Identifier;
	VAR id: CCIR.Identifier;
	BEGIN
		IF IsIdentifier() THEN 
			NEW(id, Pos(), scannerSymbol(CCScanner.Identifier).s^);
			NextSymbol
		ELSE
			Error("Identifier missing");
			id := EmptyIdentifier()
		END;
		RETURN id
	END ParseIdentifier;
		
	PROCEDURE EmptyDesignator(): CCIR.Designator;
	VAR d: CCIR.IdentifierDesignator;
	BEGIN NEW(d, Pos(), CCIR.NewIdentifier(Pos(), "")); RETURN d
	END EmptyDesignator;		

	PROCEDURE EmptyExpression(): CCIR.Expression;
	BEGIN RETURN EmptyDesignator()
	END EmptyExpression;
	
	PROCEDURE EmptyIdentifier(): CCIR.Identifier;
	BEGIN RETURN CCIR.NewIdentifier(Pos(), "")
	END EmptyIdentifier;
	
	PROCEDURE EmptyType(): CCIR.Type;
	VAR d: CCIR.AnyType;
	BEGIN NEW(d, Pos()); RETURN d
	END EmptyType;
	
	PROCEDURE CheckToken(token: LONGINT; errorText: ARRAY OF CHAR);
	BEGIN 
		IF IsToken(token) THEN 
			NextSymbol 
		ELSE
			Error(errorText);
			WHILE ~EOT() & ~IsToken(token) DO NextSymbol END
		END
	END CheckToken;
	
	PROCEDURE Error(str: ARRAY OF CHAR);
	BEGIN CCBasic.Error(Pos(), str); error := TRUE
	END Error;
	
	PROCEDURE Pos(): LONGINT;
	BEGIN RETURN CCScanner.symbolBeginPosition
	END Pos;
END CCParser.

