MODULE CCImporter; (** Component Compiler, External Program File Importer, 2005-2007 by Luc Blaeser *)
	IMPORT CCIR, CCBasic, CBC, AosIO := Streams, AosFS := Files;

	TYPE
		TextTable = POINTER TO ARRAY OF CCBasic.String;

	VAR 
		reader: AosIO.Reader; length: LONGINT; filename: CCBasic.String;
		char: CHAR; position: LONGINT; error-: BOOLEAN;

	PROCEDURE Initialize*;
	BEGIN Free
	END Initialize;
	
	PROCEDURE Free*;
	BEGIN reader := NIL; length := 0; error := FALSE
	END Free;

	PROCEDURE ImportComponent*(name: CCIR.Identifier): CCIR.ComponentDefinition;
	VAR component: CCIR.ComponentDefinition; nofComponents, i: LONGINT; ident: CCIR.Identifier; ignore: LONGINT;
	BEGIN
		Initialize;
		OpenFile(name.name^, CBC.FileSuffix);
		IF reader # NIL THEN
			ParseHeaderProlog;
			SkipUsedInterfaces;
			SkipUsedComponents;
			SkipNewInterfaces;
			nofComponents := Integer4();
			FOR i := 0 TO nofComponents-1 DO
				ident := ParseIdentifier();
				IF ident.Equal(name) THEN
					NEW(component, -1, ident);
					ParseOfferedInterfaces(component.offeredInterfaces);
					ParseRequiredInterfaces(component.requiredInterfaces);
					CCIR.importedComponents.Add(component)
				ELSE
					SkipOfferedInterfaces;
					SkipRequiredInterfaces
				END;
				ignore := Integer4(); (* size *)
				ignore := Integer4(); (* initializerOffset *)
				ignore := Integer4() (* finalizerOffset *)
			END
		END;
		Free;
		RETURN component
	END ImportComponent;
	
	PROCEDURE ImportInterface*(name: CCIR.Identifier): CCIR.Interface;
	VAR interface: CCIR.Interface; nofInterfaces, i: LONGINT; ident: CCIR.Identifier;
	BEGIN
		Initialize; 
		OpenFile(name.name^, CBC.FileSuffix);
		IF reader # NIL THEN
			ParseHeaderProlog;
			SkipUsedInterfaces;
			SkipUsedComponents;
			nofInterfaces := Integer4();
			FOR i := 0 TO nofInterfaces-1 DO
				ident := ParseIdentifier();
				IF ident.Equal(name) THEN
					NEW(interface, -1, NIL, ident);
					ParseMessageDeclList(interface.messageDeclarations);
					interface.SetProtocol(ParseProtocol(interface.messageDeclarations));
					CCIR.importedInterfaces.Add(interface)
				ELSE
					SkipMessageDeclList;
					SkipProtocol
				END;
				SkipProtocolMatrix
			END
		END;
		Free;
		RETURN interface;
	END ImportInterface;
	
	PROCEDURE ParseHeaderProlog;
	BEGIN Check(CBC.FTag); Check(CBC.FVersion)
	END ParseHeaderProlog;
	
	PROCEDURE ParseIdentifier(): CCIR.Identifier;
	VAR name: CCBasic.String;
	BEGIN
		name := Text();
		RETURN CCIR.NewIdentifier(-1, name^)
	END ParseIdentifier;

	PROCEDURE ParseOfferedInterfaces(list: CCIR.InterfaceDeclarationList);
	VAR nofInterfaces, i: LONGINT; name: CCIR.Identifier; decl: CCIR.InterfaceDeclaration;
	BEGIN
		nofInterfaces := Integer4();
		FOR i := 0 TO nofInterfaces-1 DO
			name := ParseIdentifier();
			NEW(decl, -1, name, 1, 1);
			list.Add(decl)
		END
	END ParseOfferedInterfaces;
	
	PROCEDURE SkipOfferedInterfaces;
	VAR list: CCIR.InterfaceDeclarationList;
	BEGIN
		NEW(list);
		ParseOfferedInterfaces(list)
	END SkipOfferedInterfaces;
	
	PROCEDURE ParseRequiredInterfaces(list: CCIR.InterfaceDeclarationList);
	VAR nofInterfaces, i, min, max: LONGINT; name: CCIR.Identifier; decl: CCIR.InterfaceDeclaration;
	BEGIN
		nofInterfaces := Integer4();
		FOR i := 0 TO nofInterfaces-1 DO
			name := ParseIdentifier(); min := Integer4(); max := Integer4();
			NEW(decl, -1, name, min, max);
			list.Add(decl)
		END
	END ParseRequiredInterfaces;
	
	PROCEDURE SkipRequiredInterfaces;
	VAR list: CCIR.InterfaceDeclarationList;
	BEGIN
		NEW(list);
		ParseRequiredInterfaces(list)
	END SkipRequiredInterfaces;
	
	PROCEDURE ParseMessageDeclList(list: CCIR.MessageDeclarationList);
	VAR nofMessages, i: LONGINT;
	BEGIN
		nofMessages := Integer4();
		FOR i := 0 TO nofMessages-1 DO
			ParseMessageDeclaration(list)
		END
	END ParseMessageDeclList;
	
	PROCEDURE SkipMessageDeclList;
	VAR list: CCIR.MessageDeclarationList;
	BEGIN
		NEW(list);
		ParseMessageDeclList(list)
	END SkipMessageDeclList;
	
	PROCEDURE ParseMessageDeclaration(list: CCIR.MessageDeclarationList);
	VAR in: BOOLEAN; name: CCIR.Identifier; md: CCIR.MessageDeclaration;
	BEGIN
		IF char = CBC.FIn THEN Next; in := TRUE ELSE Check(CBC.FOut); in := FALSE END;
		name := ParseIdentifier();
		NEW(md, -1, name, in);
		ParseParameterList(md.parameters);
		list.Add(md)
	END ParseMessageDeclaration;
	
	PROCEDURE ParseParameterList(list: CCIR.ParameterList);
	VAR nofParameters, i: LONGINT;
	BEGIN
		nofParameters := Integer4();
		FOR i := 0 TO nofParameters-1 DO
			ParseParameter(list)
		END
	END ParseParameterList;
	
	PROCEDURE ParseParameter(list: CCIR.ParameterList);
	VAR type: CCIR.Type; par: CCIR.Parameter;
	BEGIN
		type := ParseType();
		NEW(par, -1, CCIR.NewIdentifier(-1, ""), type); 
		list.Add(par)
	END ParseParameter;
	
	PROCEDURE ParseType(): CCIR.Type;
	VAR name: CCIR.Identifier; ct: CCIR.ComponentType; at: CCIR.AnyType;
	BEGIN
		IF char = CBC.FIntegerType THEN Next; RETURN CCIR.integerType
		ELSIF char = CBC.FRealType THEN Next; RETURN CCIR.realType
		ELSIF char = CBC.FBooleanType THEN Next; RETURN CCIR.booleanType
		ELSIF char = CBC.FCharacterType THEN Next; RETURN CCIR.characterType
		ELSIF char = CBC.FTextType THEN Next; RETURN CCIR.textType
		ELSIF char = CBC.FComponentType THEN
			Next; name := ParseIdentifier();
			NEW(ct, -1, name);
			RETURN ct
		ELSE
			Check(CBC.FAnyType);
			NEW(at, -1);
			ParseOfferedInterfaces(at.offeredInterfaces);
			ParseRequiredInterfaces(at.requiredInterfaces);
			RETURN at
		END
	END ParseType;
	
	(* NIL if empty protocol *)
	PROCEDURE ParseProtocol(mdList: CCIR.MessageDeclarationList): CCIR.Protocol;
	BEGIN
		IF char = CBC.FNoProtocol THEN Next; RETURN NIL
		ELSE RETURN ParseProtocolExpr(mdList)
		END
	END ParseProtocol;
	
	PROCEDURE ParseProtocolExpr(mdList: CCIR.MessageDeclarationList): CCIR.Protocol;
	VAR index: LONGINT; md: CCIR.MessageDeclaration; first, second: CCIR.Protocol;
		seq: CCIR.ProtocolSequence; alt: CCIR.ProtocolAlternative; rep: CCIR.ProtocolRepetition; opt: CCIR.ProtocolOption;
	BEGIN
		IF char = CBC.FMessageDecl THEN
			Next;
			index := Integer4();
			IF mdList # NIL THEN
				md := mdList.GetMessageDeclaration(index)
			ELSE md := NIL
			END;
			RETURN md
		ELSIF char = CBC.FSequence THEN
			Next;
			first := ParseProtocolExpr(mdList); second := ParseProtocolExpr(mdList);
			NEW(seq, -1, first, second); 
			RETURN seq
		ELSIF char = CBC.FAlternative THEN
			Next;
			first := ParseProtocolExpr(mdList); second := ParseProtocolExpr(mdList);
			NEW(alt, -1, first, second);
			RETURN alt
		ELSIF char = CBC.FRepetition THEN
			Next;
			first := ParseProtocolExpr(mdList);
			NEW(rep, -1, first);
			RETURN rep
		ELSIF char = CBC.FOption THEN
			Next;
			first := ParseProtocolExpr(mdList);
			NEW(opt, -1, first);
			RETURN opt
		ELSE 
			Error(0X, "Invalid protocol");
			RETURN NIL
		END
	END ParseProtocolExpr;
	
	PROCEDURE SkipProtocol;
	VAR p: CCIR.Protocol; 
	BEGIN p := ParseProtocol(NIL)
	END SkipProtocol;
	
	PROCEDURE SkipUsedInterfaceList;
	VAR nofInterfaces, i: LONGINT; name: CCIR.Identifier;
	BEGIN
		nofInterfaces := Integer4();
		FOR i := 0 TO nofInterfaces-1 DO
			name := ParseIdentifier();
			SkipMessageDeclList;
			SkipProtocol
		END
	END SkipUsedInterfaceList;
	
	PROCEDURE SkipNewInterfaceList;
	VAR nofInterfaces, i: LONGINT; name: CCIR.Identifier; 
	BEGIN
		nofInterfaces := Integer4();
		FOR i := 0 TO nofInterfaces-1 DO
			name := ParseIdentifier();
			SkipMessageDeclList;
			SkipProtocol;
			SkipProtocolMatrix
		END
	END SkipNewInterfaceList;
	
	PROCEDURE SkipProtocolMatrix;
	VAR length, k: LONGINT;
	BEGIN
		length := Integer4();
		FOR k := 0 TO length-1 DO Next END
	END SkipProtocolMatrix;
	
	PROCEDURE SkipUsedComponents;
	VAR nofComponents, i: LONGINT; name: CCIR.Identifier;
	BEGIN
		nofComponents := Integer4();
		FOR i := 0 TO nofComponents-1 DO
			name := ParseIdentifier();
			SkipOfferedInterfaces;
			SkipRequiredInterfaces
		END
	END SkipUsedComponents;
	
	PROCEDURE SkipUsedInterfaces;
	BEGIN SkipUsedInterfaceList
	END SkipUsedInterfaces;
	
	PROCEDURE SkipNewInterfaces;
	BEGIN SkipNewInterfaceList
	END SkipNewInterfaces;
		
	(* TRUE if successfull *)
	PROCEDURE OpenFile(name, suffix: ARRAY OF CHAR);
	VAR file: AosFS.File; r: AosFS.Reader;
	BEGIN
		filename := CCBasic.ConcatWithDot(name, suffix);
		file := AosFS.Old(filename^);
		IF file # NIL THEN
			AosFS.OpenReader(r, file, 0);
			reader := r; length := file.Length(); position := 0; 
			Next
		ELSE
			reader := NIL; length := 0; filename := NIL; char := 0X; position := 0
		END
	END OpenFile;
	
	PROCEDURE Error(expected: CHAR; message: ARRAY OF CHAR);
	BEGIN
		CCBasic.OutText("Error in program file "); 
		IF filename # NIL THEN CCBasic.OutText(filename^) END;
		CCBasic.OutText(" pos "); CCBasic.OutInteger(position); 
		IF expected # 0X THEN
			CCBasic.OutText(" expected"); CCBasic.OutHex(ORD(expected)); CCBasic.OutText("X ")
		END;
		CCBasic.OutText(" current"); CCBasic.OutHex(ORD(char)); CCBasic.OutText("X ");
		CCBasic.OutText(message); CCBasic.OutLine;
		position := length; char := 0X; error := TRUE
	END Error;
		
	PROCEDURE Check(x: CHAR);
	BEGIN IF char = x THEN Next ELSE Error(x, "") END
	END Check;
	
	PROCEDURE EOT(): BOOLEAN;
	BEGIN RETURN length = position
	END EOT;
	
	PROCEDURE Next;
	BEGIN IF position < length THEN reader.Char(char); INC(position) ELSE char := 0X END
	END Next;

	PROCEDURE Integer4(): LONGINT;
	VAR i: LONGINT; a: CCBasic.Integer4Byte; x: LONGINT;
	BEGIN
		FOR i := 0 TO LEN(a)-1 DO a[i] := char; Next END;
		CCBasic.Decode4ByteInteger(a, x);
		RETURN x
	END Integer4;
				
	PROCEDURE Text(): CCBasic.String;
	VAR a: ARRAY 16 OF CHAR; old, new: CCBasic.String; i, k, oldLen: LONGINT; x: CHAR;
	BEGIN
		x := char; Next; new := NIL; 
		REPEAT
			i := 0;
			WHILE (i < LEN(a)) & (x # 0X) DO
				a[i] := x; INC(i); x := char; Next
			END;
			old := new;
			IF old # NIL THEN
				NEW(new, LEN(old) + i);
				FOR k := 0 TO LEN(old)-2 DO new[k] := old[k] END;
				FOR k := 0 TO i - 1 DO new[LEN(old) - 1 + k] := a[k] END
			ELSE
				NEW(new, i + 1);
				FOR k := 0 TO i - 1 DO new[k] := a[k] END
			END;
			new[LEN(new)-1] := 0X
		UNTIL x = 0X;
		RETURN new
	END Text;
END CCImporter.

