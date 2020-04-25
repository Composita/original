MODULE CCIR; (* Component Compiler, Intermediate Representation, 2005-2007 by Luc Blaeser *)
	IMPORT CCBasic;
	
	CONST 
		(* values of Operator *)
		Minus* = 1;
		Plus* = 2;
		Times* = 3;
		RealDivision* = 4; (** /*)
		IntegerDivision* = 5; (** DIV *)
		Modulo* = 6;
		Not* = 7; (* ~ *)
		And* = 8;
		Or* = 9;
		Equal* = 10;
		Unequal* = 11;
		Less* = 12;
		Greater* = 13;
		LessEqual* = 14;
		GreaterEqual* = 15;
		
		(* predefined communication messages *)
		AnyMessage* = "ANY";
		FinishMessage* = "FINISH";
		
		HiddenNamePrefix* = "@";
		
		Infinite* = MAX(LONGINT);
		
	TYPE
		(** Intermediate representation *)
		
		Node* = OBJECT
			VAR 
				pos-: LONGINT;
				attributeList-: IdentifierList;
			
			PROCEDURE &InitNode(position: LONGINT);
			BEGIN pos := position; attributeList := NIL
			END InitNode;
			
			PROCEDURE SetAttributeList*(x: IdentifierList);
			BEGIN attributeList := x
			END SetAttributeList;
						
			PROCEDURE Print*;
			BEGIN HALT(104) (* abstract *)
			END Print;
		END Node;
		
		IdentifierList* = OBJECT(CCBasic.List)
			PROCEDURE Add*(x: PTR);
			BEGIN ASSERT(x IS Identifier); Add^(x)
			END Add;
			
			PROCEDURE GetIdentifier*(index: LONGINT): Identifier;
			VAR ptr: PTR;
			BEGIN ptr := GetItem(index); RETURN ptr(Identifier)
			END GetIdentifier;
			
			(** -1 if not present *)
			PROCEDURE IndexOf*(identifier: PTR): LONGINT;
			VAR i: LONGINT; x: Identifier;
			BEGIN
				FOR i := 0 TO Length()-1 DO
					x := GetIdentifier(i);
					IF x.Equal(identifier(Identifier)) THEN RETURN i END
				END;
				RETURN -1
			END IndexOf;
			
			PROCEDURE Contains*(identifier: PTR): BOOLEAN;
			BEGIN RETURN IndexOf(identifier) >= 0
			END Contains;
			
			PROCEDURE Copy*(): IdentifierList;
			VAR copy: IdentifierList; i: LONGINT; x: Identifier;
			BEGIN
				NEW(copy); 
				FOR i := 0 TO Length()-1 DO 
					x := GetIdentifier(i);
					copy.Add(x.Copy())
				END;
				RETURN copy
			END Copy;
			
			PROCEDURE Print*;
			VAR i: LONGINT; id: Identifier;
			BEGIN
				FOR i := 0 TO Length()-1 DO
					id := GetIdentifier(i); id.Print;
					IF i < Length()-1 THEN CCBasic.OutText(", ") END
				END
			END Print;			
		END IdentifierList;
		
		(** Identifier or QualifiedIdentifier *)
		Identifier* = OBJECT(Node)
			VAR 
				name-: CCBasic.String;
				target-: Node; (** identified element *)
			
			PROCEDURE &InitIdentifier(position: LONGINT; id: ARRAY OF CHAR);
			BEGIN InitNode(position); name := CCBasic.NewString(id); target := NIL
			END InitIdentifier;
			
			PROCEDURE SetTarget*(x: Node);
			BEGIN target := x
			END SetTarget;
			
			PROCEDURE Equal*(x: Identifier): BOOLEAN;
			BEGIN RETURN name^ = x.name^
			END Equal;
			
			PROCEDURE EqualText*(x: ARRAY OF CHAR): BOOLEAN;
			BEGIN RETURN name^ = x
			END EqualText;
						
			PROCEDURE Copy*(): Identifier;
			VAR x: Identifier;
			BEGIN NEW(x, pos, name^); RETURN x
			END Copy;
			
			PROCEDURE Print*;
			BEGIN CCBasic.OutText(name^)
			END Print;
		END Identifier;
				
		ComponentDefinitionList* = OBJECT(CCBasic.List)
			PROCEDURE Add*(x: PTR);
			BEGIN ASSERT(x IS ComponentDefinition); Add^(x)
			END Add;
			
			PROCEDURE GetComponentDefinition*(index: LONGINT): ComponentDefinition;
			VAR ptr: PTR;
			BEGIN ptr := GetItem(index); RETURN ptr(ComponentDefinition)
			END GetComponentDefinition;
			
			(* NIL if not present *)
			PROCEDURE FindComponentDefinition*(name: Identifier): ComponentDefinition;
			VAR i: LONGINT; c: ComponentDefinition;
			BEGIN
				FOR i := 0 TO Length()-1 DO
					c := GetComponentDefinition(i);
					IF c.name.Equal(name) THEN RETURN c END
				END;
				RETURN NIL
			END FindComponentDefinition;
			
			PROCEDURE Print*;
			VAR i: LONGINT; c: ComponentDefinition;
			BEGIN
				FOR i := 0 TO Length()-1 DO
					c := GetComponentDefinition(i); c.Print; CCBasic.OutLine
				END
			END Print;
		END ComponentDefinitionList;
		
		InterfaceDeclaration* = OBJECT(Node)
			VAR
				name-: Identifier;
				interface-: Interface; (** resolved by semantic checker *)
				minNumber-, maxNumber-: LONGINT; (* "*" = Infinite *)
				
			PROCEDURE &InitInterfaceDeclaration(position: LONGINT; id: Identifier; min, max: LONGINT);
			BEGIN 
				InitNode(position); name := id; interface := NIL;
				minNumber := min; maxNumber := max
			END InitInterfaceDeclaration;
			
			PROCEDURE SetInterface*(x: Interface);
			BEGIN interface := x
			END SetInterface;
			
			PROCEDURE Equal*(x: InterfaceDeclaration): BOOLEAN;
			BEGIN
				RETURN name.Equal(x.name) & (interface = x.interface) & 
					(minNumber = x.minNumber) & (maxNumber = x.maxNumber)
			END Equal;
			
			PROCEDURE Copy*(): InterfaceDeclaration;
			VAR x: InterfaceDeclaration;
			BEGIN NEW(x, pos, name, minNumber, maxNumber); x.interface := interface; RETURN x
			END Copy;
			
			PROCEDURE Print*;
			BEGIN 
				name.Print; 
				IF (minNumber # 1) OR (maxNumber # 1) THEN
					CCBasic.OutText("["); CCBasic.OutInteger(minNumber); CCBasic.OutText(" .. "); 
					IF maxNumber = Infinite THEN CCBasic.OutText("*") ELSE CCBasic.OutInteger(maxNumber) END;
					CCBasic.OutText(" ]")
				END
			END Print;
		END InterfaceDeclaration;
		
		InterfaceDeclarationList* = OBJECT(CCBasic.List)
			PROCEDURE Add*(x: PTR);
			BEGIN ASSERT(x IS InterfaceDeclaration); Add^(x)
			END Add;
			
			PROCEDURE GetInterfaceDeclaration*(index: LONGINT): InterfaceDeclaration;
			VAR ptr: PTR;
			BEGIN ptr := GetItem(index); RETURN ptr(InterfaceDeclaration)
			END GetInterfaceDeclaration;
			
			PROCEDURE FindInterfaceDeclaration*(name: Identifier): InterfaceDeclaration;
			VAR i: LONGINT; x: InterfaceDeclaration;
			BEGIN
				FOR i := 0 TO Length()-1 DO
					x := GetInterfaceDeclaration(i);
					IF x.name.Equal(name) THEN RETURN x END
				END;
				RETURN NIL
			END FindInterfaceDeclaration;
						
			PROCEDURE IndexOf*(b: PTR): LONGINT;
			VAR i: LONGINT; a: InterfaceDeclaration;
			BEGIN
				FOR i := 0 TO Length()-1 DO
					a := GetInterfaceDeclaration(i);
					IF a.Equal(b(InterfaceDeclaration)) THEN RETURN i END
				END;
				RETURN -1
			END IndexOf;
			
			PROCEDURE Equal*(list: InterfaceDeclarationList): BOOLEAN;
			VAR i: LONGINT; x, y: InterfaceDeclaration;
			BEGIN
				IF Length() = list.Length() THEN
					FOR i := 0 TO Length()-1 DO
						x := GetInterfaceDeclaration(i); y := list.GetInterfaceDeclaration(i);
						IF ~x.Equal(y) THEN RETURN FALSE END
					END;
					RETURN TRUE
				ELSE RETURN FALSE
				END
			END Equal;
			
			PROCEDURE Copy*(): InterfaceDeclarationList;
			VAR list: InterfaceDeclarationList; i: LONGINT; x, y: InterfaceDeclaration;
			BEGIN
				NEW(list);
				FOR i := 0 TO Length()-1 DO
					x := GetInterfaceDeclaration(i); y := x.Copy();
					list.Add(y)
				END;
				RETURN list
			END Copy;
			
			PROCEDURE Print*;
			VAR i: LONGINT; x: InterfaceDeclaration;
			BEGIN
				FOR i := 0 TO Length()-1 DO
					x := GetInterfaceDeclaration(i); x.Print; CCBasic.OutLine
				END
			END Print;
		END InterfaceDeclarationList;
		
		ComponentDefinition* = OBJECT(Node)
			VAR
				name-: Identifier;
				offeredInterfaces-, requiredInterfaces-: InterfaceDeclarationList;
				
			PROCEDURE &InitComponentDefinition(position: LONGINT; id: Identifier);
			BEGIN
				InitNode(position); name := id; 
				NEW(offeredInterfaces); NEW(requiredInterfaces)
			END InitComponentDefinition;
			
			PROCEDURE QualIdent*(): Identifier;
			BEGIN RETURN name
			END QualIdent;
			
			PROCEDURE Print*;
			BEGIN 
				Indent; CCBasic.OutText("COMPONENT "); name.Print; 
				IF offeredInterfaces.Length() > 0 THEN CCBasic.OutText(" OFFERS "); offeredInterfaces.Print END;
				IF requiredInterfaces.Length() > 0 THEN CCBasic.OutText(" REQUIRES "); requiredInterfaces.Print END;
				CCBasic.OutText(";"); CCBasic.OutLine;
			END Print;
		END ComponentDefinition;
				
		ComponentList* = OBJECT(CCBasic.List)
			PROCEDURE Add*(x: PTR);
			BEGIN ASSERT(x IS Component); Add^(x)
			END Add;
		
			PROCEDURE GetComponent*(index: LONGINT): Component;
			VAR ptr: PTR;
			BEGIN ptr := GetItem(index); RETURN ptr(Component)
			END GetComponent;
			
			(* NIL if not present *)
			PROCEDURE FindComponent*(name: Identifier): Component;
			VAR i: LONGINT; c: Component;
			BEGIN
				FOR i := 0 TO Length()-1 DO
					c := GetComponent(i);
					IF c.name.Equal(name) THEN RETURN c END
				END;
				RETURN NIL
			END FindComponent;
			
			PROCEDURE Print*;
			VAR i: LONGINT; c: Component;
			BEGIN
				FOR i := 0 TO Length()-1 DO
					c := GetComponent(i); c.Print; CCBasic.OutLine
				END
			END Print;
		END ComponentList;
				
		Component* = OBJECT(ComponentDefinition)
			VAR
				outer-: Node; (** NIL if outmost component *)
				usedCommunications-: InterfaceDeclarationList;  
					(** external required interfaces used for communication, resolved by checker *)
				nestedComponents-: ComponentList; 
				nestedInterfaces-: InterfaceList;
				constants-: ConstantList;
				variables-: VariableList;
				implementations-: ImplementationList;
				procedures-: ProcedureList;
				initializer-: StatementSequence;
				activity-: StatementSequence;
				finalizer-: StatementSequence;
				
				(** external dependencies to declaration *)
				usedComponents-: ComponentDefinitionList;
				usedInterfaces-: InterfaceList;
								
			PROCEDURE &InitComponent(position: LONGINT; scope: Node; id: Identifier);
			BEGIN 
				InitComponentDefinition(position, id); outer := scope; 
				NEW(usedCommunications);
				NEW(nestedComponents); NEW(nestedInterfaces);
				NEW(constants); NEW(variables); 
				NEW(implementations); NEW(procedures);
				NEW(initializer, position, SELF); 
				NEW(activity, position, SELF);
				NEW(finalizer, position, SELF);
				IF scope = NIL THEN NEW(usedComponents); NEW(usedInterfaces)
				ELSE usedComponents := NIL; usedInterfaces := NIL
				END
			END InitComponent;
			
			PROCEDURE QualIdent*(): Identifier;
			BEGIN RETURN MakeQualIdent(outer, name)
			END QualIdent;
			
			PROCEDURE Print*;
			BEGIN
				Print^;
				INC(indent); constants.Print; variables.Print; implementations.Print; procedures.Print; DEC(indent);
				Indent; CCBasic.OutText("INITIALIZE "); INC(indent); initializer.Print; DEC(indent);
				Indent; CCBasic.OutText("BEGIN "); INC(indent); activity.Print; DEC(indent);
				Indent; CCBasic.OutText("FINALIZE "); INC(indent); finalizer.Print; DEC(indent);
				Indent; CCBasic.OutText("END "); name.Print; CCBasic.OutText(";"); CCBasic.OutLine
			END Print;
		END Component;
		
		Type* = OBJECT(Node)
			(** abstract *)
			PROCEDURE &InitType(position: LONGINT);
			BEGIN InitNode(position)
			END InitType;
			
			PROCEDURE Copy*(): Type;
			BEGIN HALT(99) (* abstract *)
			END Copy;
			
			PROCEDURE Equal*(x: Type): BOOLEAN;
			BEGIN HALT(99) (* abstract *)
			END Equal;
		END Type;
		
		(** INTEGER, REAL, BOOLEAN, CHARACTER, TEXT *)
		DataType* = OBJECT(Type)
			VAR name-: Identifier;
		
			PROCEDURE &InitDataType(x: ARRAY OF CHAR);
			BEGIN InitType(-1); NEW(name, -1, x)
			END InitDataType;
			
			PROCEDURE Copy*(): Type;
			BEGIN RETURN SELF
			END Copy;
			
			PROCEDURE Equal*(x: Type): BOOLEAN;
			BEGIN RETURN x = SELF
			END Equal;
			
			PROCEDURE Print*;
			BEGIN name.Print
			END Print;
		END DataType;
		
		ComponentType* = OBJECT(Type)
			VAR 
				componentName-: Identifier;
				componentDefinition-: ComponentDefinition; (** resolved by semantic checker *)
			
			PROCEDURE &InitComponentType*(position: LONGINT; id: Identifier);
			BEGIN InitType(position); componentName := id; componentDefinition := NIL
			END InitComponentType;
			
			PROCEDURE SetComponentDefinition*(c: ComponentDefinition);
			BEGIN componentDefinition := c
			END SetComponentDefinition;
			
			PROCEDURE Copy*(): Type;
			VAR copy: ComponentType;
			BEGIN 
				NEW(copy, pos, componentName.Copy()); 
				copy.componentDefinition := componentDefinition;
				RETURN copy
			END Copy;
			
			PROCEDURE Equal*(x: Type): BOOLEAN;
			BEGIN
				IF componentDefinition = NIL THEN RETURN FALSE END; (* must already be resolved by checker *)
				IF x IS ComponentType THEN
					RETURN x(ComponentType).componentDefinition = componentDefinition
				ELSE
					RETURN FALSE
				END
			END Equal;
			
			PROCEDURE Print*;
			BEGIN componentName.Print
			END Print;
		END ComponentType;
		
		AnyType* = OBJECT(Type)
			VAR 
				offeredInterfaces-, requiredInterfaces-: InterfaceDeclarationList; 
			
			PROCEDURE &InitAnyType*(position: LONGINT);
			BEGIN 
				InitType(position); 
				NEW(offeredInterfaces); NEW(requiredInterfaces)
			END InitAnyType;
			
			PROCEDURE Copy*(): Type;
			VAR copy: AnyType; i: LONGINT;
			BEGIN
				NEW(copy, pos);
				copy.offeredInterfaces := offeredInterfaces.Copy();
				copy.requiredInterfaces := requiredInterfaces.Copy();
				RETURN copy
			END Copy;
			
			PROCEDURE Equal*(x: Type): BOOLEAN;
			VAR at: AnyType; i: LONGINT;
			BEGIN
				IF x IS AnyType THEN
					at := x(AnyType);
					RETURN offeredInterfaces.Equal(at.offeredInterfaces) & requiredInterfaces.Equal(at.requiredInterfaces)
				ELSE
					RETURN FALSE
				END
			END Equal;
			
			PROCEDURE Print*;
			BEGIN 
				CCBasic.OutText("ANY("); offeredInterfaces.Print; 
				IF requiredInterfaces.Length() > 0 THEN CCBasic.OutText("| "); requiredInterfaces.Print END;
				CCBasic.OutText(")")
			END Print;
		END AnyType;
		
		InterfaceList* = OBJECT(CCBasic.List)
			PROCEDURE Add*(x: PTR);
			BEGIN ASSERT(x IS Interface); Add^(x)
			END Add;
		
			PROCEDURE GetInterface*(index: LONGINT): Interface;
			VAR ptr: PTR;
			BEGIN ptr := GetItem(index); RETURN ptr(Interface)
			END GetInterface;
			
			(** NIL if not present *)
			PROCEDURE FindInterface*(name: Identifier): Interface;
			VAR i: LONGINT; x: Interface;
			BEGIN
				FOR i := 0 TO Length()-1 DO
					x := GetInterface(i); 
					IF x.name.Equal(name) THEN RETURN x END
				END;
				RETURN NIL
			END FindInterface;
			
			PROCEDURE Equal*(x: InterfaceList): BOOLEAN;
			VAR i: LONGINT; a, b: Interface;
			BEGIN
				IF x.Length() = Length() THEN
					FOR i := 0 TO Length()-1 DO
						a := GetInterface(i); b := x.GetInterface(i);
						IF a # b THEN RETURN FALSE END
					END;
					RETURN TRUE
				ELSE RETURN FALSE
				END
			END Equal;
			
			PROCEDURE Print*;
			VAR i: LONGINT; x: Interface;
			BEGIN
				FOR i := 0 TO Length()-1 DO
					x := GetInterface(i); x.Print
				END
			END Print;
		END InterfaceList;

		Interface* = OBJECT(Node)
			VAR
				outer-: Node; (** NIL if outmost interface *)
				name-: Identifier;
				protocol-: Protocol; (** NIL if empty *)
				messageDeclarations-: MessageDeclarationList; (** list of messages for convenient access *)
		
			PROCEDURE &InitInterface(position: LONGINT; scope: Node; id: Identifier);
			BEGIN 
				InitNode(position); 
				outer := scope; name := id; protocol := NIL; 
				NEW(messageDeclarations)
			END InitInterface;
			
			PROCEDURE QualIdent*(): Identifier;
			BEGIN RETURN MakeQualIdent(outer, name)
			END QualIdent;
			
			PROCEDURE SetProtocol*(p: Protocol);
			BEGIN protocol := p
			END SetProtocol;
			
			PROCEDURE Print*;
			BEGIN
				Indent; CCBasic.OutText("INTERFACE "); name.Print; CCBasic.OutText(";"); CCBasic.OutLine;
				IF protocol # NIL THEN INC(indent); protocol.Print; DEC(indent); CCBasic.OutLine END;
				Indent; CCBasic.OutText("END "); name.Print; CCBasic.OutText(";"); CCBasic.OutLine
			END Print;
		END Interface;
		
		(** communication protocol *)
		Protocol* = OBJECT(Node)
			(** abstract *)
			PROCEDURE &InitProtocol(position: LONGINT);
			BEGIN InitNode(position)
			END InitProtocol;
		END Protocol;
		
		MessageDeclarationList* = OBJECT(CCBasic.List)
			PROCEDURE Add*(x: PTR);
			BEGIN ASSERT(x IS MessageDeclaration); Add^(x)
			END Add;
			
			PROCEDURE GetMessageDeclaration*(index: LONGINT): MessageDeclaration;
			VAR ptr: PTR;
			BEGIN ptr := GetItem(index); RETURN ptr(MessageDeclaration)
			END GetMessageDeclaration;
			
			(** NIL if not present *)
			PROCEDURE FindMessageDeclaration*(name: Identifier): MessageDeclaration;
			VAR i: LONGINT; m: MessageDeclaration;
			BEGIN
				FOR i := 0 TO Length()-1 DO
					m := GetMessageDeclaration(i);
					IF m.name.Equal(name) THEN RETURN m END
				END;
				RETURN NIL
			END FindMessageDeclaration;
			
			(** -1 if not present *)
			PROCEDURE GetIndexOfMessageDeclaration*(name: Identifier): LONGINT;
			VAR i: LONGINT; m: MessageDeclaration;
			BEGIN
				FOR i := 0 TO Length()-1 DO
					m := GetMessageDeclaration(i);
					IF m.name.Equal(name) THEN RETURN i END
				END;
				RETURN -1
			END GetIndexOfMessageDeclaration;
		END MessageDeclarationList;
				
		MessageDeclaration* = OBJECT(Protocol)
			VAR
				name-: Identifier;
				input-: BOOLEAN; (** TRUE = IN; FALSE = OUT *)
				parameters-: ParameterList;
			
			PROCEDURE &InitMessageDeclaration(position: LONGINT; id: Identifier; isInput: BOOLEAN);
			BEGIN InitProtocol(position); name := id; input := isInput; NEW(parameters)
			END InitMessageDeclaration;
			
			PROCEDURE FindMessageDeclaration*(x: Identifier): MessageDeclaration;
			BEGIN IF name.Equal(x) THEN RETURN SELF END
			END FindMessageDeclaration;
			
			PROCEDURE Print*;
			BEGIN
				IF input THEN CCBasic.OutText("IN ") ELSE CCBasic.OutText("OUT ") END; 
				name.Print; parameters.Print
			END Print;
		END MessageDeclaration;
		
		ProtocolSequence* = OBJECT(Protocol)
			VAR first-, second-: Protocol;
			
			PROCEDURE &InitProtocolConcatenation(position: LONGINT; f, s: Protocol);
			BEGIN InitProtocol(position); first := f; second := s
			END InitProtocolConcatenation;
			
			PROCEDURE Print*;
			BEGIN first.Print; CCBasic.OutText(" "); second.Print
			END Print;
		END ProtocolSequence;
		
		ProtocolOption* = OBJECT(Protocol)
			VAR protocol-: Protocol;
			
			PROCEDURE &InitProtocolOption(position: LONGINT; p: Protocol);
			BEGIN InitProtocol(position); protocol := p
			END InitProtocolOption;
			
			PROCEDURE Print*;
			BEGIN CCBasic.OutText(" [ "); protocol.Print; CCBasic.OutText(" ] ")
			END Print;
		END ProtocolOption;
		
		ProtocolRepetition* = OBJECT(Protocol)
			VAR protocol-: Protocol;
			
			PROCEDURE &InitProtocolRepetition(position: LONGINT; p: Protocol);
			BEGIN InitProtocol(position); protocol := p
			END InitProtocolRepetition;
			
			PROCEDURE Print*;
			BEGIN CCBasic.OutText(" { "); protocol.Print; CCBasic.OutText(" } ")
			END Print;
		END ProtocolRepetition;
		
		ProtocolAlternative* = OBJECT(Protocol)
			VAR first-, second-: Protocol;
			
			PROCEDURE &InitProtocolAlternative(position: LONGINT; f, s: Protocol);
			BEGIN InitProtocol(position); first := f; second := s
			END InitProtocolAlternative;
			
			PROCEDURE Print*;
			BEGIN first.Print; CCBasic.OutText(" | "); second.Print
			END Print;
		END ProtocolAlternative;
		
		ImplementationList* = OBJECT(CCBasic.List)
			PROCEDURE Add*(x: PTR);
			BEGIN ASSERT(x IS Implementation); Add^(x)
			END Add;
			
			PROCEDURE GetImplementation*(index: LONGINT): Implementation;
			VAR ptr: PTR;
			BEGIN ptr := GetItem(index); RETURN ptr(Implementation)
			END GetImplementation;
			
			(** NIL if not present *)
			PROCEDURE FindImplementation*(name: Identifier): Implementation;
			VAR i: LONGINT; x: Implementation;
			BEGIN
				FOR i := 0 TO Length()-1 DO
					x := GetImplementation(i);
					IF x.name.Equal(name) THEN RETURN x END
				END;
				RETURN NIL
			END FindImplementation;
			
			PROCEDURE Print*;
			VAR i: LONGINT; x: Implementation;
			BEGIN
				IF Length() > 0 THEN CCBasic.OutLine END;
				FOR i := 0 TO Length()-1 DO
					x := GetImplementation(i);
					x.Print; CCBasic.OutLine
				END
			END Print;
		END ImplementationList;
		
		Implementation* = OBJECT(Node)
			VAR
				outer-: Component;
				name-: Identifier;
				interfaceDecl-: InterfaceDeclaration; (** resolved by semantic checker *)
				nestedComponents-: ComponentList;
				nestedInterfaces-: InterfaceList;
				nestedProcedures-: ProcedureList;
				constants-: ConstantList;
				variables-: VariableList;
				statements-: StatementSequence;
				
			PROCEDURE &InitImplementation(position: LONGINT; scope: Component; id: Identifier);
			BEGIN 
				InitNode(position); outer := scope; name := id; interfaceDecl := NIL; 
				NEW(nestedComponents); NEW(nestedInterfaces); NEW(nestedProcedures);
				NEW(constants); NEW(variables); 
				NEW(statements, position, SELF)
			END InitImplementation;
			
			PROCEDURE SetInterfaceDeclaration*(x: InterfaceDeclaration);
			BEGIN interfaceDecl := x
			END SetInterfaceDeclaration;
			
			PROCEDURE Print*;
			BEGIN
				Indent; CCBasic.OutText("IMPLEMENTATION "); name.Print; CCBasic.OutText(";"); CCBasic.OutLine;
				nestedComponents.Print; nestedInterfaces.Print; nestedProcedures.Print;
				constants.Print; variables.Print;
				Indent; CCBasic.OutText("BEGIN"); 
				INC(indent); statements.Print; DEC(indent);
				Indent; CCBasic.OutText("END "); name.Print; CCBasic.OutText(";"); CCBasic.OutLine
			END Print;
		END Implementation;
		
		ProcedureList* = OBJECT(CCBasic.List)
			PROCEDURE Add*(x: PTR);
			BEGIN ASSERT(x IS Procedure); Add^(x)
			END Add;
			
			PROCEDURE GetProcedure*(index: LONGINT): Procedure;
			VAR ptr: PTR;
			BEGIN ptr := GetItem(index); RETURN ptr(Procedure)
			END GetProcedure;
			
			(** NIL if not present *)
			PROCEDURE FindProcedure*(name: Identifier): Procedure;
			VAR i: LONGINT; x: Procedure;
			BEGIN
				FOR i := 0 TO Length()-1 DO
					x := GetProcedure(i);
					IF x.name.Equal(name) THEN RETURN x END
				END;
				RETURN NIL
			END FindProcedure;
			
			(** NIL if not present *)
			PROCEDURE FindProcedure2*(name: Identifier; nofParameters: LONGINT): Procedure;
			VAR i: LONGINT; x: Procedure;
			BEGIN
				FOR i := 0 TO Length()-1 DO
					x := GetProcedure(i);
					IF x.name.Equal(name) & (x.parameters.Length() = nofParameters) THEN RETURN x END
				END;
				RETURN NIL
			END FindProcedure2;
			
			PROCEDURE Print*;
			VAR i: LONGINT; x: Procedure;
			BEGIN
				IF Length() > 0 THEN CCBasic.OutLine END;
				FOR i := 0 TO Length()-1 DO
					x := GetProcedure(i);
					x.Print; CCBasic.OutLine
				END
			END Print;
		END ProcedureList;
		
		Procedure* = OBJECT(Node)
			VAR
				outer-: Node;
				name-: Identifier;
				parameters-: ProcedureParameterList;
				type-: Type;
				nestedComponents-: ComponentList;
				nestedInterfaces-: InterfaceList;
				nestedProcedures-: ProcedureList;
				constants-: ConstantList;
				variables-: VariableList;
				statements-: StatementSequence;
				
				(** static interprocedural protection checks *)
				hasProtectedRegion*: BOOLEAN;
				requiredProtection*: Identifier;
				waitsOnExternalEvent*, mustNotBeInAwait*: BOOLEAN;
				callers-: StatementList;
			
			PROCEDURE &InitProcedure(position: LONGINT; scope: Node; id: Identifier);
			BEGIN
				InitNode(position); outer := scope; name := id;
				NEW(parameters); type := NIL;
				NEW(nestedComponents); NEW(nestedInterfaces); NEW(nestedProcedures);
				NEW(constants); NEW(variables);
				NEW(statements, position, SELF);
				hasProtectedRegion := FALSE;
				requiredProtection := NIL;
				waitsOnExternalEvent := FALSE; mustNotBeInAwait := FALSE;
				NEW(callers)
			END InitProcedure;
			
			PROCEDURE SetType*(x: Type);
			BEGIN type := x
			END SetType;
			
			PROCEDURE AddParameter*(position: LONGINT; isVar: BOOLEAN; id: Identifier; t: Type);
			VAR par: ProcedureParameter;
			BEGIN NEW(par, position, SELF, isVar, id, t); parameters.Add(par)
			END AddParameter;
			
			PROCEDURE QualIdent*(): Identifier;
			VAR outerName: Identifier; s: CCBasic.String;
			BEGIN
				IF outer IS Component THEN 
					RETURN name
				ELSE
					IF outer IS Implementation THEN
						outerName := outer(Implementation).name
					ELSIF outer IS Procedure THEN
						outerName := outer(Procedure).name
					ELSE HALT(111)
					END;
					s := CCBasic.ConcatWithSeparator(outerName.name^, ".", name.name^);
					RETURN NewIdentifier(pos, s^)
				END
			END QualIdent;
			
			PROCEDURE Print*;
			BEGIN
				Indent; CCBasic.OutText("PROCEDURE "); name.Print; 
				CCBasic.OutText("("); parameters.Print; CCBasic.OutText(")");
				IF type # NIL THEN CCBasic.OutText(":"); type.Print END;
				CCBasic.OutText(";"); CCBasic.OutLine;
				nestedComponents.Print; nestedInterfaces.Print; nestedProcedures.Print;
				constants.Print; variables.Print;
				Indent; CCBasic.OutText("BEGIN"); 
				INC(indent); statements.Print; DEC(indent);
				Indent; CCBasic.OutText("END "); name.Print; CCBasic.OutText(";"); CCBasic.OutLine
			END Print;
		END Procedure;
		
		ParameterList* = OBJECT(CCBasic.List)
			PROCEDURE Add*(x: PTR);
			BEGIN ASSERT(x IS Parameter); Add^(x)
			END Add;
		
			PROCEDURE GetParameter*(index: LONGINT): Parameter;
			VAR ptr: PTR;
			BEGIN ptr := GetItem(index); RETURN ptr(Parameter)
			END GetParameter;
			
			(* NIL if not present *)
			PROCEDURE FindParameter*(name: Identifier): Parameter;
			VAR i: LONGINT; p: Parameter;
			BEGIN
				FOR i := 0 TO Length()-1 DO
					p := GetParameter(i);
					IF p.name.Equal(name) THEN RETURN p END
				END;
				RETURN NIL
			END FindParameter;
		
			PROCEDURE Print*;
			VAR i: LONGINT; p: Parameter;
			BEGIN
				IF Length() > 0 THEN
					CCBasic.OutText("(");
					FOR i := 0 TO Length()-1 DO
						p := GetParameter(i); p.Print;
						IF i < Length()-1 THEN CCBasic.OutText("; ") END
					END;
					CCBasic.OutText(")")
				END
			END Print;
		END ParameterList;
				
		Parameter* = OBJECT(Node)
			VAR
				name-: Identifier; (** NIL for imported parameter declarations *)
				type-: Type;
		
			PROCEDURE &InitParameter(position: LONGINT; id: Identifier; t: Type);
			BEGIN InitNode(position); name := id; type := t
			END InitParameter;
			
			PROCEDURE Print*;
			BEGIN name.Print; CCBasic.OutText(": "); type.Print;
			END Print;
		END Parameter;
				
		VariableList* = OBJECT(CCBasic.List)
			PROCEDURE Add*(x: PTR);
			BEGIN ASSERT(x IS Variable); Add^(x)
			END Add;
		
			PROCEDURE GetVariable*(index: LONGINT): Variable;
			VAR ptr: PTR;
			BEGIN ptr := GetItem(index); RETURN ptr(Variable)
			END GetVariable;
			
			(** NIL if not present *)
			PROCEDURE FindVariable*(name: Identifier): Variable;
			VAR i: LONGINT; v: Variable;
			BEGIN
				FOR i := 0 TO Length()-1 DO
					v := GetVariable(i);
					IF v.name.Equal(name) THEN RETURN v END
				END;
				RETURN NIL
			END FindVariable;
		
			PROCEDURE Print*;
			VAR i: LONGINT; v: Variable;
			BEGIN
				IF Length() > 0 THEN
					Indent; CCBasic.OutText("VARIABLE "); 
					FOR i := 0 TO Length()-1 DO
						v := GetVariable(i); v.Print; CCBasic.OutText("; ")
					END; 
					CCBasic.OutLine
				END
			END Print;
		END VariableList;
		
		Variable* = OBJECT(Node);
			VAR 
				name-: Identifier;
				type-: Type;
				scope-: Node; (** Component, Implementation or Procedure *)
				parameters-: ParameterList;
				usedCommunications-: InterfaceDeclarationList; 
					(** offered interfaces used for communication, resolved by semantic checker *)
				tempRiderVar-: Variable; (** if parameters > 0 and component or text type *)
			
			PROCEDURE &InitVariable*(position: LONGINT; outerScope: Node; id: Identifier);
			BEGIN 
				InitNode(position); 
				name := id; type := NIL; scope := outerScope; 
				NEW(parameters);
				NEW(usedCommunications);
				tempRiderVar := NIL
			END InitVariable;
			
			PROCEDURE SetType*(t: Type);
			BEGIN type := t
			END SetType;
			
			PROCEDURE SetTempRider*(var: Variable);
			BEGIN tempRiderVar := var
			END SetTempRider;
			
			PROCEDURE Print*;
			BEGIN
				name.Print; 
				IF parameters.Length() > 0 THEN CCBasic.OutText("["); parameters.Print; CCBasic.OutText("]") END;
				CCBasic.OutText(": "); type.Print
			END Print;
		END Variable;
		
		ProcedureParameterList* = OBJECT(CCBasic.List)
			PROCEDURE Add*(x: PTR);
			BEGIN ASSERT(x IS ProcedureParameter); Add^(x)
			END Add;
			
			PROCEDURE GetProcedureParameter*(index: LONGINT): ProcedureParameter;
			VAR ptr: PTR;
			BEGIN ptr := GetItem(index); RETURN ptr(ProcedureParameter)
			END GetProcedureParameter;
			
			(* NIL if not present *)
			PROCEDURE FindProcedureParameter*(name: Identifier): ProcedureParameter;
			VAR i: LONGINT; x: ProcedureParameter;
			BEGIN
				FOR i := 0 TO Length()-1 DO
					x := GetProcedureParameter(i);
					IF x.name.Equal(name) THEN RETURN x END
				END;
				RETURN NIL
			END FindProcedureParameter;
			
			PROCEDURE Print*;
			VAR i: LONGINT; p: ProcedureParameter;
			BEGIN
				IF Length() > 0 THEN
					CCBasic.OutText("(");
					FOR i := 0 TO Length()-1 DO
						p := GetProcedureParameter(i); p.Print;
						IF i < Length()-1 THEN CCBasic.OutText("; ") END
					END;
					CCBasic.OutText(")")
				END
			END Print;
		END ProcedureParameterList;
		
		ProcedureParameter* = OBJECT(Variable)
			VAR variable-: BOOLEAN;
				
			PROCEDURE &InitProcedureParameter(position: LONGINT; outerScope: Node; isVar: BOOLEAN; id: Identifier; t: Type);
			BEGIN InitVariable(position, outerScope, id); variable := isVar; SetType(t)
			END InitProcedureParameter;
			
			PROCEDURE Print*;
			BEGIN 
				IF variable THEN CCBasic.OutText("VARIABLE ") END; Print^
			END Print;
		END ProcedureParameter;
		
		ConstantList* = OBJECT(CCBasic.List)
			PROCEDURE Add*(x: PTR);
			BEGIN ASSERT(x IS Constant); Add^(x)
			END Add;
			
			PROCEDURE GetConstant*(index: LONGINT): Constant;
			VAR ptr: PTR;
			BEGIN ptr := GetItem(index); RETURN ptr(Constant)
			END GetConstant;
			
			(* NIL if not present *)
			PROCEDURE FindConstant*(name: Identifier): Constant;
			VAR i: LONGINT; x: Constant;
			BEGIN
				FOR i := 0 TO Length()-1 DO
					x := GetConstant(i);
					IF x.name.Equal(name) THEN RETURN x END
				END;
				RETURN NIL
			END FindConstant;
			
			PROCEDURE Print*;
			VAR i: LONGINT; c: Constant;
			BEGIN
				IF Length() > 0 THEN
					Indent; CCBasic.OutText("CONSTANT "); 
					FOR i := 0 TO Length()-1 DO
						c := GetConstant(i); c.Print; CCBasic.OutText("; ")
					END; 
					CCBasic.OutLine
				END
			END Print;
		END ConstantList;
		
		Constant* = OBJECT(Node);
			VAR
				name-: Identifier;
				expression-: Expression; (** constant expression *)
				scope-: Node; (** Component or Implementation *)
			
			PROCEDURE &InitConstant*(position: LONGINT; outerScope: Node; id: Identifier; expr: Expression);
			BEGIN InitNode(position); scope := outerScope; name := id; expression := expr
			END InitConstant;
			
			PROCEDURE SetExpression*(e: Expression);
			BEGIN expression := e
			END SetExpression;
			
			PROCEDURE Print*;
			BEGIN name.Print; CCBasic.OutText(" = "); expression.Print
			END Print;
		END Constant;
		
		Statement* = OBJECT(Node);
			VAR outer-: Node; (* Statement, Component, Implementation, NIL if not used *)
		
			PROCEDURE &InitStatement(position: LONGINT; super: Node);
			BEGIN InitNode(position); outer := super
			END InitStatement;
		END Statement;
		
		StatementSequence* = OBJECT(Statement)
			VAR
				statements-: StatementList;
				endPosition-: LONGINT;
			
			PROCEDURE &InitStatementSequence(position: LONGINT; supper: Node);
			BEGIN InitStatement(position, supper); NEW(statements); endPosition := position
			END InitStatementSequence;
			
			PROCEDURE SetEndPosition*(p: LONGINT);
			BEGIN endPosition := p
			END SetEndPosition;
			
			PROCEDURE Print*;
			BEGIN CCBasic.OutLine; statements.Print
			END Print;
		END StatementSequence;
		
		StatementList* = OBJECT(CCBasic.List)
			PROCEDURE Add*(x: PTR);
			BEGIN ASSERT(x IS Statement); Add^(x)
			END Add;
		
			PROCEDURE GetStatement*(index: LONGINT): Statement;
			VAR ptr: PTR;
			BEGIN ptr := GetItem(index); RETURN ptr(Statement)
			END GetStatement;
			
			PROCEDURE Print*;
			VAR i: LONGINT; x: Statement;
			BEGIN
				FOR i := 0 TO Length()-1 DO
					x := GetStatement(i); 
					Indent; x.Print; IF i < Length()-1 THEN CCBasic.OutText("; ") END; 
					CCBasic.OutLine
				END
			END Print;		
		END StatementList;
		
		(** abstract *)
		MessageTransferStatement* = OBJECT(Statement)
			VAR
				interfaceDesignator-: Designator; (** resolved to InterfaceDesignator by semantic checker *)
				messageIdentifier-: Identifier;
				messageArguments-: ExpressionList;
							
			PROCEDURE &InitMessageTransferStatement(position: LONGINT; super: Node; interface: Designator; message: Identifier);
			BEGIN 
				InitStatement(position, super); 
				interfaceDesignator := interface; interfaceDesignator.SetOuter(SELF);
				messageIdentifier := message; 
				NEW(messageArguments, SELF)
			END InitMessageTransferStatement;
			
			PROCEDURE SetInterfaceDesignator*(x: InterfaceDesignator);
			BEGIN interfaceDesignator := x; interfaceDesignator.SetOuter(SELF)
			END SetInterfaceDesignator;
		END MessageTransferStatement;
		
		SendStatement* = OBJECT(MessageTransferStatement)
			PROCEDURE &InitSendStatement(position: LONGINT; super: Node; interface: Designator; message: Identifier);
			BEGIN InitMessageTransferStatement(position, super, interface, message)
			END InitSendStatement;
			
			PROCEDURE Print*;
			BEGIN
				interfaceDesignator.Print;
				CCBasic.OutText("!"); messageIdentifier.Print;
				IF messageArguments.Length() > 0 THEN
					CCBasic.OutText("("); messageArguments.Print; CCBasic.OutText(")")
				END
			END Print;
		END SendStatement;
		
		ReceiveStatement* = OBJECT(MessageTransferStatement)
			PROCEDURE &InitReceiveStatement(position: LONGINT; super: Node; interface: Designator; message: Identifier);
			BEGIN InitMessageTransferStatement(position, super, interface, message)
			END InitReceiveStatement;
								
			PROCEDURE Print*;
			BEGIN
				IF interfaceDesignator # NIL THEN interfaceDesignator.Print END; 
				CCBasic.OutText("?"); messageIdentifier.Print;
				IF messageArguments.Length() > 0 THEN
					CCBasic.OutText("("); messageArguments.Print; CCBasic.OutText(")")
				END
			END Print;
		END ReceiveStatement;
		
		Assignment* = OBJECT(Statement)
			VAR
				leftDesignator-: Designator;
				rightExpression-: Expression;
				
			PROCEDURE &InitAssignment(position: LONGINT; supper: Node; lhs: Designator; rhs: Expression);
			BEGIN 
				InitStatement(position, supper); 
				leftDesignator := lhs; leftDesignator.SetOuter(SELF);
				rightExpression := rhs; rightExpression.SetOuter(SELF)
			END InitAssignment;
			
			PROCEDURE SetLeftDesignator*(d: Designator);
			BEGIN leftDesignator := d; leftDesignator.SetOuter(SELF)
			END SetLeftDesignator;
			
			PROCEDURE SetRightExpression*(e: Expression);
			BEGIN rightExpression := e; rightExpression.SetOuter(SELF)
			END SetRightExpression;
			
			PROCEDURE Print*;
			BEGIN leftDesignator.Print; CCBasic.OutText(" := "); rightExpression.Print
			END Print;
		END Assignment;
		
		ProcedureCall* = OBJECT(Statement)
			VAR
				identifier-: Identifier;
				arguments-: ExpressionList;
				declaration-: Procedure; (** resolved by semantic checker *)
				
			PROCEDURE &InitProcedureCall(position: LONGINT; super: Node; id: Identifier);
			BEGIN InitStatement(position, super); identifier := id; NEW(arguments, SELF); declaration := NIL
			END InitProcedureCall;
			
			PROCEDURE SetDeclaration*(x: Procedure);
			BEGIN declaration := x
			END SetDeclaration;
						
			PROCEDURE Print*;
			BEGIN
				identifier.Print; 
				IF arguments.Length() > 0 THEN CCBasic.OutText("("); arguments.Print; CCBasic.OutText(")") END
			END Print;
		END ProcedureCall;
		
		ConditionalBlockList* = OBJECT(CCBasic.List)
			PROCEDURE Add*(x: PTR);
			BEGIN ASSERT(x IS ConditionalBlock); Add^(x)
			END Add;
			
			PROCEDURE GetConditionalBlock*(index: LONGINT): ConditionalBlock;
			VAR ptr: PTR;
			BEGIN ptr := GetItem(index); RETURN ptr(ConditionalBlock)
			END GetConditionalBlock;
		END ConditionalBlockList;
		
		(** Part of IfStatement *)
		ConditionalBlock* = OBJECT(Node)
			VAR
				outer-: Node;
				condition-: Expression;
				statements-: StatementSequence;
				
			PROCEDURE &InitConditionalBlock(startPosition: LONGINT; super: Node; statementPosition: LONGINT; 
				conditionExpr: Expression);
			BEGIN 
				InitNode(startPosition); outer := super;
				condition := conditionExpr; condition.SetOuter(outer);
				NEW(statements, statementPosition, outer)
			END InitConditionalBlock;
			
			PROCEDURE SetCondition*(e: Expression);
			BEGIN condition := e; condition.SetOuter(outer)
			END SetCondition;
						
			PROCEDURE Print*;
			BEGIN condition.Print; CCBasic.OutText(" THEN "); INC(indent); statements.Print; DEC(indent)
			END Print;
		END ConditionalBlock;
		
		IfStatement* = OBJECT(Statement)
			VAR
				ifBlock-: ConditionalBlock;
				elsifBlocks-: ConditionalBlockList;
				else-: StatementSequence; (** NIL if no ELSE block *)
			
			PROCEDURE &InitIfStatement(startPosition: LONGINT; super: Node; thenPosition: LONGINT; ifCondition: Expression);
			BEGIN 
				InitStatement(startPosition, super); 
				NEW(ifBlock, startPosition, SELF, thenPosition, ifCondition);
				NEW(elsifBlocks); else := NIL
			END InitIfStatement;
			
			PROCEDURE AddElsifBlock*(startPosition, thenPosition: LONGINT; elsifCondition: Expression): ConditionalBlock;
			VAR b: ConditionalBlock;
			BEGIN 
				NEW(b, startPosition, SELF, thenPosition, elsifCondition); 
				elsifBlocks.Add(b);
				RETURN b
			END AddElsifBlock;
			
			PROCEDURE CreateElseBlock*(elsePosition: LONGINT);
			BEGIN NEW(else, elsePosition, SELF)
			END CreateElseBlock;
			
			PROCEDURE Print*;
			VAR i: LONGINT; n: PTR;
			BEGIN
				CCBasic.OutText("IF "); ifBlock.Print;
				FOR i := 0 TO elsifBlocks.Length()-1 DO
					n := elsifBlocks.GetItem(i);
					Indent; CCBasic.OutText("ELSIF "); n(ConditionalBlock).Print
				END;
				IF else # NIL THEN
					Indent; CCBasic.OutText("ELSE "); INC(indent); else.Print; DEC(indent)
				END;
				Indent; CCBasic.OutText("END")
			END Print;
		END IfStatement;
		
		WhileStatement* = OBJECT(Statement)
			VAR
				condition-: Expression;
				statements-: StatementSequence;
				
			PROCEDURE &InitWhileStatement(startPosition: LONGINT; super: Node; bodyPosition: LONGINT; 
				whileCondition: Expression);
			BEGIN 
				InitStatement(startPosition, super); 
				condition := whileCondition; condition.SetOuter(SELF);
				NEW(statements, bodyPosition, SELF)
			END InitWhileStatement;
			
			PROCEDURE SetCondition*(e: Expression);
			BEGIN condition := e; condition.SetOuter(SELF)
			END SetCondition;
			
			PROCEDURE Print*;
			BEGIN
				CCBasic.OutText("WHILE "); condition.Print; CCBasic.OutText(" DO ");
				INC(indent); statements.Print; DEC(indent); 
				Indent; CCBasic.OutText("END")
			END Print;
		END WhileStatement;
		
		RepeatStatement* = OBJECT(Statement)
			VAR
				statements-: StatementSequence;
				condition-: Expression;
				
			PROCEDURE &InitRepeatStatement(startPosition: LONGINT; super: Node; bodyPosition: LONGINT);
			BEGIN InitStatement(startPosition, super); condition := NIL; NEW(statements, bodyPosition, SELF)
			END InitRepeatStatement;
			
			PROCEDURE SetCondition*(e: Expression);
			BEGIN condition := e; condition.SetOuter(SELF)
			END SetCondition;
			
			PROCEDURE Print*;
			BEGIN
				CCBasic.OutText("REPEAT"); 
				INC(indent); statements.Print; DEC(indent);
				Indent; CCBasic.OutText("UNTIL "); condition.Print
			END Print;
		END RepeatStatement;
		
		ForStatement* = OBJECT(Statement)
			VAR
				varDesignator-: Designator;
				fromExpression-, toExpression-, byExpression-: Expression;
				statements-: StatementSequence;
				temporaryVariable-: Variable; (** for TO-expression, assigned by semantic checker *)
				
			PROCEDURE &InitForStatement(startPosition: LONGINT; super: Node; bodyPosition: LONGINT; 
				des: Designator; from, to, by: Expression);
			BEGIN
				InitStatement(startPosition, super); 
				varDesignator := des; varDesignator.SetOuter(SELF);
				fromExpression := from; fromExpression.SetOuter(SELF);
				toExpression := to; toExpression.SetOuter(SELF);
				byExpression := by; byExpression.SetOuter(SELF);
				NEW(statements, bodyPosition, SELF);
				temporaryVariable := NIL
			END InitForStatement;
			
			PROCEDURE SetVariableDesignator*(d: Designator);
			BEGIN varDesignator := d; varDesignator.SetOuter(SELF)
			END SetVariableDesignator;
			
			PROCEDURE SetFromExpression*(e: Expression);
			BEGIN fromExpression := e; fromExpression.SetOuter(SELF)
			END SetFromExpression;
			
			PROCEDURE SetToExpression*(e: Expression);
			BEGIN toExpression := e; toExpression.SetOuter(SELF)
			END SetToExpression;
			
			PROCEDURE SetByExpression*(e: Expression);
			BEGIN byExpression := e; byExpression.SetOuter(SELF)
			END SetByExpression;
			
			PROCEDURE SetTemporaryVariable*(v: Variable);
			BEGIN temporaryVariable := v
			END SetTemporaryVariable;
			
			PROCEDURE Print*;
			BEGIN
				CCBasic.OutText("FOR "); varDesignator.Print; CCBasic.OutText(" := "); fromExpression.Print;
				CCBasic.OutText(" TO "); toExpression.Print; CCBasic.OutText(" BY "); byExpression.Print;
				CCBasic.OutText(" DO "); INC(indent); statements.Print; DEC(indent);
				Indent; CCBasic.OutText("END")
			END Print;
		END ForStatement;
		
		ForeachStatement* = OBJECT(Statement)
			VAR 
				varDesignators-: ExpressionList;
				of-: Designator;
				statements-: StatementSequence;
				temporaryVariable-: Variable; (* set by semantic checker *)
				
			PROCEDURE &InitForeachStatement(position: LONGINT; super: Node);
			BEGIN 
				InitStatement(position, super); 
				NEW(varDesignators, SELF); 
				of := NIL;
				NEW(statements, pos, SELF)
			END InitForeachStatement;
			
			PROCEDURE SetOf*(des: Designator);
			BEGIN of := des; of.SetOuter(SELF)
			END SetOf;
			
			PROCEDURE SetTemporaryVariable*(v: Variable);
			BEGIN temporaryVariable := v
			END SetTemporaryVariable;
			
			PROCEDURE Print*;
			BEGIN
				CCBasic.OutText("FOREACH "); varDesignators.Print; CCBasic.OutText(" OF "); of.Print; CCBasic.OutText(" DO ");
				INC(indent); statements.Print; DEC(indent);
				Indent; CCBasic.OutText("END")
			END Print;
		END ForeachStatement;
				
		AwaitStatement* = OBJECT(Statement)
			VAR
				condition-: Expression;
				waitsOnExternalEvent*: BOOLEAN; (** may depend on communication input, use of TIME() *)
			
			PROCEDURE &InitAwaitStatement(position: LONGINT; super: Node; expr: Expression);
			BEGIN 
				InitStatement(position, super); 
				condition := expr; condition.SetOuter(SELF);
				waitsOnExternalEvent := FALSE
			END InitAwaitStatement;
			
			PROCEDURE SetCondition*(e: Expression);
			BEGIN condition := e; condition.SetOuter(SELF)
			END SetCondition;
			
			PROCEDURE Print*;
			BEGIN CCBasic.OutText("AWAIT("); condition.Print; CCBasic.OutText(")")
			END Print;
		END AwaitStatement;
				
		NewStatement* = OBJECT(Statement)
			VAR 
				variableDes-: Designator;
				additionalArguments-: ExpressionList; (** NIL if not specified *)
				componentType-: ComponentType; (** NIL if not defined, resolved by semantic checker *)
				
			PROCEDURE &InitNewStatement(position: LONGINT; super: Node; des: Designator);
			BEGIN 
				InitStatement(position, super); 
				variableDes := des; variableDes.SetOuter(SELF);
				NEW(additionalArguments, SELF); 
				componentType := NIL
			END InitNewStatement;
			
			PROCEDURE SetVariableDesignator*(d: Designator);
			BEGIN variableDes := d; variableDes.SetOuter(SELF)
			END SetVariableDesignator;
						
			PROCEDURE SetComponentType*(t: ComponentType);
			BEGIN componentType := t
			END SetComponentType;
			
			PROCEDURE Print*;
			BEGIN 
				CCBasic.OutText("NEW("); variableDes.Print; 
				IF additionalArguments.Length() > 0 THEN CCBasic.OutText(", "); additionalArguments.Print END;
				CCBasic.OutText(")")
			END Print;
		END NewStatement;
		
		ConnectStatement* = OBJECT(Statement)
			VAR source-, target-: Designator; (** resolved to InterfaceDesignator by semantic checker *)
			
			PROCEDURE &InitConnectStatement(position: LONGINT; super: Node; from, to: Designator);
			BEGIN 
				InitStatement(position, super); 
				source := from; source.SetOuter(SELF);
				target := to; target.SetOuter(SELF)
			END InitConnectStatement;
			
			PROCEDURE SetSource*(x: InterfaceDesignator);
			BEGIN source := x; source.SetOuter(SELF)
			END SetSource;
			
			PROCEDURE SetTarget*(x: InterfaceDesignator);
			BEGIN target := x; target.SetOuter(SELF)
			END SetTarget;
			
			PROCEDURE Print*;
			BEGIN 
				CCBasic.OutText("CONNECT("); source.Print; CCBasic.OutText(", "); target.Print; CCBasic.OutText(")"); CCBasic.OutLine
			END Print;
		END ConnectStatement;
		
		DisconnectStatement* = OBJECT(Statement)
			VAR intDes-: Designator; (** resolved to InterfaceDesignator by semantic checker *)
			
			PROCEDURE &InitDisconnectStatement(position: LONGINT; super: Node; x: Designator);
			BEGIN
				InitStatement(position, super);
				intDes := x; intDes.SetOuter(SELF)
			END InitDisconnectStatement;
			
			PROCEDURE SetDesignator*(x: InterfaceDesignator);
			BEGIN intDes := x; intDes.SetOuter(SELF)
			END SetDesignator;
			
			PROCEDURE Print*;
			BEGIN 
				CCBasic.OutText("DISCONNECT("); intDes.Print; CCBasic.OutText(")"); CCBasic.OutLine
			END Print;
		END DisconnectStatement;
		
		ReturnStatement* = OBJECT(Statement)
			VAR expression-: Expression; (** NIL if none *)
			
			PROCEDURE &InitReturnStatement(position: LONGINT; super: Node; expr: Expression);
			BEGIN 
				InitStatement(position, super); 
				expression := expr; IF expression # NIL THEN expression.SetOuter(SELF) END
			END InitReturnStatement;
			
			PROCEDURE SetExpression*(x: Expression);
			BEGIN expression := x; IF expression # NIL THEN expression.SetOuter(SELF) END
			END SetExpression;
			
			PROCEDURE Print*;
			BEGIN CCBasic.OutText("RETURN "); IF expression # NIL THEN expression.Print END; CCBasic.OutLine
			END Print;
		END ReturnStatement;
		
		ExpressionList* = OBJECT(CCBasic.List)
			VAR outer-: Node;
			
			PROCEDURE &InitExpressionList(super: Node);
			BEGIN InitList; outer := super
			END InitExpressionList;
		
			PROCEDURE Add*(x: PTR);
			VAR expr: Expression;
			BEGIN expr := x(Expression); expr.SetOuter(outer); Add^(expr)
			END Add;
		
			PROCEDURE GetExpression*(index: LONGINT): Expression;
			VAR ptr: PTR;
			BEGIN ptr := GetItem(index); RETURN ptr(Expression)
			END GetExpression;
			
			PROCEDURE ReplaceExpression*(index: LONGINT; expr: Expression);
			BEGIN ReplaceByIndex^(index, expr); expr.SetOuter(outer)
			END ReplaceExpression;
			
			PROCEDURE Replace*(x, y: PTR);
			BEGIN HALT(111) (* set outer of y *)
			END Replace;
			
			PROCEDURE ReplaceByIndex*(i: LONGINT; x: PTR);
			VAR expr: Expression;
			BEGIN expr := x(Expression); expr.SetOuter(outer); ReplaceByIndex^(i, expr)
			END ReplaceByIndex;
			
			PROCEDURE Print*;
			VAR i: LONGINT; x: Expression;
			BEGIN
				FOR i := 0 TO Length()-1 DO
					x := GetExpression(i); x.Print;
					IF i < Length()-1 THEN CCBasic.OutText(", ") END
				END
			END Print;
		END ExpressionList;
				
		Expression* = OBJECT(Node)
			VAR 
				outer-: Node;
				type-: Type;
			
			PROCEDURE &InitExpression(position: LONGINT);
			BEGIN InitNode(position); outer := NIL; type := NIL
			END InitExpression;
			
			PROCEDURE SetOuter*(x: Node);
			BEGIN 
				IF (outer # NIL) & (x # NIL) & (outer # x) THEN HALT(111) END;
				outer := x
			END SetOuter;
			
			PROCEDURE SetType*(t: Type);
			BEGIN type := t
			END SetType;
		END Expression;
				
		(** abstract *)
		Designator* = OBJECT(Expression)
			VAR node-: Node;
			
			PROCEDURE &InitDesignator(position: LONGINT);
			BEGIN InitExpression(position); node := NIL
			END InitDesignator;
			
			PROCEDURE IsEmpty*(): BOOLEAN;
			BEGIN RETURN IsEqualText("");
			END IsEmpty;
			
			PROCEDURE IsEqualIdentifier*(id: Identifier): BOOLEAN;
			BEGIN HALT(99) (* abstract *)
			END IsEqualIdentifier;
			
			PROCEDURE IsEqualText*(x: ARRAY OF CHAR): BOOLEAN;
			BEGIN HALT(99) (* abstract *)
			END IsEqualText;
			
			PROCEDURE Equal*(d: Designator): BOOLEAN;
			BEGIN HALT(99) (* abstract *)
			END Equal;

			PROCEDURE SetDesignatedNode*(x: Node);
			BEGIN node := x
			END SetDesignatedNode;
		END Designator;
		
		IdentifierDesignator* = OBJECT(Designator)
			VAR identifier-: Identifier;
				
			PROCEDURE &InitIdentifierDesignator(position: LONGINT; id: Identifier);
			BEGIN InitDesignator(position); identifier := id
			END InitIdentifierDesignator;
			
			PROCEDURE IsEqualIdentifier*(id: Identifier): BOOLEAN;
			BEGIN RETURN identifier.Equal(id)
			END IsEqualIdentifier;
			
			PROCEDURE IsEqualText*(x: ARRAY OF CHAR): BOOLEAN;
			BEGIN RETURN identifier.EqualText(x)
			END IsEqualText;
	
			PROCEDURE Print*;
			BEGIN identifier.Print;
			END Print;
		END IdentifierDesignator;
			
		(** left[arg1, arg2, ...] *)
		IndexDesignator* = OBJECT(Designator)
			VAR 
				left-: Designator;
				arguments-: ExpressionList;
			
			PROCEDURE &InitIndexDesignator(position: LONGINT; leftDes: Designator);
			BEGIN InitDesignator(position); left := leftDes; left.SetOuter(SELF); NEW(arguments, SELF)
			END InitIndexDesignator;
			
			PROCEDURE SetLeft*(d: Designator);
			BEGIN left := d; left.SetOuter(SELF)
			END SetLeft;
			
			PROCEDURE IsEqualIdentifier*(id: Identifier): BOOLEAN;
			BEGIN RETURN FALSE
			END IsEqualIdentifier;
			
			PROCEDURE IsEqualText*(x: ARRAY OF CHAR): BOOLEAN;
			BEGIN RETURN FALSE
			END IsEqualText;

			PROCEDURE Print*;
			BEGIN left.Print; CCBasic.OutText("["); arguments.Print; CCBasic.OutText("]")
			END Print;
		END IndexDesignator;
		
		(** left(arg1, arg2, ...), may designate a function call, an interface selection, or a type guard *)
		ParameterDesignator* = OBJECT(Designator)
			VAR
				left-: Designator;
				arguments-: ExpressionList;
				
			PROCEDURE &InitParameterDesignator(position: LONGINT; leftDes: Designator);
			BEGIN InitDesignator(position); left := leftDes; left.SetOuter(SELF); NEW(arguments, SELF)
			END InitParameterDesignator;
			
			PROCEDURE IsEqualIdentifier*(id: Identifier): BOOLEAN;
			BEGIN RETURN FALSE
			END IsEqualIdentifier;
			
			PROCEDURE IsEqualText*(x: ARRAY OF CHAR): BOOLEAN;
			BEGIN RETURN FALSE
			END IsEqualText;
			
			PROCEDURE Print*;
			BEGIN left.Print; CCBasic.OutText("("); arguments.Print; CCBasic.OutText(")")
			END Print;
		END ParameterDesignator;
		
		(** left(type) *)
		GuardDesignator* = OBJECT(Designator)
			VAR
				left-: Designator;
				type-: Type;
				
			PROCEDURE &InitGuardDesignator(position: LONGINT; leftDes: Designator; t: Type);
			BEGIN InitDesignator(position); left := leftDes; left.SetOuter(SELF); type := t
			END InitGuardDesignator;
			
			PROCEDURE SetLeft*(d: Designator);
			BEGIN left := d; left.SetOuter(SELF)
			END SetLeft;
			
			PROCEDURE IsEqualIdentifier*(id: Identifier): BOOLEAN;
			BEGIN RETURN FALSE
			END IsEqualIdentifier;
			
			PROCEDURE IsEqualText*(x: ARRAY OF CHAR): BOOLEAN;
			BEGIN RETURN FALSE
			END IsEqualText;
			
			PROCEDURE Print*;
			BEGIN left.Print; CCBasic.OutText("("); type.Print; CCBasic.OutText(")")
			END Print;
		END GuardDesignator;
		
		InterfaceDesignatorList* = OBJECT(CCBasic.List)
			VAR outer-: Node;
			
			PROCEDURE &InitInterfaceDesignatorList(super: Node);
			BEGIN InitList; outer := super
			END InitInterfaceDesignatorList;
		
			PROCEDURE Add*(x: PTR);
			VAR des: InterfaceDesignator;
			BEGIN des := x(InterfaceDesignator); des.SetOuter(outer); Add^(des)
			END Add;
			
			PROCEDURE Replace*(x, y: PTR);
			BEGIN HALT(111) (* set outer of y *)
			END Replace;
			
			PROCEDURE ReplaceByIndex*(i: LONGINT; x: PTR);
			BEGIN HALT(111) (* set outer of x *)
			END ReplaceByIndex;
			
			PROCEDURE GetInterfaceDesignator*(index: LONGINT): InterfaceDesignator;
			VAR ptr: PTR;
			BEGIN ptr := GetItem(index); RETURN ptr(InterfaceDesignator)
			END GetInterfaceDesignator;
			
			(* NIL if no equal interface designator is present *)
			PROCEDURE FindInterfaceDesignator*(d: InterfaceDesignator): InterfaceDesignator;
			VAR i: LONGINT; x: InterfaceDesignator;
			BEGIN
				FOR i := 0 TO Length()-1 DO
					x := GetInterfaceDesignator(i);
					IF x.Equal(d) THEN RETURN x END
				END;
				RETURN NIL
			END FindInterfaceDesignator;
		END InterfaceDesignatorList;
		
		InterfaceDesignator* = OBJECT(Designator)
			VAR 
				declaration-: InterfaceDeclaration;
				index-: Expression; (* default: NIL meaning 0*)
				isOffered-: BOOLEAN; (** TRUE = offered, FALSE = required *)
			
			PROCEDURE &InitInterfaceDesignator*(position: LONGINT; decl: InterfaceDeclaration; offered: BOOLEAN);
			BEGIN 
				InitDesignator(position); 
				node := decl; declaration := decl; isOffered := offered;
				index := NIL
			END InitInterfaceDesignator;
			
			PROCEDURE SetIndex*(e: Expression);
			BEGIN index := e; IF index # NIL THEN index.SetOuter(SELF) END
			END SetIndex;
			
			PROCEDURE PrintIndex*;
			BEGIN 
				 IF index # NIL THEN CCBasic.OutText("["); index.Print; CCBasic.OutText("]") END
			END PrintIndex;
		END InterfaceDesignator;
		
		ExternalInterfaceDesignator* = OBJECT(InterfaceDesignator)
			VAR component-: Component;
		
			PROCEDURE &InitExternalInterfaceDes*(position: LONGINT; com: Component; 
				decl: InterfaceDeclaration; offered: BOOLEAN);
			BEGIN InitInterfaceDesignator(position, decl, offered); component := com
			END InitExternalInterfaceDes;

			PROCEDURE Print*;
			BEGIN 
				IF isOffered THEN CCBasic.OutText("OFFERED ") ELSE CCBasic.OutText("REQUIRED ") END;
				CCBasic.OutText(" EXTERNAL"); declaration.name.Print; PrintIndex
			END Print;
		END ExternalInterfaceDesignator;
		
		InternalInterfaceDesignator* = OBJECT(InterfaceDesignator)
			VAR variableDes-: Designator;
			
			PROCEDURE &InitInternalInterfaceDes(position: LONGINT; decl: InterfaceDeclaration; 
				offered: BOOLEAN; varDes: Designator);
			BEGIN InitInterfaceDesignator(position, decl, offered); variableDes := varDes; variableDes.SetOuter(SELF)
			END InitInternalInterfaceDes;
		
			PROCEDURE Print*;
			BEGIN 
				IF isOffered THEN CCBasic.OutText("OFFERED ") ELSE CCBasic.OutText("REQUIRED ") END;
				declaration.name.Print; PrintIndex; CCBasic.OutText("("); variableDes.Print; CCBasic.OutText(")")
			END Print;
		END InternalInterfaceDesignator;
		
		ImplementationDesignator* = OBJECT(InterfaceDesignator)
			VAR implementation-: Implementation;
			
			PROCEDURE &InitImplementationDes*(position: LONGINT; impl: Implementation);
			BEGIN InitInterfaceDesignator(position, impl.interfaceDecl, FALSE); implementation := impl
			END InitImplementationDes;
			
			PROCEDURE Print*;
			BEGIN CCBasic.OutText("IMPLEMENTATION "); implementation.name.Print
			END Print;
		END ImplementationDesignator;
				
		Operator* = LONGINT;
		
		BinaryExpression* = OBJECT(Expression)
			VAR 
				operator-: Operator;
				left-, right-: Expression;
			
			PROCEDURE &InitBinaryExpression(position: LONGINT; op: Operator; l, r: Expression);
			BEGIN 
				InitExpression(position); operator := op; 
				left := l; left.SetOuter(SELF);
				right := r; right.SetOuter(SELF)
			END InitBinaryExpression;
			
			PROCEDURE SetLeft*(e: Expression);
			BEGIN left := e; left.SetOuter(SELF)
			END SetLeft;
			
			PROCEDURE SetRight*(e: Expression);
			BEGIN right := e; right.SetOuter(SELF)
			END SetRight;
			
			PROCEDURE Print*;
			BEGIN 
				CCBasic.OutText("("); left.Print; CCBasic.OutText(" op="); CCBasic.OutInteger(operator); 
				CCBasic.OutText(" "); right.Print; CCBasic.OutText(")")
			END Print;
		END BinaryExpression;
		
		UnaryExpression* = OBJECT(Expression)
			VAR
				operator-: Operator;
				sub-: Expression;
				
			PROCEDURE &InitUnaryExpression(position: LONGINT; op: Operator; e: Expression);
			BEGIN 
				InitExpression(position); operator := op; 
				sub := e; sub.SetOuter(SELF)
			END InitUnaryExpression;
			
			PROCEDURE SetSub*(e: Expression);
			BEGIN sub := e; sub.SetOuter(SELF)
			END SetSub;
			
			PROCEDURE Print*;
			BEGIN 
				CCBasic.OutText("( op="); CCBasic.OutInteger(operator); CCBasic.OutText(" "); sub.Print; CCBasic.OutText(")")
			END Print;
		END UnaryExpression;
		
		InterfaceTest* = OBJECT(Expression)
			VAR
				left-: Expression;
				offers-: BOOLEAN; (* FALSE = requires *)
				interfaces-: InterfaceDeclarationList;
				
			PROCEDURE &InitInterfaceTest(position: LONGINT; isOffers: BOOLEAN; expr: Expression);
			BEGIN 	
				InitExpression(position); left := expr; left.SetOuter(SELF);
				offers := isOffers; NEW(interfaces)
			END InitInterfaceTest;
			
			PROCEDURE SetLeft*(e: Expression);
			BEGIN left := e; left.SetOuter(SELF)
			END SetLeft;
			
			PROCEDURE Print*;
			BEGIN 
				CCBasic.OutText("("); left.Print; 
				IF offers THEN CCBasic.OutText(" OFFERS ") ELSE CCBasic.OutText(" REQUIRES ") END;
				interfaces.Print; CCBasic.OutText(")")
			END Print;
		END InterfaceTest;
		
		TypeTest* = OBJECT(Expression)
			VAR
				left-: Expression;
				type-: Type;
				
			PROCEDURE &InitTypeTest(position: LONGINT; expr: Expression; t: Type);
			BEGIN InitExpression(position); left := expr; left.SetOuter(SELF); type := t
			END InitTypeTest;
			
			PROCEDURE SetLeft*(e: Expression);
			BEGIN left := e; left.SetOuter(SELF)
			END SetLeft;
			
			PROCEDURE Print*;
			BEGIN CCBasic.OutText("("); left.Print; CCBasic.OutText(" IS "); type.Print; CCBasic.OutText(")")
			END Print;
		END TypeTest;
				
		TextValue* = OBJECT(Expression)
			VAR text-: CCBasic.String;
			
			PROCEDURE &InitTextValue(position: LONGINT; s: ARRAY OF CHAR);
			BEGIN InitExpression(position); text := CCBasic.NewString(s)
			END InitTextValue;
			
			PROCEDURE Equal*(t: TextValue): BOOLEAN;
			BEGIN RETURN text^ = t.text^
			END Equal;
			
			PROCEDURE EqualText*(x: ARRAY OF CHAR): BOOLEAN;
			BEGIN RETURN text^ = x
			END EqualText;
			
			PROCEDURE Print*;
			BEGIN CCBasic.OutCharacter(22X); CCBasic.OutText(text^); CCBasic.OutCharacter(22X)
			END Print;
		END TextValue;
		
		IntegerValue* = OBJECT(Expression)
			VAR int-: LONGINT;
			
			PROCEDURE &InitIntegerValue(position: LONGINT; i: LONGINT);
			BEGIN InitExpression(position); int := i
			END InitIntegerValue;
			
			PROCEDURE Print*;
			BEGIN CCBasic.OutInteger(int)
			END Print;
		END IntegerValue;
		
		RealValue* = OBJECT(Expression)
			VAR real-: REAL;
			
			PROCEDURE &InitRealValue(position: LONGINT; r: REAL);
			BEGIN InitExpression(position); real := r
			END InitRealValue;
			
			PROCEDURE Print*;
			BEGIN CCBasic.OutReal(real)
			END Print;
		END RealValue;
		
		BooleanValue* = OBJECT(Expression)
			VAR bool-: BOOLEAN;
			
			PROCEDURE &InitBooleanValue(position: LONGINT; b: BOOLEAN);
			BEGIN InitExpression(position); bool := b
			END InitBooleanValue;
			
			PROCEDURE Print*;
			BEGIN IF bool THEN CCBasic.OutText("TRUE") ELSE CCBasic.OutText("FALSE") END
			END Print;
		END BooleanValue;
		
		CharacterValue* = OBJECT(Expression)
			VAR char-: CHAR;
			
			PROCEDURE &InitCharacterValue(position: LONGINT; c: CHAR);
			BEGIN InitExpression(position); char := c
			END InitCharacterValue;
			
			PROCEDURE Print*;
			BEGIN CCBasic.OutCharacter(22X); CCBasic.OutCharacter(char); CCBasic.OutCharacter(22X)
			END Print;
		END CharacterValue;
		
		FunctionCall* = OBJECT(Expression)
			VAR 
				identifier-: Identifier;
				arguments-: ExpressionList;
				declaration-: Procedure; (** resolved by semantic checker *)
				
			PROCEDURE &InitFunctionCall(position: LONGINT; id: Identifier);
			BEGIN InitExpression(position); identifier := id; NEW(arguments, SELF); declaration := NIL
			END InitFunctionCall;
			
			PROCEDURE SetDeclaration*(x: Procedure);
			BEGIN declaration := x
			END SetDeclaration;
			
			PROCEDURE Print*;
			BEGIN identifier.Print; CCBasic.OutText("("); arguments.Print; CCBasic.OutText(")")
			END Print;
		END FunctionCall;
		
		(** INPUT(interface, message/AnyMessage/EndMessage) *)
		InputFunction* = OBJECT(Expression)
			VAR
				interfaceDesignator-: Designator; (** resolved to InterfaceDesignator by semantic checker *)
				messageIdentifier-: Identifier; (** including AnyMessage and EndMessage *)
				
			PROCEDURE &InitInputFunction(position: LONGINT; interface: Designator; message: Identifier);
			BEGIN 
				InitExpression(position); 
				interfaceDesignator := interface; interfaceDesignator.SetOuter(SELF);
				messageIdentifier := message
			END InitInputFunction;
			
			PROCEDURE SetInterfaceDesignator*(x: InterfaceDesignator);
			BEGIN interfaceDesignator := x; interfaceDesignator.SetOuter(SELF)
			END SetInterfaceDesignator;
															
			PROCEDURE Print*;
			BEGIN 
				CCBasic.OutText("INPUT("); 
				IF ~interfaceDesignator.IsEmpty() THEN interfaceDesignator.Print; CCBasic.OutText(", ") END;
				messageIdentifier.Print; CCBasic.OutText(")")
			END Print;
		END InputFunction;
		
		ReceiveTestFunction* = OBJECT(Expression)
			VAR
				interfaceDesignator-: Designator; (** resolved to InterfaceDesignator by semantic checker *)
				messageIdentifier-: Identifier; (** including EndMessage *)
			
			PROCEDURE &InitReceiveTestFunction(position: LONGINT; interface: Designator; message: Identifier);
			BEGIN 
				InitExpression(position); 
				interfaceDesignator := interface; interfaceDesignator.SetOuter(SELF);
				messageIdentifier := message
			END InitReceiveTestFunction;
			
			PROCEDURE SetInterfaceDesignator*(x: InterfaceDesignator);
			BEGIN interfaceDesignator := x; interfaceDesignator.SetOuter(SELF)
			END SetInterfaceDesignator;
			
			PROCEDURE Print*;
			BEGIN
				IF ~interfaceDesignator.IsEmpty() THEN interfaceDesignator.Print END;
				CCBasic.OutText("?"); messageIdentifier.Print
			END Print;
		END ReceiveTestFunction;
									
	VAR
		compiledComponents-: ComponentList;
		compiledInterfaces-: InterfaceList;
		importedComponents-: ComponentDefinitionList;
		importedInterfaces-: InterfaceList;
		
		reservedNames-: IdentifierList;
		predefinedProcedures-: ProcedureList;
		predefinedConstants-: ConstantList;
		predefinedVariables-: VariableList;
		
		integerType-, realType-, textType-, booleanType-, characterType-: DataType;
		anyType-: AnyType;

		time-: Variable; 
					
		writeText-, writeInt-, writeReal-, writeChar-, writeHex-, writeLine-, move-,
			inc1-, inc2-, dec1-, dec2-, delete-, halt-, assert1-, assert2-, passivate-: Procedure;
		length-, exists-, realToInteger-, integerToReal-, integerToCharacter-, characterToInteger-, characterToText-, 
			minInteger-, maxInteger-, minReal-, maxReal-, terminated-, count-, random-,
			sine-, cosine-, tangent-, arcSine-, arcCosine-, arcTangent-, sqrt-: Procedure;
		
		exclusive-, shared-: Identifier;
		timesynchron-, array-: Identifier;
		
		indent-: LONGINT;

	PROCEDURE NewIdentifier*(position: LONGINT; x: ARRAY OF CHAR): Identifier;
	VAR id: Identifier;
	BEGIN NEW(id, position, x); RETURN id
	END NewIdentifier;

	(** scope = NIL if no enclosing component *)
	PROCEDURE NewComponent*(position: LONGINT; scope: Node; name: Identifier): Component;
	VAR c: Component;
	BEGIN 
		NEW(c, position, scope, name); 
		IF scope = NIL THEN compiledComponents.Add(c)
		ELSIF scope IS Component THEN scope(Component).nestedComponents.Add(c)
		ELSIF scope IS Implementation THEN scope(Implementation).nestedComponents.Add(c)
		ELSE HALT(111)
		END;
		RETURN c
	END NewComponent;
	
	(** scope = NIL if no enclosing component *)
	PROCEDURE NewInterface*(position: LONGINT; scope: Node; name: Identifier): Interface;
	VAR i: Interface;
	BEGIN 
		NEW(i, position, scope, name);
		IF scope = NIL THEN compiledInterfaces.Add(i)
		ELSIF scope IS Component THEN scope(Component).nestedInterfaces.Add(i)
		ELSIF scope IS Implementation THEN scope(Implementation).nestedInterfaces.Add(i)
		ELSE HALT(111)
		END;
		RETURN i
	END NewInterface;
	
	PROCEDURE NewImplementation*(position: LONGINT; scope: Component; name: Identifier): Implementation;
	VAR x: Implementation;
	BEGIN NEW(x, position, scope, name); scope.implementations.Add(x); RETURN x
	END NewImplementation;

	PROCEDURE NewProcedure*(position: LONGINT; scope: Node; name: Identifier): Procedure;
	VAR x: Procedure;
	BEGIN 
		NEW(x, position, scope, name); 
		IF scope IS Component THEN
			scope(Component).procedures.Add(x)
		ELSIF scope IS Implementation THEN
			scope(Implementation).nestedProcedures.Add(x)
		ELSIF scope IS Procedure THEN
			scope(Procedure).nestedProcedures.Add(x)
		ELSE HALT(111)
		END;
		RETURN x
	END NewProcedure;
			
	PROCEDURE NewConstant*(position: LONGINT; scope: Node; name: Identifier; expr: Expression): Constant;
	VAR c: Constant;
	BEGIN
		NEW(c, position, scope, name, expr);
		IF scope IS Component THEN scope(Component).constants.Add(c)
		ELSIF scope IS Implementation THEN scope(Implementation).constants.Add(c)
		ELSIF scope IS Procedure THEN scope(Procedure).constants.Add(c)
		ELSE HALT(111)
		END;
		RETURN c
	END NewConstant;
	
	PROCEDURE NewVariable*(position: LONGINT; scope: Node; name: Identifier): Variable;
	VAR v: Variable;
	BEGIN
		NEW(v, position, scope, name); 
		IF scope IS Component THEN scope(Component).variables.Add(v)
		ELSIF scope IS Implementation THEN scope(Implementation).variables.Add(v)
		ELSIF scope IS Procedure THEN scope(Procedure).variables.Add(v)
		ELSE HALT(111) (* not supported *)
		END;
		RETURN v
	END NewVariable;
	
	PROCEDURE NewSendStatement*(position: LONGINT; outerSeq: StatementSequence; 
		interface: Designator; message: Identifier): SendStatement;
	VAR s: SendStatement;
	BEGIN NEW(s, position, outerSeq, interface, message); outerSeq.statements.Add(s); RETURN s
	END NewSendStatement;
	
	PROCEDURE NewReceiveStatement*(position: LONGINT; outerSeq: StatementSequence;
		interface: Designator; message: Identifier): ReceiveStatement;
	VAR r: ReceiveStatement;
	BEGIN NEW(r, position, outerSeq, interface, message); outerSeq.statements.Add(r); RETURN r
	END NewReceiveStatement;
	
	PROCEDURE NewAssignment*(position: LONGINT; outerSeq: StatementSequence; left: Designator; 
		right: Expression): Assignment;
	VAR a: Assignment;
	BEGIN NEW(a, position, outerSeq, left, right); outerSeq.statements.Add(a); RETURN a
	END NewAssignment;

	PROCEDURE NewProcedureCall*(position: LONGINT; outerSeq: StatementSequence; name: Identifier): ProcedureCall;
	VAR x: ProcedureCall;
	BEGIN NEW(x, position, outerSeq, name); outerSeq.statements.Add(x); RETURN x
	END NewProcedureCall;
			
	PROCEDURE NewIfStatement*(startPosition: LONGINT; outerSeq: StatementSequence; ifCondition: Expression; 
		thenPosition: LONGINT): IfStatement;
	VAR x: IfStatement;
	BEGIN NEW(x, startPosition, outerSeq, thenPosition, ifCondition); outerSeq.statements.Add(x); RETURN x
	END NewIfStatement;
	
	PROCEDURE NewWhileStatement*(startPosition: LONGINT; outerSeq: StatementSequence; whileCondition: Expression;
		doPosition: LONGINT): WhileStatement;
	VAR x: WhileStatement;
	BEGIN NEW(x, startPosition, outerSeq, doPosition, whileCondition); outerSeq.statements.Add(x); RETURN x
	END NewWhileStatement;
	
	PROCEDURE NewRepeatStatement*(startPosition: LONGINT; outerSeq: StatementSequence; 
		bodyPosition: LONGINT): RepeatStatement;
	VAR x: RepeatStatement;
	BEGIN NEW(x, startPosition, outerSeq, bodyPosition); outerSeq.statements.Add(x); RETURN x
	END NewRepeatStatement;
	
	PROCEDURE NewForStatement*(startPosition: LONGINT; outerSeq: StatementSequence; bodyPosition: LONGINT;
		des: Designator; from, to, by: Expression): ForStatement;
	VAR x: ForStatement;
	BEGIN NEW(x, startPosition, outerSeq, bodyPosition, des, from, to, by); outerSeq.statements.Add(x); RETURN x
	END NewForStatement;
	
	PROCEDURE NewForeachStatement*(startPosition: LONGINT; outerSeq: StatementSequence): ForeachStatement;
	VAR x: ForeachStatement;
	BEGIN NEW(x, startPosition, outerSeq); outerSeq.statements.Add(x); RETURN x
	END NewForeachStatement;

	PROCEDURE NewAwaitStatement*(position: LONGINT; outerSeq: StatementSequence; 
		condition: Expression): AwaitStatement;
	VAR x: AwaitStatement;
	BEGIN NEW(x, position, outerSeq, condition); outerSeq.statements.Add(x); RETURN x
	END NewAwaitStatement;
				
	(** second may be NIL if not explicitly specified *)
	PROCEDURE NewNewStatement*(position: LONGINT; outerSeq: StatementSequence; 
		variableDes: Designator): NewStatement;
	VAR x: NewStatement;
	BEGIN NEW(x, position, outerSeq, variableDes); outerSeq.statements.Add(x); RETURN x
	END NewNewStatement;

	PROCEDURE NewConnectStatement*(position: LONGINT; outerSeq: StatementSequence; 
		source, target: Designator): ConnectStatement;
	VAR x: ConnectStatement;
	BEGIN NEW(x, position, outerSeq, source, target); outerSeq.statements.Add(x); RETURN x
	END NewConnectStatement;
	
	PROCEDURE NewDisconnectStatement*(position: LONGINT; outerSeq: StatementSequence; 
		des: Designator): DisconnectStatement;
	VAR x: DisconnectStatement;
	BEGIN NEW(x, position, outerSeq, des); outerSeq.statements.Add(x); RETURN x
	END NewDisconnectStatement;
	
	PROCEDURE NewReturnStatement*(position: LONGINT; outerSeq: StatementSequence; 
		expr: Expression): ReturnStatement;
	VAR x: ReturnStatement;
	BEGIN NEW(x, position, outerSeq, expr); outerSeq.statements.Add(x); RETURN x
	END NewReturnStatement;

	PROCEDURE NewStatementBlock*(position: LONGINT; outerSeq: StatementSequence): StatementSequence;
	VAR x: StatementSequence;
	BEGIN NEW(x, position, outerSeq); outerSeq.statements.Add(x); RETURN x
	END NewStatementBlock;
	
	PROCEDURE IsComponentType*(t: Type): BOOLEAN;
	BEGIN RETURN (t # NIL) & ((t IS ComponentType) OR (t IS AnyType))
	END IsComponentType;
	
	PROCEDURE ResolveConstantExpression(expr: Expression): Expression;
	VAR des: Designator; const: Constant;
	BEGIN
		IF expr IS Designator THEN
			des := expr(Designator);
			IF (des.node # NIL) & (des.node IS Constant) THEN
				const := des.node(Constant);
				RETURN const.expression
			END
		END;
		RETURN NIL
	END ResolveConstantExpression;		
	
	PROCEDURE IsConstantText*(expr: Expression): BOOLEAN;
	VAR funCall: FunctionCall; arg0: Expression;
	BEGIN 
		IF expr IS TextValue THEN
			RETURN TRUE
		ELSIF expr IS Designator THEN
			expr := ResolveConstantExpression(expr);
			RETURN (expr # NIL) & (expr.type = textType)
		ELSIF expr IS FunctionCall THEN
			funCall := expr(FunctionCall);
			IF funCall.arguments.Length() = 1 THEN
				arg0 := funCall.arguments.GetExpression(0);
				IF funCall.declaration = integerToCharacter THEN
					RETURN IsConstantInteger(arg0)
				END
			END;
			RETURN FALSE
		ELSE RETURN FALSE
		END
	END IsConstantText;
			
	PROCEDURE IsConstantInteger*(expr: Expression): BOOLEAN;
	VAR unary: UnaryExpression; binary: BinaryExpression; op: Operator; funCall: FunctionCall; arg0: Expression;
	BEGIN
		IF expr IS IntegerValue THEN 
			RETURN TRUE
		ELSIF expr IS UnaryExpression THEN
			unary := expr(UnaryExpression); op := unary.operator;
			RETURN ((op = Plus) OR (op = Minus)) & IsConstantInteger(unary.sub)
		ELSIF expr IS BinaryExpression THEN
			binary := expr(BinaryExpression); op := binary.operator;
			RETURN ((op = Plus) OR (op = Minus) OR (op = Times) OR (op = IntegerDivision) OR (op = Modulo))
				& IsConstantInteger(binary.left) & IsConstantInteger(binary.right)
		ELSIF expr IS Designator THEN
			expr := ResolveConstantExpression(expr);
			RETURN (expr # NIL) & (expr.type = integerType)
		ELSIF expr IS FunctionCall THEN
			funCall := expr(FunctionCall);
			IF funCall.arguments.Length() = 1 THEN
				arg0 := funCall.arguments.GetExpression(0);
				IF funCall.declaration = length THEN
					RETURN IsConstantText(arg0)
				ELSIF funCall.declaration = characterToInteger THEN
					RETURN IsConstantCharacter(arg0)
				ELSIF funCall.declaration = realToInteger THEN
					RETURN IsConstantReal(arg0)
				ELSIF (funCall.declaration = minInteger) OR (funCall.declaration = maxInteger) THEN
					RETURN TRUE
				END
			END;
			RETURN FALSE
		ELSE 
			RETURN FALSE
		END
	END IsConstantInteger;
	
	PROCEDURE IsConstantReal*(expr: Expression): BOOLEAN;
	VAR unary: UnaryExpression; binary: BinaryExpression; op: Operator; funCall: FunctionCall; arg0: Expression;
	BEGIN
		IF expr IS RealValue THEN
			RETURN TRUE
		ELSIF expr IS UnaryExpression THEN
			unary := expr(UnaryExpression); op := unary.operator;
			RETURN ((op = Plus) OR (op = Minus)) & IsConstantReal(unary.sub)
		ELSIF expr IS BinaryExpression THEN
			binary := expr(BinaryExpression); op := binary.operator;
			IF (op = Plus) OR (op = Minus) OR (op = Times) THEN
				IF IsConstantReal(binary.left) THEN
					RETURN IsConstantReal(binary.right) OR IsConstantInteger(binary.right)
				ELSIF IsConstantInteger(binary.left) THEN
					RETURN IsConstantReal(binary.right)
				ELSE
					RETURN FALSE
				END
			ELSIF op = RealDivision THEN
				RETURN 
					(IsConstantInteger(binary.left) OR IsConstantReal(binary.left)) &
					(IsConstantInteger(binary.right) OR IsConstantReal(binary.right))
			ELSE
				RETURN FALSE
			END
		ELSIF expr IS Designator THEN
			expr := ResolveConstantExpression(expr);
			RETURN (expr # NIL) & (expr.type = realType)
		ELSIF expr IS FunctionCall THEN
			funCall := expr(FunctionCall);
			IF funCall.arguments.Length() = 1 THEN
				arg0 := funCall.arguments.GetExpression(0);
				IF funCall.declaration = integerToReal THEN
					RETURN IsConstantInteger(arg0)
				ELSIF (funCall.declaration = minReal) OR (funCall.declaration = maxReal) THEN
					RETURN TRUE
				END
			END;
			RETURN FALSE
		ELSE
			RETURN FALSE
		END
	END IsConstantReal;
	
	PROCEDURE IsConstantBoolean*(expr: Expression): BOOLEAN;
	VAR unary: UnaryExpression; binary: BinaryExpression; op: Operator; 
	BEGIN
		IF expr IS BooleanValue THEN 
			RETURN TRUE
		ELSIF expr IS UnaryExpression THEN
			unary := expr(UnaryExpression); op := unary.operator;
			RETURN (op = Not) & IsConstantBoolean(unary.sub)
		ELSIF expr IS BinaryExpression THEN
			binary := expr(BinaryExpression); op := binary.operator;
			IF (binary.left.type = NIL) OR (binary.right.type = NIL) THEN RETURN FALSE END;
			IF (op = And) OR (op = Or) THEN
				RETURN IsConstantBoolean(binary.left) & IsConstantBoolean(binary.right)
			ELSIF (op = Equal) OR (op = Unequal) THEN
				IF binary.left.type = booleanType THEN
					RETURN IsConstantBoolean(binary.left) & IsConstantBoolean(binary.right)
				ELSIF binary.left.type = integerType THEN
					RETURN IsConstantInteger(binary.left) & IsConstantInteger(binary.right)
				ELSIF binary.left.type = realType THEN
					RETURN IsConstantReal(binary.left) & IsConstantReal(binary.right)
				ELSIF binary.left.type = characterType THEN
					RETURN IsConstantCharacter(binary.left) & IsConstantCharacter(binary.right)
				ELSIF binary.left.type = textType THEN
					RETURN IsConstantText(binary.left) & IsConstantText(binary.right)
				ELSE
					CCBasic.Error(binary.pos, "Undefined type")
				END
			ELSIF (op = Less) OR (op = LessEqual) OR (op = Greater) OR (op = GreaterEqual) THEN
				IF binary.left.type = integerType THEN
					RETURN IsConstantInteger(binary.left) & IsConstantInteger(binary.right)
				ELSIF binary.left.type = realType THEN	
					RETURN IsConstantReal(binary.left) & IsConstantReal(binary.right)
				ELSIF binary.left.type = characterType THEN
					RETURN IsConstantCharacter(binary.left) & IsConstantCharacter(binary.right)
				ELSIF binary.left.type = textType THEN
					RETURN IsConstantText(binary.left) & IsConstantText(binary.right)
				ELSE 
					CCBasic.Error(binary.pos, "Undefined type")
				END
			ELSE RETURN FALSE
			END
		ELSIF expr IS Designator THEN
			expr := ResolveConstantExpression(expr);
			RETURN (expr # NIL) & (expr.type = booleanType)
		ELSE RETURN FALSE
		END
	END IsConstantBoolean;
	
	PROCEDURE IsConstantCharacter*(expr: Expression): BOOLEAN;
	VAR funCall: FunctionCall; arg0: Expression;
	BEGIN
		IF expr IS CharacterValue THEN
			RETURN TRUE
		ELSIF expr IS Designator THEN
			expr := ResolveConstantExpression(expr);
			RETURN (expr # NIL) & (expr.type = characterType)
		ELSIF expr IS FunctionCall THEN
			funCall := expr(FunctionCall);
			IF funCall.arguments.Length() = 1 THEN
				arg0 := funCall.arguments.GetExpression(0);
				IF funCall.declaration = integerToCharacter THEN
					RETURN IsConstantInteger(arg0)
				END
			END;
			RETURN FALSE
		ELSE RETURN FALSE
		END
	END IsConstantCharacter;
	
	PROCEDURE ConstantText*(expr: Expression): CCBasic.String;
	BEGIN
		IF expr IS TextValue THEN
			RETURN expr(TextValue).text
		ELSIF expr IS Designator THEN
			expr := ResolveConstantExpression(expr);
			(* acyclic evaluation is ensured by checker *)
			RETURN ConstantText(expr)
		ELSE HALT(111)
		END
	END ConstantText;
	
	PROCEDURE ConstantInteger*(expr: Expression): LONGINT;
	VAR unary: UnaryExpression; binary: BinaryExpression; op: Operator; funCall: FunctionCall; arg0: Expression; s: CCBasic.String;
	BEGIN
		(* TODO: look for overflows, underflows, MIN(INTEGER) = -MAX(INTEGER)-1 *)
		IF expr IS IntegerValue THEN 
			RETURN expr(IntegerValue).int
		ELSIF expr IS UnaryExpression THEN
			unary := expr(UnaryExpression); op := unary.operator;
			IF op = Plus THEN RETURN ConstantInteger(unary.sub)
			ELSIF op = Minus THEN RETURN -ConstantInteger(unary.sub)
			ELSE HALT(111)
			END
		ELSIF expr IS BinaryExpression THEN
			binary := expr(BinaryExpression); op := binary.operator;
			IF op = Plus THEN RETURN ConstantInteger(binary.left) + ConstantInteger(binary.right)
			ELSIF op = Minus THEN RETURN ConstantInteger(binary.left) - ConstantInteger(binary.right)
			ELSIF op = Times THEN RETURN ConstantInteger(binary.left) * ConstantInteger(binary.right)
			ELSIF op = IntegerDivision THEN RETURN ConstantInteger(binary.left) DIV ConstantInteger(binary.right)
			ELSIF op = Modulo THEN RETURN ConstantInteger(binary.left) MOD ConstantInteger(binary.right)
			ELSE HALT(111)
			END
		ELSIF expr IS Designator THEN
			expr := ResolveConstantExpression(expr);
			(* acyclic evaluation is ensured by checker *)
			RETURN ConstantInteger(expr)
		ELSIF expr IS FunctionCall THEN
			funCall := expr(FunctionCall);
			IF funCall.arguments.Length() = 1 THEN
				arg0 := funCall.arguments.GetExpression(0);
				IF funCall.declaration = length THEN
					s := ConstantText(arg0);
					RETURN LEN(s)
				ELSIF funCall.declaration = characterToInteger THEN
					RETURN ORD(ConstantCharacter(arg0))
				ELSIF funCall.declaration = realToInteger THEN
					RETURN ENTIER(ConstantReal(arg0))
				ELSIF funCall.declaration = minInteger THEN
					RETURN MIN(LONGINT)
				ELSIF funCall.declaration = maxInteger THEN
					RETURN MAX(LONGINT)
				ELSE HALT(111)
				END
			ELSE HALT(111)
			END
		ELSE HALT(111)
		END
	END ConstantInteger;
	
	PROCEDURE ConstantReal*(expr: Expression): REAL;
	VAR unary: UnaryExpression; binary: BinaryExpression; op: Operator; left, right: REAL; funCall: FunctionCall; arg0: Expression;
	BEGIN
		IF expr IS RealValue THEN
			RETURN expr(RealValue).real
		ELSIF expr IS UnaryExpression THEN
			unary := expr(UnaryExpression); op := unary.operator;
			IF op = Plus THEN RETURN ConstantReal(unary.sub)
			ELSIF op = Minus THEN RETURN -ConstantReal(unary.sub)
			ELSE HALT(111)
			END
		ELSIF expr IS BinaryExpression THEN
			binary := expr(BinaryExpression); op := binary.operator;
			IF (op = Plus) OR (op = Minus) OR (op = Times) THEN
				IF IsConstantReal(binary.left) THEN
					left := ConstantReal(binary.left);
					IF IsConstantReal(binary.right) THEN
						right := ConstantReal(binary.right)
					ELSE
						right := ConstantInteger(binary.right)
					END
				ELSE
					left := ConstantInteger(binary.left);
					right := ConstantReal(binary.right)
				END;
				IF op = Plus THEN RETURN left + right
				ELSIF op = Minus THEN RETURN left - right
				ELSIF op = Times THEN RETURN left * right
				ELSE HALT(111)
				END
			ELSIF op = RealDivision THEN
				IF IsConstantReal(binary.left) THEN
					left := ConstantReal(binary.left)
				ELSE
					left := ConstantInteger(binary.left)
				END;
				IF IsConstantReal(binary.right) THEN
					right := ConstantReal(binary.right)
				ELSE
					right := ConstantInteger(binary.right)
				END;
				RETURN left / right
			ELSE HALT(111)
			END
		ELSIF expr IS Designator THEN
			expr := ResolveConstantExpression(expr);
			(* acyclic evaluation is ensured by checker *)
			RETURN ConstantReal(expr)
		ELSIF expr IS FunctionCall THEN
			funCall := expr(FunctionCall);
			IF funCall.arguments.Length() = 1 THEN
				arg0 := funCall.arguments.GetExpression(0);
				IF funCall.declaration = integerToReal THEN
					RETURN ConstantInteger(arg0)
				ELSIF funCall.declaration = minReal THEN
					RETURN MIN(REAL)
				ELSIF funCall.declaration = maxReal THEN
					RETURN MAX(REAL)
				ELSE HALT(111)
				END
			ELSE HALT(111)
			END
		ELSE HALT(111)
		END
	END ConstantReal;
	
	PROCEDURE ConstantBoolean*(expr: Expression): BOOLEAN;
	VAR unary: UnaryExpression; binary: BinaryExpression; op: Operator; a, b: CCBasic.String;
	BEGIN 
		IF expr IS BooleanValue THEN	
			RETURN expr(BooleanValue).bool
		ELSIF expr IS UnaryExpression THEN
			unary := expr(UnaryExpression); op := unary.operator;
			IF op = Not THEN RETURN ~ConstantBoolean(unary.sub)
			ELSE HALT(111)
			END
		ELSIF expr IS BinaryExpression THEN
			binary := expr(BinaryExpression); op := binary.operator;
			IF op = And THEN RETURN ConstantBoolean(binary.left) & ConstantBoolean(binary.right)
			ELSIF op = Or THEN RETURN ConstantBoolean(binary.left) OR ConstantBoolean(binary.right)
			ELSIF op = Equal THEN 
				IF binary.left.type = booleanType THEN
					RETURN ConstantBoolean(binary.left) = ConstantBoolean(binary.right)
				ELSIF binary.left.type = integerType THEN
					RETURN ConstantInteger(binary.left) = ConstantInteger(binary.right)
				ELSIF binary.left.type = realType THEN
					RETURN ConstantReal(binary.left) = ConstantReal(binary.right)
				ELSIF binary.left.type = characterType THEN
					RETURN ConstantCharacter(binary.left) = ConstantCharacter(binary.right)
				ELSIF binary.left.type = textType THEN
					a := ConstantText(binary.left);
					b := ConstantText(binary.right);
					RETURN a^ = b^
				ELSE HALT(111)
				END
			ELSIF op = Unequal THEN
				IF binary.left.type = booleanType THEN
					RETURN ConstantBoolean(binary.left) # ConstantBoolean(binary.right)
				ELSIF binary.left.type = integerType THEN
					RETURN ConstantInteger(binary.left) # ConstantInteger(binary.right)
				ELSIF binary.left.type = realType THEN
					RETURN ConstantReal(binary.left) # ConstantReal(binary.right)
				ELSIF binary.left.type = characterType THEN
					RETURN ConstantCharacter(binary.left) # ConstantCharacter(binary.right)
				ELSIF binary.left.type = textType THEN
					a := ConstantText(binary.left);
					b := ConstantText(binary.right);
					RETURN a^ # b^
				ELSE HALT(111)
				END
			ELSIF op = Less THEN 
				IF binary.left.type = integerType THEN
					RETURN ConstantInteger(binary.left) < ConstantInteger(binary.right)
				ELSIF binary.left.type = realType THEN
					RETURN ConstantReal(binary.left) < ConstantReal(binary.right)
				ELSIF binary.left.type = characterType THEN
					RETURN ConstantCharacter(binary.left) < ConstantCharacter(binary.right)
				ELSIF binary.left.type = textType THEN
					a := ConstantText(binary.left);
					b := ConstantText(binary.right);
					RETURN a^ < b^
				ELSE HALT(111)
				END
			ELSIF op = LessEqual THEN 
				IF binary.left.type = integerType THEN
					RETURN ConstantInteger(binary.left) <= ConstantInteger(binary.right)
				ELSIF binary.left.type = realType THEN
					RETURN ConstantReal(binary.left) <= ConstantReal(binary.right)
				ELSIF binary.left.type = characterType THEN
					RETURN ConstantCharacter(binary.left) <= ConstantCharacter(binary.right)
				ELSIF binary.left.type = textType THEN
					a := ConstantText(binary.left);
					b := ConstantText(binary.right);
					RETURN a^ <= b^
				ELSE HALT(111)
				END
			ELSIF op = Greater THEN 
				IF binary.left.type = integerType THEN
					RETURN ConstantInteger(binary.left) > ConstantInteger(binary.right)
				ELSIF binary.left.type = realType THEN
					RETURN ConstantReal(binary.left) > ConstantReal(binary.right)
				ELSIF binary.left.type = characterType THEN
					RETURN ConstantCharacter(binary.left) > ConstantCharacter(binary.right)
				ELSIF binary.left.type = textType THEN
					a := ConstantText(binary.left);
					b := ConstantText(binary.right);
					RETURN a^ > b^
				ELSE HALT(111)
				END
			ELSIF op = GreaterEqual THEN 
				IF binary.left.type = integerType THEN
					RETURN ConstantInteger(binary.left) >= ConstantInteger(binary.right)
				ELSIF binary.left.type = realType THEN
					RETURN ConstantReal(binary.left) >= ConstantReal(binary.right)
				ELSIF binary.left.type = characterType THEN
					RETURN ConstantCharacter(binary.left) >= ConstantCharacter(binary.right)
				ELSIF binary.left.type = textType THEN
					a := ConstantText(binary.left);
					b := ConstantText(binary.right);
					RETURN a^ >= b^
				ELSE HALT(111)
				END
			ELSE HALT(111)
			END
		ELSIF expr IS Designator THEN
			expr := ResolveConstantExpression(expr);
			(* acyclic evaluation is ensured by checker *)
			RETURN ConstantBoolean(expr)
		ELSE HALT(111)
		END
	END ConstantBoolean;
	
	PROCEDURE ConstantCharacter*(expr: Expression): CHAR;
	VAR funCall: FunctionCall; arg0: Expression;
	BEGIN
		IF expr IS CharacterValue THEN
			RETURN expr(CharacterValue).char
		ELSIF expr IS Designator THEN
			expr := ResolveConstantExpression(expr);
			(* acyclic evaluation is ensured by checker *)
			RETURN ConstantCharacter(expr)
		ELSIF expr IS FunctionCall THEN
			funCall := expr(FunctionCall);
			IF funCall.arguments.Length() = 1 THEN
				arg0 := funCall.arguments.GetExpression(0);
				IF funCall.declaration = integerToCharacter THEN
					RETURN CHR(ConstantInteger(arg0))
				ELSE HALT(111)
				END
			ELSE HALT(111)
			END
		ELSE HALT(111)
		END
	END ConstantCharacter;
	
	PROCEDURE IsReservedName*(id: Identifier): BOOLEAN;
	BEGIN RETURN reservedNames.Contains(id)
	END IsReservedName;
	
	(** NIL if no surrounding component *)
	PROCEDURE GetSurroundingComponent*(current: Node): Component;
	BEGIN
		WHILE (current # NIL) & ~(current IS Component) DO
			IF current IS Statement THEN
				current := current(Statement).outer
			ELSIF current IS Expression THEN
				current := current(Expression).outer
			ELSIF current IS Implementation THEN
				current := current(Implementation).outer
			ELSIF current IS Interface THEN
				current := current(Interface).outer
			ELSIF current IS Procedure THEN
				current := current(Procedure).outer
			ELSE HALT(111)
			END
		END;
		IF current # NIL THEN RETURN current(Component) 
		ELSE RETURN NIL
		END
	END GetSurroundingComponent;
	
	PROCEDURE InInitializerOrFinalizer*(current: Node): BOOLEAN;
	VAR lastSeq: StatementSequence; com: Component;
	BEGIN
		lastSeq := NIL;
		WHILE (current # NIL) & ((current IS Statement) OR (current IS Expression)) DO
			IF current IS StatementSequence THEN
				lastSeq := current(StatementSequence)
			END;
			IF current IS Statement THEN current := current(Statement).outer
			ELSE current := current(Expression).outer
			END
		END;
		IF (current # NIL) & (current IS Component) THEN
			com := current(Component);
			RETURN (lastSeq = com.initializer) OR (lastSeq = com.finalizer)
		ELSE
			RETURN FALSE
		END
	END InInitializerOrFinalizer;
	
	(** NIL if no surrounding implementation block *)
	PROCEDURE GetSurroundingImplementation*(current: Node): Implementation;
	BEGIN
		WHILE (current # NIL) & ((current IS Statement) OR (current IS Expression)) DO
			IF current IS Statement THEN current := current(Statement).outer
			ELSE current := current(Expression).outer
			END
		END;
		IF (current # NIL) & (current IS Implementation) THEN RETURN current(Implementation)
		ELSE RETURN NIL
		END
	END GetSurroundingImplementation;
	
	(** NIL if no directly surrounding procedure *)
	PROCEDURE GetSurroundingProcedure*(current: Node): Procedure;
	BEGIN
		WHILE (current # NIL) & ((current IS Statement) OR (current IS Expression)) DO
			IF current IS Statement THEN current := current(Statement).outer
			ELSE current := current(Expression).outer
			END
		END;
		IF (current # NIL) & (current IS Procedure) THEN 
			RETURN current(Procedure)
		ELSE RETURN NIL
		END
	END GetSurroundingProcedure;
	
	PROCEDURE GetCurrentScope*(current: Node): Node;
	BEGIN
		WHILE (current # NIL) & ((current IS Statement) OR (current IS Expression)) DO
			IF current IS Statement THEN current := current(Statement).outer
			ELSE current := current(Expression).outer
			END
		END;
		RETURN current
	END GetCurrentScope;
		
	PROCEDURE GetOutmostComponent*(current: Node): Component;
	VAR outmost: Component;
	BEGIN
		outmost := NIL;
		WHILE current # NIL DO
			IF current IS Component THEN
				outmost := current(Component);
				current := outmost.outer
			ELSIF current IS Implementation THEN
				current := current(Implementation).outer
			ELSE HALT(111)
			END
		END;
		RETURN outmost
	END GetOutmostComponent;
	
	(** NIL if current has no surrounding AWAIT-statement *)
	PROCEDURE GetSurroundingAwaitStatement*(current: Node): AwaitStatement;
	BEGIN
		WHILE (current IS Statement) OR (current IS Expression) DO
			IF current IS AwaitStatement THEN RETURN current(AwaitStatement)
			ELSIF current IS Statement THEN current := current(Statement).outer
			ELSE current := current(Expression).outer
			END
		END;
		RETURN NIL
	END GetSurroundingAwaitStatement;
	
	PROCEDURE PotentialFirstMessage*(interface: Interface; message: Identifier): BOOLEAN;
	VAR optional: BOOLEAN;
	
		PROCEDURE FirstInProtocol(protocol: Protocol; VAR optional: BOOLEAN): BOOLEAN;
		VAR b, o1, o2: BOOLEAN;
		BEGIN
			IF protocol IS MessageDeclaration THEN
				b := protocol(MessageDeclaration).name.Equal(message);
				optional := FALSE
			ELSIF protocol IS ProtocolSequence THEN
				b := FirstInProtocol(protocol(ProtocolSequence).first, o1);
				IF ~b & o1 THEN
					b := FirstInProtocol(protocol(ProtocolSequence).second, o1)
				END;
				optional := o1
			ELSIF protocol IS ProtocolOption THEN
				b := FirstInProtocol(protocol(ProtocolOption).protocol, o1);
				optional := TRUE
			ELSIF protocol IS ProtocolRepetition THEN
				b := FirstInProtocol(protocol(ProtocolRepetition).protocol, o1);
				optional := TRUE
			ELSIF protocol IS ProtocolAlternative THEN
				b := FirstInProtocol(protocol(ProtocolAlternative).first, o1) OR 
					FirstInProtocol(protocol(ProtocolAlternative).second, o2);
				optional := o1 OR o2
			ELSE HALT(111)
			END;
			RETURN b
		END FirstInProtocol;
	
	BEGIN
		IF interface.protocol # NIL THEN
			RETURN FirstInProtocol(interface.protocol, optional)
		ELSE
			RETURN FALSE
		END
	END PotentialFirstMessage;
	
	PROCEDURE GuaranteedLastMessage*(interface: Interface; message: Identifier): BOOLEAN;
		VAR middle, b: BOOLEAN;
		
		PROCEDURE LastInProtocol(protocol: Protocol; VAR middle: BOOLEAN): BOOLEAN;
		VAR b, x, m1, m2: BOOLEAN;
		BEGIN
			IF protocol IS MessageDeclaration THEN
				b := protocol(MessageDeclaration).name.Equal(message);
				middle := FALSE
			ELSIF protocol IS ProtocolSequence THEN
				x := LastInProtocol(protocol(ProtocolSequence).first, m1);
				IF x OR m1 THEN b := FALSE
				ELSE
					b := LastInProtocol(protocol(ProtocolSequence).second, m2);
					IF m2 THEN b := FALSE END
				END;
				middle := x OR m1 OR m2
			ELSIF protocol IS ProtocolOption THEN
				b := LastInProtocol(protocol(ProtocolOption).protocol, m1);
				IF m1 THEN b := FALSE END;
				middle := m1
			ELSIF protocol IS ProtocolRepetition THEN
				x := LastInProtocol(protocol(ProtocolRepetition).protocol, m1);
				b := FALSE;
				middle := x OR m1
			ELSIF protocol IS ProtocolAlternative THEN
				b := LastInProtocol(protocol(ProtocolAlternative).first, m1) OR 
					LastInProtocol(protocol(ProtocolAlternative).second, m2);
				IF m1 OR m2 THEN b := FALSE END;
				middle := m1 OR m2
			ELSE HALT(111)
			END;
			RETURN b
		END LastInProtocol;
		
	BEGIN
		IF interface.protocol # NIL THEN
			b := LastInProtocol(interface.protocol, middle);
			RETURN ~middle & b
		ELSE
			RETURN FALSE
		END
	END GuaranteedLastMessage;
	
	(* NIL if no current lock *)
	PROCEDURE CurrentLockType*(node: Node): Identifier;
	VAR seq: StatementSequence;
	BEGIN
		ASSERT(node # NIL);
		WHILE (node IS Statement) OR (node IS Expression) DO
			IF node.attributeList # NIL THEN
				IF node.attributeList.Contains(exclusive) THEN RETURN exclusive
				ELSIF node.attributeList.Contains(shared) THEN RETURN shared
				END
			END;
			IF node IS Statement THEN node := node(Statement).outer
			ELSE node := node(Expression).outer
			END
		END;
		ASSERT((node IS Component) OR (node IS Implementation) OR (node IS Procedure));
		RETURN NIL
	END CurrentLockType;
		
	(** NIL if not resolved *)
	PROCEDURE OfferedInterfaces*(type: Type): InterfaceDeclarationList;
	VAR component: ComponentDefinition;
	BEGIN
		IF type IS ComponentType THEN
			component := type(ComponentType).componentDefinition;
			IF component = NIL THEN RETURN NIL (* not resolved *)
			ELSE RETURN component.offeredInterfaces
			END
		ELSIF type IS AnyType THEN
			RETURN type(AnyType).offeredInterfaces
		ELSE HALT(111)
		END
	END OfferedInterfaces;

	(** NIL if not resolved *)
	PROCEDURE RequiredInterfaces*(type: Type): InterfaceDeclarationList;
	VAR component: ComponentDefinition;
	BEGIN
		IF type IS ComponentType THEN
			component := type(ComponentType).componentDefinition;
			IF component = NIL THEN RETURN NIL (* not resolved *)
			ELSE RETURN component.requiredInterfaces
			END
		ELSIF type IS AnyType THEN
			RETURN type(AnyType).requiredInterfaces
		ELSE HALT(111)
		END
	END RequiredInterfaces;
	
	PROCEDURE IsArrayCollection*(var: Variable): BOOLEAN;
	BEGIN 
		IF (var.attributeList # NIL) & var.attributeList.Contains(array) THEN
			ASSERT(var.parameters.Length() > 0);
			RETURN TRUE
		ELSE
			RETURN FALSE
		END
	END IsArrayCollection;
	
	PROCEDURE EmptyIdentifierList*(): IdentifierList;
	VAR list: IdentifierList;
	BEGIN NEW(list); RETURN list
	END EmptyIdentifierList;
			
	PROCEDURE Initialize*;
	BEGIN NEW(compiledComponents); NEW(compiledInterfaces); NEW(importedComponents); NEW(importedInterfaces)
	END Initialize;
	
	PROCEDURE Free*;
	BEGIN compiledComponents := NIL; compiledInterfaces := NIL; importedComponents := NIL; importedInterfaces := NIL
	END Free;
	
	PROCEDURE CreateDataType(VAR dt: DataType; name: ARRAY OF CHAR);
	BEGIN NEW(dt, name); reservedNames.Add(dt.name)
	END CreateDataType;
			
	PROCEDURE NewInbuiltProcedure(VAR p: Procedure; name: ARRAY OF CHAR; result: Type);
	BEGIN
		NEW(p, -1, NIL, NewIdentifier(-1, name)); 
		predefinedProcedures.Add(p);
		IF result # NIL THEN p.SetType(result) END;
		IF ~reservedNames.Contains(p.name) THEN
			reservedNames.Add(p.name)
		END
	END NewInbuiltProcedure;

	PROCEDURE AddInbuiltParameter(p: Procedure; isVar: BOOLEAN; name: ARRAY OF CHAR; type: Type);
	BEGIN p.AddParameter(-1, isVar, NewIdentifier(-1, name), type)
	END AddInbuiltParameter;
			
	PROCEDURE NewReservedName(VAR x: Identifier; name: ARRAY OF CHAR);
	BEGIN NEW(x, -1, name); reservedNames.Add(x)
	END NewReservedName;
	
	PROCEDURE NewReservedConstant(name: ARRAY OF CHAR; expr: Expression);
	VAR c: Constant;
	BEGIN 
		NEW(c, -1, NIL, NewIdentifier(-1, name), expr);
		predefinedConstants.Add(c);
		IF ~reservedNames.Contains(c.name) THEN
			reservedNames.Add(c.name)
		END
	END NewReservedConstant;
	
	PROCEDURE NewReservedRealConstant(name: ARRAY OF CHAR; value: REAL);
	VAR rv: RealValue;
	BEGIN
		NEW(rv, -1, value); rv.SetType(realType);
		NewReservedConstant(name, rv)
	END NewReservedRealConstant;
	
	PROCEDURE NewReservedVariable(VAR v: Variable; name: ARRAY OF CHAR; type: Type);
	BEGIN
		NEW(v, -1, NIL, NewIdentifier(-1, name)); v.SetType(type);
		predefinedVariables.Add(v);
		IF ~reservedNames.Contains(v.name) THEN
			reservedNames.Add(v.name)
		END
	END NewReservedVariable;

	PROCEDURE MakeQualIdent(current: Node; id: Identifier): Identifier;
	VAR currentName: Identifier; s: CCBasic.String; 
	BEGIN
		s := id.name;
		WHILE current # NIL DO
			IF current IS Component THEN
				currentName := current(Component).name;
				current := current(Component).outer
			ELSIF current IS Implementation THEN
				currentName := current(Implementation).name;
				current := current(Implementation).outer
			ELSE HALT(111)
			END;
			s := CCBasic.ConcatWithSeparator(currentName.name^, ".", s^)
		END;
		NEW(id, id.pos, s^);
		RETURN id
	END MakeQualIdent;
			
	PROCEDURE Print*;
	BEGIN 
		indent := 0; 
		CCBasic.OutText("Compiled elements"); CCBasic.OutLine;
		Indent; compiledComponents.Print; compiledInterfaces.Print; 
		CCBasic.OutText("Imported elements"); CCBasic.OutLine;
		Indent; importedComponents.Print; importedInterfaces.Print
	END Print;
	
	PROCEDURE Indent;
	VAR i: LONGINT;
	BEGIN FOR i := 1 TO indent DO CCBasic.OutText("  ") END
	END Indent;
	
BEGIN
	NEW(reservedNames);
	NEW(predefinedProcedures);
	NEW(predefinedConstants);
	NEW(predefinedVariables);
	
	CreateDataType(integerType, "INTEGER");
	CreateDataType(realType, "REAL");
	CreateDataType(textType, "TEXT");
	CreateDataType(booleanType, "BOOLEAN");
	CreateDataType(characterType, "CHARACTER");
	NEW(anyType, -1); (* ANY *)
	
	NewReservedName(exclusive, "EXCLUSIVE");
	NewReservedName(shared, "SHARED");
	
	NewReservedName(timesynchron, "SYNCHRONOUS");
	NewReservedName(array, "ARRAY");
		
	NewReservedRealConstant("PI", 3.14159265358979323846E0);
	
	NewReservedVariable(time, "TIME", integerType);
		
	(* predefined proper procedures *)
	NewInbuiltProcedure(writeText, "WRITE", NIL); 
		AddInbuiltParameter(writeText, FALSE, "x", textType);
	NewInbuiltProcedure(writeInt, "WRITE", NIL); 
		AddInbuiltParameter(writeInt, FALSE, "x", integerType);
	NewInbuiltProcedure(writeReal, "WRITE", NIL);
		AddInbuiltParameter(writeReal, FALSE, "x", realType);
	NewInbuiltProcedure(writeChar, "WRITE", NIL); 
		AddInbuiltParameter(writeChar, FALSE, "x", characterType);
	NewInbuiltProcedure(writeHex, "WRITEHEX", NIL); 
		AddInbuiltParameter(writeHex, FALSE, "x", integerType);
	NewInbuiltProcedure(writeLine, "WRITELINE", NIL);
	NewInbuiltProcedure(inc1, "INC", NIL); 
		AddInbuiltParameter(inc1, TRUE, "x", integerType);
	NewInbuiltProcedure(inc2, "INC", NIL); 
		AddInbuiltParameter(inc2, TRUE, "x", integerType); 
		AddInbuiltParameter(inc2, FALSE, "inc", integerType);
	NewInbuiltProcedure(dec1, "DEC", NIL); 
		AddInbuiltParameter(dec1, TRUE, "x", integerType);
	NewInbuiltProcedure(dec2, "DEC", NIL); 
		AddInbuiltParameter(dec2, TRUE, "x", integerType); 
		AddInbuiltParameter(dec2, FALSE, "inc", integerType);
	NewInbuiltProcedure(delete, "DELETE", NIL); 
		AddInbuiltParameter(delete, TRUE, "x", anyType);
	NewInbuiltProcedure(halt, "HALT", NIL); 
		AddInbuiltParameter(halt, FALSE, "code", integerType);
	NewInbuiltProcedure(assert1, "ASSERT", NIL); 
		AddInbuiltParameter(assert1, FALSE, "condition", booleanType);
	NewInbuiltProcedure(assert2, "ASSERT", NIL); 
		AddInbuiltParameter(assert2, FALSE, "condition", booleanType); 
		AddInbuiltParameter(assert2, FALSE, "haltcode", integerType);
	NewInbuiltProcedure(passivate, "PASSIVATE", NIL); 
		AddInbuiltParameter(passivate, FALSE, "ms", integerType);
	NewInbuiltProcedure(move, "MOVE", NIL);
		AddInbuiltParameter(move, TRUE, "source", anyType);
		AddInbuiltParameter(move, TRUE, "target", anyType);	
	
	(* predefined function procedures *)	
	NewInbuiltProcedure(integerToReal, "REAL", realType);
		AddInbuiltParameter(integerToReal, FALSE, "x", integerType);
	NewInbuiltProcedure(realToInteger, "INTEGER", integerType);
		AddInbuiltParameter(realToInteger, FALSE, "x", realType);
	NewInbuiltProcedure(characterToInteger, "INTEGER", integerType); 
		AddInbuiltParameter(characterToInteger, FALSE, "x", characterType);
	NewInbuiltProcedure(integerToCharacter, "CHARACTER", characterType); 
		AddInbuiltParameter(integerToCharacter, FALSE, "x", integerType);
	NewInbuiltProcedure(characterToText, "TEXT", textType);
		AddInbuiltParameter(characterToText, FALSE, "x", characterType);
	NewInbuiltProcedure(length, "LENGTH", integerType); 
		AddInbuiltParameter(length, FALSE, "x", anyType);
	NewInbuiltProcedure(exists, "EXISTS", booleanType); 
		AddInbuiltParameter(exists, TRUE, "x", anyType);
	NewInbuiltProcedure(minInteger, "MIN", integerType);
		AddInbuiltParameter(minInteger, FALSE, "x", anyType); 
		(* identifier INTEGER as argument *)
	NewInbuiltProcedure(maxInteger, "MAX", integerType);
		AddInbuiltParameter(maxInteger, FALSE, "x", anyType); 
		(* identifier INTEGER as argument *)
	NewInbuiltProcedure(minReal, "MIN", realType);
		AddInbuiltParameter(minReal, FALSE, "x", anyType); 
		(* identifier REAL as argument *)
	NewInbuiltProcedure(maxReal, "MAX", realType);
		AddInbuiltParameter(maxReal, FALSE, "x", anyType); 
		(* identifier REAL as argument *)
	NewInbuiltProcedure(terminated, "TERMINATED", booleanType);
	NewInbuiltProcedure(count, "COUNT", integerType);
		AddInbuiltParameter(count, FALSE, "interfaceSet", anyType);
		(* argument is a designator of an interface collection *)
	NewInbuiltProcedure(random, "RANDOM", integerType);
		AddInbuiltParameter(random, FALSE, "min", integerType);
		AddInbuiltParameter(random, FALSE, "max", integerType);
	NewInbuiltProcedure(sine, "SIN", realType);
		AddInbuiltParameter(sine, FALSE, "x", realType);
	NewInbuiltProcedure(cosine, "COS", realType);
		AddInbuiltParameter(cosine, FALSE, "x", realType);
	NewInbuiltProcedure(tangent, "TAN", realType);
		AddInbuiltParameter(tangent, FALSE, "x", realType);
	NewInbuiltProcedure(arcSine, "ARCSIN", realType);
		AddInbuiltParameter(arcSine, FALSE, "x", realType);
	NewInbuiltProcedure(arcCosine, "ARCCOS", realType);
		AddInbuiltParameter(arcCosine, FALSE, "x", realType);
	NewInbuiltProcedure(arcTangent, "ARCTAN", realType);
		AddInbuiltParameter(arcTangent, FALSE, "x", realType);
	NewInbuiltProcedure(sqrt, "SQRT", realType);
		AddInbuiltParameter(sqrt, FALSE, "x", realType)
END CCIR.

