MODULE CCChecker; (** Component Compiler, Semantic Checker, 2005-2007 by Luc Blaeser *)
	IMPORT CCImporter, CCIR, CCBasic;
	
	CONST MaxNameLength = 32 - 3 (* length of suffix *);
	CONST CheckSynchronization = TRUE;
	
	VAR error-: BOOLEAN;
	
	PROCEDURE Check*;
	VAR i: LONGINT; interface: CCIR.Interface; component: CCIR.Component;
	BEGIN
		error := FALSE;
		CheckInterfaceList(CCIR.compiledInterfaces);
		CheckComponents(CCIR.compiledComponents)
	END Check;
	
	PROCEDURE CheckInterfaceList(list: CCIR.InterfaceList);
	VAR i: LONGINT; interface: CCIR.Interface;
	BEGIN
		FOR i := 0 TO list.Length()-1 DO
			interface := list.GetInterface(i);
			CheckInterface(interface)
		END
	END CheckInterfaceList;
	
	PROCEDURE CheckComponents(list: CCIR.ComponentList);
	BEGIN
		CheckComponentListForDef(list);
		CheckComponentListForImpl(list)
	END CheckComponents;
	
	PROCEDURE CheckComponentListForDef(list: CCIR.ComponentList);
	VAR i: LONGINT; component: CCIR.Component;
	BEGIN
		FOR i := 0 TO list.Length()-1 DO
			component := list.GetComponent(i);
			CheckComponentForDef(component)
		END
	END CheckComponentListForDef;
	
	PROCEDURE CheckComponentListForImpl(list: CCIR.ComponentList);
	VAR i: LONGINT; component: CCIR.Component;
	BEGIN
		FOR i := 0 TO list.Length()-1 DO
			component := list.GetComponent(i);
			CheckComponentForImpl(component)
		END
	END CheckComponentListForImpl;
	
	PROCEDURE CheckComponentForDef(c: CCIR.Component);
	BEGIN
		IF c.outer = NIL THEN CheckNameLength(c.name) END;
		CheckUniqueIdentifier(c.name, c.outer);
		CheckInterfaceDeclList(c, TRUE, c.offeredInterfaces);
		CheckInterfaceDeclList(c, FALSE, c.requiredInterfaces);
		CheckInterfaceList(c.nestedInterfaces);
		CheckConstants(c, c.constants);
		CheckComponentListForDef(c.nestedComponents);
		CheckProcedureListForDef(c.procedures)
	END CheckComponentForDef;
	
	PROCEDURE CheckNameLength(x: CCIR.Identifier);
	BEGIN IF LEN(x.name^) > MaxNameLength THEN Error(x.pos, "Too long identifier") END
	END CheckNameLength;
	
	PROCEDURE CheckComponentForImpl(c: CCIR.Component);
	BEGIN
		CheckComponentListForImpl(c.nestedComponents);
		CheckVariables(c, c.variables);
		CheckImplementations(c.implementations);
		CheckProcedureListForImpl(c.procedures);
		CheckStatementSequence(c.initializer);
		CheckStatementSequence(c.activity);
		CheckStatementSequence(c.finalizer);
		CollectUsesInComponent(c);
		CheckInterproceduralProtection(c);
		CheckAwaitDependencies(c)
	END CheckComponentForImpl;
	
	PROCEDURE CollectUsesInComponent(current: CCIR.Component);
	VAR i: LONGINT; impl: CCIR.Implementation; topmost: CCIR.Component;
	BEGIN
		topmost := CCIR.GetOutmostComponent(current);
		CollectInterfaceList(topmost, current.offeredInterfaces);
		CollectInterfaceList(topmost, current.requiredInterfaces);
		CollectVariableList(topmost, current.variables);
		FOR i := 0 TO current.implementations.Length()-1 DO
			impl := current.implementations.GetImplementation(i);
			CollectVariableList(topmost, impl.variables);
			CollectUsesInProcedureList(topmost, impl.nestedProcedures)
		END;
		CollectUsesInProcedureList(current, current.procedures)
	END CollectUsesInComponent;
	
	PROCEDURE CollectUsesInProcedureList(topmost: CCIR.Component; list: CCIR.ProcedureList);
	VAR i: LONGINT; proc: CCIR.Procedure;
	BEGIN
		FOR i := 0 TO list.Length()-1 DO
			proc := list.GetProcedure(i);
			CollectVariableList(topmost, proc.variables);
			CollectUsesInProcedureList(topmost, proc.nestedProcedures)
		END
	END CollectUsesInProcedureList;
	
	PROCEDURE CollectUsedExternalComponent(current: CCIR.Node; used: CCIR.ComponentDefinition);
	VAR component: CCIR.Component;
	BEGIN
		component := CCIR.GetSurroundingComponent(current); ASSERT(component # NIL);
		component := CCIR.GetOutmostComponent(component); ASSERT(component # NIL);
		IF IsExternalComponent(component, used) & ~component.usedComponents.Contains(used) THEN
			component.usedComponents.Add(used)
		END
	END CollectUsedExternalComponent;
	
	PROCEDURE CollectUsedExternalInterface(current: CCIR.Node; used: CCIR.Interface);
	VAR component: CCIR.Component;
	BEGIN
		component := CCIR.GetSurroundingComponent(current); ASSERT(component # NIL);
		component := CCIR.GetOutmostComponent(component); ASSERT(component # NIL);
		IF IsExternalInterface(used) & ~component.usedInterfaces.Contains(used) THEN
			component.usedInterfaces.Add(used)
		END
	END CollectUsedExternalInterface;
		
	PROCEDURE CollectInterfaceList(component: CCIR.Component; list: CCIR.InterfaceDeclarationList);
	VAR i: LONGINT; x: CCIR.InterfaceDeclaration;
	BEGIN
		FOR i := 0 TO list.Length()-1 DO
			x := list.GetInterfaceDeclaration(i);
			CollectUsedExternalInterface(component, x.interface)
		END
	END CollectInterfaceList;
	
	PROCEDURE CollectVariableList(component: CCIR.Component; list: CCIR.VariableList);
	VAR i: LONGINT; variable: CCIR.Variable; 
	BEGIN
		FOR i := 0 TO list.Length()-1 DO
			variable := list.GetVariable(i);
			CheckVariableParameterList(component, variable.parameters);
			CollectType(component, variable.type)
		END
	END CollectVariableList;
	
	PROCEDURE CollectType(current: CCIR.Node; type: CCIR.Type);
	VAR com: CCIR.Component; ct: CCIR.ComponentType; at: CCIR.AnyType; ctcom: CCIR.ComponentDefinition;
	BEGIN
		com := CCIR.GetSurroundingComponent(current);
		IF type IS CCIR.ComponentType THEN
			ct := type(CCIR.ComponentType);
			ctcom := ct.componentDefinition;
			IF ctcom # NIL THEN
				CollectUsedExternalComponent(com, ctcom)
			ELSE Error(ct.pos, "Undefined component")
			END
		ELSIF type IS CCIR.AnyType THEN
			at := type(CCIR.AnyType);
			CollectInterfaceList(com, at.offeredInterfaces);
			CollectInterfaceList(com, at.requiredInterfaces)
		END
	END CollectType;
	
	PROCEDURE CheckVariableParameterList(current: CCIR.Node; list: CCIR.ParameterList);
	VAR i: LONGINT; par: CCIR.Parameter;
	BEGIN
		CheckParameterList(current, list);
		FOR i := 0 TO list.Length()-1 DO
			par := list.GetParameter(i);
			IF par.type # NIL THEN
				IF (par.type # CCIR.integerType) & (par.type # CCIR.booleanType) & (par.type # CCIR.realType) &
						(par.type # CCIR.characterType) & (par.type # CCIR.textType) THEN
					Error(par.pos, "Unsupported index type") 
				END
			END
		END
	END CheckVariableParameterList;
	
	PROCEDURE IsExternalComponent(current: CCIR.Component; component: CCIR.ComponentDefinition): BOOLEAN;
	BEGIN 
		IF component IS CCIR.Component THEN
			RETURN (current # component) & (component(CCIR.Component).outer = NIL)
		ELSE RETURN TRUE
		END
	END IsExternalComponent;

	PROCEDURE IsExternalInterface(interface: CCIR.Interface): BOOLEAN;
	BEGIN RETURN (interface # NIL) & (interface.outer = NIL)
	END IsExternalInterface;
	
	PROCEDURE CheckUniqueIdentifier(name: CCIR.Identifier; scope: CCIR.Node);
	VAR comScope: CCIR.Component; componentList: CCIR.ComponentList; interfaceList: CCIR.InterfaceList; 
		constantList: CCIR.ConstantList; variableList: CCIR.VariableList; implScope: CCIR.Implementation; 
		procedureList: CCIR.ProcedureList; procedure: CCIR.Procedure; counter, i: LONGINT; 
		component: CCIR.Component; interface: CCIR.Interface; constant: CCIR.Constant; 
		variable: CCIR.Variable; procScope: CCIR.Procedure; parameterList: CCIR.ProcedureParameterList;
		parameter: CCIR.ProcedureParameter;
	BEGIN
		CheckNotReserved(name);
		IF scope = NIL THEN
			componentList := CCIR.compiledComponents;
			interfaceList := CCIR.compiledInterfaces;
			constantList := NIL; 
			variableList := NIL;
			procedureList := NIL;
			parameterList := NIL
		ELSIF scope IS CCIR.Component THEN
			comScope := scope(CCIR.Component);
			componentList := comScope.nestedComponents;
			interfaceList := comScope.nestedInterfaces;
			constantList := comScope.constants;
			variableList := comScope.variables;
			procedureList := comScope.procedures;
			parameterList := NIL
		ELSIF scope IS CCIR.Implementation THEN
			implScope := scope(CCIR.Implementation);
			componentList := implScope.nestedComponents;
			interfaceList := implScope.nestedInterfaces;
			constantList := implScope.constants;
			variableList := implScope.variables;
			procedureList := implScope.nestedProcedures;
			parameterList := NIL
		ELSIF scope IS CCIR.Procedure THEN
			procScope := scope(CCIR.Procedure);
			componentList := procScope.nestedComponents;
			interfaceList := procScope.nestedInterfaces;
			constantList := procScope.constants;
			variableList := procScope.variables;
			procedureList := procScope.nestedProcedures;
			parameterList := procScope.parameters
		ELSE HALT(111)
		END;
		counter := 0;
		IF componentList # NIL THEN
			FOR i := 0 TO componentList.Length()-1 DO
				component := componentList.GetComponent(i);
				IF component.name.Equal(name) THEN INC(counter) END
			END
		END;
		IF interfaceList # NIL THEN
			FOR i := 0 TO interfaceList.Length()-1 DO
				interface := interfaceList.GetInterface(i);
				IF interface.name.Equal(name) THEN INC(counter) END
			END
		END;
		IF constantList # NIL THEN
			FOR i := 0 TO constantList.Length()-1 DO
				constant := constantList.GetConstant(i);
				IF constant.name.Equal(name) THEN INC(counter) END
			END
		END;
		IF variableList # NIL THEN
			FOR i := 0 TO variableList.Length()-1 DO
				variable := variableList.GetVariable(i);
				IF variable.name.Equal(name) THEN INC(counter) END
			END
		END;
		IF procedureList # NIL THEN
			FOR i := 0 TO procedureList.Length()-1 DO
				procedure := procedureList.GetProcedure(i);
				IF procedure.name.Equal(name) THEN INC(counter) END
			END
		END;
		IF parameterList # NIL THEN
			FOR i := 0 TO parameterList.Length()-1 DO
				parameter := parameterList.GetProcedureParameter(i);
				IF parameter.name.Equal(name) THEN INC(counter) END
			END
		END;
		ASSERT(counter > 0);
		IF counter > 1 THEN
			Error(name.pos, "Multiply declared identifier")
		END
	END CheckUniqueIdentifier;
		
	(* current = NIL if imported *)
	PROCEDURE CheckInterfaceDeclList(current: CCIR.Node; isOffered: BOOLEAN; list: CCIR.InterfaceDeclarationList);
	VAR i: LONGINT; decl: CCIR.InterfaceDeclaration; interface: CCIR.Interface;
	BEGIN
		FOR i := 0 TO list.Length()-1 DO
			decl := list.GetInterfaceDeclaration(i);
			CheckUniqueInterfaceDecl(decl, list);
			interface := ResolveInterface(current, decl.name);
			IF interface # NIL THEN
				decl.SetInterface(interface)
			ELSE
				Error(decl.pos, "Undefined interface")
			END;
			IF isOffered & ((decl.minNumber # 1) OR (decl.maxNumber # 1)) THEN
				Error(decl.pos, "Only one interface of the same name can be offered")
			ELSIF decl.minNumber < 0 THEN
				Error(decl.pos, "Number of interfaces cannot be negative")
			ELSIF decl.maxNumber < decl.minNumber THEN
				Error(decl.pos, "Upper bound is less than lower bound in interface number range")
			END
		END
	END CheckInterfaceDeclList;
	
	PROCEDURE CheckUniqueInterfaceDecl(decl: CCIR.InterfaceDeclaration; list: CCIR.InterfaceDeclarationList);
	VAR i: LONGINT; x: CCIR.InterfaceDeclaration;
	BEGIN
		FOR i := 0 TO list.Length()-1 DO
			x := list.GetInterfaceDeclaration(i);
			IF (x # decl) & x.name.Equal(decl.name) THEN 
				Error(decl.pos, "Multiply used interface identifier in the same list") 
			END
		END
	END CheckUniqueInterfaceDecl;
		
	PROCEDURE CheckInterface(interface: CCIR.Interface);
	VAR i: LONGINT;
	BEGIN
		IF interface.outer = NIL THEN CheckNameLength(interface.name) END;
		CheckUniqueIdentifier(interface.name, interface.outer);
		IF interface.protocol # NIL THEN CheckProtocol(interface, interface.protocol) END
	END CheckInterface;
	
	PROCEDURE CheckImplementations(list: CCIR.ImplementationList);
	VAR i: LONGINT;
	BEGIN
		FOR i := 0 TO list.Length()-1 DO
			CheckImplementation(list.GetImplementation(i))
		END
	END CheckImplementations;

	PROCEDURE CheckImplementation(impl: CCIR.Implementation);
	BEGIN
		CheckImplementationName(impl);
		CheckInterfaceList(impl.nestedInterfaces);
		CheckComponentListForDef(impl.nestedComponents);
		CheckProcedureListForDef(impl.nestedProcedures);
		CheckConstants(impl, impl.constants);
		CheckVariables(impl, impl.variables);
		CheckComponentListForImpl(impl.nestedComponents);
		CheckProcedureListForImpl(impl.nestedProcedures);
		CheckStatementSequence(impl.statements)
	END CheckImplementation;
	
	PROCEDURE CheckImplementationName(impl: CCIR.Implementation);
	VAR interfaceDecl: CCIR.InterfaceDeclaration; interface: CCIR.Interface;
	BEGIN
		CheckNotReserved(impl.name);
		CheckUniqueImplName(impl, impl.outer.implementations);
		interfaceDecl := impl.outer.offeredInterfaces.FindInterfaceDeclaration(impl.name);
		IF interfaceDecl = NIL THEN
			interface := ResolveInterface(impl.outer, impl.name);
			IF interface # NIL THEN
				NEW(interfaceDecl, -1, impl.name, 1, 1); 
				interfaceDecl.SetInterface(interface);
			END
		END;
		IF interfaceDecl # NIL THEN
			impl.SetInterfaceDeclaration(interfaceDecl)
		ELSE
			Error(impl.name.pos, "Undefined interface")
		END
	END CheckImplementationName;
	
	PROCEDURE CheckUniqueImplName(impl: CCIR.Implementation; list: CCIR.ImplementationList);
	VAR i: LONGINT; x: CCIR.Implementation;
	BEGIN
		FOR i := 0 TO list.Length()-1 DO
			x := list.GetImplementation(i);
			IF (x # impl) & x.name.Equal(impl.name) THEN
				Error(impl.pos, "Multiply defined implementation for same interface")
			END
		END
	END CheckUniqueImplName;
	
	PROCEDURE CheckProcedureListForDef(list: CCIR.ProcedureList);
	VAR i: LONGINT;
	BEGIN
		FOR i := 0 TO list.Length()-1 DO
			CheckProcedureDecl(list.GetProcedure(i))
		END
	END CheckProcedureListForDef;
	
	PROCEDURE CheckProcedureListForImpl(list: CCIR.ProcedureList);
	VAR i: LONGINT;
	BEGIN
		FOR i := 0 TO list.Length()-1 DO
			CheckProcedureImpl(list.GetProcedure(i))
		END
	END CheckProcedureListForImpl;
	
	PROCEDURE CheckProcedureDecl(proc: CCIR.Procedure);
	BEGIN
		CheckUniqueIdentifier(proc.name, proc.outer);
		CheckProcedureParameters(proc);
		IF proc.type # NIL THEN 
			CheckType(proc, proc.type);
			IF CCIR.IsComponentType(proc.type) THEN
				Error(proc.type.pos, "Result value of a procedure must be of a data type")
			END
		END;
		CheckInterfaceList(proc.nestedInterfaces);
		CheckComponentListForDef(proc.nestedComponents);
		CheckProcedureListForDef(proc.nestedProcedures);
		CheckConstants(proc, proc.constants)
	END CheckProcedureDecl;
	
	PROCEDURE CheckProcedureImpl(proc: CCIR.Procedure);
	BEGIN
		CheckVariables(proc, proc.variables);
		CheckComponentListForImpl(proc.nestedComponents);
		CheckProcedureListForImpl(proc.nestedProcedures);
		CheckStatementSequence(proc.statements)
	END CheckProcedureImpl;
	
	PROCEDURE CheckProcedureParameters(proc: CCIR.Procedure);
	VAR parameters: CCIR.ProcedureParameterList; i: LONGINT; par: CCIR.ProcedureParameter;
	BEGIN
		parameters := proc.parameters;
		FOR i := 0 TO parameters.Length()-1 DO
			par := parameters.GetProcedureParameter(i);
			CheckUniqueIdentifier(par.name, proc);
			CheckType(proc, par.type);
			IF CCIR.IsComponentType(par.type) THEN 
				Error(par.pos, "Procedure parameter must be of a data type")
			END
		END
	END CheckProcedureParameters;
																											
	PROCEDURE CheckNotReserved(name: CCIR.Identifier);
	BEGIN IF CCIR.IsReservedName(name) THEN Error(name.pos, "Reserved identifier") END
	END CheckNotReserved;
	
	PROCEDURE CheckProtocol(interface: CCIR.Interface; current: CCIR.Protocol);
	VAR seq: CCIR.ProtocolSequence; alt: CCIR.ProtocolAlternative; rep: CCIR.ProtocolRepetition; opt: CCIR.ProtocolOption;
	BEGIN
		IF current IS CCIR.MessageDeclaration THEN
			CheckMessageDeclaration(interface, current(CCIR.MessageDeclaration))
		ELSIF current IS CCIR.ProtocolSequence THEN
			seq := current(CCIR.ProtocolSequence);
			CheckProtocol(interface, seq.first); CheckProtocol(interface, seq.second)
		ELSIF current IS CCIR.ProtocolAlternative THEN
			alt := current(CCIR.ProtocolAlternative);
			CheckProtocol(interface, alt.first); CheckProtocol(interface, alt.second)
		ELSIF current IS CCIR.ProtocolRepetition THEN
			rep := current(CCIR.ProtocolRepetition);
			CheckProtocol(interface, rep.protocol)
		ELSIF current IS CCIR.ProtocolOption THEN
			opt := current(CCIR.ProtocolOption);
			CheckProtocol(interface, opt.protocol)
		ELSE HALT(111)
		END
	END CheckProtocol;
	
	PROCEDURE CheckMessageDeclaration(interface: CCIR.Interface; m: CCIR.MessageDeclaration);
	BEGIN
		CheckUniqueMessageName(interface.protocol, m);
		CheckParameterList(interface, m.parameters);
		interface.messageDeclarations.Add(m)
	END CheckMessageDeclaration;
	
	PROCEDURE CheckUniqueMessageName(current: CCIR.Protocol; message: CCIR.MessageDeclaration);
	VAR seq: CCIR.ProtocolSequence; alt: CCIR.ProtocolAlternative; rep: CCIR.ProtocolRepetition; opt: CCIR.ProtocolOption;
	BEGIN
		IF CCIR.IsReservedName(message.name) THEN Error(message.name.pos, "Identifier is reserved") END;
		IF current IS CCIR.MessageDeclaration THEN
			IF (current # message) & current(CCIR.MessageDeclaration).name.Equal(message.name) THEN
				Error(message.name.pos, "Multiply defined message")
			END
		ELSIF current IS CCIR.ProtocolSequence THEN
			seq := current(CCIR.ProtocolSequence);
			CheckUniqueMessageName(seq.first, message); CheckUniqueMessageName(seq.second, message)
		ELSIF current IS CCIR.ProtocolAlternative THEN
			alt := current(CCIR.ProtocolAlternative);
			CheckUniqueMessageName(alt.first, message); CheckUniqueMessageName(alt.second, message)
		ELSIF current IS CCIR.ProtocolRepetition THEN
			rep := current(CCIR.ProtocolRepetition);
			CheckUniqueMessageName(rep.protocol, message)
		ELSIF current IS CCIR.ProtocolOption THEN
			opt := current(CCIR.ProtocolOption);
			CheckUniqueMessageName(opt.protocol, message)
		END
	END CheckUniqueMessageName;
	
	PROCEDURE CheckParameterList(current: CCIR.Node; list: CCIR.ParameterList);
	VAR i: LONGINT; par: CCIR.Parameter;
	BEGIN
		FOR i := 0 TO list.Length()-1 DO
			par := list.GetParameter(i);
			CheckUniqueParameterName(list, par);
			CheckType(current, par.type)
		END
	END CheckParameterList;
	
	PROCEDURE CheckUniqueParameterName(list: CCIR.ParameterList; parameter: CCIR.Parameter);
	VAR i: LONGINT; p: CCIR.Parameter;
	BEGIN
		CheckNotReserved(parameter.name);
		FOR i := 0 TO list.Length()-1 DO
			p := list.GetParameter(i);
			IF (p # parameter) & p.name.Equal(parameter.name) THEN Error(parameter.pos, "Multiply defined parameter") END
		END
	END CheckUniqueParameterName;
	
	PROCEDURE CheckType(current: CCIR.Node; type: CCIR.Type);
	VAR compType: CCIR.ComponentType; anyType: CCIR.AnyType; com: CCIR.ComponentDefinition; 
	BEGIN
		IF type = NIL THEN (* skip *)
		ELSIF type IS CCIR.DataType THEN
			ASSERT((type = CCIR.integerType) OR (type = CCIR.realType) OR 
				(type = CCIR.booleanType) OR (type = CCIR.textType) OR (type = CCIR.characterType))
		ELSIF type IS CCIR.ComponentType THEN
			compType := type(CCIR.ComponentType);
			com := ResolveComponent(current, compType.componentName);
			IF com # NIL THEN
				compType.SetComponentDefinition(com)
			ELSE
				Error(type.pos, "Undefined component")
			END
		ELSIF type IS CCIR.AnyType THEN
			anyType := type(CCIR.AnyType);
			CheckInterfaceDeclList(current, TRUE, anyType.offeredInterfaces);
			CheckInterfaceDeclList(current, FALSE, anyType.requiredInterfaces)
		ELSE HALT(111)
		END
	END CheckType;
	
	PROCEDURE CheckVariables(current: CCIR.Node; variableList: CCIR.VariableList);
	VAR i: LONGINT; v: CCIR.Variable; 
	BEGIN
		FOR i := 0 TO variableList.Length()-1 DO
			v := variableList.GetVariable(i);
			CheckUniqueIdentifier(v.name, current);
			CheckType(current, v.type);
			CheckAttributeList(v);
			IF (v.parameters.Length() > 0) & (CCIR.IsComponentType(v.type) OR (v.type = CCIR.textType)) THEN
				v.SetTempRider(GetTempVariable(current))
			END
		END
	END CheckVariables;
		
	PROCEDURE CheckConstants(current: CCIR.Node; constantList: CCIR.ConstantList);
	VAR i: LONGINT; c: CCIR.Constant;
	BEGIN
		FOR i := 0 TO constantList.Length()-1 DO
			c := constantList.GetConstant(i);
			CheckUniqueIdentifier(c.name, current);
			c.SetExpression(CheckExpression(current, c.expression));
			IF (c.expression.type = NIL) OR ~(c.expression.type IS CCIR.DataType) THEN 
				Error(c.expression.pos, "Invalid constant expression")
			END;
			CheckConstantExpression(c, c.expression)
		END
	END CheckConstants;
		
	PROCEDURE CheckConstantExpression(current: CCIR.Constant; expr: CCIR.Expression);
	VAR error: BOOLEAN; des: CCIR.Designator; prevConst: CCIR.Constant; constantList: CCIR.ConstantList; 
		pos: LONGINT; ue: CCIR.UnaryExpression; be: CCIR.BinaryExpression; funCall: CCIR.FunctionCall;
		arg0: CCIR.Expression; decl: CCIR.Procedure;
	BEGIN
		IF expr IS CCIR.Designator THEN
			des := expr(CCIR.Designator);
			IF (des.node # NIL) & (des.node IS CCIR.Constant) THEN
				prevConst := des.node(CCIR.Constant);
				IF current.scope = prevConst.scope THEN
					IF current.scope IS CCIR.Component THEN 
						constantList := current.scope(CCIR.Component).constants
					ELSIF current.scope IS CCIR.Implementation THEN 
						constantList := current.scope(CCIR.Implementation).constants
					ELSIF current.scope IS CCIR.Procedure THEN
						constantList := current.scope(CCIR.Procedure).constants
					ELSE HALT(111)
					END;
					IF constantList.IndexOf(prevConst) >= constantList.IndexOf(current) THEN
						Error(expr.pos, "Can only refer to preceding constants")
					END
				END
			ELSE error := TRUE
			END
		ELSIF (expr IS CCIR.TextValue) OR (expr IS CCIR.CharacterValue) OR 
				(expr IS CCIR.IntegerValue) OR (expr IS CCIR.BooleanValue) OR 
				(expr IS CCIR.RealValue) THEN
			(* ok *)
		ELSIF expr IS CCIR.UnaryExpression THEN
			ue := expr(CCIR.UnaryExpression);
			CheckConstantExpression(current, ue.sub)
		ELSIF expr IS CCIR.BinaryExpression THEN
			be := expr(CCIR.BinaryExpression);
			CheckConstantExpression(current, be.left);
			CheckConstantExpression(current, be.right)
		ELSIF expr IS CCIR.FunctionCall THEN
			funCall := expr(CCIR.FunctionCall); decl := funCall.declaration;
			IF funCall.arguments.Length() > 0 THEN 
				arg0 := funCall.arguments.GetExpression(0)
			ELSE
				arg0 := NIL
			END;
			IF (decl = CCIR.integerToReal) OR (decl = CCIR.realToInteger) OR (decl = CCIR.integerToCharacter) OR 
				(decl = CCIR.characterToInteger) OR (decl = CCIR.characterToText) THEN
				IF arg0 # NIL THEN CheckConstantExpression(current, arg0) ELSE error := TRUE END
			ELSIF (decl = CCIR.minInteger) OR (decl = CCIR.maxInteger) OR (decl = CCIR.minReal) OR (decl = CCIR.maxReal) THEN 
				(* ok *)
			ELSE error := TRUE
			END
		END;
		IF error THEN Error(expr.pos, "Not a constant expression") END
	END CheckConstantExpression;
	
	PROCEDURE CheckAttributeList(node: CCIR.Node);
	VAR list: CCIR.IdentifierList; i: LONGINT; a: CCIR.Identifier; exclusive, shared: BOOLEAN; proc: CCIR.Procedure;
		outer: CCIR.Node; var: CCIR.Variable; k: LONGINT; par: CCIR.Parameter;
	BEGIN
		list := node.attributeList;
		exclusive := FALSE; shared := FALSE;
		IF list # NIL THEN
			FOR i := 0 TO list.Length()-1 DO
				a := list.GetIdentifier(i);
				IF (node IS CCIR.Statement) OR (node IS CCIR.Expression) THEN
					IF a.Equal(CCIR.exclusive) THEN
						IF exclusive THEN Error(a.pos, "Multiple use of EXCLUSIVE")
						ELSIF shared THEN Error(a.pos, "EXCLUSIVE can not be used together with SHARED")
						END;
						exclusive := TRUE
					ELSIF a.Equal(CCIR.shared) THEN
						IF exclusive THEN Error(a.pos, "SHARED can not be used together with EXCLUSIVE")
						ELSIF shared THEN Error(a.pos, "Multiple use of SHARED")
						END;
						shared := TRUE
					ELSE Error(a.pos, "Undefined attribute")
					END;
					IF a.Equal(CCIR.exclusive) OR a.Equal(CCIR.shared) THEN
						IF node IS CCIR.Statement THEN outer := node(CCIR.Statement).outer 
						ELSE outer := node(CCIR.Expression).outer 
						END;
						IF CCIR.CurrentLockType(outer) # NIL THEN
							Error(a.pos, "Nested locks not allowed")
						END
					END
				ELSIF node IS CCIR.Variable THEN
					var := node(CCIR.Variable);
					IF a.Equal(CCIR.timesynchron) THEN
						IF ~CCIR.IsComponentType(var.type) THEN
							Error(a.pos, "Can only be used for component types")
						END
					ELSIF a.Equal(CCIR.array) THEN
						IF var.parameters.Length() > 0 THEN
							FOR k := 0 TO var.parameters.Length()-1 DO
								par := var.parameters.GetParameter(k);
								IF par.type # CCIR.integerType THEN 
									Error(par.pos, "Only INTEGER parameters allowed for array") 
								END
							END
						ELSE Error(a.pos, "Can only be used for collection variables")
						END
					ELSE
						Error(a.pos, "Undefined attribute")
					END
				ELSE Error(a.pos, "Undefined attribute")
				END
			END
		END;
		IF exclusive OR shared THEN
			proc := CCIR.GetSurroundingProcedure(node);
			IF proc # NIL THEN proc.hasProtectedRegion := TRUE END
		END
	END CheckAttributeList;
		
	PROCEDURE CheckStatementSequence(seq: CCIR.StatementSequence);
	VAR i: LONGINT;
	BEGIN
		CheckAttributeList(seq);
		FOR i := 0 TO seq.statements.Length()-1 DO
			CheckStatement(seq.statements.GetStatement(i))
		END
	END CheckStatementSequence;
		
	PROCEDURE CheckStatement(s: CCIR.Statement);
	BEGIN
		IF s IS CCIR.SendStatement THEN CheckSendStatement(s(CCIR.SendStatement))
		ELSIF s IS CCIR.ReceiveStatement THEN CheckReceiveStatement(s(CCIR.ReceiveStatement))
		ELSIF s IS CCIR.Assignment THEN CheckAssignment(s(CCIR.Assignment))
		ELSIF s IS CCIR.ProcedureCall THEN CheckProcedureCall(s(CCIR.ProcedureCall))
		ELSIF s IS CCIR.IfStatement THEN CheckIfStatement(s(CCIR.IfStatement))
		ELSIF s IS CCIR.WhileStatement THEN CheckWhileStatement(s(CCIR.WhileStatement))
		ELSIF s IS CCIR.RepeatStatement THEN CheckRepeatStatement(s(CCIR.RepeatStatement))
		ELSIF s IS CCIR.ForStatement THEN CheckForStatement(s(CCIR.ForStatement))
		ELSIF s IS CCIR.ForeachStatement THEN CheckForeachStatement(s(CCIR.ForeachStatement))
		ELSIF s IS CCIR.StatementSequence THEN CheckStatementSequence(s(CCIR.StatementSequence))
		ELSIF s IS CCIR.AwaitStatement THEN CheckAwaitStatement(s(CCIR.AwaitStatement))
		ELSIF s IS CCIR.NewStatement THEN CheckNewStatement(s(CCIR.NewStatement))
		ELSIF s IS CCIR.ConnectStatement THEN CheckConnectStatement(s(CCIR.ConnectStatement))
		ELSIF s IS CCIR.DisconnectStatement THEN CheckDisconnectStatement(s(CCIR.DisconnectStatement))
		ELSIF s IS CCIR.ReturnStatement THEN CheckReturnStatement(s(CCIR.ReturnStatement))
		ELSE HALT(111) (* not implemented *)
		END
	END CheckStatement;
		
	PROCEDURE CheckReturnStatement(return: CCIR.ReturnStatement);
	VAR proc: CCIR.Procedure;
	BEGIN
		IF return.expression # NIL THEN
			return.SetExpression(CheckExpression(return, return.expression))
		END;
		proc := CCIR.GetSurroundingProcedure(return);
		IF proc = NIL THEN
			Error(return.pos, "RETURN not within a procedure")
		ELSIF proc.type # NIL THEN
			IF return.expression = NIL THEN
				Error(return.pos, "Missing result expression")
			ELSE
				CheckAssignmentCompatibility(return, return.pos, return.expression.type, proc.type)
			END
		ELSE
			IF return.expression # NIL THEN
				Error(return.pos, "Procedure has no result value")
			END
		END 
	END CheckReturnStatement;
		
	PROCEDURE CheckAssignment(a: CCIR.Assignment);
	VAR targetType: CCIR.Type;
	BEGIN
		a.SetLeftDesignator(CheckStorageDesignator(a, a.leftDesignator));
		targetType := a.leftDesignator.type;
		IF targetType # NIL THEN
			a.SetRightExpression(CheckExpression(a, a.rightExpression));
			a.SetRightExpression(ImplicitConversion(a.rightExpression, targetType));
			CheckAssignmentCompatibility(a, a.pos, a.rightExpression.type, targetType)
		END;
		IF CCIR.IsComponentType(targetType) THEN
			Error(a.pos, "Assignment of a component")
		END;
		CheckProtection(a.leftDesignator, CCIR.exclusive);
		CheckProtection(a.rightExpression, CCIR.shared)
	END CheckAssignment;
			
	PROCEDURE ImplicitConversion(expression: CCIR.Expression; target: CCIR.Type): CCIR.Expression;
	VAR tv: CCIR.TextValue; a: ARRAY 2 OF CHAR; funCall: CCIR.FunctionCall;
	BEGIN
		IF (expression.type = CCIR.characterType) & (target = CCIR.textType) THEN
			IF expression IS CCIR.CharacterValue THEN
				a[0] := expression(CCIR.CharacterValue).char; a[1] := 0X;
				NEW(tv, expression.pos, a); tv.SetType(CCIR.textType); RETURN tv
			ELSE Error(expression.pos, "Incompatible assignment, no implicit conversion")
			END
		ELSIF (expression.type = CCIR.integerType) & (target = CCIR.realType) THEN
			NEW(funCall, expression.pos, CCIR.integerToReal.name);
			expression.SetOuter(NIL);
			funCall.arguments.Add(expression);
			funCall.SetDeclaration(CCIR.integerToReal);
			funCall.SetType(CCIR.realType);
			expression := OptimizeConstantExpression(funCall)
		END;
		RETURN expression
	END ImplicitConversion;
	
	PROCEDURE CheckAssignmentCompatibility(current: CCIR.Node; pos: LONGINT; source: CCIR.Type; target: CCIR.Type);
	VAR sourceOffered, sourceRequired, targetOffered, targetRequired: CCIR.InterfaceDeclarationList; 
		i: LONGINT; x, y: CCIR.InterfaceDeclaration; component: CCIR.ComponentDefinition;
	BEGIN
		IF (source # NIL) & (target # NIL) THEN
			IF target IS CCIR.DataType THEN
				IF target # source THEN Error(pos, "Incompatible assignment") END
			ELSIF target IS CCIR.ComponentType THEN
				IF ~(source IS CCIR.ComponentType) OR 
						~target(CCIR.ComponentType).componentName.Equal(source(CCIR.ComponentType).componentName) THEN
					Error(pos, "Incompatible assignmemt")	
				END
			ELSIF target IS CCIR.AnyType THEN
				targetOffered := target(CCIR.AnyType).offeredInterfaces;
				targetRequired := target(CCIR.AnyType).requiredInterfaces;
				IF (targetOffered.Length() = 0) & (targetRequired.Length() = 0) THEN (* generic type *)
					IF ~(source IS CCIR.ComponentType) & ~(source IS CCIR.AnyType) THEN
						Error(pos, "Incompatible assignment")
					END
				ELSE (* abstract component type *)
					IF (source IS CCIR.ComponentType) OR (source IS CCIR.AnyType) THEN
						IF source IS CCIR.ComponentType THEN
							IF source(CCIR.ComponentType).componentDefinition = NIL THEN CheckType(current, source) END;
							component := source(CCIR.ComponentType).componentDefinition;
							IF component # NIL THEN
								sourceOffered := component.offeredInterfaces;
								sourceRequired := component.requiredInterfaces
							ELSE
								NEW(sourceOffered); NEW(sourceRequired)
							END
						ELSE
							sourceOffered := source(CCIR.AnyType).offeredInterfaces;
							sourceRequired := source(CCIR.AnyType).requiredInterfaces
						END;
						FOR i := 0 TO targetOffered.Length()-1 DO 
							x := targetOffered.GetInterfaceDeclaration(i);
							y := sourceOffered.FindInterfaceDeclaration(x.name);
							IF y = NIL THEN
								Error3(pos, "Incompatible assignment: Offered interface ", x.name.name^, " can not be postulated")
							ELSIF ~y.Equal(x) THEN
								Error2(pos, "Incompatible assignment: Different number of the offered interface ", x.name.name^)
							END
						END;
						FOR i := 0 TO sourceRequired.Length()-1 DO
							x := sourceRequired.GetInterfaceDeclaration(i);
							y := targetRequired.FindInterfaceDeclaration(x.name);
							IF y = NIL THEN
								Error3(pos, "Incompatible assignment: Required interface ", x.name.name^, " must be postulated")
							ELSIF ~y.Equal(x) THEN
								Error2(pos, "Incompatible assignment: Different number of the required interface ", x.name.name^)
							END
						END
					ELSE Error(source.pos, "Incompatible assignment")
					END
				END
			ELSE HALT(111)
			END
		ELSE Error(pos, "Invalid assignment")
		END
	END CheckAssignmentCompatibility;
	
	PROCEDURE CheckProcedureCall(call: CCIR.ProcedureCall);
	VAR proc: CCIR.Procedure; expr, source, target: CCIR.Expression; iv: CCIR.IntegerValue; var: CCIR.Variable;
	BEGIN
		proc := ResolveProcedure(call, call.identifier, call.arguments.Length());
		IF proc # CCIR.delete THEN CheckExpressionList(call, call.arguments) END;
		IF proc = NIL THEN
			Error(call.pos, "Undeclared procedure")
		ELSIF proc.name.Equal(CCIR.writeText.name) THEN (* WRITE *)
			IF call.arguments.Length() = 1 THEN
				expr := call.arguments.GetExpression(0);
				IF expr.type = CCIR.textType THEN proc := CCIR.writeText
				ELSIF expr.type = CCIR.characterType THEN proc := CCIR.writeChar
				ELSIF expr.type = CCIR.integerType THEN proc := CCIR.writeInt
				ELSIF expr.type = CCIR.realType THEN proc := CCIR.writeReal
				ELSE Error(expr.pos, "Invalid argument for WRITE procedure")
				END
			ELSE Error(call.pos, "Invalid number of arguments")
			END
		ELSIF proc = CCIR.delete THEN
			IF call.arguments.Length() = 1 THEN
				expr := call.arguments.GetExpression(0);
				IF (expr IS CCIR.Designator) & IsCollectionDesignator(call, expr(CCIR.Designator)) THEN
					var := CheckCollectionDesignator(call, expr(CCIR.Designator));
					IF ~CCIR.IsArrayCollection(var) THEN Error(expr.pos, "Not a collection variable designator") END
				ELSE
					CheckExpressionList(call, call.arguments); expr := call.arguments.GetExpression(0);
					CheckComponentDesignator(expr)
				END;
				CheckProtection(expr, CCIR.exclusive)
			ELSE Error(call.pos, "Invalid number of arguments")
			END
		ELSIF proc = CCIR.move THEN
			IF call.arguments.Length() = 2 THEN
				source := call.arguments.GetExpression(0);
				target := call.arguments.GetExpression(1);
				CheckComponentDesignator(source);
				CheckComponentDesignator(target);
				CheckAssignmentCompatibility(call, source.pos, source.type, target.type);
				CheckProtection(source, CCIR.exclusive);
				CheckProtection(target, CCIR.exclusive)
			ELSE Error(call.pos, "Invalid number of arguments")
			END
		ELSE
			CheckProcParamCompatibility(call, proc, call.arguments, proc.parameters);
			CheckProtectionForList(call.arguments, CCIR.shared);
			IF proc.type # NIL THEN
				Error(call.pos, "Invalid use of a function procedure")
			END
		END;
		IF proc # NIL THEN
			call.SetDeclaration(proc);
			IF ~CCIR.predefinedProcedures.Contains(proc) THEN
				proc.callers.Add(call)
			END;
			IF proc = CCIR.passivate THEN 
				MustNotBeInAwait(call)
			END
		END
	END CheckProcedureCall;
	
	PROCEDURE CheckComponentDesignator(expr: CCIR.Expression);
	VAR var: CCIR.Variable;
	BEGIN
		IF (expr IS CCIR.Designator) & (expr(CCIR.Designator).node # NIL) & (expr(CCIR.Designator).node IS CCIR.Variable) THEN
			var := expr(CCIR.Designator).node(CCIR.Variable);
			IF (expr IS CCIR.IndexDesignator) OR CCIR.IsComponentType(var.type) THEN (* ok *)
			ELSE Error(expr.pos, "Not applicable for the argument")
			END
		ELSE Error(expr.pos, "Undefined storage location designator")
		END
	END CheckComponentDesignator;
		
	PROCEDURE CheckFunctionCall(current: CCIR.Node; call: CCIR.FunctionCall);
	VAR proc: CCIR.Procedure; expr: CCIR.Expression; id: CCIR.Identifier; 
		component: CCIR.Component; interfaceDecl: CCIR.InterfaceDeclaration; 
		externalInterface: CCIR.ExternalInterfaceDesignator; var: CCIR.Variable;
	BEGIN
		ASSERT(call.outer # NIL);
		proc := NIL;
		IF call.identifier.Equal(CCIR.minInteger.name) OR call.identifier.Equal(CCIR.maxInteger.name) OR
				call.identifier.Equal(CCIR.minReal.name) OR call.identifier.Equal(CCIR.maxReal.name) THEN
			IF call.arguments.Length() = 1 THEN
				expr := call.arguments.GetExpression(0);
				IF expr IS CCIR.IdentifierDesignator THEN
					id := expr(CCIR.IdentifierDesignator).identifier;
					IF CCIR.integerType.name.Equal(id) THEN
						IF call.identifier.Equal(CCIR.minInteger.name) THEN proc := CCIR.minInteger 
						ELSIF call.identifier.Equal(CCIR.maxInteger.name) THEN proc := CCIR.maxInteger 
						END
					ELSIF CCIR.realType.name.Equal(id) THEN
						IF call.identifier.Equal(CCIR.minReal.name) THEN proc := CCIR.minReal
						ELSIF call.identifier.Equal(CCIR.maxReal.name) THEN proc := CCIR.maxReal
						END
					ELSE
						CheckExpressionList(current, call.arguments)
					END
				ELSE
					CheckExpressionList(current, call.arguments)
				END;
				IF proc = NIL THEN
					Error(expr.pos, "Invalid argument, INTEGER or REAL required")
				END
			ELSE Error(call.pos, "Invalid number of arguments")
			END
		ELSIF call.identifier.Equal(CCIR.count.name) THEN
			IF call.arguments.Length() = 1 THEN
				expr := call.arguments.GetExpression(0);
				IF expr IS CCIR.IdentifierDesignator THEN
					id := expr(CCIR.IdentifierDesignator).identifier;
					component := CCIR.GetSurroundingComponent(current);
					interfaceDecl := component.requiredInterfaces.FindInterfaceDeclaration(id);
					IF interfaceDecl # NIL THEN
						IF (interfaceDecl.minNumber # 1) OR (interfaceDecl.maxNumber # 1) THEN
							NEW(externalInterface, expr.pos, component, interfaceDecl, FALSE);
							call.arguments.ReplaceExpression(0, externalInterface); 
							proc := CCIR.count
						ELSE Error(call.pos, "Not applicable if exactly one interface of that name is required")
						END
					ELSE Error(expr.pos, "Undefined set of required interfaces, must have no index") 
					END
				ELSE Error(expr.pos, "Invalid argument, designator of required interfaces expected")
				END
			ELSE Error(call.pos, "Invalid number of arguments")
			END
		ELSIF call.identifier.Equal(CCIR.length.name) THEN
			IF call.arguments.Length() > 0 THEN
				expr := call.arguments.GetExpression(0);
				IF (expr IS CCIR.Designator) & IsCollectionDesignator(current, expr(CCIR.Designator)) THEN
					var := CheckCollectionDesignator(current, expr(CCIR.Designator));
					call.arguments.ReplaceExpression(0, expr);
					IF CCIR.IsArrayCollection(var) THEN
						IF var.parameters.Length() = 1 THEN
							IF call.arguments.Length() > 1 THEN Error(call.pos, "Too many arguments") END;
							proc := CCIR.length
						ELSE
							IF call.arguments.Length() = 2 THEN 
								expr := call.arguments.GetExpression(1);
								expr := CheckExpression(current, expr);
								call.arguments.ReplaceExpression(1, expr);
								CheckDataType(expr, CCIR.integerType);
								proc := CCIR.length
							ELSIF call.arguments.Length() < 2 THEN Error(call.pos, "Too few arguments")
							ELSE Error(call.pos, "Too many arguments")
							END
						END
					ELSE Error(expr.pos, "Not a collection variable designator")
					END
				ELSE
					IF call.arguments.Length() > 1 THEN Error(call.pos, "Too many arguments") END;
					expr := CheckExpression(current, expr);
					call.arguments.ReplaceExpression(0, expr);
					CheckDataType(expr, CCIR.textType);
					proc := CCIR.length
				END
			ELSE
				Error(call.pos, "Too few arguments")
			END
		ELSE
			CheckExpressionList(current, call.arguments);
			IF (call.identifier.Equal(CCIR.characterToInteger.name) OR call.identifier.Equal(CCIR.realToInteger.name)) & 
					(call.arguments.Length() = 1) THEN
				expr := call.arguments.GetExpression(0);
				IF expr.type = CCIR.characterType THEN proc := CCIR.characterToInteger
				ELSIF expr.type = CCIR.realType THEN proc := CCIR.realToInteger
				ELSE proc := NIL
				END
			ELSE
				proc := ResolveProcedure(current, call.identifier, call.arguments.Length())
			END;
			IF proc = NIL THEN
				Error(call.pos, "Undeclared function procedure")
			ELSIF proc = CCIR.exists THEN
				IF call.arguments.Length() = 1 THEN
					expr := call.arguments.GetExpression(0);
					CheckComponentDesignator(expr)
				ELSE Error(call.pos, "Invalid number of arguments")
				END
			ELSE
				CheckProcParamCompatibility(current, proc, call.arguments, proc.parameters)
			END
		END;
		IF proc # NIL THEN
			IF proc.type = NIL THEN
				Error(call.pos, "Procedure has no return value")
			ELSE
				call.SetType(proc.type);
				call.SetDeclaration(proc);
				IF ~CCIR.predefinedProcedures.Contains(proc) THEN
					IF ~proc.callers.Contains(current) THEN
						proc.callers.Add(current)
					END
				END
			END
		END
	END CheckFunctionCall;
	
	PROCEDURE CheckReceiveTestFunction(current: CCIR.Node; function: CCIR.ReceiveTestFunction);
	VAR interfaceDes: CCIR.InterfaceDesignator; md: CCIR.MessageDeclaration;
	BEGIN
		RegisterExternalEventForAwait(current);
		interfaceDes := CheckCommunicationDesignator(function.pos, current, function, function.interfaceDesignator);
		IF interfaceDes # NIL THEN
			function.SetInterfaceDesignator(interfaceDes);
			IF ~function.messageIdentifier.EqualText(CCIR.AnyMessage) & 
					~function.messageIdentifier.EqualText(CCIR.FinishMessage) THEN
				IF interfaceDes.declaration.interface # NIL THEN
					md := interfaceDes.declaration.interface.messageDeclarations.FindMessageDeclaration(function.messageIdentifier);
					IF md # NIL THEN
						CheckCommunicationDirection(function.pos, interfaceDes, md, FALSE)
					ELSE Error(function.messageIdentifier.pos, "Undefined message")
					END
				ELSE Error(interfaceDes.pos, "Undefined interface")
				END
			END
		END;
		function.SetType(CCIR.booleanType)
	END CheckReceiveTestFunction;
	
	PROCEDURE CheckInputFunction(current: CCIR.Node; input: CCIR.InputFunction);
	VAR interfaceDes: CCIR.InterfaceDesignator; md: CCIR.MessageDeclaration; 
	BEGIN
		RegisterExternalEventForAwait(current);
		interfaceDes := CheckCommunicationDesignator(input.pos, current, input, input.interfaceDesignator);
		IF interfaceDes # NIL THEN
			input.SetInterfaceDesignator(interfaceDes);
			IF ~input.messageIdentifier.EqualText(CCIR.AnyMessage) & 
					~input.messageIdentifier.EqualText(CCIR.FinishMessage) THEN
				md := interfaceDes.declaration.interface.messageDeclarations.FindMessageDeclaration(input.messageIdentifier);
				IF md # NIL THEN 
					CheckCommunicationDirection(input.pos, interfaceDes, md, FALSE)
				ELSE Error(input.messageIdentifier.pos, "Undefined message");
				END
			END
		END;
		input.SetType(CCIR.booleanType)
	END CheckInputFunction;
	
	(* NIL if undefined *)
	PROCEDURE CheckCommunicationDesignator(pos: LONGINT; currentStatement: CCIR.Node; currentNode: CCIR.Node;
		designator: CCIR.Designator): CCIR.InterfaceDesignator;
	VAR impl: CCIR.Implementation; comp: CCIR.Component; externalInterface: CCIR.ExternalInterfaceDesignator;
		internalInterface: CCIR.InternalInterfaceDesignator; interfaceDes: CCIR.InterfaceDesignator; var: CCIR.Variable; 
		usedComm: CCIR.InterfaceDeclarationList;
	BEGIN
		interfaceDes := NIL;
		comp := CCIR.GetSurroundingComponent(currentStatement);
		IF designator.IsEmpty() THEN
			(* communication with offered external interface *)
			impl := CCIR.GetSurroundingImplementation(currentStatement);
			IF (impl # NIL) & (impl.interfaceDecl # NIL) THEN
				NEW(externalInterface, designator.pos, comp, impl.interfaceDecl, TRUE); 
				interfaceDes := externalInterface
			ELSE Error(pos, "Undefined offered external interface")
			END
		ELSIF IsExternalInterfaceDesignator(currentStatement, designator) THEN
			interfaceDes := CheckInterfaceDesignator(currentStatement, designator, FALSE, NIL);
			IF interfaceDes # NIL THEN
				CollectUsedExternalInterface(comp, interfaceDes.declaration.interface);
				IF interfaceDes IS CCIR.ExternalInterfaceDesignator THEN
					externalInterface := interfaceDes(CCIR.ExternalInterfaceDesignator);
					usedComm := externalInterface.component.usedCommunications;
					IF ~usedComm.Contains(externalInterface.declaration) THEN 
						usedComm.Add(externalInterface.declaration) 
					END;
					externalInterface.SetOuter(currentNode);
					CheckProtection(externalInterface, CCIR.exclusive)
				ELSE
					interfaceDes := NIL;
					Error(designator.pos, "Invalid interface designator for communication")
				END
			END
		ELSE
			interfaceDes := CheckInterfaceDesignator(currentStatement, designator, TRUE, NIL);
			IF interfaceDes # NIL THEN
				CollectUsedExternalInterface(comp, interfaceDes.declaration.interface);
				IF interfaceDes IS CCIR.InternalInterfaceDesignator THEN
					internalInterface := interfaceDes(CCIR.InternalInterfaceDesignator);
					var := internalInterface.variableDes.node(CCIR.Variable);
					usedComm := var.usedCommunications;
					IF ~usedComm.Contains(internalInterface.declaration) THEN
						usedComm.Add(internalInterface.declaration)
					END;
					internalInterface.SetOuter(currentNode);
					CheckProtection(internalInterface, CCIR.shared)
				ELSE
					interfaceDes := NIL;
					Error(designator.pos, "Invalid interface designator for communication")
				END
			END
		END;
		RETURN interfaceDes
	END CheckCommunicationDesignator;
	
	PROCEDURE CheckConnectDesignator(current: CCIR.Node; designator: CCIR.Designator;  
		isSource: BOOLEAN; hint: CCIR.Interface): CCIR.InterfaceDesignator;
	VAR isOffered: BOOLEAN; 
	BEGIN
		IF IsExternalInterfaceDesignator(current, designator) THEN
			(* external interface *)
			isOffered := isSource
		ELSE
			(* internal interface *)
			isOffered := ~isSource
		END;
		RETURN CheckInterfaceDesignator(current, designator, isOffered, hint)
	END CheckConnectDesignator;
	
	(* NIL if undefined, hint if certain interface is implicitly determined, hint may be NIL *)
	PROCEDURE CheckInterfaceDesignator(current: CCIR.Node; inputDes: CCIR.Designator; 
		isOffered: BOOLEAN; hint: CCIR.Interface): CCIR.InterfaceDesignator;
	VAR varDes: CCIR.Designator; indexExpr: CCIR.Expression; interfaceName: CCIR.Identifier;
		list: CCIR.InterfaceDeclarationList; interfaceDes: CCIR.InterfaceDesignator; component: CCIR.Component;
		internalInterface: CCIR.InternalInterfaceDesignator; externalInterface: CCIR.ExternalInterfaceDesignator;
		interfaceDecl: CCIR.InterfaceDeclaration; implementation: CCIR.Implementation; 
		implementationDes: CCIR.ImplementationDesignator;
	BEGIN
		IF IsInterfaceDesignator(current, inputDes) THEN
			ExplicitInterfaceSelection(current, inputDes, isOffered, varDes, indexExpr, interfaceName)
		ELSE
			ImplicitInterfaceSelection(current, inputDes, isOffered, hint, varDes, indexExpr, interfaceName)
		END;
		interfaceDes := NIL;
		IF interfaceName # NIL THEN
			IF varDes # NIL THEN (* internal *)
				varDes.SetOuter(NIL);
				IF varDes.type # NIL THEN
					IF isOffered THEN list := CCIR.OfferedInterfaces(varDes.type)
					ELSE list := CCIR.RequiredInterfaces(varDes.type)
					END
				END;
				IF list # NIL THEN
					interfaceDecl := list.FindInterfaceDeclaration(interfaceName);
					IF interfaceDecl # NIL THEN
						NEW(internalInterface, inputDes.pos, interfaceDecl, isOffered, varDes);
						interfaceDes := internalInterface
					END
				END
			ELSE (* external *)
				component := CCIR.GetSurroundingComponent(current);
				IF isOffered THEN list := component.offeredInterfaces
				ELSE list := component.requiredInterfaces
				END;
				IF list # NIL THEN
					interfaceDecl := list.FindInterfaceDeclaration(interfaceName);
					IF (interfaceDecl = NIL) & ~isOffered THEN
						implementation := component.implementations.FindImplementation(interfaceName);
						NEW(implementationDes, inputDes.pos, implementation);
						interfaceDes := implementationDes
					ELSIF interfaceDecl # NIL THEN
						NEW(externalInterface, inputDes.pos, component, interfaceDecl, isOffered);
						interfaceDes := externalInterface
					END
				END
			END
		END;
		IF interfaceDes # NIL THEN
			IF indexExpr # NIL THEN indexExpr.SetOuter(NIL) END;
			interfaceDes.SetIndex(indexExpr);
			IF interfaceDes.index = NIL THEN
				IF (interfaceDes.declaration.minNumber # 1) OR (interfaceDes.declaration.maxNumber # 1) THEN
					Error(inputDes.pos, "Specific interface must be selected by an index")
				END
			END
		ELSE Error(inputDes.pos, "Undefined interface")
		END;
		RETURN interfaceDes
	END CheckInterfaceDesignator;
	
	PROCEDURE ExplicitInterfaceSelection(current: CCIR.Node; inputDes: CCIR.Designator; isOffered: BOOLEAN; 
		VAR varDes: CCIR.Designator; VAR indexExpr: CCIR.Expression; VAR interfaceName: CCIR.Identifier);
	VAR part: CCIR.Designator; paramDes: CCIR.ParameterDesignator; varExp: CCIR.Expression; 
		indexDes: CCIR.IndexDesignator;
	BEGIN
		varDes := NIL; indexExpr := NIL; interfaceName := NIL;
		part := inputDes;
		IF part IS CCIR.ParameterDesignator THEN
			paramDes := part(CCIR.ParameterDesignator);
			part := paramDes.left;
			IF paramDes.arguments.Length() = 1 THEN
				varExp := paramDes.arguments.GetExpression(0);
				IF varExp IS CCIR.Designator THEN
					varDes := varExp(CCIR.Designator);
					varDes := CheckStorageDesignator(current, varDes);
					paramDes.arguments.ReplaceExpression(0, varDes)
				END
			END
		END;
		IF part IS CCIR.IndexDesignator THEN
			indexDes := part(CCIR.IndexDesignator);
			part := indexDes.left;
			indexExpr := ExtractInterfaceIndex(current, indexDes)
		END;
		IF part IS CCIR.IdentifierDesignator THEN
			interfaceName := part(CCIR.IdentifierDesignator).identifier
		END
	END ExplicitInterfaceSelection;
	
	PROCEDURE ImplicitInterfaceSelection(current: CCIR.Node; inputDes: CCIR.Designator; isOffered: BOOLEAN;
		hint: CCIR.Interface; VAR varDes: CCIR.Designator; VAR indexExpr: CCIR.Expression; VAR interfaceName: CCIR.Identifier);
	VAR interfaceDecl: CCIR.InterfaceDeclaration;
	BEGIN
		varDes := NIL; indexExpr := NIL; interfaceName := NIL;
		IF IsVariableDesignator(current, inputDes) THEN
			varDes := CheckStorageDesignator(current, inputDes);
			IF hint # NIL THEN 
				interfaceName := hint.name 
			ELSE
				IF isOffered THEN interfaceDecl := SingleOfferedInterface(varDes.type)
				ELSE interfaceDecl := SingleRequiredInterface(varDes.type)
				END;
				IF (interfaceDecl # NIL) & (interfaceDecl.interface # NIL) THEN
					IF (interfaceDecl.minNumber = 1) & (interfaceDecl.maxNumber = 1) THEN
						interfaceName := interfaceDecl.interface.name
					END
				END
			END
		END
	END ImplicitInterfaceSelection;
	
	PROCEDURE IsInterfaceDesignator(current: CCIR.Node; designator: CCIR.Designator): BOOLEAN;
	VAR ident: CCIR.Identifier; 
	BEGIN
		IF designator IS CCIR.ParameterDesignator THEN
			designator := designator(CCIR.ParameterDesignator).left
		END;
		IF designator IS CCIR.IndexDesignator THEN
			designator := designator(CCIR.IndexDesignator).left
		END;
		IF designator IS CCIR.IdentifierDesignator THEN
			ident := designator(CCIR.IdentifierDesignator).identifier;
			RETURN ResolveInterface(current, ident) # NIL
		ELSE RETURN FALSE
		END
	END IsInterfaceDesignator;
		
	PROCEDURE IsExternalInterfaceDesignator(current: CCIR.Node; designator: CCIR.Designator): BOOLEAN;
	BEGIN RETURN IsInterfaceDesignator(current, designator) & ~(designator IS CCIR.ParameterDesignator)
	END IsExternalInterfaceDesignator;
		
	PROCEDURE ExtractInterfaceIndex(current: CCIR.Node; indexDes: CCIR.IndexDesignator): CCIR.Expression;
	VAR indexExpr: CCIR.Expression;
	BEGIN
		IF indexDes.arguments.Length() = 1 THEN 
			indexExpr := indexDes.arguments.GetExpression(0);
			indexExpr := CheckExpression(current, indexExpr);
			indexDes.arguments.ReplaceExpression(0, indexExpr);
			CheckDataType(indexExpr, CCIR.integerType);
			RETURN indexExpr
		ELSE RETURN NIL
		END
	END ExtractInterfaceIndex;
		
	(* NIL if no unique single offered interface *)
	PROCEDURE SingleOfferedInterface(type: CCIR.Type): CCIR.InterfaceDeclaration;
	VAR component: CCIR.ComponentDefinition; offered: CCIR.InterfaceDeclarationList; 
	BEGIN
		IF CCIR.IsComponentType(type) THEN
			IF type IS CCIR.ComponentType THEN
				component := type(CCIR.ComponentType).componentDefinition;
				IF component # NIL THEN
					offered := component.offeredInterfaces
				END
			ELSIF type IS CCIR.AnyType THEN
				offered := type(CCIR.AnyType).offeredInterfaces
			ELSE HALT(111)
			END;
			IF (offered # NIL) & (offered.Length() = 1) THEN
				RETURN offered.GetInterfaceDeclaration(0)
			ELSE RETURN NIL
			END
		ELSE RETURN NIL
		END
	END SingleOfferedInterface;
	
	PROCEDURE SingleRequiredInterface(type: CCIR.Type): CCIR.InterfaceDeclaration;
	VAR component: CCIR.ComponentDefinition; required: CCIR.InterfaceDeclarationList; 
	BEGIN
		IF CCIR.IsComponentType(type) THEN
			IF type IS CCIR.ComponentType THEN
				component := type(CCIR.ComponentType).componentDefinition;
				required := component.requiredInterfaces
			ELSE HALT(111)
			END;
			IF required.Length() = 1 THEN
				RETURN required.GetInterfaceDeclaration(0)
			ELSE RETURN NIL
			END
		ELSE RETURN NIL
		END
	END SingleRequiredInterface;
				
	PROCEDURE CheckProcParamCompatibility(current: CCIR.Node; decl: CCIR.Procedure; arguments: CCIR.ExpressionList; 	
		parameters: CCIR.ProcedureParameterList);
	VAR pos, i: LONGINT; par: CCIR.ProcedureParameter; expr: CCIR.Expression; des: CCIR.Designator; var: CCIR.Variable;
	BEGIN
		pos := current.pos;
		IF arguments.Length() = parameters.Length() THEN
			FOR i := 0 TO arguments.Length()-1 DO
				par := parameters.GetProcedureParameter(i);
				expr := arguments.GetExpression(i);
				IF expr.type # NIL THEN
					IF par.variable THEN
						CheckResolvedStorageDesignator(expr);
						IF ~expr.type.Equal(par.type) THEN 
							Error(expr.pos, "Not the same type like the VARIABLE-parameter") 
						ELSIF expr IS CCIR.Designator THEN
							des := expr(CCIR.Designator);
							IF (des.node # NIL) & (des.node IS CCIR.Variable) THEN
								var := des.node(CCIR.Variable);
								IF var.parameters.Length() > 0 THEN 
									IF (decl # CCIR.inc1) & (decl # CCIR.inc2) & (decl # CCIR.dec1) & (decl # CCIR.dec2) THEN
										Error(expr.pos, "Collection element can not be passed to VARIABLE-parameter")
									END
								END
							END;
							CheckProtection(expr, CCIR.exclusive)
						END
					ELSE
						expr := ImplicitConversion(expr, par.type);
						arguments.ReplaceByIndex(i, expr);
						CheckAssignmentCompatibility(current, expr.pos, expr.type, par.type)
					END
				END
			END
		ELSIF arguments.Length() < parameters.Length() THEN
			Error(pos, "Too few arguments")
		ELSE
			Error(pos, "Too many arguments")
		END
	END CheckProcParamCompatibility;
				
	PROCEDURE CheckParameterCompatibility(current: CCIR.Node; argAssignedToParam: BOOLEAN;
		arguments: CCIR.ExpressionList; parameters: CCIR.ParameterList);
	VAR i: LONGINT; par: CCIR.Parameter; expr: CCIR.Expression; pos: LONGINT;
	BEGIN
		pos := current.pos; 
		IF arguments.Length() = parameters.Length() THEN
			FOR i := 0 TO arguments.Length()-1 DO
				par := parameters.GetParameter(i);
				expr := arguments.GetExpression(i);
				IF argAssignedToParam THEN
					expr := ImplicitConversion(expr, par.type);
					arguments.ReplaceByIndex(i, expr);
					CheckAssignmentCompatibility(current, expr.pos, expr.type, par.type)
				ELSE
					CheckAssignmentCompatibility(current, expr.pos, par.type, expr.type)
				END
			END
		ELSIF arguments.Length() < parameters.Length() THEN
			Error(pos, "Too few arguments")
		ELSE
			Error(pos, "Too many arguments")
		END
	END CheckParameterCompatibility;
		
	PROCEDURE CheckSendStatement(send: CCIR.SendStatement);
	VAR interfaceDes: CCIR.InterfaceDesignator; md: CCIR.MessageDeclaration; 
	BEGIN
		RegisterExternalEventForAwait(send);
		interfaceDes := CheckCommunicationDesignator(send.pos, send, send, send.interfaceDesignator);
		CheckSendExpressionList(send);
		IF interfaceDes # NIL THEN
			send.SetInterfaceDesignator(interfaceDes);
			IF interfaceDes.declaration.interface # NIL THEN
				md := interfaceDes.declaration.interface.messageDeclarations.FindMessageDeclaration(send.messageIdentifier);
				IF md # NIL THEN 
					CheckCommunicationDirection(send.pos, interfaceDes, md, TRUE);
					CheckParameterCompatibility(send, TRUE, send.messageArguments, md.parameters);
				ELSE Error(send.messageIdentifier.pos, "Undefined message")
				END
			ELSE Error(interfaceDes.pos, "Undefined interface")
			END
		END
	END CheckSendStatement;
	
	PROCEDURE CheckSendExpressionList(send: CCIR.SendStatement);
	VAR list: CCIR.ExpressionList; expr: CCIR.Expression; i: LONGINT;
	BEGIN
		list := send.messageArguments;
		CheckExpressionList(send, list);
		FOR i := 0 TO list.Length()-1 DO
			expr := list.GetExpression(i);
			IF expr.type # NIL THEN
				IF CCIR.IsComponentType(expr.type) THEN (* must be storage location designator *)
					IF ~(expr IS CCIR.Designator) OR ~(expr(CCIR.Designator).node IS CCIR.Variable) THEN
						Error(expr.pos, "Variable designator required for sending components") 
					END;
					CheckProtection(expr, CCIR.exclusive)
				ELSE
					CheckProtection(expr, CCIR.shared)
				END
			END
		END
	END CheckSendExpressionList;
	
	PROCEDURE CheckReceiveStatement(receive: CCIR.ReceiveStatement);
	VAR interfaceDes: CCIR.InterfaceDesignator; md: CCIR.MessageDeclaration;
	BEGIN
		RegisterExternalEventForAwait(receive);
		interfaceDes := CheckCommunicationDesignator(receive.pos, receive, receive, receive.interfaceDesignator);
		CheckStorageDesignatorList(receive, receive.messageArguments);
		IF interfaceDes # NIL THEN
			receive.SetInterfaceDesignator(interfaceDes);
			IF interfaceDes.declaration.interface # NIL THEN
				md := interfaceDes.declaration.interface.messageDeclarations.FindMessageDeclaration(receive.messageIdentifier);
				IF md # NIL THEN 
					CheckCommunicationDirection(receive.pos, interfaceDes, md, FALSE);
					CheckParameterCompatibility(receive, FALSE, receive.messageArguments, md.parameters)
				ELSE Error(receive.messageIdentifier.pos, "Undefined message")
				END
			ELSE Error(interfaceDes.pos, "Undefined interface")
			END
		END
	END CheckReceiveStatement;
	
	(* isSend = FALSE: receive (?) or INPUT otherwise send (!) *)
	PROCEDURE CheckCommunicationDirection(pos: LONGINT; interfaceDes: CCIR.InterfaceDesignator; 
		message: CCIR.MessageDeclaration;  isSend: BOOLEAN);
	BEGIN
		IF (interfaceDes IS CCIR.ExternalInterfaceDesignator) & interfaceDes.isOffered THEN 
			(* communication server *)
			IF isSend & message.input THEN Error(pos, "Server must not send an input message") END;
			IF ~isSend & ~message.input THEN Error(pos, "Server must not receive an output message") END
		ELSE
			(* communication client *)
			IF isSend & ~message.input THEN Error(pos, "Client must not send an output message") END;
			IF ~isSend & message.input THEN Error(pos, "Client must not receive an input message") END
		END
	END CheckCommunicationDirection;
			
	PROCEDURE CheckStorageDesignatorList(current: CCIR.Node; list: CCIR.ExpressionList);
	VAR i: LONGINT; e: CCIR.Expression; v: CCIR.Variable;
	BEGIN
		FOR i := 0 TO list.Length()-1 DO
			e := list.GetExpression(i);
			list.ReplaceExpression(i, CheckExpression(current, e));
			CheckResolvedStorageDesignator(e);
			CheckProtection(e, CCIR.exclusive)
		END
	END CheckStorageDesignatorList;
	
	PROCEDURE CheckIfStatement(ifStatement: CCIR.IfStatement);
	VAR i: LONGINT; cb: CCIR.ConditionalBlock;
	BEGIN
		CheckConditionalBlock(ifStatement.ifBlock);
		FOR i := 0 TO ifStatement.elsifBlocks.Length()-1 DO
			cb := ifStatement.elsifBlocks.GetConditionalBlock(i);
			CheckConditionalBlock(cb)
		END;
		IF ifStatement.else # NIL THEN
			CheckStatementSequence(ifStatement.else)
		END
	END CheckIfStatement;

	PROCEDURE CheckConditionalBlock(b: CCIR.ConditionalBlock);
	BEGIN
		b.SetCondition(CheckExpression(b.statements.outer, b.condition));
		CheckDataType(b.condition, CCIR.booleanType);
		CheckStatementSequence(b.statements);
		CheckProtection(b.condition, CCIR.shared)
	END CheckConditionalBlock;
		
	PROCEDURE CheckWhileStatement(w: CCIR.WhileStatement);
	BEGIN
		w.SetCondition(CheckExpression(w, w.condition));
		CheckDataType(w.condition, CCIR.booleanType);
		CheckStatementSequence(w.statements);
		CheckProtection(w.condition, CCIR.shared)
	END CheckWhileStatement;
	
	PROCEDURE CheckRepeatStatement(r: CCIR.RepeatStatement);
	BEGIN
		CheckStatementSequence(r.statements);
		r.SetCondition(CheckExpression(r, r.condition));
		CheckDataType(r.condition, CCIR.booleanType);
		CheckProtection(r.condition, CCIR.shared)
	END CheckRepeatStatement;
	
	PROCEDURE CheckDataType(exp: CCIR.Expression; type: CCIR.DataType);
	BEGIN IF exp.type # type THEN Error(exp.pos, "Invalid data type") END
	END CheckDataType;
		
	PROCEDURE CheckForStatement(for: CCIR.ForStatement);
	VAR varType: CCIR.Type;
	BEGIN
		for.SetTemporaryVariable(GetTempVariable(for));
		for.SetVariableDesignator(CheckStorageDesignator(for, for.varDesignator));
		varType := for.varDesignator.type;
		IF varType # NIL THEN
			IF varType # CCIR.integerType THEN Error(for.varDesignator.pos, "Invalid data type") END
		END;
		CheckProtection(for.varDesignator, CCIR.exclusive);
		for.SetFromExpression(CheckExpression(for, for.fromExpression));
		CheckDataType(for.fromExpression, CCIR.integerType);
		CheckProtection(for.fromExpression, CCIR.shared);
		for.SetToExpression(CheckExpression(for, for.toExpression));
		CheckDataType(for.toExpression, CCIR.integerType);
		CheckProtection(for.toExpression, CCIR.shared);
		for.SetByExpression(CheckExpression(for, for.byExpression));
		IF CCIR.IsConstantInteger(for.byExpression) THEN
			IF CCIR.ConstantInteger(for.byExpression) = 0 THEN Error(for.byExpression.pos, "Zero iteration step") END
		ELSE Error(for.byExpression.pos, "Not a constant integer")
		END;
		CheckStatementSequence(for.statements)
	END CheckForStatement;

	PROCEDURE CheckForeachStatement(foreach: CCIR.ForeachStatement);
	VAR i: LONGINT; ofVar: CCIR.Variable;
	BEGIN
		foreach.SetTemporaryVariable(GetTempVariable(foreach));
		ofVar := CheckCollectionDesignator(foreach, foreach.of); 
		IF ofVar # NIL THEN
			CheckStorageDesignatorList(foreach, foreach.varDesignators);
			CheckParameterCompatibility(foreach, FALSE, foreach.varDesignators, ofVar.parameters)
		END;
		CheckStatementSequence(foreach.statements);
		CheckProtection(foreach.of, CCIR.shared)
	END CheckForeachStatement;

	PROCEDURE CheckAwaitStatement(await: CCIR.AwaitStatement);
	VAR varDep: BOOLEAN; des: CCIR.InterfaceDesignator;
	BEGIN
		MustNotBeInAwait(await.outer);
		await.SetCondition(CheckExpression(await, await.condition));
		CheckDataType(await.condition, CCIR.booleanType);
		IF CCIR.CurrentLockType(await) = NIL THEN
			Error(await.pos, "must be used in SHARED or EXCLUSIVE block")
		END
	END CheckAwaitStatement;
			
	PROCEDURE CheckNewStatement(new: CCIR.NewStatement);
	VAR var: CCIR.Variable; varType: CCIR.Type; ct: CCIR.ComponentType; com: CCIR.ComponentDefinition; 
		second: CCIR.Expression; k: LONGINT; arg: CCIR.Expression;
	BEGIN
		IF IsCollectionDesignator(new, new.variableDes) THEN
			var := CheckCollectionDesignator(new, new.variableDes);
			IF (var.attributeList # NIL) & var.attributeList.Contains(CCIR.array) THEN (* ok *)
				IF new.additionalArguments.Length() = var.parameters.Length() THEN
					FOR k := 0 TO new.additionalArguments.Length()-1 DO
						arg := new.additionalArguments.GetExpression(k);
						arg := CheckExpression(new, arg);
						new.additionalArguments.ReplaceExpression(k, arg);
						CheckDataType(arg, CCIR.integerType)
					END
				ELSIF new.additionalArguments.Length() < var.parameters.Length() THEN
					Error(new.pos, "Too few arguments")
				ELSE
					Error(new.pos, "Too many arguments")
				END
			ELSE Error(new.variableDes.pos, "Not an array collection")
			END
		ELSE
			new.SetVariableDesignator(CheckStorageDesignator(new, new.variableDes));
			IF (new.variableDes # NIL) & (new.variableDes.node # NIL) THEN
				var := new.variableDes.node(CCIR.Variable); varType := new.variableDes.type;
				IF new.additionalArguments.Length() > 1 THEN Error(new.pos, "Too many arguments")
				ELSIF new.additionalArguments.Length() = 1 THEN second := new.additionalArguments.GetExpression(0)
				ELSE second := NIL
				END;
				IF varType # NIL THEN
					IF varType IS CCIR.ComponentType THEN
						ct := varType(CCIR.ComponentType);
						IF second # NIL THEN
							com := CheckComponentName(new, second);
							IF com # ct.componentDefinition THEN
								Error(second.pos, "Variable has a different declared component type")
							END
						END;
						new.SetComponentType(ct)
					ELSIF varType IS CCIR.AnyType THEN
						IF second # NIL THEN
							com := CheckComponentName(new, second);
							IF com # NIL THEN
								CollectUsedExternalComponent(new, com);
								NEW(ct, second.pos, com.name); ct.SetComponentDefinition(com);
								new.SetComponentType(ct);
								CheckAssignmentCompatibility(new, new.pos, ct, varType)
							END
						ELSE Error(new.pos, "Component type not specified")
						END
					ELSIF varType = CCIR.textType THEN
						IF second = NIL THEN
							Error(new.pos, "Text length not specified")
						ELSE
							second := CheckExpression(new, second);
							new.additionalArguments.ReplaceExpression(0, second);
							CheckDataType(second, CCIR.integerType)
						END
					ELSE Error(new.pos, "NEW not applicable for this variable type")
					END;
				END;
				CheckProtection(new.variableDes, CCIR.exclusive)
			END
		END
	END CheckNewStatement;
		
	PROCEDURE CheckConnectStatement(connect: CCIR.ConnectStatement);
	VAR source, target: CCIR.InterfaceDesignator;
	BEGIN
		source := CheckConnectDesignator(connect, connect.source, TRUE, NIL);
		IF source # NIL THEN
			connect.SetSource(source);
			target := CheckConnectDesignator(connect, connect.target, FALSE, source.declaration.interface);
			IF target # NIL THEN
				connect.SetTarget(target);
				IF source.declaration.interface # target.declaration.interface THEN
					Error(connect.pos, "Interfaces do not match")
				END;
				CheckProtection(source, CCIR.exclusive);
				CheckProtection(target, CCIR.exclusive)
			END
		END
	END CheckConnectStatement;
	
	PROCEDURE CheckDisconnectStatement(disconnect: CCIR.DisconnectStatement);
	VAR des: CCIR.InterfaceDesignator;
	BEGIN
		des := CheckConnectDesignator(disconnect, disconnect.intDes, TRUE, NIL);
		IF des # NIL THEN
			disconnect.SetDesignator(des);
			CheckProtection(des, CCIR.exclusive)
		END
	END CheckDisconnectStatement;

	PROCEDURE CheckConstantDesignator(current: CCIR.Node; des: CCIR.Designator): CCIR.Designator;
	VAR c: CCIR.Constant;
	BEGIN
		IF des IS CCIR.IdentifierDesignator THEN
			c := ResolveConstant(current, des(CCIR.IdentifierDesignator).identifier);
			IF c # NIL THEN
				des.SetDesignatedNode(c);
				des.SetType(c.expression.type)
			ELSE
				Error(des.pos, "Undefined constant identifier")
			END
		ELSE
			Error(des.pos, "Invalid constant designator")
		END;
		RETURN des
	END CheckConstantDesignator;
																																																																														
	(* resolve if necessary and check variable designator *)
	PROCEDURE CheckStorageDesignator(current: CCIR.Node; des: CCIR.Designator): CCIR.Designator;
	BEGIN
		des := CheckInstanceDesignator(current, des);
		IF (des.node = NIL) OR ~((des.node IS CCIR.Parameter) OR (des.node IS CCIR.Variable)) THEN
			Error(des.pos, "Undefined variable")
		ELSIF des.node IS CCIR.Variable THEN 
			(* local variable, or procedure parameter *)
		ELSIF des.node IS CCIR.Parameter THEN
			Error(des.pos, "Parameter can not be used as a variable")
		ELSE HALT(111)
		END;
		RETURN des
	END CheckStorageDesignator;
		
	PROCEDURE IsVariableDesignator(current: CCIR.Node; des: CCIR.Designator): BOOLEAN;
	VAR v: CCIR.Variable;
	BEGIN
		IF des IS CCIR.IdentifierDesignator THEN
			v := ResolveVariable(current, des(CCIR.IdentifierDesignator).identifier)
		ELSIF des IS CCIR.IndexDesignator THEN
			v := ResolveVariable(current, des(CCIR.IndexDesignator).left(CCIR.IdentifierDesignator).identifier)
		ELSE
			v := NIL
		END;
		RETURN v # NIL
	END IsVariableDesignator;
		
	PROCEDURE CheckResolvedStorageDesignator(expr: CCIR.Expression);
	BEGIN 
		IF ~((expr IS CCIR.Designator) & (expr(CCIR.Designator).node # NIL) & (expr(CCIR.Designator).node IS CCIR.Variable)) THEN
			Error(expr.pos, "Variable designator required")
		END
	END CheckResolvedStorageDesignator;
	
	(* NIL if undefined *)
	PROCEDURE CheckComponentName(current: CCIR.Node; expr: CCIR.Expression): CCIR.ComponentDefinition;
	VAR com: CCIR.ComponentDefinition;
	BEGIN
		IF expr IS CCIR.IdentifierDesignator THEN
			com := ResolveComponent(current, expr(CCIR.IdentifierDesignator).identifier);
			IF com # NIL THEN
				expr(CCIR.IdentifierDesignator).SetDesignatedNode(com)
			ELSE
				Error(expr.pos, "Undefined component type")
			END;
			RETURN com
		ELSE
			Error(expr.pos, "Undefined component type");
			RETURN NIL
		END
	END CheckComponentName;
	
	(* NIL if not defined, nofParameters is only relevant for some predefined procedures *)
	PROCEDURE ResolveProcedure(current: CCIR.Node; id: CCIR.Identifier; nofParameters: LONGINT): CCIR.Procedure;
	VAR p: CCIR.Procedure;
	BEGIN
		p := NIL;
		IF current = NIL THEN
			p := CCIR.predefinedProcedures.FindProcedure2(id, nofParameters)
		ELSIF current IS CCIR.Statement THEN
			p := ResolveProcedure(current(CCIR.Statement).outer, id, nofParameters)
		ELSIF current IS CCIR.Component THEN
			p := current(CCIR.Component).procedures.FindProcedure(id);
			IF p = NIL THEN
				p := ResolveProcedure(NIL, id, nofParameters)
			END
		ELSIF current IS CCIR.Implementation THEN
			p := current(CCIR.Implementation).nestedProcedures.FindProcedure(id);
			IF p = NIL THEN
				p := ResolveProcedure(current(CCIR.Implementation).outer, id, nofParameters)
			END
		ELSIF current IS CCIR.Procedure THEN
			p := current(CCIR.Procedure).nestedProcedures.FindProcedure(id);
			IF p = NIL THEN
				p := ResolveProcedure(current(CCIR.Procedure).outer, id, nofParameters)
			END
		ELSE HALT(111)
		END;
		RETURN p
	END ResolveProcedure;
	
	(* NIL if not defined, parameter or variable *)
	PROCEDURE ResolveVariable(current: CCIR.Node; id: CCIR.Identifier): CCIR.Variable;
	VAR v: CCIR.Variable; 
	BEGIN
		v := NIL;
		IF current = NIL THEN (* nothing *)
		ELSIF current IS CCIR.Statement THEN
			v := ResolveVariable(current(CCIR.Statement).outer, id)
		ELSIF current IS CCIR.Component THEN
			v := current(CCIR.Component).variables.FindVariable(id)
		ELSIF current IS CCIR.Implementation THEN
			v := current(CCIR.Implementation).variables.FindVariable(id);
			IF v = NIL THEN
				v := ResolveVariable(current(CCIR.Implementation).outer, id)
			END
		ELSIF current IS CCIR.Procedure THEN
			v := current(CCIR.Procedure).variables.FindVariable(id);
			IF v = NIL THEN
				v := current(CCIR.Procedure).parameters.FindProcedureParameter(id);
				IF v = NIL THEN
					v := ResolveVariable(current(CCIR.Procedure).outer, id)
				END
			END
		ELSE HALT(111) (* invalid *)
		END;
		IF v = NIL THEN
			v := CCIR.predefinedVariables.FindVariable(id)
		END;
		RETURN v
	END ResolveVariable;
	
	(* NIL if not defined *)
	PROCEDURE ResolveConstant(current: CCIR.Node; id: CCIR.Identifier): CCIR.Constant;
	VAR c: CCIR.Constant;
	BEGIN
		c := NIL;
		IF current IS CCIR.Statement THEN
			c := ResolveConstant(current(CCIR.Statement).outer, id)
		ELSIF current IS CCIR.Component THEN
			c := current(CCIR.Component).constants.FindConstant(id);
			IF (c = NIL) & (current(CCIR.Component).outer # NIL) THEN
				c := ResolveConstant(current(CCIR.Component).outer, id)
			END;
			IF c = NIL THEN
				c := CCIR.predefinedConstants.FindConstant(id)
			END
		ELSIF current IS CCIR.Implementation THEN
			c := current(CCIR.Implementation).constants.FindConstant(id);
			IF c = NIL THEN
				c := ResolveConstant(current(CCIR.Implementation).outer, id)
			END
		ELSIF current IS CCIR.Procedure THEN
			c := current(CCIR.Procedure).constants.FindConstant(id);
			IF c = NIL THEN
				c := ResolveConstant(current(CCIR.Procedure).outer, id)
			END
		ELSE HALT(111)
		END;
		RETURN c
	END ResolveConstant;
	
	(* NIL if undefined *)
	PROCEDURE ResolveComponent(current: CCIR.Node; id: CCIR.Identifier): CCIR.ComponentDefinition;
	VAR x: CCIR.ComponentDefinition; nestedComponents: CCIR.ComponentList;
	BEGIN
		WHILE current # NIL DO
			IF current IS CCIR.Statement THEN
				nestedComponents := NIL;
				current := current(CCIR.Statement).outer
			ELSIF current IS CCIR.Implementation THEN
				nestedComponents := current(CCIR.Implementation).nestedComponents;
				current := current(CCIR.Implementation).outer
			ELSIF current IS CCIR.Procedure THEN
				nestedComponents := current(CCIR.Procedure).nestedComponents;
				current := current(CCIR.Procedure).outer
			ELSIF current IS CCIR.Interface THEN
				nestedComponents := NIL;
				current := current(CCIR.Interface).outer
			ELSIF current IS CCIR.Component THEN
				nestedComponents := current(CCIR.Component).nestedComponents;
				current := current(CCIR.Component).outer
			ELSE HALT(111)
			END;
			IF nestedComponents # NIL THEN
				x := nestedComponents.FindComponent(id);
				IF x # NIL THEN RETURN x END
			END			
		END;
		x := CCIR.compiledComponents.FindComponent(id);
		IF x = NIL THEN
			x := CCIR.importedComponents.FindComponentDefinition(id);
			IF x = NIL THEN
				x := CCImporter.ImportComponent(id);
				IF x # NIL THEN
					CheckInterfaceDeclList(NIL, TRUE, x.offeredInterfaces);
					CheckInterfaceDeclList(NIL, FALSE, x.requiredInterfaces)
				END
			END
		END;
		RETURN x
	END ResolveComponent;
	
	(* NIL If undefined *)
	PROCEDURE ResolveInterface(current: CCIR.Node; id: CCIR.Identifier): CCIR.Interface;
	VAR x: CCIR.Interface; nestedInterfaces: CCIR.InterfaceList;
	BEGIN
		WHILE current # NIL DO
			IF current IS CCIR.Statement THEN
				nestedInterfaces := NIL;
				current := current(CCIR.Statement).outer
			ELSIF current IS CCIR.Implementation THEN
				nestedInterfaces := current(CCIR.Implementation).nestedInterfaces;
				current := current(CCIR.Implementation).outer
			ELSIF current IS CCIR.Procedure THEN
				nestedInterfaces := current(CCIR.Procedure).nestedInterfaces;
				current := current(CCIR.Procedure).outer
			ELSIF current IS CCIR.Interface THEN
				nestedInterfaces := NIL;
				current := current(CCIR.Interface).outer
			ELSIF current IS CCIR.Component THEN
				nestedInterfaces := current(CCIR.Component).nestedInterfaces;
				current := current(CCIR.Component).outer
			ELSE HALT(111)
			END;
			IF nestedInterfaces # NIL THEN
				x := nestedInterfaces.FindInterface(id);
				IF x # NIL THEN RETURN x END
			END
		END;
		x := CCIR.compiledInterfaces.FindInterface(id);
		IF x = NIL THEN
			x := CCIR.importedInterfaces.FindInterface(id);
			IF x = NIL THEN
				x := CCImporter.ImportInterface(id);
				IF x # NIL THEN
					CheckImportedInterface(x)
				END
			END
		END;
		RETURN x
	END ResolveInterface;
	
	PROCEDURE CheckImportedInterface(x: CCIR.Interface);
	VAR i: LONGINT; m: CCIR.MessageDeclaration;
	BEGIN
		FOR i := 0 TO x.messageDeclarations.Length()-1 DO
			m := x.messageDeclarations.GetMessageDeclaration(i);
			CheckImportedParameters(m.parameters)
		END
	END CheckImportedInterface;
	
	PROCEDURE CheckImportedParameters(list: CCIR.ParameterList);
	VAR i: LONGINT; p: CCIR.Parameter;
	BEGIN
		FOR i := 0 TO list.Length()-1 DO
			p := list.GetParameter(i);
			CheckType(NIL, p.type)
		END
	END CheckImportedParameters;
			
	PROCEDURE CheckExpressionList(current: CCIR.Node; list: CCIR.ExpressionList);
	VAR i: LONGINT;
	BEGIN
		FOR i := 0 TO list.Length()-1 DO
			list.ReplaceExpression(i, CheckExpression(current, list.GetExpression(i)))
		END
	END CheckExpressionList;
	
	(* fixup types *)
	PROCEDURE CheckExpression(current: CCIR.Node; expr: CCIR.Expression): CCIR.Expression;
	VAR ue: CCIR.UnaryExpression; be: CCIR.BinaryExpression;  
	BEGIN
		CheckAttributeList(expr);
		IF expr IS CCIR.TextValue THEN
			expr.SetType(CCIR.textType)
		ELSIF expr IS CCIR.IntegerValue THEN
			expr.SetType(CCIR.integerType)
		ELSIF expr IS CCIR.RealValue THEN
			expr.SetType(CCIR.realType)
		ELSIF expr IS CCIR.BooleanValue THEN
			expr.SetType(CCIR.booleanType)
		ELSIF expr IS CCIR.CharacterValue THEN
			expr.SetType(CCIR.characterType)
		ELSIF expr IS CCIR.Designator THEN
			expr := CheckDesignatorExpression(current, expr(CCIR.Designator));
		ELSIF expr IS CCIR.UnaryExpression THEN
			ue := expr(CCIR.UnaryExpression);
			ue.SetSub(CheckExpression(current, ue.sub));
			IF (ue.operator = CCIR.Plus) OR (ue.operator = CCIR.Minus) THEN
				IF ue.sub.type = CCIR.integerType THEN
					expr.SetType(CCIR.integerType)
				ELSIF ue.sub.type = CCIR.realType THEN
					expr.SetType(CCIR.realType)
				ELSE Error(expr.pos, "Operand must be INTEGER or REAL number value")
				END
			ELSIF ue.operator = CCIR.Not THEN
				CheckDataType(ue.sub, CCIR.booleanType);
				expr.SetType(CCIR.booleanType)
			ELSE HALT(101) (* not supported *)
			END
		ELSIF expr IS CCIR.BinaryExpression THEN
			be := expr(CCIR.BinaryExpression);
			be.SetLeft(CheckExpression(current, be.left));
			be.SetRight(CheckExpression(current, be.right));
			be.SetLeft(ImplicitConversion(be.left, be.right.type));
			be.SetRight(ImplicitConversion(be.right, be.left.type));
			IF (be.operator = CCIR.Plus) OR (be.operator = CCIR.Minus) OR (be.operator = CCIR.Times) THEN
				IF be.left.type = CCIR.integerType THEN
					CheckDataType(be.right, CCIR.integerType);
					expr.SetType(CCIR.integerType)
				ELSIF be.left.type = CCIR.realType THEN
					CheckDataType(be.right, CCIR.realType);
					expr.SetType(CCIR.realType)
				ELSE Error(be.pos, "Operands must be INTEGER or REAL number values")
				END
			ELSIF (be.operator = CCIR.IntegerDivision) OR (be.operator = CCIR.Modulo) THEN
				CheckDataType(be.left, CCIR.integerType);
				CheckDataType(be.right, CCIR.integerType);
				expr.SetType(CCIR.integerType)
			ELSIF be.operator = CCIR.RealDivision THEN
				be.SetLeft(ImplicitConversion(be.left, CCIR.realType));
				be.SetRight(ImplicitConversion(be.right, CCIR.realType));
				CheckDataType(be.left, CCIR.realType);
				CheckDataType(be.right, CCIR.realType);
				expr.SetType(CCIR.realType)
			ELSIF (be.operator = CCIR.Equal) OR (be.operator = CCIR.Unequal) THEN
				IF be.left.type = CCIR.integerType THEN
					CheckDataType(be.right, CCIR.integerType)
				ELSIF be.left.type = CCIR.realType THEN
					CheckDataType(be.right, CCIR.realType)
				ELSIF be.left.type = CCIR.booleanType THEN
					CheckDataType(be.right, CCIR.booleanType)
				ELSIF be.left.type = CCIR.textType THEN
					CheckDataType(be.right, CCIR.textType)
				ELSIF be.left.type = CCIR.characterType THEN
					CheckDataType(be.right, CCIR.characterType)
				ELSE
					Error(be.left.pos, "Inapplicable operator")
				END;
				expr.SetType(CCIR.booleanType)
			ELSIF (be.operator = CCIR.Less) OR (be.operator = CCIR.LessEqual) OR 
					(be.operator = CCIR.Greater) OR (be.operator = CCIR.GreaterEqual) THEN
				IF be.left.type = CCIR.integerType THEN
					CheckDataType(be.right, CCIR.integerType)
				ELSIF be.left.type = CCIR.realType THEN
					CheckDataType(be.right, CCIR.realType)
				ELSIF be.left.type = CCIR.characterType THEN
					CheckDataType(be.right, CCIR.characterType)
				ELSIF be.left.type = CCIR.textType THEN
					CheckDataType(be.right, CCIR.textType)
				ELSE
					Error(be.left.pos, "Inapplicable operator")
				END;
				expr.SetType(CCIR.booleanType)
			ELSIF (be.operator = CCIR.And) OR (be.operator = CCIR.Or) THEN
				CheckDataType(be.left, CCIR.booleanType);
				CheckDataType(be.right, CCIR.booleanType);
				expr.SetType(CCIR.booleanType)
			ELSE HALT(111) (* not supported *)
			END
		ELSIF expr IS CCIR.FunctionCall THEN
			CheckFunctionCall(current, expr(CCIR.FunctionCall))
		ELSIF expr IS CCIR.InputFunction THEN
			CheckInputFunction(current, expr(CCIR.InputFunction))
		ELSIF expr IS CCIR.ReceiveTestFunction THEN
			CheckReceiveTestFunction(current, expr(CCIR.ReceiveTestFunction))
		ELSIF expr IS CCIR.InterfaceTest THEN
			CheckInterfaceTest(current, expr(CCIR.InterfaceTest))
		ELSIF expr IS CCIR.TypeTest THEN
			CheckTypeTest(current, expr(CCIR.TypeTest))
		ELSE HALT(111)
		END;
		expr := OptimizeConstantExpression(expr);
		RETURN expr
	END CheckExpression;
	
	PROCEDURE OptimizeConstantExpression(expr: CCIR.Expression): CCIR.Expression;
	VAR iv: CCIR.IntegerValue; rv: CCIR.RealValue; bv: CCIR.BooleanValue;
	BEGIN
		IF expr.type # NIL THEN
			IF expr.type = CCIR.integerType THEN
				IF ~(expr IS CCIR.IntegerValue) & CCIR.IsConstantInteger(expr) THEN
					NEW(iv, expr.pos, CCIR.ConstantInteger(expr)); iv.SetType(CCIR.integerType);
					RETURN iv
				END
			ELSIF expr.type = CCIR.booleanType THEN
				IF ~(expr IS CCIR.BooleanValue) & CCIR.IsConstantBoolean(expr) THEN
					NEW(bv, expr.pos, CCIR.ConstantBoolean(expr)); bv.SetType(CCIR.booleanType);
					RETURN bv
				END
			ELSIF expr.type = CCIR.realType THEN
				IF ~(expr IS CCIR.RealValue) & CCIR.IsConstantReal(expr) THEN
					NEW(rv, expr.pos, CCIR.ConstantReal(expr)); rv.SetType(CCIR.realType);
					RETURN rv
				END
			END
		END;
		RETURN expr
	END OptimizeConstantExpression;
	
	PROCEDURE CheckInterfaceTest(current: CCIR.Node; test: CCIR.InterfaceTest);
	VAR x: CCIR.Identifier; currentCom: CCIR.Component; interface: CCIR.Interface;
	BEGIN
		test.SetLeft(CheckExpression(current, test.left));
		CheckResolvedStorageDesignator(test.left);
		CheckInterfaceDeclList(current, test.offers, test.interfaces);
		CollectInterfaceList(CCIR.GetSurroundingComponent(current), test.interfaces);
		test.SetType(CCIR.booleanType)
	END CheckInterfaceTest;
	
	PROCEDURE CheckTypeTest(current: CCIR.Node; test: CCIR.TypeTest);
	BEGIN
		test.SetLeft(CheckExpression(current, test.left));
		CheckResolvedStorageDesignator(test.left);
		CheckType(current, test.type);
		CollectType(current, test.type);
		test.SetType(CCIR.booleanType)
	END CheckTypeTest;
	
	PROCEDURE CheckDesignatorExpression(current: CCIR.Node; des: CCIR.Designator): CCIR.Expression;
	VAR parDes: CCIR.ParameterDesignator; id: CCIR.Identifier; ct: CCIR.ComponentType; guard: CCIR.GuardDesignator;
		functionCall: CCIR.FunctionCall; i: LONGINT; arg: CCIR.Expression; left: CCIR.Designator;
	BEGIN
		IF des IS CCIR.ParameterDesignator THEN
			parDes := des(CCIR.ParameterDesignator);
			left := parDes.left;
			IF parDes.arguments.Length() = 1 THEN
				arg := parDes.arguments.GetExpression(0);
				IF arg IS CCIR.IdentifierDesignator THEN
					id := arg(CCIR.IdentifierDesignator).identifier;
					IF ResolveComponent(current, id) # NIL THEN
						NEW(ct, id.pos, id); 
						left.SetOuter(NIL);
						NEW(guard, id.pos, left, ct);
						CheckGuardDesignator(current, guard);
						RETURN guard
					END
				END
			END;
			IF left IS CCIR.IdentifierDesignator THEN
				id := left(CCIR.IdentifierDesignator).identifier;
				IF id.Equal(CCIR.length.name) OR (ResolveProcedure(current, id, parDes.arguments.Length()) # NIL) THEN
					NEW(functionCall, id.pos, id); functionCall.SetOuter(des.outer);
					FOR i := 0 TO parDes.arguments.Length()-1 DO
						arg := parDes.arguments.GetExpression(i);
						arg.SetOuter(NIL);
						functionCall.arguments.Add(arg)
					END;
					CheckFunctionCall(current, functionCall);
					RETURN functionCall
				END
			END
		END;
		IF (des IS CCIR.IdentifierDesignator) & (ResolveConstant(current, des(CCIR.IdentifierDesignator).identifier) # NIL) THEN
			RETURN CheckConstantDesignator(current, des)
		ELSE
			RETURN CheckInstanceDesignator(current, des)
		END
	END CheckDesignatorExpression;
	
	PROCEDURE CheckCollectionDesignator(current: CCIR.Node; des: CCIR.Designator): CCIR.Variable;
	VAR var: CCIR.Variable;
	BEGIN
		var := NIL;
		IF des IS CCIR.IdentifierDesignator THEN
			var := ResolveVariable(current, des(CCIR.IdentifierDesignator).identifier);
			IF var = NIL THEN
				Error(des.pos, "Undefined collection variable")
			ELSIF var.parameters.Length() = 0 THEN
				Error(des.pos, "No collection variable designated")
			ELSE
				des.SetDesignatedNode(var);
				des.SetType(var.type)
			END
		ELSE 
			Error(des.pos, "Invalid designator of collection variable")
		END;
		RETURN var
	END CheckCollectionDesignator;
	
	PROCEDURE IsCollectionDesignator(current: CCIR.Node; des: CCIR.Designator): BOOLEAN;
	VAR var: CCIR.Variable;
	BEGIN
		IF des IS CCIR.IdentifierDesignator THEN
			var := ResolveVariable(current, des(CCIR.IdentifierDesignator).identifier);
			RETURN (var # NIL) & (var.parameters.Length() > 0 )
		ELSE 
			RETURN FALSE
		END
	END IsCollectionDesignator;
	
	PROCEDURE CheckInstanceDesignator(current: CCIR.Node; des: CCIR.Designator): CCIR.Designator;
	VAR parDes: CCIR.ParameterDesignator; var: CCIR.Variable; index: CCIR.IndexDesignator; expr: CCIR.Expression; 
		guard: CCIR.GuardDesignator; id: CCIR.Identifier; ct: CCIR.ComponentType;
	BEGIN
		IF des IS CCIR.ParameterDesignator THEN
			parDes := des(CCIR.ParameterDesignator);
			IF parDes.arguments.Length() = 1 THEN
				expr := parDes.arguments.GetExpression(0);
				IF expr IS CCIR.IdentifierDesignator THEN
					id := expr(CCIR.IdentifierDesignator).identifier;
					IF ResolveComponent(current, id) # NIL THEN
						NEW(ct, id.pos, id);
						parDes.left.SetOuter(NIL);
						NEW(guard, id.pos, parDes.left, ct);
						CheckGuardDesignator(current, guard);
						des := guard
					ELSE Error(expr.pos, "Undefined component type")
					END
				ELSE Error(expr.pos, "Invalid type guard")
				END
			ELSE Error(des.pos, "Undefined designator")
			END
		ELSIF des IS CCIR.IdentifierDesignator THEN
			var := ResolveVariable(current, des(CCIR.IdentifierDesignator).identifier);
			IF var # NIL THEN
				IF var.parameters.Length() > 0 THEN
					Error(des.pos, "No collection element")
				ELSE
					des.SetDesignatedNode(var);
					des.SetType(var.type)
				END
			ELSE Error(des.pos, "Undefined designator") 
			END
		ELSIF des IS CCIR.IndexDesignator THEN
			index := des(CCIR.IndexDesignator);
			CheckExpressionList(current, index.arguments);
			IF index.left IS CCIR.IdentifierDesignator THEN
				var := ResolveVariable(current, index.left(CCIR.IdentifierDesignator).identifier);
				IF var = NIL THEN
					Error(des.pos, "Undefined designator")
				ELSIF var.parameters.Length() = 0 THEN
					index.SetLeft(CheckInstanceDesignator(current, index.left));
					IF index.left.type = CCIR.textType THEN
						IF index.arguments.Length() = 1 THEN
							CheckDataType(index.arguments.GetExpression(0), CCIR.integerType);
							des.SetType(CCIR.characterType);
							des.SetDesignatedNode(var)
						ELSE Error(des.pos, "Illegal character selection")
						END
					ELSE Error(des.pos, "Inapplicable element selection")
					END
				ELSE
					var := CheckCollectionDesignator(current, index.left);
					IF var # NIL THEN
						CheckParameterCompatibility(current, TRUE, index.arguments, var.parameters);
						des.SetType(var.type);
						des.SetDesignatedNode(var)
					END
				END
			ELSE Error(index.left.pos, "Undefined designator")
			END
		ELSIF des IS CCIR.GuardDesignator THEN
			CheckGuardDesignator(current, des(CCIR.GuardDesignator))
		ELSE HALT(111)
		END;
		RETURN des
	END CheckInstanceDesignator;
	
	PROCEDURE CheckGuardDesignator(current: CCIR.Node; des: CCIR.GuardDesignator);
	BEGIN
		des.SetLeft(CheckInstanceDesignator(current, des.left));
		IF des.left IS CCIR.Designator THEN
			des.SetDesignatedNode(des.left(CCIR.Designator).node)
		END;
		CheckType(current, des.type);
		des.SetType(des.type);
		CollectType(current, des.type)
	END CheckGuardDesignator;
	
	PROCEDURE GetTempVariable(current: CCIR.Node): CCIR.Variable;
	VAR index: LONGINT; scope: CCIR.Node; list: CCIR.VariableList; name: CCBasic.String; id: CCIR.Identifier; var: CCIR.Variable;
	BEGIN
		GetVariableScope(current, scope, list);
		IF (current IS CCIR.Procedure) OR (current IS CCIR.Implementation) OR (current IS CCIR.Component) THEN
			index := 0
		ELSIF (current IS CCIR.ForStatement) OR (current IS CCIR.ForeachStatement) THEN
			index := TempVariableIndex(current)
		ELSE HALT(111)
		END;
		name := CCBasic.ConcatWithNumber(CCIR.HiddenNamePrefix, index);
		id := CCIR.NewIdentifier(-1, name^);
		var := list.FindVariable(id);
		IF var = NIL THEN
			var := CCIR.NewVariable(-1, scope, id); var.SetType(CCIR.integerType)
		ELSE ASSERT(var.type = CCIR.integerType)
		END;
		RETURN var
	END GetTempVariable;
	
	PROCEDURE TempVariableIndex(current: CCIR.Node): LONGINT;
	VAR index: LONGINT;
	BEGIN
		ASSERT((current IS CCIR.ForStatement) OR (current IS CCIR.ForeachStatement));
		current := current(CCIR.Statement).outer;
		index := 0;
		WHILE (current # NIL) & (current IS CCIR.Statement) DO
			IF (current IS CCIR.ForStatement) OR (current IS CCIR.ForeachStatement) THEN
				INC(index)
			END;
			current := current(CCIR.Statement).outer
		END;
		ASSERT((current IS CCIR.Component) OR (current IS CCIR.Implementation) OR (current IS CCIR.Procedure));
		RETURN index
	END TempVariableIndex;
	
	PROCEDURE GetVariableScope(current: CCIR.Node; VAR scope: CCIR.Node; VAR variableList: CCIR.VariableList);
	BEGIN
		WHILE (current # NIL) & (current IS CCIR.Statement) DO
			current := current(CCIR.Statement).outer
		END;
		scope := current;
		IF current IS CCIR.Component THEN
			variableList := current(CCIR.Component).variables
		ELSIF current IS CCIR.Implementation THEN
			variableList := current(CCIR.Implementation).variables
		ELSIF current IS CCIR.Procedure THEN
			variableList := current(CCIR.Procedure).variables
		ELSE HALT(111)
		END
	END GetVariableScope;
	
	PROCEDURE InExclusiveRegion(current: CCIR.Node): BOOLEAN;
	BEGIN RETURN CCIR.CurrentLockType(current) = CCIR.exclusive
	END InExclusiveRegion;
	
	PROCEDURE InSharedRegion(current: CCIR.Node): BOOLEAN;
	BEGIN RETURN CCIR.CurrentLockType(current) = CCIR.shared
	END InSharedRegion;
		
	PROCEDURE CheckProtectionForList(list: CCIR.ExpressionList; lockType: CCIR.Identifier);
	VAR i: LONGINT; expr: CCIR.Expression;
	BEGIN
		FOR i := 0 TO list.Length()-1 DO
			expr := list.GetExpression(i);
			CheckProtection(expr, lockType)
		END
	END CheckProtectionForList;
	
	PROCEDURE EnforceProtection(pos: LONGINT; current: CCIR.Node; lockType: CCIR.Identifier);
	VAR l: CCIR.Identifier; proc: CCIR.Procedure;
	BEGIN
		l := CCIR.CurrentLockType(current);
		IF CCIR.InInitializerOrFinalizer(current) THEN l := CCIR.exclusive END;
		IF (l = NIL) OR ((l = CCIR.shared) & (lockType = CCIR.exclusive)) THEN
			proc := CCIR.GetSurroundingProcedure(current);
			IF (proc = NIL) OR (l # NIL) THEN
				IF lockType = CCIR.exclusive THEN
					Error(pos, "must be used in an EXCLUSIVE region")
				ELSE
					Error(pos, "must be used in at least a SHARED region")
				END
			ELSE
				IF (lockType = CCIR.exclusive) & (proc.requiredProtection # CCIR.exclusive) THEN
					proc.requiredProtection := CCIR.exclusive
				ELSIF (lockType = CCIR.shared) & (proc.requiredProtection = NIL) THEN
					proc.requiredProtection := CCIR.shared
				END
			END
		END
	END EnforceProtection;
	
	PROCEDURE CheckProtection(expr: CCIR.Expression; lockType: CCIR.Identifier);
	VAR var: CCIR.Variable; des: CCIR.Designator; intDes: CCIR.InterfaceDesignator; 
	BEGIN
		IF CheckSynchronization THEN
			IF expr = NIL THEN (* do nothing *)
			ELSIF expr IS CCIR.Designator THEN
				des := expr(CCIR.Designator);
				IF des IS CCIR.IdentifierDesignator THEN
					IF (des.node # NIL) & (des.node IS CCIR.Variable) THEN
						var := des.node(CCIR.Variable);
						IF (var.scope # NIL) & (var.scope IS CCIR.Component) THEN
							EnforceProtection(des.pos, expr, lockType)
						END
					END
				ELSIF des IS CCIR.IndexDesignator THEN
					CheckProtection(des(CCIR.IndexDesignator).left, lockType);
					CheckProtectionForList(des(CCIR.IndexDesignator).arguments, CCIR.shared)
				ELSIF des IS CCIR.ParameterDesignator THEN
					CheckProtection(des(CCIR.ParameterDesignator).left, lockType);
					CheckProtectionForList(des(CCIR.ParameterDesignator).arguments, lockType)
				ELSIF des IS CCIR.GuardDesignator THEN
					CheckProtection(des(CCIR.GuardDesignator).left, lockType)
				ELSIF des IS CCIR.InterfaceDesignator THEN
					intDes := des(CCIR.InterfaceDesignator);
					CheckProtection(intDes.index, CCIR.shared);
					IF intDes IS CCIR.InternalInterfaceDesignator THEN
						CheckProtection(intDes(CCIR.InternalInterfaceDesignator).variableDes, lockType)
					END
				ELSE HALT(111)
				END
			ELSIF expr IS CCIR.BinaryExpression THEN
				CheckProtection(expr(CCIR.BinaryExpression).left, lockType);
				CheckProtection(expr(CCIR.BinaryExpression).right, lockType)
			ELSIF expr IS CCIR.UnaryExpression THEN
				CheckProtection(expr(CCIR.UnaryExpression).sub, lockType)
			ELSIF expr IS CCIR.InterfaceTest THEN
				CheckProtection(expr(CCIR.InterfaceTest).left, lockType)
			ELSIF expr IS CCIR.TypeTest THEN
				CheckProtection(expr(CCIR.TypeTest).left, lockType)
			ELSIF expr IS CCIR.FunctionCall THEN
				CheckProtectionForList(expr(CCIR.FunctionCall).arguments, lockType)
			ELSIF expr IS CCIR.InputFunction THEN
				des := expr(CCIR.InputFunction).interfaceDesignator;
				IF des IS CCIR.InternalInterfaceDesignator THEN
					CheckProtection(intDes, CCIR.shared)
				ELSE
					CheckProtection(intDes, CCIR.exclusive)
				END
			ELSIF expr IS CCIR.ReceiveTestFunction THEN
				des := expr(CCIR.ReceiveTestFunction).interfaceDesignator;
				IF des IS CCIR.InternalInterfaceDesignator THEN
					CheckProtection(intDes, CCIR.shared)
				ELSE
					CheckProtection(intDes, CCIR.exclusive)
				END
			ELSE
				ASSERT((expr IS CCIR.TextValue) OR (expr IS CCIR.IntegerValue) OR 
					(expr IS CCIR.RealValue) OR (expr IS CCIR.CharacterValue) OR (expr IS CCIR.BooleanValue))
			END
		END
	END CheckProtection;
	
	PROCEDURE CheckInterproceduralProtection(com: CCIR.Component);
	VAR hasChanged: BOOLEAN;
	BEGIN
		IF CheckSynchronization THEN
			REPEAT
				hasChanged := FALSE;
				CalculateProtectionForComponent(com, hasChanged)
			UNTIL ~hasChanged;
			CheckProtectionForComponent(com)
		END
	END CheckInterproceduralProtection;
	
	PROCEDURE CalculateProtectionForComponent(com: CCIR.Component; VAR hasChanged: BOOLEAN);
	VAR i: LONGINT; impl: CCIR.Implementation;
	BEGIN
		CalculateProtectionForProcList(com.procedures, hasChanged);
		FOR i := 0 TO com.implementations.Length()-1 DO
			impl := com.implementations.GetImplementation(i);
			CalculateProtectionForProcList(impl.nestedProcedures, hasChanged)
		END
	END CalculateProtectionForComponent;
	
	PROCEDURE CalculateProtectionForProcList(list: CCIR.ProcedureList; VAR hasChanged: BOOLEAN);
	VAR i: LONGINT; proc: CCIR.Procedure;
	BEGIN
		FOR i := 0 TO list.Length()-1 DO
			proc := list.GetProcedure(i);
			CalculateProtectionForProcedure(proc, hasChanged)
		END
	END CalculateProtectionForProcList;
		
	PROCEDURE CalculateProtectionForProcedure(proc: CCIR.Procedure; VAR hasChanged: BOOLEAN);
	VAR i: LONGINT; stat: CCIR.Statement; caller: CCIR.Procedure; callerLock: CCIR.Identifier;
	BEGIN
		CalculateProtectionForProcList(proc.nestedProcedures, hasChanged);
		IF proc.hasProtectedRegion OR (proc.requiredProtection # NIL) THEN
			FOR i := 0 TO proc.callers.Length()-1 DO
				stat := proc.callers.GetStatement(i);
				callerLock := CCIR.CurrentLockType(stat);
				caller := CCIR.GetSurroundingProcedure(stat);
				IF proc.hasProtectedRegion THEN
					IF callerLock # NIL THEN
						Error(stat.pos, "Procedure call may lead to nested locks") 
					ELSIF caller # NIL THEN
						IF ~caller.hasProtectedRegion THEN
							caller.hasProtectedRegion := TRUE;
							hasChanged := TRUE
						END
					END
				END;
				IF caller # NIL THEN
					IF proc.requiredProtection = CCIR.exclusive THEN
						IF (callerLock # CCIR.exclusive) & (caller.requiredProtection # CCIR.exclusive) THEN
							caller.requiredProtection := CCIR.exclusive;
							hasChanged := TRUE
						END
					ELSIF proc.requiredProtection = CCIR.shared THEN
						IF (callerLock = NIL) & (caller.requiredProtection = NIL) THEN
							caller.requiredProtection := CCIR.shared;
							hasChanged := TRUE
						END
					END
				END
			END
		END
	END CalculateProtectionForProcedure;
	
	PROCEDURE CheckProtectionForComponent(com: CCIR.Component);
	VAR i: LONGINT; impl: CCIR.Implementation;
	BEGIN
		CheckProtectionForProcList(com.procedures);
		FOR i := 0 TO com.implementations.Length()-1 DO
			impl := com.implementations.GetImplementation(i);
			CheckProtectionForProcList(impl.nestedProcedures)
		END
	END CheckProtectionForComponent;
	
	PROCEDURE CheckProtectionForProcList(list: CCIR.ProcedureList);
	VAR i: LONGINT; proc: CCIR.Procedure;
	BEGIN
		FOR i := 0 TO list.Length()-1 DO
			proc := list.GetProcedure(i);
			CheckProtectionForProcedure(proc)
		END
	END CheckProtectionForProcList;

	PROCEDURE CheckProtectionForProcedure(proc: CCIR.Procedure);
	VAR i: LONGINT; stat: CCIR.Statement; callerLock: CCIR.Identifier;
	BEGIN
		CheckProtectionForProcList(proc.nestedProcedures);
		IF proc.hasProtectedRegion OR (proc.requiredProtection # NIL) THEN
			FOR i := 0 TO proc.callers.Length()-1 DO
				stat := proc.callers.GetStatement(i);
				IF proc.hasProtectedRegion THEN
					callerLock := CCIR.CurrentLockType(stat);
					IF callerLock # NIL THEN
						Error(stat.pos, "Procedure call may lead to nested locks") 
					END
				END;
				IF proc.requiredProtection # NIL THEN
					EnforceProtection(stat.pos, stat, proc.requiredProtection)
				END
			END
		END
	END CheckProtectionForProcedure;
	
	PROCEDURE RegisterExternalEventForAwait(current: CCIR.Node);
	VAR await: CCIR.AwaitStatement; proc: CCIR.Procedure;
	BEGIN
		await := CCIR.GetSurroundingAwaitStatement(current);
		IF await # NIL THEN await.waitsOnExternalEvent := TRUE END;
		proc := CCIR.GetSurroundingProcedure(current);
		IF proc # NIL THEN proc.waitsOnExternalEvent := TRUE END
	END RegisterExternalEventForAwait;
	
	PROCEDURE MustNotBeInAwait(current: CCIR.Node);
	VAR await: CCIR.AwaitStatement; proc: CCIR.Procedure;
	BEGIN
		await := CCIR.GetSurroundingAwaitStatement(current);
		IF await # NIL THEN Error(current.pos, "Must not be executed in AWAIT-condition") END;
		proc := CCIR.GetSurroundingProcedure(current);
		IF proc # NIL THEN proc.mustNotBeInAwait := TRUE END
	END MustNotBeInAwait;
	
	PROCEDURE CheckAwaitDependencies(component: CCIR.Component);
	VAR i: LONGINT; proc: CCIR.Procedure; hasChanged: BOOLEAN;
	BEGIN
		REPEAT
			hasChanged := FALSE;
			FOR i := 0 TO component.procedures.Length()-1 DO
				proc := component.procedures.GetProcedure(i);
				PropagateAwaitDependencies(proc, hasChanged)
			END
		UNTIL ~hasChanged;
		FOR i := 0 TO component.procedures.Length()-1 DO
			proc := component.procedures.GetProcedure(i);
			CheckAwaitDependenciesForProc(proc)
		END
	END CheckAwaitDependencies;
	
	PROCEDURE PropagateAwaitDependencies(proc: CCIR.Procedure; VAR hasChanged: BOOLEAN);
	VAR i: LONGINT; stat: CCIR.Statement; caller: CCIR.Procedure; 
	BEGIN
		IF proc.waitsOnExternalEvent OR proc.mustNotBeInAwait THEN
			FOR i := 0 TO proc.callers.Length()-1 DO
				stat := proc.callers.GetStatement(i);
				caller := CCIR.GetSurroundingProcedure(stat);
				IF caller # NIL THEN
					IF proc.waitsOnExternalEvent & ~caller.waitsOnExternalEvent THEN
						caller.waitsOnExternalEvent := TRUE; hasChanged := TRUE
					END;
					IF proc.mustNotBeInAwait & ~caller.mustNotBeInAwait THEN
						caller.mustNotBeInAwait := TRUE; hasChanged := TRUE
					END
				END
			END
		END
	END PropagateAwaitDependencies;
	
	PROCEDURE CheckAwaitDependenciesForProc(proc: CCIR.Procedure);
	VAR i: LONGINT; stat: CCIR.Statement; await: CCIR.AwaitStatement;
	BEGIN
		IF proc.waitsOnExternalEvent OR proc.mustNotBeInAwait THEN
			FOR i := 0 TO proc.callers.Length()-1 DO
				stat := proc.callers.GetStatement(i);
				await := CCIR.GetSurroundingAwaitStatement(stat);
				IF await # NIL THEN
					IF proc.waitsOnExternalEvent THEN await.waitsOnExternalEvent := TRUE END;
					IF proc.mustNotBeInAwait THEN Error(stat.pos, "Must not be executed in AWAIT-condition") END
				END
			END
		END
	END CheckAwaitDependenciesForProc;
		
	PROCEDURE HasRequiredInterfaces(type: CCIR.Type): BOOLEAN;
	VAR required: CCIR.InterfaceDeclarationList;
	BEGIN 
		required := CCIR.RequiredInterfaces(type); 
		IF required # NIL THEN RETURN required.Length() > 0
		ELSE RETURN FALSE
		END
	END HasRequiredInterfaces;
		
	PROCEDURE Error(pos: LONGINT; text: ARRAY OF CHAR);
	BEGIN error := TRUE; CCBasic.Error(pos, text)
	END Error;
	
	PROCEDURE Error2(pos: LONGINT; x, y: ARRAY OF CHAR);
	BEGIN error := TRUE; CCBasic.Error3(pos, x, y, "")
	END Error2;
	
	PROCEDURE Error3(pos: LONGINT; x, y, z: ARRAY OF CHAR);
	BEGIN error := TRUE; CCBasic.Error3(pos, x, y, z)
	END Error3;
END CCChecker.

