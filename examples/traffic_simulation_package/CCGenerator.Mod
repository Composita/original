MODULE CCGenerator; (** Component Compiler, Code Generator, 2006 by Luc Blaeser *)
	IMPORT CCIR, CG := CCIx86CG, CCBasic, CBC, AosFS, AosIO, Utilities;

	CONST
		NilValue = 0FFFFF800H; (* depends on target machine *)
				
	CONST
		TrueValue = 1; 
		FalseValue = 0;
				
		NoLock = 0;
		ExclusiveLock = -1;
		(* positive value counts shared locks *)
		
		ProcessHeaderSize = 11*4; 
		ProcessBackupPCOffset = 0*4;
		ProcessBackupESPOffset = 1*4;
		ProcessBackupEBPOffset = 2*4;
		ProcessStackLimitOffset = 3*4;
		ProcessPrevProcessOffset = 4*4; 
		ProcessNextProcessOffset = 5*4;
		ProcessHeaderCompOffset = 6*4;
		ProcessAwaitLockOffset = 7*4;
		ProcessAwaitMessageOffset = 7*4+1;
		ProcessAwaitEBPOffset = 8*4;
		ProcessAwaitPCOffset = 9*4;
		ProcessNextTimeOffset = 10*4;
			
		ProcessTailSize = 4*4;
		ProcessTailNil1Offset = 0*4;
		ProcessTailNil2Offset = 1*4;
		ProcessTailSelfProcessOffset = 2*4;
		ProcessTailComponentOffset = 3*4;
		ProcessTailCommBufferOffset = 4*4;

		ProcessReservedSize = ProcessHeaderSize + ProcessTailSize;
				
		ProcessParameterOffset = 2*4;
		ComponentParameterOffset = 3*4;
		CommunicationSetParamOffset* =  4*4; 
		StackReserveParameterOffset* = 5*4;
		StaticLinkParameterOffset* = 6*4;
		
		ComponentHeaderSize = 20*4;
		ComponentTemplateOffset = 0*4;
		ComponentSpinLockOffset = 1*4;
		ComponentSuperComOffset = 2*4;
		ComponentLockListOffset = 3*4;
		ComponentAwaitListOffset = 5*4;
		ComponentPassiveUnsortedOffset = 7*4;
		ComponentPassiveSortedOffset = 9*4;
		ComponentExternalWaitOffset = 11*4;
		ComponentLifeStateOffset = 13*4;
		ComponentTerminatedOffset = 13*4+1;
		ComponentSynchronizedOffset = 13*4+2;
		ComponentLocalProcCounterOffset = 14*4;
		ComponentLocalWaitCounterOffset = 15*4;
		ComponentSyncProcCounterOffset = 16*4;
		ComponentPassiveCounterOffset = 17*4;
		ComponentLockCounterOffset = 18*4;
		ComponentVirtualTimeOffset = 19*4;
																	
		InterfaceConnectionSize = 5*4;
		InterfaceConnFlagOffset = 0*4;
		InterfaceConnReferenceOffset = 1*4; (* target connection, implementation code, interface collection *)
		InterfaceConnComponentOffset = 2*4;
		InterfaceConnCounterOffset = 3*4;
		InterfaceConnCommCounterOffset = 4*4;
			
		ConnectionFlagNone = 0;
		ConnectionFlagRedirected = 1;
		ConnectionFlagImplemented = 2;
		ConnectionFlagCollection = 3;
		
		CommEntryHeaderSize = 2*4; (* sender, message *)
		CommEntrySenderOffset = 0*4;
		CommEntryMessageOffset = 1*4;
		CommEntryParameterOffset = 2*4;
			
		NoMessage = -1; 
		FinishMessage = -2; 
	
		CharacterTypeCode = 1;
		BooleanTypeCode = 2;
		IntegerTypeCode = 3;
		RealTypeCode = 4;
		TextTypeCode = 5;
		
		(* protocol state machine encoded in array format *)
		
		ExtraRows = 3;
		ErrorProtocolRow = 0;
		FinishProtocolRow = 1;
		StartProtocolRow = 2;
		(* other rows for states, indexed by last messageId + 2 *)
		
		ExtraColumns = 1;
		FinishProtocolColumn = 0;
		(* other column for transitions, indexed by sent messageId + 1 *)
																				
		SimpleCallStackSize = 512;
		CollectionCallStackSize = 640;
		StackExtensionSize = 64*1024;
		
		SequentialPreemptionLimit = 100; (* preemption check after sequence of 100 statements *)
		MaxProcedureNesting = 16;
		
	CONST
		ArrayHeaderSize = 8; (* nofDims, elemSize *)
		ArrayNofDimsOffset = 0;
		ArrayElemSizeOffset = 4;

	CONST
		(* shortint *)
		LifeStateCreated = 0;
		LifeStateInitialized = 1;
		LifeStateInactive = 2;
		LifeStateFinalized = 3;

	TYPE
		CodeFixup = OBJECT(CG.FixupReference)
			VAR targetPos: LONGINT; 
			
			PROCEDURE &InitCodeFixup(list: CG.FixupList);
			BEGIN InitFixupReference(list); targetPos := 0 (* set later *)
			END InitCodeFixup;
		END CodeFixup;
		
		ConstFixup = OBJECT(CG.FixupReference)
			VAR constPos: LONGINT;
			
			PROCEDURE &InitConstFixup(list: CG.FixupList);
			BEGIN InitFixupReference(list); constPos := 0 (* set later *)
			END InitConstFixup;
		END ConstFixup;
		
		ProcessFixup = OBJECT(CG.FixupReference)
			VAR
				component: CCIR.Component;
				processName: CCIR.Identifier;
				targetPos: LONGINT;
			
			PROCEDURE &InitProcessFixup(list: CG.FixupList; com: CCIR.Component; name: CCIR.Identifier);
			BEGIN InitFixupReference(list); component := com; processName := name; targetPos := 0 (* set later *)
			END InitProcessFixup;
		END ProcessFixup;
				
		ProcedureCallFixup = OBJECT(CG.FixupReference)
			VAR procedure: CCIR.Procedure;
			
			PROCEDURE &InitProcedureCallFixup(list: CG.FixupList; proc: CCIR.Procedure);
			BEGIN InitFixupReference(list); procedure := proc
			END InitProcedureCallFixup;
		END ProcedureCallFixup;
		
		ImplementationFixup = OBJECT(CG.FixupReference)
			VAR implementation: CCIR.Implementation;
			
			PROCEDURE &InitImplementationFixup(list: CG.FixupList; impl: CCIR.Implementation);
			BEGIN InitFixupReference(list); implementation := impl
			END InitImplementationFixup;
		END ImplementationFixup;
		
		ComponentSizeFixup = OBJECT(CG.FixupReference)
			VAR
				component: CCIR.Component;
				size: LONGINT;
				
			PROCEDURE &InitComponentSizeFixup(list: CG.FixupList; com: CCIR.Component);
			BEGIN InitFixupReference(list); component := com; size := 0 (* set later *)
			END InitComponentSizeFixup;
		END ComponentSizeFixup;
				
		SystemCallFixup = OBJECT(CG.FixupReference)
			VAR callCode: CHAR; (* defined in CBC *)
		
			PROCEDURE &InitSystemCallFixup(list: CG.FixupList; code: CHAR);
			BEGIN InitFixupReference(list); callCode := code
			END InitSystemCallFixup;
		END SystemCallFixup;
		
		SizeFixup = OBJECT(CG.FixupReference)
			VAR size: LONGINT;
			
			PROCEDURE &InitSizeFixup(list: CG.FixupList);
			BEGIN InitFixupReference(list); size := 0 (* set later *)
			END InitSizeFixup;
		END SizeFixup;
		
		ComponentTemplateFixup = OBJECT(CG.FixupReference)
			VAR com: CCIR.ComponentDefinition;
			
			PROCEDURE &InitComponentTemplateFixup(list: CG.FixupList; def: CCIR.ComponentDefinition);
			BEGIN InitFixupReference(list); com := def
			END InitComponentTemplateFixup;
		END ComponentTemplateFixup;

		InterfaceSpecificationFixup = OBJECT(CG.FixupReference)
			VAR interface: CCIR.Interface;
			
			PROCEDURE &InitInterfaceSpecificationFixup(list: CG.FixupList; int: CCIR.Interface);
			BEGIN InitFixupReference(list); interface := int
			END InitInterfaceSpecificationFixup;
		END InterfaceSpecificationFixup;

		FixupType = OBJECT
			VAR
				count: LONGINT;
			
			PROCEDURE &InitFixupType;
			BEGIN HALT(89) (* abstract *)
			END InitFixupType
		END FixupType;

		SystemCallFixupType = OBJECT(FixupType)
			VAR
				callCode: CHAR;
				relative: BOOLEAN;
				
			PROCEDURE &InitSystemCallFixupType(sysCallCode: CHAR; isRelative: BOOLEAN);
			BEGIN callCode := sysCallCode; relative := isRelative; count := 0
			END InitSystemCallFixupType;
		END SystemCallFixupType;
		
		ComponentTemplateFixupType = OBJECT(FixupType)
			VAR com: CCIR.ComponentDefinition;
			
			PROCEDURE &InitComponentTemplateFixupType(def: CCIR.ComponentDefinition);
			BEGIN com := def; count := 0
			END InitComponentTemplateFixupType;
		END ComponentTemplateFixupType;
		
		InterfaceSpecFixupType = OBJECT(FixupType)
			VAR interface: CCIR.Interface;
			
			PROCEDURE &InitInterfaceSpecFixupType(int: CCIR.Interface);
			BEGIN interface := int; count := 0
			END InitInterfaceSpecFixupType;
		END InterfaceSpecFixupType;
		
		FixupTypeList = OBJECT(CCBasic.List)
			PROCEDURE Add(x: PTR);
			BEGIN HALT(99) (* use Register procedures *)
			END Add;
			
			PROCEDURE RegisterSystemCall(callCode: CHAR; relative: BOOLEAN);
			VAR type: SystemCallFixupType;
			BEGIN
				type := FindSystemCallFixupType(callCode, relative);
				IF type = NIL THEN
					NEW(type, callCode, relative); Add^(type)
				END;
				INC(type.count)
			END RegisterSystemCall;
			
			PROCEDURE RegisterComponentTemplate(def: CCIR.ComponentDefinition);
			VAR type: ComponentTemplateFixupType;
			BEGIN
				type := FindComponentTemplateFixupType(def);
				IF type = NIL THEN
					NEW(type, def); Add^(type)
				END;
				INC(type.count)
			END RegisterComponentTemplate;
			
			PROCEDURE RegisterInterfaceSpecification(int: CCIR.Interface);
			VAR type: InterfaceSpecFixupType;
			BEGIN
				type := FindInterfaceSpecFixupType(int);
				IF type = NIL THEN
					NEW(type, int); Add^(type)
				END;
				INC(type.count)
			END RegisterInterfaceSpecification;
			
			PROCEDURE GetFixupType(i: LONGINT): FixupType;
			VAR ptr: PTR;
			BEGIN ptr := GetItem(i); RETURN ptr(FixupType)
			END GetFixupType;
			
			PROCEDURE FindSystemCallFixupType(callCode: CHAR; relative: BOOLEAN): SystemCallFixupType;
			VAR i: LONGINT; f: FixupType; sf: SystemCallFixupType;
			BEGIN
				FOR i := 0 TO Length()-1 DO
					f := GetFixupType(i);
					IF f IS SystemCallFixupType THEN
						sf := f(SystemCallFixupType);
						IF (sf.callCode = callCode) & (sf.relative = relative) THEN 
							RETURN sf 
						END
					END
				END;
				RETURN NIL
			END FindSystemCallFixupType;
			
			PROCEDURE FindComponentTemplateFixupType(def: CCIR.ComponentDefinition): ComponentTemplateFixupType;
			VAR i: LONGINT; f: FixupType; cf: ComponentTemplateFixupType;
			BEGIN
				FOR i := 0 TO Length()-1 DO
					f := GetFixupType(i);
					IF f IS ComponentTemplateFixupType THEN
						cf := f(ComponentTemplateFixupType);
						IF cf.com = def THEN RETURN cf END
					END
				END;
				RETURN NIL
			END FindComponentTemplateFixupType;
			
			PROCEDURE FindInterfaceSpecFixupType(int: CCIR.Interface): InterfaceSpecFixupType;
			VAR i: LONGINT; f: FixupType; if: InterfaceSpecFixupType;
			BEGIN
				FOR i := 0 TO Length()-1 DO
					f := GetFixupType(i);
					IF f IS InterfaceSpecFixupType THEN
						if := f(InterfaceSpecFixupType);
						IF if.interface = int THEN RETURN if END
					END
				END;
				RETURN NIL
			END FindInterfaceSpecFixupType;
			
			PROCEDURE NofSystemCallFixupTypes(): LONGINT;
			VAR count, i: LONGINT; f: FixupType;
			BEGIN
				count := 0;
				FOR i := 0 TO Length()-1 DO
					f := GetFixupType(i);
					IF f IS SystemCallFixupType THEN INC(count) END
				END;
				RETURN count
			END NofSystemCallFixupTypes;
			
			PROCEDURE NofComponentTemplateFixupTypes(): LONGINT;
			VAR count, i: LONGINT; f: FixupType;
			BEGIN
				count := 0;
				FOR i := 0 TO Length()-1 DO
					f := GetFixupType(i);
					IF f IS ComponentTemplateFixupType THEN INC(count) END
				END;
				RETURN count
			END NofComponentTemplateFixupTypes;
			
			PROCEDURE NofInterfaceSpecFixupTypes(): LONGINT;
			VAR count, i: LONGINT; f: FixupType;
			BEGIN
				count :=  0;
				FOR i := 0 TO Length()-1 DO
					f := GetFixupType(i);
					IF f IS InterfaceSpecFixupType THEN INC(count) END
				END;
				RETURN count
			END NofInterfaceSpecFixupTypes;
		END FixupTypeList;
		
		VariableAllocation = OBJECT
			VAR
				variable: CCIR.Variable;
				offset: LONGINT;
				varSize: LONGINT;
				elemSize: LONGINT; (* defined for collection variables *)
				
			PROCEDURE &InitVariableAllocation(var: CCIR.Variable; ofs: LONGINT);
			VAR totalSize: LONGINT;
			BEGIN
				variable := var; offset := ofs;
				IF variable.usedCommunications.Length() > 0 THEN
					ASSERT(TypeSize(var.type) MOD 4 = 0);
					totalSize := TypeSize(var.type) + variable.usedCommunications.Length() * 4 
						(* space for communications via offered interfaces *)
				ELSE
					totalSize := TypeSize(var.type)
				END;
				IF variable.parameters.Length() > 0 THEN
					varSize := 4;
					elemSize := totalSize
				ELSE
					varSize := totalSize;
					elemSize := 0
				END
			END InitVariableAllocation;
		END VariableAllocation;
		
		VariableAllocationList = OBJECT(CCBasic.List)
			VAR
				offset: LONGINT;
				size: LONGINT;
			
			PROCEDURE &InitVariableAllocationList(initialOffset, reservedInitialSize: LONGINT);
			BEGIN offset := initialOffset; size := reservedInitialSize; InitList
			END InitVariableAllocationList;
			
			PROCEDURE Add(x: PTR);
			BEGIN HALT(98) (* use AddVariable *)
			END Add;
			
			PROCEDURE AddVariableAllocation(var: CCIR.Variable);
			VAR typeSize: LONGINT; alloc: VariableAllocation;
			BEGIN 
				ASSERT(FindVariableAllocation(var) = NIL);
				typeSize := TypeSize(var.type);
				IF size MOD typeSize # 0 THEN
					INC(size, typeSize - size MOD typeSize) (* inser padding, align on variable size *)
				END;
				NEW(alloc, var, size); INC(size, alloc.varSize);
				Add^(alloc)
			END AddVariableAllocation;
			
			PROCEDURE GetVariableAllocation(index: LONGINT): VariableAllocation;
			VAR ptr: PTR;
			BEGIN ptr := GetItem(index); RETURN ptr(VariableAllocation)
			END GetVariableAllocation;
			
			PROCEDURE FindVariableAllocation(var: CCIR.Variable): VariableAllocation;
			VAR i: LONGINT; alloc: VariableAllocation;
			BEGIN
				FOR i := 0 TO Length()-1 DO
					alloc := GetVariableAllocation(i);
					IF alloc.variable = var THEN RETURN alloc END
				END;
				RETURN NIL
			END FindVariableAllocation;
			
			PROCEDURE Align(bytes: LONGINT);
			BEGIN IF size MOD bytes # 0 THEN INC(size, bytes - size MOD bytes) END
			END Align;					
		END VariableAllocationList;

		ProcedureParamAllocation = OBJECT
			VAR 
				param: CCIR.ProcedureParameter;
				offset: LONGINT;
				
			PROCEDURE &InitProcedureParamAllocation(par: CCIR.ProcedureParameter; ofs: LONGINT);
			BEGIN param := par; offset := ofs
			END InitProcedureParamAllocation;
		END ProcedureParamAllocation;
		
		ProcedureParamAllocationList = OBJECT(CCBasic.List)
			VAR size: LONGINT;
			
			PROCEDURE &InitProcedureParamAllocList;
			BEGIN size := 0; InitList
			END InitProcedureParamAllocList;
			
			PROCEDURE Add(x: PTR);
			BEGIN HALT(98) (* use AddProcedureParamAlloc *)
			END Add;
			
			PROCEDURE AddProcedureParamAlloc(par: CCIR.ProcedureParameter);
			VAR alloc: ProcedureParamAllocation;
			BEGIN
				ASSERT(size MOD 4 = 0);
				ASSERT(TypeSize(par.type) <= 4);
				NEW(alloc, par, size);
				INC(size, 4);
				Add^(alloc)
			END AddProcedureParamAlloc;
			
			PROCEDURE AddExtraParameters(number: LONGINT);
			BEGIN INC(size, number * 4)
			END AddExtraParameters;
			
			PROCEDURE Offset(par: CCIR.ProcedureParameter): LONGINT;
			VAR alloc: ProcedureParamAllocation;
			BEGIN
				alloc := FindProcedureParamAlloc(par); ASSERT(alloc # NIL);
				RETURN size - alloc.offset
			END Offset;
			
			PROCEDURE NofPushParameters(): LONGINT;
			BEGIN RETURN (size - 4) DIV 4 (* without return PC *)
			END NofPushParameters;
			
			PROCEDURE GetProcedureParamAlloc(index: LONGINT): ProcedureParamAllocation;
			VAR ptr: PTR;
			BEGIN ptr := GetItem(index); RETURN ptr(ProcedureParamAllocation)
			END GetProcedureParamAlloc;
			
			PROCEDURE FindProcedureParamAlloc(par: CCIR.ProcedureParameter): ProcedureParamAllocation;
			VAR i: LONGINT; x: ProcedureParamAllocation;
			BEGIN
				FOR i := 0 TO Length()-1 DO
					x := GetProcedureParamAlloc(i);
					IF x.param = par THEN RETURN x END
				END;
				RETURN NIL
			END FindProcedureParamAlloc;
		END ProcedureParamAllocationList;
						
		ProcedureAllocation = OBJECT
			VAR
				procedure: CCIR.Procedure;
				nestLevel: LONGINT;
				startPos: LONGINT;
				parameters: ProcedureParamAllocationList;
				variables: VariableAllocationList;
				stackSizeFixup: SizeFixup;
				
			PROCEDURE &InitProcedureAllocation(proc: CCIR.Procedure; level: LONGINT);
			BEGIN 
				procedure := proc; nestLevel := level; startPos := 0; 
				parameters := NIL; variables := NIL; stackSizeFixup := NIL
			END InitProcedureAllocation;
		END ProcedureAllocation;
		
		ProcedureAllocationList = OBJECT(CCBasic.List)
			PROCEDURE Add(x: PTR);
			BEGIN ASSERT(x IS ProcedureAllocation); Add^(x)
			END Add;
			
			PROCEDURE GetProcedureAllocation(index: LONGINT): ProcedureAllocation;
			VAR ptr: PTR;
			BEGIN ptr := GetItem(index); RETURN ptr(ProcedureAllocation)
			END GetProcedureAllocation;
			
			PROCEDURE FindProcedureAllocation(proc: CCIR.Procedure): ProcedureAllocation;
			VAR i: LONGINT; x: ProcedureAllocation;
			BEGIN
				FOR i := 0 TO Length()-1 DO
					x := GetProcedureAllocation(i);
					IF x.procedure = proc THEN RETURN x END
				END;
				RETURN NIL
			END FindProcedureAllocation;
		END ProcedureAllocationList;
		
		ProcessAllocation = OBJECT
			VAR
				stackSizeFixup: SizeFixup;
				
			PROCEDURE &InitProcessAllocation;
			BEGIN stackSizeFixup := NIL
			END InitProcessAllocation;
		END ProcessAllocation;
		
		ImplementationAllocation = OBJECT(ProcessAllocation)
			VAR
				implementation: CCIR.Implementation;
				startPos: LONGINT;
				variables: VariableAllocationList;
				
			PROCEDURE &InitImplementationAllocation(impl: CCIR.Implementation);
			BEGIN InitProcessAllocation; implementation := impl; startPos := 0; variables := NIL
			END InitImplementationAllocation;
		END ImplementationAllocation;
		
		ImplementationAllocationList = OBJECT(CCBasic.List)
			PROCEDURE Add(x: PTR);
			BEGIN ASSERT(x IS ImplementationAllocation); Add^(x)
			END Add;
			
			PROCEDURE GetImplementationAllocation(index: LONGINT): ImplementationAllocation;
			VAR ptr: PTR;
			BEGIN ptr := GetItem(index); RETURN ptr(ImplementationAllocation)
			END GetImplementationAllocation;
			
			PROCEDURE FindImplementationAllocation(impl: CCIR.Implementation): ImplementationAllocation;
			VAR i: LONGINT; x: ImplementationAllocation;
			BEGIN
				FOR i := 0 TO Length()-1 DO
					x := GetImplementationAllocation(i);
					IF x.implementation = impl THEN RETURN x END
				END;
				RETURN NIL
			END FindImplementationAllocation;
		END ImplementationAllocationList;
		
		GenericForAllOperation = PROCEDURE (scope: CCIR.Node; var: CCIR.Variable);

		MessageIdentifier = LONGINT;
		MessageIdentifierList = CCBasic.LongIntList;

		ProtocolTransition = OBJECT
			VAR previous, next: MessageIdentifier;
			
			PROCEDURE &InitProtocolTransition(from, to: MessageIdentifier);
			BEGIN previous := from; next := to
			END InitProtocolTransition;
			
			PROCEDURE Equal(x: ProtocolTransition): BOOLEAN;
			BEGIN RETURN (x # NIL) & (x.previous = previous) & (x.next = next)
			END Equal;
		END ProtocolTransition;

		ProtocolTransitionList = OBJECT(CCBasic.List)
			PROCEDURE Add(x: PTR);
			BEGIN ASSERT(x IS ProtocolTransition); Add^(x)
			END Add;
			
			PROCEDURE GetProtocolTransition(i: LONGINT): ProtocolTransition;
			VAR ptr: PTR;
			BEGIN ptr := GetItem(i); RETURN ptr(ProtocolTransition)
			END GetProtocolTransition;
		END ProtocolTransitionList;
		
		ProtocolStateGraph = OBJECT
			VAR
				interface: CCIR.Interface;
				start: MessageIdentifier;
				final: MessageIdentifierList; 
				transitions: ProtocolTransitionList;
				
			PROCEDURE &InitProtocol(int: CCIR.Interface);
			BEGIN interface := int; NEW(transitions); start := NoMessage; final := NIL
			END InitProtocol;
			
			PROCEDURE AddTransition(previous, next: MessageIdentifier);
			VAR t: ProtocolTransition;
			BEGIN 
				NEW(t, previous, next); 
				IF ~ContainsTransition(t) THEN transitions.Add(t) END
			END AddTransition;
			
			PROCEDURE ContainsTransition(x: ProtocolTransition): BOOLEAN;
			VAR i: LONGINT; y: ProtocolTransition;
			BEGIN
				FOR i := 0 TO transitions.Length()-1 DO
					y := transitions.GetProtocolTransition(i);
					IF y.Equal(x) THEN RETURN TRUE END
				END;
				RETURN FALSE
			END ContainsTransition;
		END ProtocolStateGraph;
		
		ProtocolStateMatrix = POINTER TO ARRAY OF SHORTINT;
	
	VAR 
		initializer, finalizer: CCIR.Identifier;
		procedureResultVariable, stackExtensionVariable: CCIR.Variable;
		header, constants, code, tail: CCBasic.DataSequence;
		headerFixups, codeFixups: CG.FixupList;
		componentVariables: VariableAllocationList;
		procedureAllocations: ProcedureAllocationList;
		implementationAllocations: ImplementationAllocationList;
		currentProcessAllocation: ProcessAllocation;
		breakRequired, breakActive: BOOLEAN;
		breakComponent: CCBasic.String;
		breakCodePos: LONGINT;
		breakSourcePos: LONGINT;
		outPartition: ARRAY 32 OF CHAR;
		
	PROCEDURE MakeProtocolStateMatrix(interface: CCIR.Interface): ProtocolStateMatrix;
	VAR protocol: ProtocolStateGraph; i, nofMessages, nofColumns, nofRows, size: LONGINT; matrix: ProtocolStateMatrix;
		trans: ProtocolTransition; row, col, pos, messageId: LONGINT;
	BEGIN 
		protocol := ParseProtocolStateGraph(interface);
		nofMessages := interface.messageDeclarations.Length();
		nofColumns := nofMessages + ExtraColumns;
		nofRows := nofMessages + ExtraRows;
		size := nofRows * nofColumns;
		NEW(matrix, size);
		FOR pos := 0 TO size-1 DO matrix[pos] := ErrorProtocolRow END;
		FOR i := 0 TO protocol.transitions.Length()-1 DO
			trans := protocol.transitions.GetProtocolTransition(i);
			IF trans.previous = protocol.start THEN
				row := StartProtocolRow
			ELSE
				row := GetProtocolMatrixRow(trans.previous)
			END;
			ASSERT(trans.next >= 0);
			col := GetProtocolMatrixColumn(trans.next);
			pos := row * nofColumns + col;
			matrix[pos] := SHORT(SHORT(GetProtocolMatrixRow(trans.next)))
		END;
		FOR i := 0 TO protocol.final.Length()-1 DO
			messageId := protocol.final.GetItem(i);
			row := GetProtocolMatrixRow(messageId);
			col := FinishProtocolColumn;
			pos := row * nofColumns + col;
			matrix[pos] := FinishProtocolRow
		END;
		RETURN matrix
	END MakeProtocolStateMatrix;
			
	PROCEDURE GetProtocolMatrixRow(messageId: LONGINT): LONGINT;
	BEGIN RETURN messageId + ExtraRows
	END GetProtocolMatrixRow;
	
	PROCEDURE GetProtocolMatrixColumn(messageId: LONGINT): LONGINT;
	BEGIN RETURN messageId + ExtraColumns
	END GetProtocolMatrixColumn;
								
	PROCEDURE ParseProtocolStateGraph(interface: CCIR.Interface): ProtocolStateGraph;
	VAR output: ProtocolStateGraph; previousStates, firstStates: MessageIdentifierList;
	BEGIN
		NEW(output, interface);
		IF interface.protocol = NIL THEN
			NEW(output.final)
		ELSE
			NEW(previousStates); previousStates.Add(output.start);
			ParseProtocolStateGraphExpr(interface.protocol, output, previousStates, firstStates, output.final)
		END;
		RETURN output
	END ParseProtocolStateGraph;
		
	PROCEDURE ParseProtocolStateGraphExpr(input: CCIR.Protocol; output: ProtocolStateGraph; 
		previousStates: MessageIdentifierList; VAR firstStates, lastStates: MessageIdentifierList);
	VAR lastTempStates, firstTempStates: MessageIdentifierList; messageId: LONGINT;
		md: CCIR.MessageDeclaration; seq: CCIR.ProtocolSequence; alt: CCIR.ProtocolAlternative;
		rep: CCIR.ProtocolRepetition; opt: CCIR.ProtocolOption;
		
		PROCEDURE CombineTransitions(from, to: MessageIdentifierList);
		VAR i: LONGINT; a: LONGINT;
		BEGIN
			FOR i := 0 TO from.Length()-1 DO
				a := from.GetItem(i);
				IF ~to.Contains(a) THEN to.Add(a) END
			END
		END CombineTransitions;
		
		PROCEDURE MakeTransitions(from, to: MessageIdentifierList);
		VAR i, k: LONGINT; a, b: LONGINT;
		BEGIN
			FOR i := 0 TO from.Length()-1 DO
				a := from.GetItem(i);
				FOR k := 0 TO to.Length()-1 DO
					b := to.GetItem(k);
					output.AddTransition(a, b)
				END
			END
		END MakeTransitions;
		
	BEGIN
		ASSERT(firstStates = NIL); ASSERT(lastStates = NIL);
		IF input IS CCIR.MessageDeclaration THEN
			md := input(CCIR.MessageDeclaration); 
			messageId := output.interface.messageDeclarations.GetIndexOfMessageDeclaration(md.name);
			ASSERT(messageId >= 0);
			NEW(firstStates); firstStates.Add(messageId);
			NEW(lastStates); lastStates.Add(messageId);
			MakeTransitions(previousStates, firstStates)
		ELSIF input IS CCIR.ProtocolSequence THEN
			seq := input(CCIR.ProtocolSequence);
			ParseProtocolStateGraphExpr(seq.first, output, previousStates, firstStates, lastTempStates);
			ParseProtocolStateGraphExpr(seq.second, output, lastTempStates, firstTempStates, lastStates)
		ELSIF input IS CCIR.ProtocolAlternative THEN
			alt := input(CCIR.ProtocolAlternative);
			ParseProtocolStateGraphExpr(alt.first, output, previousStates, firstStates, lastStates);
			ParseProtocolStateGraphExpr(alt.second, output, previousStates, firstTempStates, lastTempStates);
			CombineTransitions(firstTempStates, firstStates);
			CombineTransitions(lastTempStates, lastStates)
		ELSIF input IS CCIR.ProtocolRepetition THEN
			rep := input(CCIR.ProtocolRepetition);
			ParseProtocolStateGraphExpr(rep.protocol, output, previousStates, firstStates, lastStates);
			MakeTransitions(lastStates, firstStates);
			CombineTransitions(previousStates, lastStates)
		ELSIF input IS CCIR.ProtocolOption THEN
			opt := input(CCIR.ProtocolOption);
			ParseProtocolStateGraphExpr(opt.protocol, output, previousStates, firstStates, lastStates);
			CombineTransitions(previousStates, lastStates)
		ELSE  HALT(111)
		END
	END ParseProtocolStateGraphExpr;

	PROCEDURE TypeSize(type: CCIR.Type): LONGINT;
	BEGIN
		IF type = CCIR.booleanType THEN RETURN 1
		ELSIF type = CCIR.characterType THEN RETURN 1
		ELSIF type = CCIR.integerType THEN RETURN 4
		ELSIF type = CCIR.realType THEN RETURN 4
		ELSIF type = CCIR.textType THEN RETURN 4
		ELSIF CCIR.IsComponentType(type) THEN RETURN 4 
		ELSE HALT(111)
		END
	END TypeSize;
	
	PROCEDURE MakeCopy(expr: CCIR.Expression);
	VAR copyTextFixup: SystemCallFixup;
	BEGIN
		IF (expr.type = CCIR.integerType) OR (expr.type = CCIR.realType) OR 
				(expr.type = CCIR.booleanType) OR (expr.type = CCIR.characterType) THEN
			(* ok *)
		ELSE
			IF ~IsDetachedExpression(expr) THEN
				IF expr.type = CCIR.textType THEN
					CG.SaveTemporary(1);
					NEW(copyTextFixup, codeFixups, CBC.FCopyText);
					CG.Call(copyTextFixup, 1, SimpleCallStackSize);
					CG.GetProcedureResult(4)
				ELSIF CCIR.IsComponentType(expr.type) THEN
					HALT(111) (* not yet implemented *)
				ELSE HALT(111)
				END
			END
		END
	END MakeCopy;
	
	PROCEDURE IsDetachedExpression(expr: CCIR.Expression): BOOLEAN;
	VAR des: CCIR.Designator; send: CCIR.SendStatement; call: CCIR.ProcedureCall; arg0: CCIR.Expression;
	BEGIN 
		ASSERT((expr.type = CCIR.textType) OR CCIR.IsComponentType(expr.type));
		IF expr IS CCIR.TextValue THEN RETURN TRUE
		ELSIF expr IS CCIR.FunctionCall THEN RETURN TRUE
		ELSIF expr IS CCIR.Designator THEN
			des := expr(CCIR.Designator);
			IF des.node IS CCIR.Constant THEN RETURN TRUE END;
			WHILE (des.outer # NIL) & (des.outer IS CCIR.Designator) DO des := des.outer(CCIR.Designator) END;
			ASSERT(des # NIL);
			IF des.outer IS CCIR.SendStatement THEN
				send := des.outer(CCIR.SendStatement);
				RETURN CCIR.IsComponentType(expr.type) & send.messageArguments.Contains(des)
			ELSIF des.outer IS CCIR.ProcedureCall THEN
				call := des.outer(CCIR.ProcedureCall);
				IF call.declaration = CCIR.move THEN
					arg0 := call.arguments.GetExpression(0);
					RETURN arg0 = des
				END
			END;
			RETURN FALSE
		ELSE HALT(111)
		END
	END IsDetachedExpression; 

	PROCEDURE AllocateVariables(allocList: VariableAllocationList; varList: CCIR.VariableList);
	VAR i: LONGINT; var: CCIR.Variable;
	BEGIN
		FOR i := 0 TO varList.Length()-1 DO
			var := varList.GetVariable(i);
			allocList.AddVariableAllocation(var)
		END;
		allocList.Align(4)
	END AllocateVariables;
	
	PROCEDURE AllocateProcedureParameters(VAR allocList: ProcedureParamAllocationList; 
			parList: CCIR.ProcedureParameterList; nestLevel: LONGINT);
	VAR i: LONGINT; par: CCIR.ProcedureParameter;
	BEGIN
		FOR i := 0 TO parList.Length()-1 DO
			par := parList.GetProcedureParameter(i);
			allocList.AddProcedureParamAlloc(par)
		END;
		IF nestLevel > 0 THEN
			allocList.AddExtraParameters(1) (* static link *)
		END;
		allocList.AddExtraParameters(5) (* stack reserve, communication set, component, process, return pc *)
	END AllocateProcedureParameters;

	PROCEDURE Generate*(outPart: ARRAY OF CHAR; break: BOOLEAN; breakComponentName: ARRAY OF CHAR;
		breakCodePosition: LONGINT; VAR breakSourcePosition: LONGINT);
	BEGIN
		COPY(outPart, outPartition);
		breakRequired := break;
		IF break THEN
			breakComponent := CCBasic.NewString(breakComponentName);
			breakCodePos := breakCodePosition; breakSourcePos := -1
		END;
		GenerateCompiledInterfaces;
		GenerateCompiledComponents;
		IF break THEN
			breakSourcePosition := breakSourcePos
		END
	END Generate;
	
	PROCEDURE GenerateCompiledInterfaces;
	VAR i: LONGINT; interface: CCIR.Interface;
	BEGIN 
		FOR i := 0 TO CCIR.compiledInterfaces.Length()-1 DO
			interface := CCIR.compiledInterfaces.GetInterface(i);
			BeginOutput;
			header.Integer4(0); (* used interfaces *)
			header.Integer4(0); (* used components *)
			header.Integer4(1); (* new interfaces *)
			GenerateNewInterface(interface);
			header.Integer4(0); (* new components *)
			(* no constants, no code *)
			GenerateTail;
			EndOutput(interface.name.name^, FALSE)
		END
	END GenerateCompiledInterfaces;
	
	PROCEDURE GenerateNewInterface(interface: CCIR.Interface);
	VAR matrix: ProtocolStateMatrix; i: LONGINT;
	BEGIN
		matrix := MakeProtocolStateMatrix(interface);
		GenerateInterfaceSpecification(interface);
		header.Integer4(LEN(matrix));
		FOR i := 0 TO LEN(matrix)-1 DO header.Char(CHR(matrix[i])) END
	END GenerateNewInterface;
	
	PROCEDURE GenerateCompiledComponents;
	VAR i: LONGINT; component: CCIR.Component;
	BEGIN
		FOR i := 0 TO CCIR.compiledComponents.Length()-1 DO
			component := CCIR.compiledComponents.GetComponent(i);
			breakActive := (breakRequired) & component.name.EqualText(breakComponent^);
			BeginOutput;
			GenerateHeader(component);
			GenerateCode(component);
			GenerateTail;
			EndOutput(component.name.name^, TRUE)
		END
	END GenerateCompiledComponents;
	
	PROCEDURE GenerateHeader(outmostCom: CCIR.Component);
	BEGIN
		GenerateUsedInterfaceList(outmostCom.usedInterfaces);
		
		GenerateUsedComponentList(outmostCom.usedComponents);
		
		header.Integer4(NofInterfaces(outmostCom));
		GenerateAllInterfaces(outmostCom);
		
		header.Integer4(NofComponents(outmostCom));
		GenerateAllComponentHeaders(outmostCom);
	END GenerateHeader;
	
	PROCEDURE GenerateUsedComponentList(list: CCIR.ComponentDefinitionList);
	VAR i: LONGINT; def: CCIR.ComponentDefinition;
	BEGIN
		header.Integer4(list.Length());
		FOR i := 0 TO list.Length()-1 DO
			def := list.GetComponentDefinition(i);
			GenerateComponentDefinition(def)
		END
	END GenerateUsedComponentList;
	
	PROCEDURE GenerateComponentDefinition(def: CCIR.ComponentDefinition);
	BEGIN
		GenerateComponentName(header, def);
		GenerateOfferedInterfaces(def.offeredInterfaces);
		GenerateRequiredInterfaces(def.requiredInterfaces)
	END GenerateComponentDefinition;
	
	PROCEDURE GenerateOfferedInterfaces(list: CCIR.InterfaceDeclarationList);
	VAR i: LONGINT; x: CCIR.InterfaceDeclaration;
	BEGIN
		header.Integer4(list.Length());
		FOR i := 0 TO list.Length()-1 DO
			x := list.GetInterfaceDeclaration(i);
			ASSERT((x.minNumber = 1) & (x.maxNumber = 1));
			IF x.interface # NIL THEN
				GenerateInterfaceName(header, x.interface)
			ELSE (* imported *)
				header.Text(x.name.name^)
			END
		END
	END GenerateOfferedInterfaces;
	
	PROCEDURE GenerateRequiredInterfaces(list: CCIR.InterfaceDeclarationList);
	VAR  i: LONGINT; x: CCIR.InterfaceDeclaration;
	BEGIN
		header.Integer4(list.Length());
		FOR i := 0 TO list.Length()-1 DO
			x := list.GetInterfaceDeclaration(i);
			IF x.interface # NIL THEN
				GenerateInterfaceName(header, x.interface)
			ELSE (* imported *)
				header.Text(x.name.name^)
			END;
			header.Integer4(x.minNumber); 
			header.Integer4(x.maxNumber)
		END
	END GenerateRequiredInterfaces;

	PROCEDURE GenerateUsedInterfaceList(list: CCIR.InterfaceList);
	VAR i: LONGINT; interface: CCIR.Interface;
	BEGIN
		header.Integer4(list.Length());
		FOR i := 0 TO list.Length()-1 DO
			interface := list.GetInterface(i);
			GenerateInterfaceSpecification(interface)
		END
	END GenerateUsedInterfaceList;
	
	PROCEDURE GenerateInterfaceSpecification(interface: CCIR.Interface);
	BEGIN
		GenerateInterfaceName(header, interface);
		GenerateMessageDeclList(interface.messageDeclarations);
		IF interface.protocol = NIL THEN
			header.Char(CBC.FNoProtocol)
		ELSE
			GenerateProtocol(interface.messageDeclarations, interface.protocol)
		END
	END GenerateInterfaceSpecification;
	
	PROCEDURE GenerateMessageDeclList(list: CCIR.MessageDeclarationList);
	VAR i: LONGINT; decl: CCIR.MessageDeclaration;
	BEGIN
		header.Integer4(list.Length());
		FOR i := 0 TO list.Length()-1 DO
			decl := list.GetMessageDeclaration(i);
			GenerateMessageDeclaration(decl)
		END
	END GenerateMessageDeclList;
	
	PROCEDURE GenerateMessageDeclaration(decl: CCIR.MessageDeclaration);
	BEGIN
		IF decl.input THEN header.Char(CBC.FIn) ELSE header.Char(CBC.FOut) END;
		header.Text(decl.name.name^);
		GenerateParameterList(decl.parameters)
	END GenerateMessageDeclaration;
	
	PROCEDURE GenerateParameterList(list: CCIR.ParameterList);
	VAR i: LONGINT; par: CCIR.Parameter;
	BEGIN
		header.Integer4(list.Length());
		FOR i := 0 TO list.Length()-1 DO
			par := list.GetParameter(i);
			GenerateType(par.type)
		END
	END GenerateParameterList;
	
	PROCEDURE GenerateType(type: CCIR.Type);
	VAR ct: CCIR.ComponentType; at: CCIR.AnyType;
	BEGIN
		IF type = CCIR.characterType THEN header.Char(CBC.FCharacterType)
		ELSIF type = CCIR.booleanType THEN header.Char(CBC.FBooleanType)
		ELSIF type = CCIR.integerType THEN header.Char(CBC.FIntegerType)
		ELSIF type = CCIR.realType THEN header.Char(CBC.FRealType)
		ELSIF type = CCIR.textType THEN header.Char(CBC.FTextType)
		ELSIF type IS CCIR.ComponentType THEN
			header.Char(CBC.FComponentType);
			ct := type(CCIR.ComponentType);
			IF ct.componentDefinition # NIL THEN
				GenerateComponentName(header, ct.componentDefinition)
			ELSE
				header.Text(ct.componentName.name^)
			END
		ELSIF type IS CCIR.AnyType THEN
			header.Char(CBC.FAnyType);
			at := type(CCIR.AnyType);
			GenerateOfferedInterfaces(at.offeredInterfaces);
			GenerateRequiredInterfaces(at.requiredInterfaces)
		ELSE HALT(111)
		END
	END GenerateType;
	
	PROCEDURE GenerateProtocol(mdList: CCIR.MessageDeclarationList; protocol: CCIR.Protocol);
	VAR md: CCIR.MessageDeclaration; seq: CCIR.ProtocolSequence; opt: CCIR.ProtocolOption; 
		rep: CCIR.ProtocolRepetition; alt: CCIR.ProtocolAlternative; index: LONGINT;
	BEGIN 
		IF protocol IS CCIR.MessageDeclaration THEN
			header.Char(CBC.FMessageDecl);
			md := protocol(CCIR.MessageDeclaration);
			index := mdList.GetIndexOfMessageDeclaration(md.name); ASSERT(index >= 0);
			header.Integer4(index)
		ELSIF protocol IS CCIR.ProtocolSequence THEN
			header.Char(CBC.FSequence);
			seq := protocol(CCIR.ProtocolSequence);
			GenerateProtocol(mdList, seq.first);
			GenerateProtocol(mdList, seq.second)
		ELSIF protocol IS CCIR.ProtocolOption THEN
			header.Char(CBC.FOption);
			opt := protocol(CCIR.ProtocolOption);
			GenerateProtocol(mdList, opt.protocol)
		ELSIF protocol IS CCIR.ProtocolRepetition THEN
			header.Char(CBC.FRepetition);
			rep := protocol(CCIR.ProtocolRepetition);
			GenerateProtocol(mdList, rep.protocol)
		ELSIF protocol IS CCIR.ProtocolAlternative THEN
			header.Char(CBC.FAlternative);
			alt := protocol(CCIR.ProtocolAlternative);
			GenerateProtocol(mdList, alt.first);
			GenerateProtocol(mdList, alt.second)
		ELSE HALT(111)
		END
	END GenerateProtocol;
	
	PROCEDURE NofInterfaces(com: CCIR.Component): LONGINT;
	VAR count, i: LONGINT; nested: CCIR.Component;
	BEGIN
		count := com.nestedInterfaces.Length();
		FOR i := 0 TO com.nestedComponents.Length()-1 DO
			nested := com.nestedComponents.GetComponent(i);
			INC(count, NofInterfaces(nested))
		END;
		RETURN count
	END NofInterfaces;
	
	PROCEDURE GenerateAllInterfaces(com: CCIR.Component);
	VAR i: LONGINT; nested: CCIR.Component; interface: CCIR.Interface;
	BEGIN
		FOR i := 0 TO com.nestedComponents.Length()-1 DO
			nested := com.nestedComponents.GetComponent(i);
			GenerateAllInterfaces(nested)
		END;
		FOR i := 0 TO com.nestedInterfaces.Length()-1 DO
			interface := com.nestedInterfaces.GetInterface(i);
			GenerateNewInterface(interface)
		END
	END GenerateAllInterfaces;
			
	PROCEDURE NofComponents(com: CCIR.Component): LONGINT;
	VAR count, i: LONGINT; nested: CCIR.Component;
	BEGIN
		count := 1;
		FOR i := 0 TO com.nestedComponents.Length()-1 DO
			nested := com.nestedComponents.GetComponent(i);
			INC(count, NofComponents(nested))
		END;
		RETURN count
	END NofComponents;
	
	PROCEDURE GenerateAllComponentHeaders(com: CCIR.Component);
	VAR i: LONGINT; nested: CCIR.Component;
	BEGIN
		FOR i := 0 TO com.nestedComponents.Length()-1 DO
			nested := com.nestedComponents.GetComponent(i);
			GenerateAllComponentHeaders(nested)
		END;
		GenerateComponentHeader(com)
	END GenerateAllComponentHeaders;
	
	PROCEDURE GenerateComponentHeader(component: CCIR.Component);
	VAR comSizeFixup: ComponentSizeFixup; processFixup: ProcessFixup; fixup: CG.Fixup;
	BEGIN
		GenerateComponentDefinition(component);
		
		NEW(comSizeFixup, headerFixups, component);
		NEW(fixup, header.Length(), FALSE, comSizeFixup);
		headerFixups.Add(fixup);
		header.Integer4(0); (* fixup later *)
		
		NEW(processFixup, headerFixups, component, initializer);
		NEW(fixup, header.Length(), FALSE, processFixup);
		headerFixups.Add(fixup);
		header.Integer4(0); (* fixup later *)
		
		NEW(processFixup, headerFixups, component, finalizer);
		NEW(fixup, header.Length(), FALSE, processFixup);
		headerFixups.Add(fixup);
		header.Integer4(0) (* fixup later *)
	END GenerateComponentHeader;	
	
	PROCEDURE GenerateCode(outmostCom: CCIR.Component);
	BEGIN GenerateAllComponentCode(outmostCom)
	END GenerateCode;
	
	PROCEDURE GenerateAllComponentCode(com: CCIR.Component);
	VAR i: LONGINT; nested: CCIR.Component;
	BEGIN
		FOR i := 0 TO com.nestedComponents.Length()-1 DO
			nested := com.nestedComponents.GetComponent(i);
			GenerateAllComponentCode(nested)
		END;
		GenerateComponentCode(com)
	END GenerateAllComponentCode;
	
	PROCEDURE GenerateComponentCode(component: CCIR.Component);
	VAR headerSize, nofOffered, nofRequired: LONGINT; componentSizeFixup: ComponentSizeFixup;
	BEGIN
		nofOffered := component.offeredInterfaces.Length();
		nofRequired := component.requiredInterfaces.Length();
		headerSize := ComponentHeaderSize + (nofOffered + nofRequired) * InterfaceConnectionSize;
		NEW(componentVariables, headerSize, component.usedCommunications.Length() * 4);
			(* reserve space for communications via required external interfaces *)
		AllocateVariables(componentVariables, component.variables);
		componentSizeFixup := FindComponentSizeFixup(headerFixups, component);
		componentSizeFixup.size := headerSize + componentVariables.size;
		
		AllocateImplementationList(component.implementations);
		AllocateAllProcedures(component);
		
		GenerateAllProcedures(component);
		GenerateImplementationList(component.implementations);
		GenerateInitializerAndActivity(component);
		GenerateFinalizer(component);
		
		componentVariables := NIL
	END GenerateComponentCode;
	
	PROCEDURE AllocateImplementationList(list: CCIR.ImplementationList);
	VAR i: LONGINT; impl: CCIR.Implementation;
	BEGIN
		FOR i := 0 TO list.Length()-1 DO
			impl := list.GetImplementation(i);
			AllocateImplementation(impl)
		END
	END AllocateImplementationList;
	
	PROCEDURE AllocateImplementation(impl: CCIR.Implementation);
	VAR implAlloc: ImplementationAllocation;
	BEGIN
		NEW(implAlloc, impl); implementationAllocations.Add(implAlloc);
		NEW(implAlloc.variables, 0, 4); (* reserve for communication set *)
		AllocateVariables(implAlloc.variables, impl.variables)
	END AllocateImplementation;
	
	PROCEDURE GenerateImplementationList(list: CCIR.ImplementationList);
	VAR i: LONGINT; impl: CCIR.Implementation;
	BEGIN
		FOR i := 0 TO list.Length()-1 DO
			impl := list.GetImplementation(i);
			GenerateImplementation(impl)
		END
	END GenerateImplementationList;
	
	PROCEDURE GenerateImplementation(impl: CCIR.Implementation);
	VAR implAlloc: ImplementationAllocation; sizeFixup, ebpOffsetFixup, espOffsetFixup: SizeFixup; 
	BEGIN
		implAlloc := implementationAllocations.FindImplementationAllocation(impl); ASSERT(implAlloc # NIL);
		implAlloc.startPos := CG.CodePos();
		ASSERT(currentProcessAllocation = NIL);
		currentProcessAllocation := implAlloc;
		NEW(currentProcessAllocation.stackSizeFixup, codeFixups);
		
		GenerateProcessProlog(impl, sizeFixup, ebpOffsetFixup, espOffsetFixup);
		InitializeVariables(impl);
		CreateCollections(impl);
		
		AwaitInitializationEnd;
		
		GenerateStatementSequence(impl.statements);
		
		DeleteAllSubComponents(impl);
		DeleteCollections(impl);
		EndServerProcess(impl);
		
		GenerateProcessEpilog(impl);
		
		currentProcessAllocation.stackSizeFixup.size := CG.MaxStackSize() + ProcedureStackReserve();
		(* communication buffer size is added by the runtime system *)
		sizeFixup.size := ProcessReservedSize + currentProcessAllocation.stackSizeFixup.size;
		ebpOffsetFixup.size := sizeFixup.size - ProcessTailSize;
		espOffsetFixup.size := ebpOffsetFixup.size - 4 - implAlloc.variables.size;
		
		currentProcessAllocation := NIL
	END GenerateImplementation;
	
	PROCEDURE AllocateAllProcedures(component: CCIR.Component);
	VAR i: LONGINT; impl: CCIR.Implementation;
	BEGIN
		AllocateProcedureList(component.procedures, 0);
		FOR i := 0 TO component.implementations.Length()-1 DO
			impl := component.implementations.GetImplementation(i);
			AllocateProcedureList(impl.nestedProcedures, 1)
		END
	END AllocateAllProcedures;
	
	PROCEDURE AllocateProcedureList(list: CCIR.ProcedureList; nestLevel: LONGINT);
	VAR i: LONGINT; proc: CCIR.Procedure;
	BEGIN
		FOR i := 0 TO list.Length()-1 DO
			proc := list.GetProcedure(i);
			AllocateProcedure(proc, nestLevel);
			AllocateProcedureList(proc.nestedProcedures, nestLevel + 1)
		END
	END AllocateProcedureList;
	
	PROCEDURE AllocateProcedure(proc: CCIR.Procedure; nestLevel: LONGINT);
	VAR procAlloc: ProcedureAllocation;
	BEGIN
		NEW(procAlloc, proc, nestLevel);
		procedureAllocations.Add(procAlloc);
		NEW(procAlloc.stackSizeFixup, codeFixups);
		
		NEW(procAlloc.parameters);
		AllocateProcedureParameters(procAlloc.parameters, proc.parameters, nestLevel);
		
		NEW(procAlloc.variables, 0, 0);
		IF proc.type # NIL THEN
			procAlloc.variables.AddVariableAllocation(procedureResultVariable)
		END;
		procAlloc.variables.AddVariableAllocation(stackExtensionVariable);
		AllocateVariables(procAlloc.variables, proc.variables)
	END AllocateProcedure;
	
	PROCEDURE GenerateAllProcedures(component: CCIR.Component);
	VAR i: LONGINT; impl: CCIR.Implementation;
	BEGIN
		GenerateProcedureList(component.procedures, 0);
		FOR i := 0 TO component.implementations.Length()-1 DO
			impl := component.implementations.GetImplementation(i);
			GenerateProcedureList(impl.nestedProcedures, 1)
		END
	END GenerateAllProcedures;
	
	PROCEDURE GenerateProcedureList(list: CCIR.ProcedureList; nestLevel: LONGINT);
	VAR i: LONGINT; proc: CCIR.Procedure;
	BEGIN
		FOR i := 0 TO list.Length()-1 DO
			proc := list.GetProcedure(i);
			(* generate top-most procedure first to use the variable allocations *)
			GenerateProcedure(proc, nestLevel);
			GenerateProcedureList(proc.nestedProcedures, nestLevel + 1)
		END
	END GenerateProcedureList;

	PROCEDURE GenerateProcedure(proc: CCIR.Procedure; nestLevel: LONGINT);
	VAR procAlloc: ProcedureAllocation; 
	BEGIN
		procAlloc := procedureAllocations.FindProcedureAllocation(proc); ASSERT(procAlloc # NIL);
		procAlloc.startPos := CG.CodePos();
			
		CG.ProcedureProlog(procAlloc.variables.size);
		
		InitializeVariables(proc);
		
		ExtendStackOnProcedureEntry(proc, procAlloc.stackSizeFixup);
		CreateCollections(proc);
		
		GeneratePreemptionCheck;
		
		GenerateStatementSequence(proc.statements);
		
		IF proc.type = NIL THEN
			GenerateProcedureExit(proc)
		ELSE
			CG.LoadInteger4(3); CG.Interrupt(3, 1) (* HALT(3): missing return *)
		END;
		
		procAlloc.stackSizeFixup.size := CG.MaxStackSize();
	END GenerateProcedure;
			
	PROCEDURE GenerateProcedureExit(proc: CCIR.Procedure);
	VAR procAlloc: ProcedureAllocation;
	BEGIN
		procAlloc := procedureAllocations.FindProcedureAllocation(proc); ASSERT(procAlloc # NIL);
	
		DeleteAllValueProcedureParams(proc);
		DeleteAllSubComponents(proc);
		DeleteCollections(proc);
		
		ReduceStackOnProcedureExit(proc);
				
		IF proc.type # NIL THEN
			GenerateVariable(proc, procedureResultVariable);
			CG.Convert(TypeSize(proc.type));
			CG.MakeProcedureResult(TypeSize(proc.type))
		END;
		
		CG.ProcedureEpilog(procAlloc.parameters.NofPushParameters() * 4);
		CG.EndInstruction
	END GenerateProcedureExit;
			
	PROCEDURE GenerateInitializerAndActivity(component: CCIR.Component);
	VAR processFixup: ProcessFixup; sizeFixup, ebpOffsetFixup, espOffsetFixup: SizeFixup; 
	BEGIN
		processFixup := FindProcessFixup(headerFixups, component, initializer);
		processFixup.targetPos := CG.CodePos();
		
		ASSERT(currentProcessAllocation = NIL);
		NEW(currentProcessAllocation); NEW(currentProcessAllocation.stackSizeFixup, codeFixups);
		
		GenerateProcessProlog(component, sizeFixup, ebpOffsetFixup, espOffsetFixup);
				
		InitializeInterfaceConnections(component);
		InitializeVariables(component);
		CreateCollections(component);
		CreateCommunicationBufferLists(component);
		
		GenerateStatementSequence(component.initializer);
		SetLifeState(LifeStateInitialized);
		
		GenerateStatementSequence(component.activity);
		SetLifeState(LifeStateInactive);
		
		GenerateProcessEpilog(component);
		
		currentProcessAllocation.stackSizeFixup.size := CG.MaxStackSize() + ProcedureStackReserve();
		sizeFixup.size := ProcessReservedSize + currentProcessAllocation.stackSizeFixup.size;
		ebpOffsetFixup.size := sizeFixup.size - ProcessTailSize;
		espOffsetFixup.size := ebpOffsetFixup.size - 4;
		
		currentProcessAllocation := NIL
	END GenerateInitializerAndActivity;
	
	PROCEDURE GenerateFinalizer(component: CCIR.Component);
	VAR processFixup: ProcessFixup; sizeFixup, ebpOffsetFixup, espOffsetFixup: SizeFixup; 
	BEGIN
		processFixup := FindProcessFixup(headerFixups, component, finalizer);
		processFixup.targetPos := CG.CodePos();
		
		ASSERT(currentProcessAllocation = NIL);
		NEW(currentProcessAllocation); NEW(currentProcessAllocation.stackSizeFixup, codeFixups);
		
		GenerateProcessProlog(component, sizeFixup, ebpOffsetFixup, espOffsetFixup);
		
		AwaitFinalizationStart;
		DisconnectOfferedInterfaces(component);
		
		GenerateStatementSequence(component.finalizer);
		
		CloseAllRequiredExternalComm(component);
		DeleteAllSubComponents(component);		
		DeleteCommunicationBufferLists(component);
		DeleteCollections(component);
		
		DisconnectRequiredInterfaces(component);
		AwaitDisconnectedInterfaces(component);
		DeleteInterfaceConnections(component);
		SetLifeState(LifeStateFinalized);
		
		GenerateProcessEpilog(component);
		currentProcessAllocation.stackSizeFixup.size := CG.MaxStackSize() + ProcedureStackReserve();
		sizeFixup.size := ProcessReservedSize + currentProcessAllocation.stackSizeFixup.size;
		ebpOffsetFixup.size := sizeFixup.size - ProcessTailSize;
		espOffsetFixup.size := ebpOffsetFixup.size - 4;
		
		currentProcessAllocation := NIL
	END GenerateFinalizer;
	
	PROCEDURE GenerateProcessProlog(scope: CCIR.Node; VAR sizeFixup, ebpOffsetFixup, espOffsetFixup: SizeFixup);
	VAR startFixup: CodeFixup; createProcessFixup: SystemCallFixup; interfaceFixup: InterfaceSpecificationFixup;
	BEGIN
		ASSERT((scope IS CCIR.Component) OR (scope IS CCIR.Implementation));
		
		(* StartProcess(component: PTR) *)
		CG.ProcedureProlog(0);
			
		(* processPtr := CreateProcess(component, processSize, ebpOffset, espOffset, codeAdr) *)
		CG.ProcedureParameter(0, FALSE, 8, 4);
		NEW(sizeFixup, codeFixups);
		CG.LoadAddress(sizeFixup, 0);
		NEW(ebpOffsetFixup, codeFixups);
		CG.LoadAddress(ebpOffsetFixup, 0);
		NEW(espOffsetFixup, codeFixups);
		CG.LoadAddress(espOffsetFixup, 0);
		NEW(startFixup, codeFixups);
		CG.LoadAddress(startFixup, 0);
		IF scope IS CCIR.Implementation THEN
			NEW(interfaceFixup, codeFixups, scope(CCIR.Implementation).interfaceDecl.interface);
			CG.LoadAddress(interfaceFixup, 0)
		ELSE
			CG.LoadInteger4(NilValue)
		END;
		NEW(createProcessFixup, codeFixups, CBC.FCreateProcess);
		CG.Call(createProcessFixup, 6, SimpleCallStackSize);
		CG.GetProcedureResult(4); (* processPtr *)
		IF scope IS CCIR.Implementation THEN
			CG.LoadAddress(ebpOffsetFixup, ProcessTailCommBufferOffset);
			CG.AddInteger;
			CG.MakeProcedureResult(4)
		ELSE
			CG.Discard
		END;
		CG.EndInstruction;
		CG.ProcedureEpilog(4);
		startFixup.targetPos := CG.CodePos()
	END GenerateProcessProlog;
	
	PROCEDURE GenerateProcessEpilog(scope: CCIR.Node);
	VAR deleteProcessFixup: SystemCallFixup;
	BEGIN
		GenerateProcessPointer(scope);
		CG.GetAddress;
		NEW(deleteProcessFixup, codeFixups, CBC.FDeleteProcess);
		CG.Call(deleteProcessFixup, 1, SimpleCallStackSize);
		CG.EndInstruction
	END GenerateProcessEpilog;
	
	PROCEDURE GenerateProcessPointer(scope: CCIR.Node);
	BEGIN
		IF (scope IS CCIR.Component) OR (scope IS CCIR.Implementation) THEN
			CG.ProcessParameter(ProcessParameterOffset, 4)
		ELSE
			HALT(111) (* not yet implemented *)
		END 
	END GenerateProcessPointer;
	
	PROCEDURE CheckBreakPosition(sourcePos: LONGINT);
	BEGIN
		IF breakActive THEN
			IF (CG.CodePos() > breakCodePos) & (breakSourcePos = -1) THEN 
				breakSourcePos := sourcePos
			END
		END
	END CheckBreakPosition;
	
	PROCEDURE GenerateStatementSequence(seq: CCIR.StatementSequence);
	VAR i: LONGINT; stat: CCIR.Statement;
	BEGIN
		BeginSynchronizableSection(seq);
		FOR i := 0 TO seq.statements.Length()-1 DO
			stat := seq.statements.GetStatement(i);
			GenerateStatement(stat);
			CG.EndInstruction;
			IF (i + 1) MOD SequentialPreemptionLimit = 0 THEN 
				GeneratePreemptionCheck
			END
		END;
		EndSynchronizableSection(seq)
	END GenerateStatementSequence;
	
	PROCEDURE GenerateStatement(stat: CCIR.Statement);
	BEGIN
		IF stat IS CCIR.StatementSequence THEN
			GenerateStatementSequence(stat(CCIR.StatementSequence))
		ELSIF stat IS CCIR.Assignment THEN
			GenerateAssignment(stat(CCIR.Assignment))
		ELSIF stat IS CCIR.ProcedureCall THEN
			GenerateProcedureCall(stat(CCIR.ProcedureCall))
		ELSIF stat IS CCIR.IfStatement THEN
			GenerateIfStatement(stat(CCIR.IfStatement))
		ELSIF stat IS CCIR.WhileStatement THEN
			GenerateWhileStatement(stat(CCIR.WhileStatement))
		ELSIF stat IS CCIR.RepeatStatement THEN
			GenerateRepeatStatement(stat(CCIR.RepeatStatement))
		ELSIF stat IS CCIR.ForStatement THEN
			GenerateForStatement(stat(CCIR.ForStatement))
		ELSIF stat IS CCIR.ForeachStatement THEN
			GenerateForeachStatement(stat(CCIR.ForeachStatement))
		ELSIF stat IS CCIR.ReturnStatement THEN
			GenerateReturnStatement(stat(CCIR.ReturnStatement))
		ELSIF stat IS CCIR.NewStatement THEN
			GenerateNewStatement(stat(CCIR.NewStatement))
		ELSIF stat IS CCIR.ConnectStatement THEN
			GenerateConnectStatement(stat(CCIR.ConnectStatement))
		ELSIF stat IS CCIR.DisconnectStatement THEN
			GenerateDisconnectStatement(stat(CCIR.DisconnectStatement))
		ELSIF stat IS CCIR.SendStatement THEN
			GenerateSendStatement(stat(CCIR.SendStatement))
		ELSIF stat IS CCIR.ReceiveStatement THEN
			GenerateReceiveStatement(stat(CCIR.ReceiveStatement))
		ELSIF stat IS CCIR.AwaitStatement THEN
			GenerateAwaitStatement(stat(CCIR.AwaitStatement))
		ELSE HALT(111)
		END;
		CheckBreakPosition(stat.pos)
	END GenerateStatement;
	
	PROCEDURE GenerateAssignment(assign: CCIR.Assignment);
	BEGIN
		GenerateExpression(assign.rightExpression);
		MakeCopy(assign.rightExpression);
		CreatePotentialElement(assign.leftDesignator);
		DeleteVariableContent(FALSE, FALSE, assign.leftDesignator);
		GenerateVariableDesignator(assign.leftDesignator);
		CG.Swap(2);
		CG.Store;
		CG.EndInstruction
	END GenerateAssignment;
	
	PROCEDURE DeleteVariableContent(elementDeletion, justClear: BOOLEAN; varDes: CCIR.Designator);
	VAR var: CCIR.Variable; deleteTextFixup, deleteElemFixup, existsElemFixup: SystemCallFixup; 
		args: CCIR.ExpressionList; nofKeys: LONGINT; endFixup: CodeFixup;
	BEGIN
		var := varDes.node(CCIR.Variable);
		IF (var.parameters.Length() > 0) & elementDeletion THEN
			IF ~CCIR.IsArrayCollection(var) THEN
				NEW(endFixup, codeFixups);
				args := varDes(CCIR.IndexDesignator).arguments; nofKeys := args.Length();
				
				GenerateCollectionKeyList(args);
				GenerateVariable(CCIR.GetCurrentScope(varDes), var); CG.Load;
				CG.LoadInteger4(nofKeys);
				CG.SaveTemporary(2 + nofKeys);
				NEW(existsElemFixup, codeFixups, CBC.FExistsElement);
				CG.CallWithAdditionalParameters(existsElemFixup, 2, nofKeys, CollectionCallStackSize);
				CG.GetProcedureResult(1);
				CG.ConditionalBranch(FALSE, endFixup)
			END
		END;
			
		IF varDes.type = CCIR.textType THEN
			ASSERT(~justClear);
			GenerateVariableDesignator(varDes);
			CG.GetAddress;
			CG.SaveTemporary(1);
			NEW(deleteTextFixup, codeFixups, CBC.FDeleteText);
			CG.Call(deleteTextFixup, 1, SimpleCallStackSize)
		ELSIF CCIR.IsComponentType(varDes.type) THEN
			IF justClear THEN
				GenerateVariableDesignator(varDes);
				CG.LoadInteger4(NilValue);
				CG.Store
			ELSE
				GenerateVariableDesignator(varDes);
				CG.Duplicate;
				InternalFinalizeComponent(var);
				InternalDeleteComponent
			END
		END;
			
		IF (var.parameters.Length() > 0) & elementDeletion THEN
			IF ~CCIR.IsArrayCollection(var) THEN
				GenerateCollectionKeyList(args);
				GenerateVariable(CCIR.GetCurrentScope(varDes), var); CG.Load;
				CG.LoadInteger4(nofKeys);
				CG.SaveTemporary(2 + nofKeys);
				NEW(deleteElemFixup, codeFixups, CBC.FDeleteElement);
				CG.CallWithAdditionalParameters(deleteElemFixup, 2, nofKeys, CollectionCallStackSize);
					
				BranchEntry(endFixup)
			ELSE
				IF ~justClear THEN
					GenerateVariableDesignator(varDes);
					CG.LoadInteger4(NilValue);
					CG.Store
				END
			END
		END
	END DeleteVariableContent;
			
	PROCEDURE InternalFinalizeComponent(var: CCIR.Variable);
	VAR finalizeComFixup: SystemCallFixup;
	BEGIN
		IF var.usedCommunications.Length() > 0 THEN (* close communications *)
			CG.Duplicate;
			CloseAllClientCommunications(var)
		END;
		CG.SaveTemporary(1);
		NEW(finalizeComFixup, codeFixups, CBC.FFinalizeComponent);
		CG.Call(finalizeComFixup, 1, SimpleCallStackSize)
	END InternalFinalizeComponent;
	
	PROCEDURE CloseAllClientCommunications(var: CCIR.Variable);
	VAR index, nofComm: LONGINT; decl: CCIR.InterfaceDeclaration; 
	BEGIN
		nofComm := var.usedCommunications.Length();
		FOR index := 0 TO nofComm-1 DO
			CG.Duplicate;
			decl := var.usedCommunications.GetInterfaceDeclaration(index);
			CG.CommunicationBufferForVariable(index);
			InternalCloseCommunication(decl, FALSE)
		END;
		CG.Discard
	END CloseAllClientCommunications;
		
	PROCEDURE InternalDeleteComponent;
	VAR deleteComFixup: SystemCallFixup;
	BEGIN
		CG.GetAddress; 
		CG.ProcessPointer;
		CG.SaveTemporary(2);
		NEW(deleteComFixup, codeFixups, CBC.FDeleteComponent);
		CG.Call(deleteComFixup, 2, SimpleCallStackSize)
	END InternalDeleteComponent;
		
	PROCEDURE CreatePotentialElement(varDes: CCIR.Designator);
	VAR var: CCIR.Variable; args: CCIR.ExpressionList; nofKeys: LONGINT; createElemFixup: SystemCallFixup;
	BEGIN
		var := varDes.node(CCIR.Variable);
		IF (var.parameters.Length() > 0) & ~CCIR.IsArrayCollection(var) THEN 
			args := varDes(CCIR.IndexDesignator).arguments; nofKeys := args.Length();
			GenerateCollectionKeyList(args);
			GenerateVariable(CCIR.GetCurrentScope(varDes), var); CG.Load;
			CG.LoadInteger4(nofKeys);
			CG.SaveTemporary(2 + nofKeys);
			NEW(createElemFixup, codeFixups, CBC.FCreateElement);
			CG.CallWithAdditionalParameters(createElemFixup, 2, nofKeys, CollectionCallStackSize)
		END
	END CreatePotentialElement;
	
	PROCEDURE GenerateCollectionKeyList(list: CCIR.ExpressionList);
	VAR i: LONGINT; expr: CCIR.Expression;
	BEGIN
		FOR i := 0 TO list.Length()-1 DO
			expr := list.GetExpression(i);
			GenerateExpression(expr);
			MakeCopy(expr)
		END
	END GenerateCollectionKeyList;
	
	PROCEDURE GenerateStorageParameterList(list: CCIR.ExpressionList);
	VAR i: LONGINT; expr: CCIR.Expression;
	BEGIN
		FOR i := 0 TO list.Length()-1 DO
			expr := list.GetExpression(i);
			GenerateVariableDesignator(expr(CCIR.Designator));
			CG.GetAddress
		END
	END GenerateStorageParameterList;
	
	PROCEDURE DeleteContentOfAllVariables(list: CCIR.ExpressionList);
	VAR i: LONGINT; expr: CCIR.Expression;
	BEGIN
		FOR i := 0 TO list.Length()-1 DO
			expr := list.GetExpression(i);
			DeleteVariableContent(FALSE, FALSE, expr(CCIR.Designator))
		END
	END DeleteContentOfAllVariables;
	
	PROCEDURE GenerateProcedureCall(call: CCIR.ProcedureCall);
	VAR decl: CCIR.Procedure; sysCallFixup: SystemCallFixup; arg0: CCIR.Expression;
	BEGIN
		decl := call.declaration;
		IF CCIR.predefinedProcedures.Contains(decl) THEN
			IF (decl = CCIR.writeChar) OR (decl = CCIR.writeInt) OR (decl = CCIR.writeReal) OR 
					(decl = CCIR.writeText) OR (decl = CCIR.writeLine) OR (decl = CCIR.writeHex) THEN
				GenerateProcedureArgumentList(call.arguments, decl.parameters);
				IF decl = CCIR.writeChar THEN
					NEW(sysCallFixup, codeFixups, CBC.FWriteCharacter)
				ELSIF decl = CCIR.writeInt THEN
					NEW(sysCallFixup, codeFixups, CBC.FWriteInteger)
				ELSIF decl = CCIR.writeReal THEN
					NEW(sysCallFixup, codeFixups, CBC.FWriteReal)
				ELSIF decl = CCIR.writeText THEN
					NEW(sysCallFixup, codeFixups, CBC.FWriteText)
				ELSIF decl = CCIR.writeLine THEN
					NEW(sysCallFixup, codeFixups, CBC.FWriteLine)
				ELSIF decl = CCIR.writeHex THEN
					NEW(sysCallFixup, codeFixups, CBC.FWriteHex)
				END;
				CG.Call(sysCallFixup, decl.parameters.Length(), SimpleCallStackSize);
				CG.EndInstruction
			ELSIF decl = CCIR.delete THEN
				ASSERT(call.arguments.Length() = 1);
				arg0 := call.arguments.GetExpression(0);
				IF (arg0 IS CCIR.IdentifierDesignator) & (arg0(CCIR.Designator).node(CCIR.Variable).parameters.Length() > 0) THEN
					DeleteArray(CCIR.GetCurrentScope(call), arg0(CCIR.Designator).node(CCIR.Variable))
				ELSE
					DeleteVariableContent(TRUE, FALSE, arg0(CCIR.Designator))
				END
			ELSIF (decl = CCIR.inc1) OR (decl = CCIR.dec1) THEN
				GenerateIncOrDecBy1(call)
			ELSIF (decl = CCIR.inc2) OR (decl = CCIR.dec2) THEN
				GenerateIncOrDecByAny(call)
			ELSIF decl = CCIR.move THEN
				GenerateMove(call)
			ELSIF decl = CCIR.halt THEN
				GenerateHalt(call)
			ELSIF (decl = CCIR.assert1) OR (decl = CCIR.assert2) THEN
				GenerateAssert(call)
			ELSIF decl = CCIR.passivate THEN
				ASSERT(call.arguments.Length() = 1);
				arg0 := call.arguments.GetExpression(0);
				GeneratePassivate(arg0)
			ELSE HALT(111)
			END
		ELSE
			GenerateGeneralProcedureCall(call, call.arguments, decl)
		END
	END GenerateProcedureCall;
	
	PROCEDURE GeneratePassivate(expr: CCIR.Expression);
		VAR lockType: CCIR.Identifier; passivateFixup: SystemCallFixup;
	BEGIN
		lockType := CCIR.CurrentLockType(expr);
		CG.ProcessPointer;
		GenerateExpression(expr);
		IF lockType = NIL THEN
			CG.LoadInteger1(NoLock)
		ELSIF lockType = CCIR.exclusive THEN
			CG.LoadInteger1(ExclusiveLock)
		ELSIF lockType = CCIR.shared THEN
			CG.LoadInteger1(2)
		ELSE HALT(111)
		END;
		NEW(passivateFixup, codeFixups, CBC.FPassivate);
		CG.Call(passivateFixup, 3, SimpleCallStackSize)
	END GeneratePassivate;
		
	PROCEDURE GenerateGeneralProcedureCall(current: CCIR.Node; arguments: CCIR.ExpressionList; proc: CCIR.Procedure);
	VAR i: LONGINT; expr: CCIR.Expression; par: CCIR.ProcedureParameter; scope: CCIR.Node; callFixup: ProcedureCallFixup;
		procAlloc: ProcedureAllocation; nofPushParams, maxCalleeSize: LONGINT;
	BEGIN
		procAlloc := procedureAllocations.FindProcedureAllocation(proc); ASSERT(procAlloc # NIL);
		nofPushParams := procAlloc.parameters.NofPushParameters();
		
		FOR i := 0 TO proc.parameters.Length()-1 DO
			par := proc.parameters.GetProcedureParameter(i); expr := arguments.GetExpression(i);
			IF par.variable THEN
				GenerateVariableDesignator(expr(CCIR.Designator));
				CG.GetAddress;
			ELSE
				GenerateExpression(expr);
				MakeCopy(expr)
			END
		END;
		
		scope := CCIR.GetCurrentScope(current); ASSERT(scope # NIL);
		IF ~(proc.outer IS CCIR.Component) THEN
			(* static link required *)
			IF proc.outer = scope THEN
				CG.ProcedureFrameBase
			ELSE
				CG.ProcedureStaticLink
			END
		END;
		
		(* space for callee's locals; callee works then with ESP on new stack, while EBP remains on old stack *)
		maxCalleeSize := procAlloc.variables.size + 4 + SimpleCallStackSize; (* 4 for old EBP *)
		RemainingStackSize(CCIR.GetCurrentScope(current), nofPushParams + maxCalleeSize);
		
		(* communication set *)
		IF scope IS CCIR.Component THEN
			CG.LoadInteger4(NilValue)
		ELSE
			AddressOfCommunicationSet(scope)
		END;
		CG.ComponentPointer;
		CG.ProcessPointer;
		
		IF proc.type # NIL THEN
			CG.SaveTemporary(nofPushParams)
		END;
		
		NEW(callFixup, codeFixups, proc);	
		(* reserve space for callee's local variables, as stack may be only extended at callee-side *)
		CG.Call(callFixup, nofPushParams, maxCalleeSize);
		IF proc.type = NIL THEN
			CG.EndInstruction
		ELSE
			CG.GetProcedureResult(TypeSize(proc.type))
		END
	END GenerateGeneralProcedureCall;
		
	PROCEDURE GenerateIncOrDecBy1(call: CCIR.ProcedureCall);
	VAR expr: CCIR.Expression;
	BEGIN
		ASSERT(call.arguments.Length() = 1);
		expr := call.arguments.GetExpression(0);
		GenerateVariableDesignator(expr(CCIR.Designator));
		GenerateExpression(expr);
		CG.LoadInteger4(1); 
		IF call.declaration = CCIR.inc1 THEN CG.AddInteger 
		ELSIF call.declaration = CCIR.dec1 THEN CG.SubtractInteger
		ELSE HALT(111)
		END;
		CG.Store;
		CG.EndInstruction
	END GenerateIncOrDecBy1;

	PROCEDURE GenerateHalt(call: CCIR.ProcedureCall);
	VAR expr: CCIR.Expression; 
	BEGIN
		ASSERT(call.arguments.Length() = 1);
		expr := call.arguments.GetExpression(0);
		GenerateExpression(expr);
		CG.Interrupt(3, 1);
		CG.EndInstruction
	END GenerateHalt;

	PROCEDURE GenerateAssert(call: CCIR.ProcedureCall);
	VAR condition, code: CCIR.Expression; endFixup: CodeFixup;
	BEGIN
		condition := call.arguments.GetExpression(0);
		IF call.arguments.Length() = 1 THEN code := NIL
		ELSIF call.arguments.Length() = 2 THEN code := call.arguments.GetExpression(1)
		ELSE HALT(111)
		END;
		GenerateExpression(condition);
		NEW(endFixup, codeFixups);
		CG.ConditionalBranch(TRUE, endFixup);
		IF code = NIL THEN
			CG.LoadInteger4(8) (* HALT code *)
		ELSE
			GenerateExpression(code)
		END;
		CG.Interrupt(3, 1);
		BranchEntry(endFixup);
		CG.EndInstruction
	END GenerateAssert;
									
	PROCEDURE GenerateIncOrDecByAny(call: CCIR.ProcedureCall);
	VAR a, b: CCIR.Expression;
	BEGIN
		ASSERT(call.arguments.Length() = 2);
		a := call.arguments.GetExpression(0); b := call.arguments.GetExpression(1);
		GenerateVariableDesignator(a(CCIR.Designator));
		GenerateExpression(a);
		GenerateExpression(b);
		IF call.declaration = CCIR.inc2 THEN CG.AddInteger
		ELSIF call.declaration = CCIR.dec2 THEN CG.SubtractInteger
		ELSE HALT(111)
		END;
		CG.Store;
		CG.EndInstruction
	END GenerateIncOrDecByAny;
	
	PROCEDURE GenerateMove(call: CCIR.ProcedureCall);
	VAR sourceExpr, targetExpr: CCIR.Expression; sourceDes, targetDes: CCIR.Designator;
	BEGIN
		sourceExpr := call.arguments.GetExpression(0); sourceDes := sourceExpr(CCIR.Designator);
		targetExpr := call.arguments.GetExpression(1); targetDes := targetExpr(CCIR.Designator);
		GenerateDetach(sourceDes);
		CG.Duplicate;
		GenerateAttach(targetDes);
		CreatePotentialElement(targetDes);
		DeleteVariableContent(FALSE, FALSE, targetDes);
		GenerateVariableDesignator(targetDes);
		CG.Swap(2);
		CG.Store;
		CG.EndInstruction
	END GenerateMove;
	
	PROCEDURE GenerateDetach(des: CCIR.Designator);
	VAR var: CCIR.Variable; detachFixup: SystemCallFixup;
	BEGIN
		var := des.node(CCIR.Variable);
		
		GenerateVariableDesignator(des);
		
		CG.Duplicate;
		CloseAllClientCommunications(var);
		
		CG.Duplicate;
		CG.ProcessPointer;
		CG.SaveTemporary(2);
		NEW(detachFixup, codeFixups, CBC.FDetachComponent);
		CG.Call(detachFixup, 2, SimpleCallStackSize);
		
		CG.LoadToRegister; (* hold reference to component in register *)
				
		DeleteVariableContent(TRUE, TRUE, des)
	END GenerateDetach;

	PROCEDURE GenerateProcedureArgumentList(args: CCIR.ExpressionList; pars: CCIR.ProcedureParameterList);
	VAR i: LONGINT; arg: CCIR.Expression; par: CCIR.ProcedureParameter;
	BEGIN
		FOR i := 0 TO args.Length()-1 DO
			arg := args.GetExpression(i); par := pars.GetProcedureParameter(i);
			ASSERT(~par.variable);
			GenerateExpression(arg);
			MakeCopy(arg)
		END
	END GenerateProcedureArgumentList;
	
	PROCEDURE GenerateIfStatement(if: CCIR.IfStatement);
	VAR i: LONGINT; nextFixup, endFixup: CodeFixup; cb: CCIR.ConditionalBlock;
	BEGIN
		NEW(endFixup, codeFixups);
		GenerateConditionalBlock(if.ifBlock, nextFixup);
		FOR i := 0 TO if.elsifBlocks.Length()-1 DO
			CG.Branch(endFixup);
			BranchEntry(nextFixup);
			cb := if.elsifBlocks.GetConditionalBlock(i);
			GenerateConditionalBlock(cb, nextFixup)
		END;
		IF if.else # NIL THEN
			CG.Branch(endFixup);
			BranchEntry(nextFixup);
			GenerateStatementSequence(if.else)
		ELSE
			BranchEntry(nextFixup)
		END;
		BranchEntry(endFixup)
	END GenerateIfStatement;
	
	PROCEDURE GenerateConditionalBlock(cb: CCIR.ConditionalBlock; VAR nextFixup: CodeFixup);
	BEGIN
		NEW(nextFixup, codeFixups);
		GenerateExpression(cb.condition);
		CG.ConditionalBranch(FALSE, nextFixup);
		GenerateStatementSequence(cb.statements)
	END GenerateConditionalBlock;
	
	PROCEDURE GenerateWhileStatement(while: CCIR.WhileStatement);
	VAR startFixup, endFixup: CodeFixup;
	BEGIN
		NEW(startFixup, codeFixups); NEW(endFixup, codeFixups);
		BranchEntry(startFixup);
		GenerateExpression(while.condition);
		CG.ConditionalBranch(FALSE, endFixup);
		GenerateStatementSequence(while.statements);
		GeneratePreemptionCheck;
		CG.Branch(startFixup);
		BranchEntry(endFixup)
	END GenerateWhileStatement;
	
	PROCEDURE GenerateRepeatStatement(repeat: CCIR.RepeatStatement);
	VAR startFixup: CodeFixup;
	BEGIN
		NEW(startFixup, codeFixups);
		BranchEntry(startFixup);
		GenerateStatementSequence(repeat.statements);
		GeneratePreemptionCheck;
		GenerateExpression(repeat.condition);
		CG.ConditionalBranch(FALSE, startFixup)
	END GenerateRepeatStatement;
	
	PROCEDURE GenerateForStatement(for: CCIR.ForStatement);
	VAR startFixup, endFixup: CodeFixup; toDes: CCIR.IdentifierDesignator;
	BEGIN
		NEW(startFixup, codeFixups); NEW(endFixup, codeFixups);
		
		(* init *)
		GenerateVariableDesignator(for.varDesignator);
		GenerateExpression(for.fromExpression);
		CG.Store;
		CG.EndInstruction;
		
		(* pre-evaluate to *)
		NEW(toDes, -1, for.temporaryVariable.name); 
		toDes.SetDesignatedNode(for.temporaryVariable);
		toDes.SetOuter(for);
		GenerateVariableDesignator(toDes);
		GenerateExpression(for.toExpression);
		CG.Store;
		CG.EndInstruction;
		
		(* to *)
		BranchEntry(startFixup);
		GenerateExpression(for.varDesignator);
		GenerateExpression(toDes);
		IF CCIR.ConstantInteger(for.byExpression) > 0 THEN CG.GreaterInteger
		ELSIF CCIR.ConstantInteger(for.byExpression) < 0 THEN CG.LessInteger
		ELSE HALT(100) (* BY 0 not allowed *)
		END;
		CG.ConditionalBranch(TRUE, endFixup);
		
		(* body *)
		GenerateStatementSequence(for.statements);
		GeneratePreemptionCheck;
		
		(* increment *)
		GenerateVariableDesignator(for.varDesignator);
		GenerateExpression(for.varDesignator);
		GenerateExpression(for.byExpression);
		CG.AddInteger;
		CG.Store;
		CG.EndInstruction;
		
		(* end *)
		CG.Branch(startFixup);
		BranchEntry(endFixup)
	END GenerateForStatement;
	
	PROCEDURE ForAllSubComponents(scope: CCIR.Node; var: CCIR.Variable; op: GenericForAllOperation);
	VAR startFixup, endFixup: CodeFixup; riderDes: CCIR.IdentifierDesignator; isArray: BOOLEAN;
		foreachStartFixup, foreachContinueFixup, foreachGetValueFixup, foreachNextFixup: SystemCallFixup;
	BEGIN
		isArray := CCIR.IsArrayCollection(var);
		ASSERT(var.tempRiderVar # NIL);
		NEW(riderDes, -1, var.tempRiderVar.name); 
		riderDes.SetDesignatedNode(var.tempRiderVar);
		riderDes.SetOuter(scope);
		
		NEW(startFixup, codeFixups); NEW(endFixup, codeFixups);
		
		(* ForeachStart(collection, ADR(rider), isArray) *)
		GenerateVariable(scope, var);
		GenerateVariableDesignator(riderDes);
		CG.GetAddress;
		IF isArray THEN CG.LoadInteger1(TrueValue) ELSE CG.LoadInteger1(FalseValue) END;
		NEW(foreachStartFixup, codeFixups, CBC.FForeachStart);
		CG.Call(foreachStartFixup, 3, SimpleCallStackSize);
		CG.EndInstruction;
		
		(* WHILE ForeachContinue(collection, rider, isArray) DO *)
		BranchEntry(startFixup);
		GenerateVariable(scope, var);
		GenerateExpression(riderDes);
		IF isArray THEN CG.LoadInteger1(TrueValue) ELSE CG.LoadInteger1(FalseValue) END;
		CG.SaveTemporary(3);
		NEW(foreachContinueFixup, codeFixups, CBC.FForeachContinue);
		CG.Call(foreachContinueFixup, 3, SimpleCallStackSize);
		CG.GetProcedureResult(1);
		CG.ConditionalBranch(FALSE, endFixup);
		
		(* adr := ForeachGetValue(collection, rider, isArray) *)
		GenerateVariable(scope, var);
		GenerateExpression(riderDes);
		IF isArray THEN CG.LoadInteger1(TrueValue) ELSE CG.LoadInteger1(FalseValue) END;
		NEW(foreachGetValueFixup, codeFixups, CBC.FForeachGetValue);
		CG.Call(foreachGetValueFixup, 3, SimpleCallStackSize);
		CG.GetProcedureResult(4);
		CG.MakeDeref(TypeSize(var.type));
				
		(* body *)
		op(scope, var);
		
		(* ForeachNext(coll, ADR(rider), isArray) *)
		GenerateVariable(scope, var);
		GenerateVariableDesignator(riderDes);
		CG.GetAddress;
		IF isArray THEN CG.LoadInteger1(TrueValue) ELSE CG.LoadInteger1(FalseValue) END;
		NEW(foreachNextFixup, codeFixups, CBC.FForeachNext);
		CG.Call(foreachNextFixup, 3, SimpleCallStackSize);
		CG.EndInstruction;
		GeneratePreemptionCheck;
		
		(* END *)
		CG.Branch(startFixup);
		BranchEntry(endFixup)
	END ForAllSubComponents;
	
	PROCEDURE GenerateForeachStatement(foreach: CCIR.ForeachStatement);
	VAR startFixup, endFixup: CodeFixup; riderDes: CCIR.IdentifierDesignator; nofKeys: LONGINT; isArray: BOOLEAN;
		foreachStartFixup, foreachContinueFixup, foreachGetKeyFixup, foreachNextFixup: SystemCallFixup;
	BEGIN
		isArray := CCIR.IsArrayCollection(foreach.of.node(CCIR.Variable));
		NEW(riderDes, -1, foreach.temporaryVariable.name); 
		riderDes.SetDesignatedNode(foreach.temporaryVariable);
		riderDes.SetOuter(foreach);
		
		NEW(startFixup, codeFixups); NEW(endFixup, codeFixups);
		
		(* ForeachStart(collection, ADR(rider), isArray) *)
		GenerateVariableDesignator(foreach.of);
		GenerateVariableDesignator(riderDes);
		CG.GetAddress;
		IF isArray THEN CG.LoadInteger1(TrueValue) ELSE CG.LoadInteger1(FalseValue) END;
		NEW(foreachStartFixup, codeFixups, CBC.FForeachStart);
		CG.Call(foreachStartFixup, 3, SimpleCallStackSize);
		CG.EndInstruction;
		
		(* WHILE ForeachContinue(collection, rider, isArray) DO *)
		BranchEntry(startFixup);
		GenerateVariableDesignator(foreach.of);
		GenerateExpression(riderDes);
		IF isArray THEN CG.LoadInteger1(TrueValue) ELSE CG.LoadInteger1(FalseValue) END;
		CG.SaveTemporary(3);
		NEW(foreachContinueFixup, codeFixups, CBC.FForeachContinue);
		CG.Call(foreachContinueFixup, 3, SimpleCallStackSize);
		CG.GetProcedureResult(1);
		CG.ConditionalBranch(FALSE, endFixup);
		
		(* ForeachGetKey(ADR(key[0]), .., ADR(key[nofKeys-1]), collection, rider, nofKeys, isArray) *)
		DeleteContentOfAllVariables(foreach.varDesignators);
		GenerateStorageParameterList(foreach.varDesignators);
		nofKeys := foreach.varDesignators.Length();
		GenerateVariableDesignator(foreach.of);
		GenerateVariableDesignator(riderDes);
		CG.LoadInteger4(nofKeys);
		IF isArray THEN CG.LoadInteger1(TrueValue) ELSE CG.LoadInteger1(FalseValue) END;
		NEW(foreachGetKeyFixup, codeFixups, CBC.FForeachGetKey);
		CG.CallWithAdditionalParameters(foreachGetKeyFixup, 4, nofKeys, SimpleCallStackSize);
		CG.EndInstruction;
		
		(* body *)
		GenerateStatementSequence(foreach.statements);
		
		(* ForeachNext(coll, ADR(rider), isArray) *)
		GenerateVariableDesignator(foreach.of);
		GenerateVariableDesignator(riderDes);
		CG.GetAddress;
		IF isArray THEN CG.LoadInteger1(TrueValue) ELSE CG.LoadInteger1(FalseValue) END;
		NEW(foreachNextFixup, codeFixups, CBC.FForeachNext);
		CG.Call(foreachNextFixup, 3, SimpleCallStackSize);
		CG.EndInstruction;
		
		(* END *)
		CG.Branch(startFixup);
		BranchEntry(endFixup)
	END GenerateForeachStatement;
	
	PROCEDURE GenerateReturnStatement(return: CCIR.ReturnStatement);
	VAR proc: CCIR.Procedure; lockType: CCIR.Identifier;
	BEGIN
		proc := CCIR.GetSurroundingProcedure(return);
		IF return.expression # NIL THEN
			GenerateExpression(return.expression);
			MakeCopy(return.expression);
			GenerateVariable(CCIR.GetCurrentScope(return), procedureResultVariable);
			CG.Convert(TypeSize(return.expression.type));
			CG.Swap(2);
			CG.Store
		END;
		lockType := CCIR.CurrentLockType(return);
		IF lockType # NIL THEN
			GenerateUnlock(lockType)
		END;
		GenerateProcedureExit(proc)
	END GenerateReturnStatement;

	PROCEDURE GenerateAwaitStatement(await: CCIR.AwaitStatement);
	VAR lockType: CCIR.Identifier; endAwaitFixupPos: LONGINT; startAwaitFixup, continueFixup: CodeFixup; 
		awaitCallFixup: SystemCallFixup;
	BEGIN
		IF await.condition IS CCIR.InputFunction THEN
			GenerateAwaitMessageInput(await)
		ELSE
			NEW(startAwaitFixup, codeFixups);
			CG.BeginAwaitCondition(startAwaitFixup.targetPos, endAwaitFixupPos);
			GenerateExpression(await.condition);
			CG.EndAwaitCondition(endAwaitFixupPos);
			CG.EndInstruction;
		
			lockType := CCIR.CurrentLockType(await);
			NEW(continueFixup, codeFixups);
			GenerateExpression(await.condition);
			CG.ConditionalBranch(TRUE, continueFixup);
									
			CG.ProcessPointer;
			IF lockType = CCIR.exclusive THEN
				CG.LoadInteger1(TrueValue)
			ELSIF lockType = CCIR.shared THEN
				CG.LoadInteger1(FalseValue)
			ELSE HALT(111)
			END;
			CG.LoadEBP;
			CG.LoadAddress(startAwaitFixup, 0);
			NEW(awaitCallFixup, codeFixups, CBC.FAwait);
			CG.Call(awaitCallFixup, 4, SimpleCallStackSize);
						
			(* END *)
			BranchEntry(continueFixup)
		END
	END GenerateAwaitStatement;
	
	PROCEDURE GenerateAwaitMessageInput(await: CCIR.AwaitStatement);
	VAR input: CCIR.InputFunction; lockType: CCIR.Identifier; endFixup: CodeFixup; intDes: CCIR.InterfaceDesignator;
		awaitMessageFixup: SystemCallFixup;
	BEGIN
		input := await.condition(CCIR.InputFunction);
		intDes := input.interfaceDesignator(CCIR.InterfaceDesignator);
		PotentialOpenCommunication(intDes, input.messageIdentifier);
		
		NEW(endFixup, codeFixups);
		GenerateExpression(input);
		CG.ConditionalBranch(TRUE, endFixup);
		
		lockType := CCIR.CurrentLockType(await);
		SelectCommunication(intDes);
		CG.ProcessPointer;
		IF lockType = CCIR.exclusive THEN CG.LoadInteger1(TrueValue) ELSE CG.LoadInteger1(FalseValue) END;
		NEW(awaitMessageFixup, codeFixups, CBC.FAwaitMessage);
		CG.Call(awaitMessageFixup, 3, SimpleCallStackSize);
		CG.GetProcedureResult(4); (* returns message id *)
		IF input.messageIdentifier.EqualText(CCIR.AnyMessage) THEN
			CG.Discard;
		ELSE
			InternalCheckMessage(intDes.declaration.interface, input.messageIdentifier)
		END;
				
		BranchEntry(endFixup)
	END GenerateAwaitMessageInput;

	PROCEDURE GenerateNewStatement(new: CCIR.NewStatement);
	VAR setTextFixup, createComFixup: SystemCallFixup; synchronized: BOOLEAN; 
		templateFixup: ComponentTemplateFixup; var: CCIR.Variable; 
	BEGIN
		var := new.variableDes.node(CCIR.Variable);
		IF (new.variableDes IS CCIR.IdentifierDesignator) & CCIR.IsArrayCollection(var) THEN
			GenerateNewArray(new)
		ELSE	
			CreatePotentialElement(new.variableDes);
			DeleteVariableContent(FALSE, FALSE, new.variableDes);
			IF new.variableDes.type = CCIR.textType THEN
				GenerateVariableDesignator(new.variableDes);
				CG.GetAddress;
				GenerateExpression(new.additionalArguments.GetExpression(0));
				NEW(setTextFixup, codeFixups, CBC.FSetTextLength);
				CG.Call(setTextFixup, 2, SimpleCallStackSize);
				CG.EndInstruction
			ELSIF CCIR.IsComponentType(new.variableDes.type) THEN
				ASSERT(new.componentType.componentDefinition # NIL);
				synchronized := (var.attributeList # NIL) & var.attributeList.Contains(CCIR.timesynchron);
							
				NEW(templateFixup, codeFixups, new.componentType.componentDefinition);
				CG.LoadAddress(templateFixup, 0);
				CG.ComponentPointer;
				IF synchronized THEN CG.LoadInteger1(TrueValue) ELSE CG.LoadInteger1(FalseValue) END;
				CG.SaveTemporary(3);
				NEW(createComFixup, codeFixups, CBC.FCreateComponent);
				CG.Call(createComFixup, 3, SimpleCallStackSize);
				CG.GetProcedureResult(4);
				
				GenerateVariableDesignator(new.variableDes);
				CG.Swap(2);
				CG.Store;
				CG.EndInstruction
			ELSE HALT(111)
			END
		END
	END GenerateNewStatement;
	
	PROCEDURE GenerateNewArray(new: CCIR.NewStatement);
	VAR var: CCIR.Variable; varAlloc: VariableAllocation; nofDims, i: LONGINT; 
		expr: CCIR.Expression; createFixup: SystemCallFixup;
	BEGIN
		ASSERT(new.variableDes IS CCIR.IdentifierDesignator);
		var := new.variableDes.node(CCIR.Variable); 
		varAlloc := GetVariableAllocation(var); ASSERT(varAlloc # NIL); ASSERT(varAlloc.elemSize > 0);
		ASSERT(CCIR.IsArrayCollection(var));
		nofDims := new.additionalArguments.Length(); ASSERT(nofDims > 0);
		FOR i := 0 TO nofDims-1 DO
			expr := new.additionalArguments.GetExpression(i);
			GenerateExpression(expr)
		END;
		GenerateVariable(CCIR.GetCurrentScope(new), var);
		CG.GetAddress;
		CG.LoadInteger4(nofDims);
		CG.LoadInteger4(varAlloc.elemSize);
		IF CCIR.IsComponentType(var.type) THEN CG.LoadInteger1(TrueValue) ELSE CG.LoadInteger1(FalseValue) END;
		NEW(createFixup, codeFixups, CBC.FCreateArray);
		CG.CallWithAdditionalParameters(createFixup, 4, nofDims, SimpleCallStackSize)
	END GenerateNewArray;
	
	PROCEDURE GenerateConnectStatement(connect: CCIR.ConnectStatement);
	VAR connectFixup: SystemCallFixup;
	BEGIN
		IF connect.target IS CCIR.ImplementationDesignator THEN
			SetImplementation(connect.source(CCIR.InterfaceDesignator), 
				connect.target(CCIR.ImplementationDesignator).implementation)
		ELSE
			SelectInterface(connect.source(CCIR.InterfaceDesignator));
			SelectInterface(connect.target(CCIR.InterfaceDesignator));
			CG.ProcessPointer;
			NEW(connectFixup, codeFixups, CBC.FConnect);
			CG.Call(connectFixup, 3, SimpleCallStackSize);
			CG.EndInstruction
		END
	END GenerateConnectStatement;
	
	PROCEDURE SetImplementation(des: CCIR.InterfaceDesignator; impl: CCIR.Implementation);
	VAR implFixup: ImplementationFixup;
	BEGIN
		SelectInterface(des);
		CG.Deref(InterfaceConnComponentOffset, 4);
		CG.ComponentPointer;
		CG.Store;
	
		SelectInterface(des);
		CG.Deref(InterfaceConnReferenceOffset, 4);
		NEW(implFixup, codeFixups, impl);
		CG.LoadAddress(implFixup, 0);
		CG.Store;
		
		SelectInterface(des);
		CG.Deref(InterfaceConnFlagOffset, 1);
		CG.LoadInteger1(ConnectionFlagImplemented);
		CG.Store
	END SetImplementation;
	
	PROCEDURE GenerateDisconnectStatement(disconnect: CCIR.DisconnectStatement);
	VAR disconnectFixup: SystemCallFixup;
	BEGIN
		SelectInterface(disconnect.intDes(CCIR.InterfaceDesignator));
		CG.ProcessPointer;
		NEW(disconnectFixup, codeFixups, CBC.FDisconnect);
		CG.Call(disconnectFixup, 2, SimpleCallStackSize);
		CG.EndInstruction
	END GenerateDisconnectStatement;
	
	PROCEDURE GenerateSendStatement(send: CCIR.SendStatement);
	VAR intDes: CCIR.InterfaceDesignator; i: LONGINT; par: CCIR.Expression; 
	BEGIN
		intDes := send.interfaceDesignator(CCIR.InterfaceDesignator);
		
		PotentialOpenCommunication(intDes, send.messageIdentifier);
		
		WaitToSend(intDes);
		(* returns entry address *)
				
		FOR i := 0 TO send.messageArguments.Length()-1 DO (* set parameter *)
			par := send.messageArguments.GetExpression(i); 
			CG.Duplicate; ASSERT(TypeSize(par.type) <= 4);
			CG.Deref(CommEntryParameterOffset + i * 4, TypeSize(par.type));
			GenerateSendParameter(par);
			CG.Store
		END;
		
		(* requires entryAdr *)
		CompleteSend(intDes, send.messageIdentifier);
			
		PotentialCloseCommunication(intDes, send.messageIdentifier);
		CG.EndInstruction
	END GenerateSendStatement;
	
	(* requires entryAdr *)
	PROCEDURE CompleteSend(intDes: CCIR.InterfaceDesignator; messageId: CCIR.Identifier);
	VAR completeSendFixup: SystemCallFixup;
	BEGIN
		(* entryAdr already generated *)
		SelectCommunication(intDes); 
		CG.ProcessPointer;
		GenerateMessage(intDes.declaration.interface, messageId);
		NEW(completeSendFixup, codeFixups, CBC.FCompleteSend);
		CG.Call(completeSendFixup, 4, SimpleCallStackSize);
		CG.EndInstruction
	END CompleteSend;
			
	PROCEDURE GenerateReceiveStatement(receive: CCIR.ReceiveStatement);
	VAR intDes: CCIR.InterfaceDesignator; i: LONGINT; par: CCIR.Expression; 
	BEGIN
		intDes := receive.interfaceDesignator(CCIR.InterfaceDesignator);
		FOR i := 0 TO receive.messageArguments.Length()-1 DO
			par := receive.messageArguments.GetExpression(i);
			CreatePotentialElement(par(CCIR.Designator));
			DeleteVariableContent(FALSE, FALSE, par(CCIR.Designator))
		END;
		PotentialOpenCommunication(intDes, receive.messageIdentifier);
				
		WaitToReceive(intDes);
		(* returns entry address *)
		
		CG.Duplicate;
		InternalCheckMessage(intDes.declaration.interface, receive.messageIdentifier);
		
		FOR i := 0 TO receive.messageArguments.Length()-1 DO (* get parameters *)
			par := receive.messageArguments.GetExpression(i);
			CG.Duplicate; 
			CG.Deref(CommEntryParameterOffset + i*4, TypeSize(par.type));
			
			IF CCIR.IsComponentType(par.type) THEN
				CG.Duplicate;
				GenerateAttach(par(CCIR.Designator))
			END;
			
			GenerateVariableDesignator(par(CCIR.Designator)); ASSERT(TypeSize(par.type) <= 4);
			CG.Swap(2);
			CG.Store
		END;
		CG.Discard; (* discard entryAdr *)
		
		CompleteReceive(intDes);

		PotentialCloseCommunication(intDes, receive.messageIdentifier);
		CG.EndInstruction
	END GenerateReceiveStatement;
	
	(* component address already generated *)
	PROCEDURE GenerateAttach(des: CCIR.Designator);
	VAR var: CCIR.Variable; attachFixup: SystemCallFixup;
	BEGIN
		CG.ComponentPointer;
		var := des.node(CCIR.Variable);
		IF (var.attributeList # NIL) & var.attributeList.Contains(CCIR.timesynchron) THEN
			CG.LoadInteger1(TrueValue)
		ELSE
			CG.LoadInteger1(FalseValue)
		END;
		CG.SaveTemporary(3);
		NEW(attachFixup, codeFixups, CBC.FAttachComponent);
		CG.Call(attachFixup, 3, SimpleCallStackSize)
	END GenerateAttach;
	
	PROCEDURE CompleteReceive(intDes: CCIR.InterfaceDesignator);
	VAR completeReceiveFixup: SystemCallFixup;
	BEGIN
		SelectCommunication(intDes);
		NEW(completeReceiveFixup, codeFixups, CBC.FCompleteReceive);
		CG.Call(completeReceiveFixup, 1, SimpleCallStackSize);
		CG.EndInstruction
	END CompleteReceive;
	
	PROCEDURE GenerateReceiveTest(receive: CCIR.ReceiveTestFunction);
	VAR intDes: CCIR.InterfaceDesignator;
	BEGIN
		intDes := receive.interfaceDesignator(CCIR.InterfaceDesignator);
		PotentialOpenCommunication(intDes, receive.messageIdentifier);
		
		WaitToReceive(intDes);
		(* returns entry address *)
		
		CG.Deref(CommEntryMessageOffset, 4);
		GenerateMessage(intDes.declaration.interface, receive.messageIdentifier);
		CG.EqualInteger
	END GenerateReceiveTest;
	
	PROCEDURE GenerateInputFunction(input: CCIR.InputFunction);
	VAR intDes: CCIR.InterfaceDesignator; inputFixup: SystemCallFixup;
	BEGIN
		intDes := input.interfaceDesignator(CCIR.InterfaceDesignator);
		PotentialOpenCommunication(intDes, input.messageIdentifier);
		
		SelectCommunication(intDes);
		CG.ProcessPointer;
		CG.SaveTemporary(2);
		NEW(inputFixup, codeFixups, CBC.FInputMessage);
		CG.Call(inputFixup, 2, SimpleCallStackSize);
		CG.GetProcedureResult(4);
		IF input.messageIdentifier.EqualText(CCIR.AnyMessage) THEN
			CG.LoadInteger4(NoMessage);
			CG.UnequalInteger
		ELSE
			GenerateMessage(intDes.declaration.interface, input.messageIdentifier);
			CG.EqualInteger
		END
	END GenerateInputFunction;
	
	PROCEDURE WaitToSend(intDes: CCIR.InterfaceDesignator);
	VAR waitFixup: SystemCallFixup;
	BEGIN
		SelectCommunication(intDes);
		CG.ProcessPointer;
		CG.SaveTemporary(2);
		NEW(waitFixup, codeFixups, CBC.FWaitToSend);
		CG.Call(waitFixup, 2, SimpleCallStackSize);
		CG.GetProcedureResult(4)
	END WaitToSend;
	
	PROCEDURE WaitToReceive(intDes: CCIR.InterfaceDesignator);
	VAR waitFixup: SystemCallFixup;
	BEGIN
		SelectCommunication(intDes);
		CG.ProcessPointer;
		CG.SaveTemporary(2);
		NEW(waitFixup, codeFixups, CBC.FWaitToReceive);
		CG.Call(waitFixup, 2, SimpleCallStackSize);
		CG.GetProcedureResult(4)
	END WaitToReceive;
	
	PROCEDURE GenerateMessage(interface: CCIR.Interface; messageId: CCIR.Identifier);
	VAR index: LONGINT;
	BEGIN
		IF messageId.EqualText(CCIR.AnyMessage) THEN HALT(111) (* cannot be generated *)
		ELSIF messageId.EqualText(CCIR.FinishMessage) THEN CG.LoadInteger4(FinishMessage)
		ELSE
			index := interface.messageDeclarations.GetIndexOfMessageDeclaration(messageId); ASSERT(index >= 0);
			CG.LoadInteger4(index)
		END
	END GenerateMessage;
		
	PROCEDURE InternalCheckMessage(interface: CCIR.Interface; message: CCIR.Identifier);
	VAR endFixup: CodeFixup;
	BEGIN
		(* entry address already generated *)
		NEW(endFixup, codeFixups);
		CG.Deref(CommEntryMessageOffset, 4);
		GenerateMessage(interface, message);
		CG.EqualInteger;
		CG.ConditionalBranch(TRUE, endFixup);
		CG.LoadInteger4(212); (* wrong message received *)
		CG.SaveTemporary(1);
		CG.Interrupt(3, 1);
		BranchEntry(endFixup)
	END InternalCheckMessage;
	
	PROCEDURE PotentialOpenCommunication(interfaceDes: CCIR.InterfaceDesignator; message: CCIR.Identifier);
	BEGIN
		IF ~((interfaceDes IS CCIR.ExternalInterfaceDesignator) & interfaceDes.isOffered) THEN
			IF CCIR.PotentialFirstMessage(interfaceDes.declaration.interface, message) THEN
				GenerateOpenCommunication(interfaceDes)
			END
		END
	END PotentialOpenCommunication;
	
	PROCEDURE GenerateOpenCommunication(interfaceDes: CCIR.InterfaceDesignator);
	VAR openFixup: SystemCallFixup;
	BEGIN
		SelectInterface(interfaceDes);
		SelectCommunication(interfaceDes);
		CG.GetAddress;
		CG.ProcessPointer;
		CG.SaveTemporary(3);
		NEW(openFixup, codeFixups, CBC.FOpenCommunication);
		CG.Call(openFixup, 3, SimpleCallStackSize)
	END GenerateOpenCommunication;

	PROCEDURE PotentialCloseCommunication(interfaceDes: CCIR.InterfaceDesignator; message: CCIR.Identifier);
	BEGIN
		IF ~((interfaceDes IS CCIR.ExternalInterfaceDesignator) & interfaceDes.isOffered) THEN
			IF CCIR.GuaranteedLastMessage(interfaceDes.declaration.interface, message) THEN
				GenerateCloseCommunication(interfaceDes)
			END
		END
	END PotentialCloseCommunication;
	
	PROCEDURE GenerateCloseCommunication(interfaceDes: CCIR.InterfaceDesignator);
	VAR closeFixup: SystemCallFixup;
	BEGIN
		SelectCommunication(interfaceDes);
		InternalCloseCommunication(interfaceDes.declaration, interfaceDes.index # NIL)
	END GenerateCloseCommunication;
	
	PROCEDURE InternalCloseCommunication(decl: CCIR.InterfaceDeclaration; hasIndex: BOOLEAN);
	VAR closeFixup: SystemCallFixup;
	BEGIN
		(* communication buffer already generated *)
		CG.GetAddress;
		CG.ProcessPointer;
		CG.SaveTemporary(2);
		IF ((decl.minNumber = 1) & (decl.maxNumber = 1)) OR hasIndex THEN 
			NEW(closeFixup, codeFixups, CBC.FCloseCommunication);
		ELSE
			NEW(closeFixup, codeFixups, CBC.FCloseCommunicationList)
		END;
		CG.Call(closeFixup, 2, SimpleCallStackSize)
	END InternalCloseCommunication;
	
	PROCEDURE GenerateSendParameter(expr: CCIR.Expression);
	BEGIN
		IF CCIR.IsComponentType(expr.type) THEN (* send by moving *)
			GenerateDetach(expr(CCIR.Designator))
		ELSIF expr.type IS CCIR.DataType THEN (* send by copying *)
			GenerateExpression(expr);
			MakeCopy(expr)
		ELSE HALT(111)
		END
	END GenerateSendParameter;
		
	PROCEDURE GeneratePreemptionCheck;
	VAR endFixup: CodeFixup;
	BEGIN
		NEW(endFixup, codeFixups);
		CG.PreemptionCheck(endFixup);
		GenerateSuspendProcess;
		BranchEntry(endFixup);
		CG.EndInstruction
	END GeneratePreemptionCheck;
	
	PROCEDURE GenerateSuspendProcess;
	VAR suspendFixup: SystemCallFixup;
	BEGIN
		CG.ProcessPointer;
		CG.SaveTemporary(1);
		NEW(suspendFixup, codeFixups, CBC.FPreempt);
		CG.Call(suspendFixup, 1, SimpleCallStackSize)
	END GenerateSuspendProcess;
	
	PROCEDURE GenerateExpression(expr: CCIR.Expression);
	VAR var: CCIR.Variable;
	BEGIN
		BeginSynchronizableSection(expr);
		IF expr IS CCIR.CharacterValue THEN
			GenerateCharacterValue(expr(CCIR.CharacterValue))
		ELSIF expr IS CCIR.BooleanValue THEN
			GenerateBooleanValue(expr(CCIR.BooleanValue))
		ELSIF expr IS CCIR.IntegerValue THEN
			GenerateIntegerValue(expr(CCIR.IntegerValue))
		ELSIF expr IS CCIR.RealValue THEN
			GenerateRealValue(expr(CCIR.RealValue))
		ELSIF expr IS CCIR.TextValue THEN
			GenerateTextValue(expr(CCIR.TextValue))
		ELSIF expr IS CCIR.Designator THEN
			IF expr(CCIR.Designator).node IS CCIR.Variable THEN
				var := expr(CCIR.Designator).node(CCIR.Variable);
				IF CCIR.predefinedVariables.Contains(var) THEN
					GenerateTimeVariable
				ELSE
					GenerateVariableDesignator(expr(CCIR.Designator));
					CG.Load
				END
			ELSIF expr(CCIR.Designator).node IS CCIR.Constant THEN
				GenerateExpression(expr(CCIR.Designator).node(CCIR.Constant).expression)
			ELSE HALT(111)
			END
		ELSIF expr IS CCIR.UnaryExpression THEN
			GenerateUnaryExpression(expr(CCIR.UnaryExpression))
		ELSIF expr IS CCIR.BinaryExpression THEN
			GenerateBinaryExpression(expr(CCIR.BinaryExpression))
		ELSIF expr IS CCIR.FunctionCall THEN
			GenerateFunctionCall(expr(CCIR.FunctionCall))
		ELSIF expr IS CCIR.ReceiveTestFunction THEN
			GenerateReceiveTest(expr(CCIR.ReceiveTestFunction))
		ELSIF expr IS CCIR.InputFunction THEN
			GenerateInputFunction(expr(CCIR.InputFunction))
		ELSIF expr IS CCIR.InterfaceTest THEN
			GenerateInterfaceTest(expr(CCIR.InterfaceTest))
		ELSIF expr IS CCIR.TypeTest THEN
			GenerateTypeTest(expr(CCIR.TypeTest))
		ELSE HALT(111)
		END;
		EndSynchronizableSection(expr);
		CheckBreakPosition(expr.pos)
	END GenerateExpression;
	
	PROCEDURE GenerateInterfaceTest(test: CCIR.InterfaceTest);
	VAR be: CCIR.BinaryExpression; test1, test2: CCIR.InterfaceTest; 
		i: LONGINT; decl: CCIR.InterfaceDeclaration; 
	BEGIN
		IF test.interfaces.Length() > 1 THEN
			(* split *)
			decl := test.interfaces.GetInterfaceDeclaration(0);
			NEW(test1, test.pos, test.offers, test.left); test1.SetType(CCIR.booleanType);
			test1.interfaces.Add(decl);
			
			NEW(test2, test.pos, test.offers, test.left); test2.SetType(CCIR.booleanType);
			FOR i := 1 TO test.interfaces.Length()-1 DO
				decl := test.interfaces.GetInterfaceDeclaration(i);
				test2.interfaces.Add(decl)
			END;
			
			NEW(be, test.pos, CCIR.And, test1, test2); be.SetType(CCIR.booleanType);
			test1.SetOuter(be); test2.SetOuter(be); be.SetOuter(test.outer);
			GenerateExpression(be)
		ELSE
			decl := test.interfaces.GetInterfaceDeclaration(0);
			InternalInterfaceTest(test.left(CCIR.Designator), test.offers, decl)
		END
	END GenerateInterfaceTest;
	
	PROCEDURE InternalInterfaceTest(des: CCIR.Designator; offers: BOOLEAN; decl: CCIR.InterfaceDeclaration);
	VAR interfaceFixup: InterfaceSpecificationFixup; interfaceTestFixup: SystemCallFixup;
	BEGIN
		GenerateVariableDesignator(des);
		IF offers THEN CG.LoadInteger1(TrueValue) ELSE CG.LoadInteger1(FalseValue) END;
		NEW(interfaceFixup, codeFixups, decl.interface);
		CG.LoadAddress(interfaceFixup, 0);
		CG.LoadInteger4(decl.minNumber);
		CG.LoadInteger4(decl.maxNumber);
		CG.SaveTemporary(5);
		NEW(interfaceTestFixup, codeFixups, CBC.FInterfaceTest);
		CG.Call(interfaceTestFixup, 5, SimpleCallStackSize);
		CG.GetProcedureResult(1)
	END InternalInterfaceTest;
	
	PROCEDURE GenerateTypeTest(test: CCIR.TypeTest);
	BEGIN InternalTypeTest(test.left(CCIR.Designator), test.type)
	END GenerateTypeTest;
	
	PROCEDURE InternalTypeTest(des: CCIR.Designator; type: CCIR.Type);
	VAR def: CCIR.ComponentDefinition; templateFixup: ComponentTemplateFixup; i: LONGINT;
		offered, required: CCIR.InterfaceDeclarationList; at: CCIR.AnyType; decl: CCIR.InterfaceDeclaration;
		first: BOOLEAN;
	BEGIN
		IF type IS CCIR.AnyType THEN
			offered := CCIR.OfferedInterfaces(des.type);
			required := CCIR.RequiredInterfaces(des.type);
			at := type(CCIR.AnyType);
			first := TRUE;
			FOR i := 0 TO at.offeredInterfaces.Length()-1 DO
				decl := at.offeredInterfaces.GetInterfaceDeclaration(i);
				IF ~offered.Contains(decl) THEN
					InternalInterfaceTest(des, TRUE, decl); 
					IF ~first THEN CG.AndBoolean END; first := FALSE
				END
			END;
			FOR i := 0 TO required.Length()-1 DO
				decl := required.GetInterfaceDeclaration(i);
				IF ~at.requiredInterfaces.Contains(decl) THEN
					InternalInterfaceTest(des, FALSE, decl);
					CG.NotBoolean;
					IF ~first THEN CG.AndBoolean END; first := FALSE
				END
			END;
			IF first THEN CG.LoadInteger1(TrueValue) END
		ELSIF type IS CCIR.ComponentType THEN
			GenerateVariableDesignator(des);
			CG.Deref(ComponentTemplateOffset, 4);
			def := type(CCIR.ComponentType).componentDefinition; ASSERT(def # NIL);
			NEW(templateFixup, codeFixups, def);
			CG.LoadAddress(templateFixup, 0);
			CG.EqualInteger
		ELSE HALT(111)
		END
	END InternalTypeTest;
	
	PROCEDURE BeginSynchronizableSection(node: CCIR.Node);
	BEGIN
		IF node.attributeList # NIL THEN
			IF node.attributeList.Contains(CCIR.exclusive) THEN
				GenerateLock(CCIR.exclusive)
			ELSIF node.attributeList.Contains(CCIR.shared) THEN
				GenerateLock(CCIR.shared)
			END
		END
	END BeginSynchronizableSection;
	
	PROCEDURE EndSynchronizableSection(node: CCIR.Node);
	BEGIN
		IF node.attributeList # NIL THEN
			IF node.attributeList.Contains(CCIR.exclusive) THEN
				GenerateUnlock(CCIR.exclusive)
			ELSIF node.attributeList.Contains(CCIR.shared) THEN
				GenerateUnlock(CCIR.shared)
			END
		END
	END EndSynchronizableSection;
	
	PROCEDURE GenerateLock(attribute: CCIR.Identifier);
	VAR lockFixup: SystemCallFixup;
	BEGIN
		CG.ProcessPointer;
		IF attribute = CCIR.exclusive THEN CG.LoadInteger1(TrueValue) ELSE CG.LoadInteger1(FalseValue) END;
		CG.SaveTemporary(2);
		NEW(lockFixup, codeFixups, CBC.FLock);
		CG.Call(lockFixup, 2, SimpleCallStackSize)
	END GenerateLock;
	
	PROCEDURE GenerateUnlock(attribute: CCIR.Identifier);
	VAR unlockFixup: SystemCallFixup;
	BEGIN
		CG.ProcessPointer;
		IF attribute = CCIR.exclusive THEN CG.LoadInteger1(TrueValue) ELSE CG.LoadInteger1(FalseValue) END;
		CG.SaveTemporary(2);
		NEW(unlockFixup, codeFixups, CBC.FUnlock);
		CG.Call(unlockFixup, 2, SimpleCallStackSize)
	END GenerateUnlock;
			
	PROCEDURE GenerateFunctionCall(call: CCIR.FunctionCall);
	VAR decl: CCIR.Procedure; arg0: CCIR.Expression;
	BEGIN
		decl := call.declaration;
		IF CCIR.predefinedProcedures.Contains(decl) THEN
			IF decl = CCIR.exists THEN
				ASSERT(call.arguments.Length() = 1);
				arg0 := call.arguments.GetExpression(0);
				GenerateExists(arg0(CCIR.Designator))
			ELSIF decl = CCIR.count THEN
				ASSERT(call.arguments.Length() = 1);
				arg0 := call.arguments.GetExpression(0);
				GenerateCountConnections(arg0(CCIR.ExternalInterfaceDesignator))
			ELSIF decl = CCIR.length THEN
				ASSERT(call.arguments.Length() >= 1);
				arg0 := call.arguments.GetExpression(0);
				IF (arg0 IS CCIR.IdentifierDesignator) & CCIR.IsArrayCollection(arg0(CCIR.Designator).node(CCIR.Variable)) THEN
					GenerateArrayLength(call)
				ELSE
					ASSERT(call.arguments.Length() = 1);
					GenerateTextLength(arg0)
				END
			ELSIF (decl = CCIR.realToInteger) OR (decl = CCIR.integerToReal) OR 
					(decl = CCIR.integerToCharacter) OR (decl = CCIR.characterToInteger) OR
					(decl = CCIR.characterToText) THEN
				ASSERT(call.arguments.Length() = 1);
				arg0 := call.arguments.GetExpression(0);
				GenerateConvert(decl, arg0)
			ELSIF (decl = CCIR.minInteger) OR (decl = CCIR.maxInteger) OR 
					(decl = CCIR.minReal) OR (decl = CCIR.maxReal) THEN
				GenerateMinMax(decl)
			ELSIF decl = CCIR.terminated THEN
				GenerateTerminated
			ELSIF decl = CCIR.random THEN
				GenerateRandom(call.arguments)
			ELSIF (decl = CCIR.sine) OR (decl = CCIR.cosine) OR (decl = CCIR.tangent) OR
					(decl = CCIR.arcSine) OR (decl = CCIR.arcCosine) OR (decl = CCIR.arcTangent) OR
					(decl = CCIR.sqrt) THEN
				ASSERT(call.arguments.Length() = 1);
				arg0 := call.arguments.GetExpression(0);
				GenerateMath(decl, arg0)
			ELSE
				HALT(111) (* not yet implemented *)
			END
		ELSE
			GenerateGeneralProcedureCall(call, call.arguments, decl)
		END
	END GenerateFunctionCall;
	
	PROCEDURE GenerateArrayLength(call: CCIR.FunctionCall);
	VAR expr: CCIR.Expression; des: CCIR.Designator; var: CCIR.Variable; nofDims: LONGINT;
	BEGIN
		expr := call.arguments.GetExpression(0); 
		des := expr(CCIR.Designator); var := des.node(CCIR.Variable); nofDims := var.parameters.Length();
		ASSERT(nofDims > 0);
		ASSERT((des IS CCIR.IdentifierDesignator) & CCIR.IsArrayCollection(var));
		IF call.arguments.Length() = 1 THEN
			expr := NIL
		ELSE
			ASSERT(call.arguments.Length() = 2);
			expr := call.arguments.GetExpression(1);
		END;
		IF expr = NIL THEN
			CG.LoadInteger4(0)
		ELSE
			GenerateExpression(expr);
			
			CG.Duplicate;
			CG.LoadInteger4(0);
			CheckBoundary(CCIR.GreaterEqual);
			
			CG.Duplicate;
			CG.LoadInteger4(nofDims);
			CheckBoundary(CCIR.Less)
		END;
		CG.LoadInteger4(4);
		CG.MultiplyInteger;
		CG.LoadInteger4(ArrayHeaderSize);
		CG.AddInteger;
		GenerateVariable(CCIR.GetCurrentScope(call), var); CG.Load;
		CG.AddInteger;
		CG.MakeDeref(4)
	END GenerateArrayLength;
	
	PROCEDURE CheckBoundary(comparison: CCIR.Operator);
	VAR endFixup: CodeFixup;
	BEGIN
		NEW(endFixup, codeFixups);
		IF comparison = CCIR.Less THEN CG.LessInteger
		ELSIF comparison = CCIR.LessEqual THEN CG.LessEqualInteger
		ELSIF comparison = CCIR.Greater THEN CG.GreaterInteger
		ELSIF comparison = CCIR.GreaterEqual THEN CG.GreaterEqualInteger
		ELSE HALT(111)
		END;
		CG.ConditionalBranch(TRUE, endFixup);
		CG.SaveTemporary(0);
		CG.LoadInteger4(7); (* index out of range *)
		CG.Interrupt(3, 1);
		BranchEntry(endFixup)
	END CheckBoundary;
	
	PROCEDURE GenerateMath(decl: CCIR.Procedure; expr: CCIR.Expression);
	VAR sysCallFixup: SystemCallFixup;
	BEGIN
		GenerateExpression(expr);
		IF decl = CCIR.sine THEN CG.Sine
		ELSIF decl = CCIR.cosine THEN CG.Cosine
		ELSIF decl = CCIR.tangent THEN CG.Tangent
		ELSIF decl = CCIR.arcTangent THEN CG.ArcTangent
		ELSIF decl = CCIR.sqrt THEN CG.SquareRoot
		ELSE
			CG.SaveTemporary(1);
			IF decl = CCIR.arcSine THEN
				NEW(sysCallFixup, codeFixups, CBC.FArcSine)
			ELSIF decl = CCIR.arcCosine THEN
				NEW(sysCallFixup, codeFixups, CBC.FArcCosine)
			ELSE HALT(111)
			END;
			CG.Call(sysCallFixup, 1, SimpleCallStackSize);
			CG.GetProcedureResult(4)
		END
	END GenerateMath;
	
	PROCEDURE GenerateRandom(args: CCIR.ExpressionList);
	VAR low, high: CCIR.Expression; randomFixup: SystemCallFixup;
	BEGIN
		ASSERT(args.Length() = 2);
		low := args.GetExpression(0);
		high := args.GetExpression(1);
		GenerateExpression(low);
		GenerateExpression(high);
		CG.SaveTemporary(2);
		NEW(randomFixup, codeFixups, CBC.FRandom);
		CG.Call(randomFixup, 2, SimpleCallStackSize);
		CG.GetProcedureResult(4)
	END GenerateRandom;
	
	PROCEDURE GenerateTerminated;
	BEGIN
		(* component.terminated & (component.nofProcesses <= 2) *) (* count also finalizer process *)
		CG.ComponentVariable(ComponentLocalProcCounterOffset, 4);
		CG.LoadInteger4(2);
		CG.LessEqualInteger;
		
		CG.ComponentVariable(ComponentTerminatedOffset, 1);
		CG.AndBoolean
	END GenerateTerminated;
	
	PROCEDURE GenerateMinMax(decl: CCIR.Procedure);
	VAR x: LONGINT;
	BEGIN
		IF decl = CCIR.minInteger THEN x := MIN(LONGINT)
		ELSIF decl = CCIR.maxInteger THEN x := MAX(LONGINT)
		ELSIF decl = CCIR.minReal THEN x := CCBasic.EncodeReal(MIN(REAL))
		ELSIF decl = CCIR.maxReal THEN x := CCBasic.EncodeReal(MAX(REAL))
		ELSE HALT(111)
		END;
		CG.LoadInteger4(x)
	END GenerateMinMax;
	
	PROCEDURE GenerateConvert(decl: CCIR.Procedure; expr: CCIR.Expression);
	VAR convertFixup: SystemCallFixup;
	BEGIN	
		GenerateExpression(expr);
		IF decl = CCIR.realToInteger THEN CG.ConvertRealToInteger
		ELSIF decl = CCIR.integerToReal THEN CG.ConvertIntegerToReal
		ELSIF decl = CCIR.integerToCharacter THEN CG.Convert(1)
		ELSIF decl = CCIR.characterToInteger THEN CG.Convert(4)
		ELSIF decl = CCIR.characterToText THEN
			CG.SaveTemporary(1);
			NEW(convertFixup, codeFixups, CBC.FCharacterToText);
			CG.Call(convertFixup, 1, SimpleCallStackSize);
			CG.GetProcedureResult(4)
		ELSE HALT(111)
		END
	END GenerateConvert;
	
	PROCEDURE GenerateTextLength(expr: CCIR.Expression);
	VAR lengthFixup: SystemCallFixup;
	BEGIN
		GenerateExpression(expr);
		CG.SaveTemporary(1);
		NEW(lengthFixup, codeFixups, CBC.FTextLength);
		CG.Call(lengthFixup, 1, SimpleCallStackSize);
		CG.GetProcedureResult(4)
	END GenerateTextLength;
	
	PROCEDURE GenerateExists(des: CCIR.Designator);
	VAR var: CCIR.Variable;
	BEGIN
		var := des.node(CCIR.Variable);
		IF var.parameters.Length() = 0 THEN
			GenerateVariableDesignator(des); CG.Load;
			CG.LoadInteger4(NilValue);
			CG.UnequalInteger
		ELSE
			GenerateExistsElement(des)
		END
	END GenerateExists;
	
	PROCEDURE GenerateExistsElement(des: CCIR.Designator);
	VAR var: CCIR.Variable; args: CCIR.ExpressionList; nofKeys: LONGINT; existsElemFixup: SystemCallFixup;
	BEGIN
		var := des.node(CCIR.Variable); ASSERT(var.parameters.Length() > 0);
		args := des(CCIR.IndexDesignator).arguments; nofKeys := args.Length();
		IF CCIR.IsArrayCollection(var) THEN
			GenerateArrayAccess(CCIR.GetCurrentScope(des), var, args);
			CG.LoadInteger4(NilValue);
			CG.UnequalInteger
		ELSE
			GenerateCollectionKeyList(args);
			GenerateVariable(CCIR.GetCurrentScope(des), var); CG.Load;
			CG.LoadInteger4(nofKeys);
			CG.SaveTemporary(2 + nofKeys);
			NEW(existsElemFixup, codeFixups, CBC.FExistsElement);
			CG.CallWithAdditionalParameters(existsElemFixup, 2, nofKeys, CollectionCallStackSize);
			CG.GetProcedureResult(1)
		END
	END GenerateExistsElement;
	
	PROCEDURE GenerateCountConnections(des: CCIR.ExternalInterfaceDesignator);
	VAR countFixup: SystemCallFixup;
	BEGIN
		IF (des.declaration.minNumber = 1) & (des.declaration.maxNumber = 1) THEN
			CG.LoadInteger4(1)
		ELSE
			ASSERT(des.index = NIL);
			SelectInterface(des);
			CG.SaveTemporary(1);
			NEW(countFixup, codeFixups, CBC.FCountConnections);
			CG.Call(countFixup, 1, SimpleCallStackSize);
			CG.GetProcedureResult(4)
		END
	END GenerateCountConnections;
	
	PROCEDURE GenerateVariableDesignator(des: CCIR.Designator);
	VAR var: CCIR.Variable; args: CCIR.ExpressionList; nofKeys: LONGINT; 
		selectElemFixup, selectTextCharFixup: SystemCallFixup; arg0: CCIR.Expression;
	BEGIN
		IF des IS CCIR.IndexDesignator THEN
			var := des.node(CCIR.Variable); 
			args := des(CCIR.IndexDesignator).arguments; nofKeys := args.Length();
			IF var.parameters.Length() = 0 THEN
				IF (des.type = CCIR.characterType) & (des.node(CCIR.Variable).type = CCIR.textType) THEN
					ASSERT(nofKeys = 1);
					arg0 := args.GetExpression(0);
					GenerateVariableDesignator(des(CCIR.IndexDesignator).left);
					GenerateExpression(arg0);
					CG.SaveTemporary(2);
					NEW(selectTextCharFixup, codeFixups, CBC.FSelectTextCharacter);
					CG.Call(selectTextCharFixup, 2, SimpleCallStackSize);
					CG.GetProcedureResult(4);
					CG.MakeDeref(1)
				ELSE HALT(111)
				END
			ELSIF CCIR.IsArrayCollection(var) THEN
				GenerateArrayAccess(CCIR.GetCurrentScope(des), var, args)
			ELSE
				GenerateCollectionKeyList(args);
				GenerateVariable(CCIR.GetCurrentScope(des), var); CG.Load;
				CG.LoadInteger4(nofKeys);
				CG.SaveTemporary(2 + nofKeys);
				NEW(selectElemFixup, codeFixups, CBC.FSelectElement);
				CG.CallWithAdditionalParameters(selectElemFixup, 2, nofKeys, CollectionCallStackSize);
				CG.GetProcedureResult(4);
				CG.MakeDeref(TypeSize(var.type))
			END
		ELSIF des IS CCIR.GuardDesignator THEN
			GenerateTypeGuard(des(CCIR.GuardDesignator))
		ELSIF des IS CCIR.IdentifierDesignator THEN
			var := des.node(CCIR.Variable);
			ASSERT(~CCIR.predefinedVariables.Contains(var));
			GenerateVariable(CCIR.GetCurrentScope(des), var)
		ELSE HALT(111)
		END
	END GenerateVariableDesignator;
	
	PROCEDURE GenerateArrayAccess(currentScope: CCIR.Node; var: CCIR.Variable; args: CCIR.ExpressionList);
	VAR i, nofDims: LONGINT; expr: CCIR.Expression; varAlloc: VariableAllocation;
	BEGIN
		(* access a[i, j, k] to a: ARRAY L, M, N OF T
			refers to ADR(a) + ArrayHeader + 4*nofDims + ((i * M + j) * N + k) * elemSize
		  *)
		varAlloc := GetVariableAllocation(var); ASSERT(varAlloc # NIL); ASSERT(varAlloc.elemSize > 0);
		nofDims := args.Length();
		FOR i := 0 TO nofDims-1 DO
			expr := args.GetExpression(i);
			GenerateExpression(expr);
			CG.Duplicate;
			CG.LoadInteger4(0); 
			CheckBoundary(CCIR.GreaterEqual);
			CG.Duplicate;
			GenerateArrayDimension(currentScope, var, i);
			CheckBoundary(CCIR.Less);
			IF i > 0 THEN
				CG.AddInteger
			END;
			IF i < args.Length()-1 THEN
				GenerateArrayDimension(currentScope, var, i+1);
				CG.MultiplyInteger
			END
		END;
		CG.LoadInteger4(varAlloc.elemSize);
		CG.MultiplyInteger;
		GenerateVariable(currentScope, var); CG.Load;
		CG.AddInteger;
		CG.LoadInteger4(ArrayHeaderSize + nofDims * 4);
		CG.AddInteger;
		CG.MakeDeref(TypeSize(var.type))
	END GenerateArrayAccess;
	
	PROCEDURE GenerateArrayDimension(currentScope: CCIR.Node; var: CCIR.Variable; dim: LONGINT);
	BEGIN
		ASSERT((dim >= 0) & (dim < var.parameters.Length()));
		GenerateVariable(currentScope, var); CG.Load;
		CG.LoadInteger4(ArrayHeaderSize + dim * 4);
		CG.AddInteger;
		CG.MakeDeref(4)
	END GenerateArrayDimension;
	
	PROCEDURE GenerateTimeVariable;
	VAR timeFixup: SystemCallFixup;
	BEGIN 
		CG.ComponentPointer;
		CG.SaveTemporary(1);
		NEW(timeFixup, codeFixups, CBC.FVirtualTime);
		CG.Call(timeFixup, 1, SimpleCallStackSize);
		CG.GetProcedureResult(4)
	END GenerateTimeVariable;
	
	PROCEDURE GenerateTypeGuard(guard: CCIR.GuardDesignator);
	VAR des: CCIR.Designator; endFixup: CodeFixup;
	BEGIN
		des := guard.left(CCIR.Designator);
		InternalTypeTest(des, guard.type);
		NEW(endFixup, codeFixups);
		CG.SaveTemporary(1);
		CG.ConditionalBranch(TRUE, endFixup);
		CG.LoadInteger4(6); (* type guard failed *)
		CG.SaveTemporary(1);
		CG.Interrupt(3, 1);
		BranchEntry(endFixup);
		GenerateVariableDesignator(des)
	END GenerateTypeGuard;
	
	PROCEDURE GenerateVariable(currentScope: CCIR.Node; var: CCIR.Variable);
	VAR varAlloc: VariableAllocation; procAlloc: ProcedureAllocation; parAlloc: ProcedureParamAllocation; 
		par: CCIR.ProcedureParameter; scopeIndex: LONGINT; implAlloc: ImplementationAllocation; loadSize: LONGINT;
	BEGIN
		ASSERT(currentScope # NIL);
		loadSize := TypeSize(var.type); 
		IF var.parameters.Length() > 0 THEN loadSize := 4 END;
		IF (var = procedureResultVariable) OR (var = stackExtensionVariable) THEN
			procAlloc := procedureAllocations.FindProcedureAllocation(currentScope(CCIR.Procedure)); ASSERT(procAlloc # NIL);
			varAlloc := procAlloc.variables.FindVariableAllocation(var); ASSERT(varAlloc # NIL);
			CG.LocalVariable(0, varAlloc.offset, varAlloc.varSize, loadSize)
		ELSE
			scopeIndex := VariableScopeDifference(currentScope, var.scope);
			IF var IS CCIR.ProcedureParameter THEN
				par := var(CCIR.ProcedureParameter);
				procAlloc := procedureAllocations.FindProcedureAllocation(var.scope(CCIR.Procedure)); ASSERT(procAlloc # NIL);
				parAlloc := procAlloc.parameters.FindProcedureParamAlloc(par); ASSERT(parAlloc # NIL);
				CG.ProcedureParameter(scopeIndex, par.variable, procAlloc.parameters.Offset(par), loadSize)
			ELSE
				IF var.scope IS CCIR.Component THEN
					varAlloc := componentVariables.FindVariableAllocation(var); ASSERT(varAlloc # NIL);
					CG.ComponentVariable(componentVariables.offset + varAlloc.offset, loadSize)
				ELSE
					IF var.scope IS CCIR.Implementation THEN
						implAlloc := implementationAllocations.FindImplementationAllocation(var.scope(CCIR.Implementation));
						ASSERT(implAlloc # NIL);
						varAlloc := implAlloc.variables.FindVariableAllocation(var); ASSERT(varAlloc # NIL)
					ELSIF var.scope IS CCIR.Procedure THEN
						procAlloc := procedureAllocations.FindProcedureAllocation(var.scope(CCIR.Procedure)); ASSERT(procAlloc # NIL);
						varAlloc := procAlloc.variables.FindVariableAllocation(var); ASSERT(varAlloc # NIL)
					ELSE HALT(111)
					END;
					CG.LocalVariable(scopeIndex, varAlloc.offset, varAlloc.varSize, loadSize)
				END
			END
		END
	END GenerateVariable;
	
	PROCEDURE VariableScopeDifference(current, varScope: CCIR.Node): LONGINT;
	VAR diff: LONGINT;
	BEGIN
		diff := 0;
		WHILE current # varScope DO
			ASSERT(current # NIL);
			IF current IS CCIR.Procedure THEN current := current(CCIR.Procedure).outer
			ELSIF current IS CCIR.Implementation THEN current := current(CCIR.Implementation).outer
			ELSE HALT(111) (* must not go out of component *)
			END;
			INC(diff)
		END;
		RETURN diff
	END VariableScopeDifference;
	
	PROCEDURE GetVariableAllocation(var: CCIR.Variable): VariableAllocation;
	VAR procAlloc: ProcedureAllocation; implAlloc: ImplementationAllocation; varAlloc: VariableAllocation;
	BEGIN
		ASSERT(~(var IS CCIR.ProcedureParameter));
		IF var.scope IS CCIR.Procedure THEN
			procAlloc := procedureAllocations.FindProcedureAllocation(var.scope(CCIR.Procedure)); ASSERT(procAlloc # NIL);
			varAlloc := procAlloc.variables.FindVariableAllocation(var)
		ELSIF var.scope IS CCIR.Implementation THEN
			implAlloc := implementationAllocations.FindImplementationAllocation(var.scope(CCIR.Implementation)); 
			ASSERT(implAlloc # NIL);
			varAlloc := implAlloc.variables.FindVariableAllocation(var)
		ELSIF var.scope IS CCIR.Component THEN
			varAlloc := componentVariables.FindVariableAllocation(var)
		ELSE HALT(111)
		END;
		RETURN varAlloc
	END GetVariableAllocation;
							
	PROCEDURE GenerateCharacterValue(cv: CCIR.CharacterValue);
	BEGIN CG.LoadInteger1(SHORT(ORD(cv.char)))
	END GenerateCharacterValue;
	
	PROCEDURE GenerateBooleanValue(bv: CCIR.BooleanValue);
	BEGIN IF bv.bool THEN CG.LoadInteger1(TrueValue) ELSE CG.LoadInteger1(FalseValue) END
	END GenerateBooleanValue;
	
	PROCEDURE GenerateIntegerValue(iv: CCIR.IntegerValue);
	BEGIN CG.LoadInteger4(iv.int)
	END GenerateIntegerValue;
	
	PROCEDURE GenerateRealValue(rv: CCIR.RealValue);
	BEGIN CG.LoadInteger4(CCBasic.EncodeReal(rv.real))
	END GenerateRealValue;
	
	PROCEDURE GenerateTextValue(tv: CCIR.TextValue);
	VAR constPos, i: LONGINT; constFixup: ConstFixup; createTextFixup: SystemCallFixup;
	BEGIN
		IF (LEN(tv.text) = 0) OR (tv.text[0] = 0X) THEN
			CG.LoadInteger4(NilValue)
		ELSE
			NEW(constFixup, codeFixups); constFixup.constPos := constants.Length();
			i := 0; WHILE (i < LEN(tv.text)) & (tv.text[i] # 0X) DO constants.Char(tv.text[i]); INC(i) END;
			constants.Char(0X); 
			CG.LoadAddress(constFixup, 0);
			CG.SaveTemporary(1);
			NEW(createTextFixup, codeFixups, CBC.FCreateText);
			CG.Call(createTextFixup, 1, SimpleCallStackSize);
			CG.GetProcedureResult(4)
		END
	END GenerateTextValue;
	
	PROCEDURE GenerateUnaryExpression(expr: CCIR.UnaryExpression);
	BEGIN
		GenerateExpression(expr.sub);
		IF expr.sub.type = CCIR.integerType THEN
			IF expr.operator = CCIR.Plus THEN (* do nothing *)
			ELSIF expr.operator = CCIR.Minus THEN
				CG.NegateInteger
			ELSE HALT(111)
			END
		ELSIF expr.sub.type = CCIR.realType THEN
			IF expr.operator = CCIR.Plus THEN (* do nothing *)
			ELSIF expr.operator = CCIR.Minus THEN
				CG.NegateReal
			ELSE HALT(111)
			END
		ELSIF expr.sub.type = CCIR.booleanType THEN
			IF expr.operator = CCIR.Not THEN
				CG.NotBoolean
			ELSE HALT(111)
			END
		ELSE HALT(111)
		END
	END GenerateUnaryExpression;
	
	PROCEDURE GenerateBinaryExpression(expr: CCIR.BinaryExpression);
	VAR condition: BOOLEAN; nextFixup, endFixup: CodeFixup;
	BEGIN
		IF (expr.operator = CCIR.Equal) OR (expr.operator = CCIR.Unequal) OR 
				(expr.operator = CCIR.Less) OR (expr.operator = CCIR.LessEqual) OR
				(expr.operator = CCIR.Greater) OR (expr.operator = CCIR.GreaterEqual) THEN
			GenerateExpression(expr.left);
			MakeCopy(expr.left); (* for text *)
			GenerateExpression(expr.right);
			MakeCopy(expr.right); (* for text *)
			IF ((expr.left.type = CCIR.integerType) & (expr.right.type = CCIR.integerType)) OR 
				((expr.left.type = CCIR.characterType) & (expr.right.type = CCIR.characterType)) THEN
				IF expr.operator = CCIR.Equal THEN
					CG.EqualInteger
				ELSIF expr.operator = CCIR.Unequal THEN
					CG.UnequalInteger
				ELSIF expr.operator = CCIR.Less THEN
					CG.LessInteger
				ELSIF expr.operator = CCIR.LessEqual THEN
					CG.LessEqualInteger
				ELSIF expr.operator = CCIR.Greater THEN
					CG.GreaterInteger
				ELSIF expr.operator = CCIR.GreaterEqual THEN
					CG.GreaterEqualInteger
				ELSE HALT(111)
				END
			ELSIF (expr.left.type = CCIR.realType) & (expr.right.type = CCIR.realType) THEN
				IF expr.operator = CCIR.Equal THEN
					CG.EqualReal
				ELSIF expr.operator = CCIR.Unequal THEN
					CG.UnequalReal
				ELSIF expr.operator = CCIR.Less THEN
					CG.LessReal
				ELSIF expr.operator = CCIR.LessEqual THEN
					CG.LessEqualReal
				ELSIF expr.operator = CCIR.Greater THEN
					CG.GreaterReal
				ELSIF expr.operator = CCIR.GreaterEqual THEN
					CG.GreaterEqualReal
				ELSE HALT(111)
				END
			ELSIF (expr.left.type = CCIR.booleanType) & (expr.right.type = CCIR.booleanType) THEN
				IF expr.operator = CCIR.Equal THEN
					CG.EqualInteger
				ELSIF expr.operator = CCIR.Unequal THEN
					CG.UnequalInteger
				ELSE HALT(111)
				END
			ELSIF (expr.left.type = CCIR.textType) & (expr.right.type = CCIR.textType) THEN
				IF expr.operator = CCIR.Equal THEN
					GenerateEqualText
				ELSIF expr.operator = CCIR.Unequal THEN
					GenerateEqualText;
					CG.NotBoolean
				ELSIF expr.operator = CCIR.Less THEN
					GenerateLessText
				ELSIF expr.operator = CCIR.LessEqual THEN
					GenerateLessEqualText
				ELSIF expr.operator = CCIR.Greater THEN
					GenerateLessEqualText;
					CG.NotBoolean
				ELSIF expr.operator = CCIR.GreaterEqual THEN
					GenerateLessText;
					CG.NotBoolean
				ELSE HALT(111)
				END
			ELSE HALT(111)
			END
		ELSIF (expr.left.type = CCIR.integerType) & (expr.right.type = CCIR.integerType) THEN
			GenerateExpression(expr.left);
			GenerateExpression(expr.right);
			IF expr.operator = CCIR.Plus THEN
				CG.AddInteger
			ELSIF expr.operator = CCIR.Minus THEN
				CG.SubtractInteger
			ELSIF expr.operator = CCIR.Times THEN
				CG.MultiplyInteger
			ELSIF expr.operator = CCIR.IntegerDivision THEN
				CG.DivideInteger
			ELSIF expr.operator = CCIR.Modulo THEN
				CG.ModuloInteger
			ELSE HALT(111)
			END
		ELSIF (expr.left.type = CCIR.realType) & (expr.right.type = CCIR.realType) THEN
			GenerateExpression(expr.left);
			GenerateExpression(expr.right);
			IF expr.operator = CCIR.Plus THEN
				CG.AddReal
			ELSIF expr.operator = CCIR.Minus THEN
				CG.SubtractReal
			ELSIF expr.operator = CCIR.Times THEN
				CG.MultiplyReal
			ELSIF expr.operator = CCIR.RealDivision THEN
				CG.DivideReal
			ELSE HALT(111)
			END
		ELSIF (expr.left.type = CCIR.booleanType) & (expr.right.type = CCIR.booleanType) THEN
			IF (expr.operator = CCIR.And) OR (expr.operator = CCIR.Or) THEN
				(* conditional evaluation *)
				GenerateExpression(expr.left);
				NEW(nextFixup, codeFixups); NEW(endFixup, codeFixups);
				IF expr.operator = CCIR.And THEN condition := FALSE
				ELSIF expr.operator = CCIR.Or THEN condition := TRUE
				ELSE HALT(111)
				END;
				CG.ConditionalBranch(condition, nextFixup);	
				GenerateExpression(expr.right);
				CG.Branch(endFixup);
				BranchEntry(nextFixup);
				IF expr.operator = CCIR.And THEN CG.LoadInteger1(FalseValue)
				ELSIF expr.operator = CCIR.Or THEN CG.LoadInteger1(TrueValue)
				ELSE HALT(111)
				END;
				BranchEntry(endFixup)
			ELSE HALT(111)
			END
		ELSE HALT(111)
		END
	END GenerateBinaryExpression;
	
	PROCEDURE GenerateEqualText;
	VAR sysCallFixup: SystemCallFixup;
	BEGIN
		NEW(sysCallFixup, codeFixups, CBC.FEqualText);
		CG.SaveTemporary(2);
		CG.Call(sysCallFixup, 2, SimpleCallStackSize);
		CG.GetProcedureResult(1)
	END GenerateEqualText;
	
	PROCEDURE GenerateLessText;
	VAR sysCallFixup: SystemCallFixup;
	BEGIN
		NEW(sysCallFixup, codeFixups, CBC.FLessText);
		CG.SaveTemporary(2);
		CG.Call(sysCallFixup, 2, SimpleCallStackSize);
		CG.GetProcedureResult(1)
	END GenerateLessText;

	PROCEDURE GenerateLessEqualText;
	VAR sysCallFixup: SystemCallFixup;
	BEGIN
		NEW(sysCallFixup, codeFixups, CBC.FLessEqualText);
		CG.SaveTemporary(2);
		CG.Call(sysCallFixup, 2, SimpleCallStackSize);
		CG.GetProcedureResult(1)
	END GenerateLessEqualText;
		
	PROCEDURE GenerateTail;
	VAR typeList: FixupTypeList; absConstFixups, absCodeFixups: LONGINT;
	BEGIN
		NEW(typeList); absConstFixups := 0; absCodeFixups := 0;
		CollectFixups(headerFixups, typeList, absConstFixups, absCodeFixups);
		CollectFixups(codeFixups, typeList, absConstFixups, absCodeFixups);
		GenerateLocalConstFixups(absConstFixups);
		GenerateLocalCodeFixups(absCodeFixups);
		GenerateSystemCallFixups(typeList);
		GenerateTemplateFixups(typeList);
		GenerateInterfaceFixups(typeList);
		(* compile-time fixups *)
		ResolveLocalFixups(headerFixups);
		ResolveLocalFixups(codeFixups)
	END GenerateTail;
	
	PROCEDURE GenerateLocalConstFixups(length: LONGINT);
	BEGIN
		tail.Integer4(length);
		EmitLocalConstFixups(codeFixups, length);
		ASSERT(length = 0)
	END GenerateLocalConstFixups;
	
	PROCEDURE GenerateLocalCodeFixups(length: LONGINT);
	VAR i: LONGINT;
	BEGIN
		tail.Integer4(length);
		EmitLocalCodeFixups(headerFixups, length);
		EmitLocalCodeFixups(codeFixups, length);
		ASSERT(length = 0)
	END GenerateLocalCodeFixups;
		
	PROCEDURE EmitLocalConstFixups(list: CG.FixupList; VAR length: LONGINT);
	VAR i: LONGINT; fixup: CG.Fixup;
	BEGIN
		FOR i := 0 TO list.Length()-1 DO
			fixup := list.GetFixup(i);
			IF fixup.reference IS ConstFixup THEN
				ASSERT(~fixup.relative);
				DEC(length);
				tail.Integer4(fixup.codePos)
			END
		END
	END EmitLocalConstFixups;
		
	PROCEDURE EmitLocalCodeFixups(list: CG.FixupList; VAR length: LONGINT);
	VAR i: LONGINT; fixup: CG.Fixup;
	BEGIN
		FOR i := 0 TO list.Length()-1 DO
			fixup := list.GetFixup(i);
			IF ((fixup.reference IS CodeFixup) OR (fixup.reference IS ImplementationFixup)) & ~fixup.relative THEN
				DEC(length);
				tail.Integer4(fixup.codePos)
			END
		END
	END EmitLocalCodeFixups;
		
	PROCEDURE GenerateSystemCallFixups(typeList: FixupTypeList);
	VAR i: LONGINT; type: FixupType; sysCallType: SystemCallFixupType; nofLists, count: LONGINT;
	BEGIN
		nofLists := typeList.NofSystemCallFixupTypes();
		tail.Integer4(nofLists);
		FOR i := 0 TO typeList.Length()-1 DO
			type := typeList.GetFixupType(i);
			IF type IS SystemCallFixupType THEN
				sysCallType := type(SystemCallFixupType);
				tail.Char(sysCallType.callCode);
				IF sysCallType.relative THEN tail.Char(CBC.FRelative) ELSE tail.Char(CBC.FAbsolute) END;
				count := sysCallType.count;
				tail.Integer4(count);
				EmitSystemCallFixups(codeFixups, sysCallType.callCode, sysCallType.relative, count);
				ASSERT(count = 0);
				DEC(nofLists)
			END
		END;
		ASSERT(nofLists = 0)
	END GenerateSystemCallFixups;
	
	PROCEDURE EmitSystemCallFixups(list: CG.FixupList; callCode: CHAR; relative: BOOLEAN; VAR count: LONGINT);
	VAR i: LONGINT; fixup: CG.Fixup;
	BEGIN
		FOR i := 0 TO list.Length()-1 DO
			fixup := list.GetFixup(i);
			IF (fixup.reference IS SystemCallFixup) & (fixup.reference(SystemCallFixup).callCode = callCode) & 
					(fixup.relative = relative) THEN
				DEC(count);
				tail.Integer4(fixup.codePos)
			END
		END
	END EmitSystemCallFixups;
	
	PROCEDURE GenerateTemplateFixups(typeList: FixupTypeList);
	VAR i: LONGINT; type: FixupType; templateType: ComponentTemplateFixupType; nofLists, count: LONGINT;
	BEGIN
		nofLists := typeList.NofComponentTemplateFixupTypes();
		tail.Integer4(nofLists);
		FOR i := 0 TO typeList.Length()-1 DO
			type := typeList.GetFixupType(i);
			IF type IS ComponentTemplateFixupType THEN
				templateType := type(ComponentTemplateFixupType);
				GenerateComponentName(tail, templateType.com);
				count := templateType.count;
				tail.Integer4(count);
				EmitComponentTemplateFixups(codeFixups, templateType.com, count);
				ASSERT(count = 0);
				DEC(nofLists)
			END
		END;
		ASSERT(nofLists = 0)
	END GenerateTemplateFixups;
	
	PROCEDURE EmitComponentTemplateFixups(list: CG.FixupList; def: CCIR.ComponentDefinition; VAR count: LONGINT);
	VAR i: LONGINT; fixup: CG.Fixup;
	BEGIN
		FOR i := 0 TO list.Length()-1 DO
			fixup := list.GetFixup(i);
			IF (fixup.reference IS ComponentTemplateFixup) & (fixup.reference(ComponentTemplateFixup).com = def) THEN
				ASSERT(~fixup.relative);
				DEC(count);
				tail.Integer4(fixup.codePos)
			END
		END
	END EmitComponentTemplateFixups;
	
	PROCEDURE GenerateInterfaceFixups(typeList: FixupTypeList);
	VAR i: LONGINT; type: FixupType; interfaceType: InterfaceSpecFixupType; nofLists, count: LONGINT;
	BEGIN
		nofLists := typeList.NofInterfaceSpecFixupTypes();
		tail.Integer4(nofLists);
		FOR i := 0 TO typeList.Length()-1 DO
			type := typeList.GetFixupType(i);
			IF type IS InterfaceSpecFixupType THEN
				interfaceType := type(InterfaceSpecFixupType);
				GenerateInterfaceName(tail, interfaceType.interface);
				count := interfaceType.count;
				tail.Integer4(count);
				EmitInterfaceSpecFixups(codeFixups, interfaceType.interface, count);
				ASSERT(count = 0);
				DEC(nofLists)
			END
		END;
		ASSERT(nofLists = 0)
	END GenerateInterfaceFixups;
	
	PROCEDURE EmitInterfaceSpecFixups(list: CG.FixupList; int: CCIR.Interface; VAR count: LONGINT);
	VAR i: LONGINT; fixup: CG.Fixup;
	BEGIN
		FOR i := 0 TO list.Length()-1 DO
			fixup := list.GetFixup(i);
			IF (fixup.reference IS InterfaceSpecificationFixup) & (fixup.reference(InterfaceSpecificationFixup).interface = int) THEN
				ASSERT(~fixup.relative);
				DEC(count);
				tail.Integer4(fixup.codePos)
			END
		END
	END EmitInterfaceSpecFixups;
	
	PROCEDURE BranchEntry(codeFixup: CodeFixup);
	BEGIN 
		CG.BranchEntry(codeFixup);
		codeFixup.targetPos := CG.CodePos()
	END BranchEntry;
	
	PROCEDURE GetVariableList(scope: CCIR.Node): CCIR.VariableList;
	VAR varList: CCIR.VariableList;
	BEGIN
		IF scope IS CCIR.Component THEN
			varList := scope(CCIR.Component).variables
		ELSIF scope IS CCIR.Procedure THEN
			varList := scope(CCIR.Procedure).variables
		ELSIF scope IS CCIR.Implementation THEN
			varList := scope(CCIR.Implementation).variables
		ELSE HALT(111)
		END;
		RETURN varList
	END GetVariableList;
	
	PROCEDURE InitializeInterfaceConnections(component: CCIR.Component);
	VAR index: LONGINT; decl: CCIR.InterfaceDeclaration; createConnListFixup: SystemCallFixup;
		impl: CCIR.Implementation; implFixup: ImplementationFixup;
	BEGIN
		FOR index := 0 TO component.offeredInterfaces.Length()-1 DO
			decl := component.offeredInterfaces.GetInterfaceDeclaration(index);
			ASSERT((decl.minNumber = 1) & (decl.maxNumber = 1));
			impl := component.implementations.FindImplementation(decl.name);
			IF impl # NIL THEN (* implemented *)
				(* start address for implementation process, use component reference in connection to start process *)
				GenerateExternalInterface(component, TRUE, index);
				CG.Deref(InterfaceConnReferenceOffset, 4);
				NEW(implFixup, codeFixups, impl);
				CG.LoadAddress(implFixup, 0);
				CG.Store;

				GenerateExternalInterface(component, TRUE, index);
				CG.Deref(InterfaceConnFlagOffset, 1);
				CG.LoadInteger1(ConnectionFlagImplemented);
				CG.Store
			END;
			CG.EndInstruction
		END;
		FOR index := 0 TO component.requiredInterfaces.Length()-1 DO
			decl := component.requiredInterfaces.GetInterfaceDeclaration(index);
			IF (decl.minNumber # 1) OR (decl.maxNumber # 1) THEN (* collection *)
				GenerateExternalInterface(component, FALSE, index);
				CG.LoadInteger4(decl.minNumber);
				CG.LoadInteger4(decl.maxNumber);
				NEW(createConnListFixup, codeFixups, CBC.FCreateConnectionList);
				CG.Call(createConnListFixup, 3, SimpleCallStackSize)
			END;
			CG.EndInstruction
		END
	END InitializeInterfaceConnections;
	
	PROCEDURE DeleteInterfaceConnections(component: CCIR.Component);
	VAR index: LONGINT; decl: CCIR.InterfaceDeclaration; deleteConnListFixup: SystemCallFixup;
	BEGIN
		FOR index := 0 TO component.requiredInterfaces.Length()-1 DO
			decl := component.requiredInterfaces.GetInterfaceDeclaration(index);
			IF (decl.minNumber # 1) OR (decl.maxNumber # 1) THEN (* collection *)
				GenerateExternalInterface(component, FALSE, index);
				NEW(deleteConnListFixup, codeFixups, CBC.FDeleteConnectionList);
				CG.Call(deleteConnListFixup, 1, SimpleCallStackSize);
				CG.EndInstruction
			END
		END
	END DeleteInterfaceConnections;
				
	PROCEDURE InitializeVariables(scope: CCIR.Node);
	VAR varIndex, bufferIndex: LONGINT; varList: CCIR.VariableList; variable: CCIR.Variable;
	BEGIN
		varList := GetVariableList(scope);
		IF scope IS CCIR.Implementation THEN (* communication set for process-individual comm *)
			CG.AdrOfCommSetInImplementation;
			CG.MakeDeref(4);
			CG.LoadInteger4(NilValue);
			CG.Store
		END;
		IF scope IS CCIR.Procedure THEN
			GenerateVariable(scope, stackExtensionVariable);
			CG.LoadInteger4(NilValue);
			CG.Store
		END;
		FOR varIndex := 0 TO varList.Length()-1 DO
			variable := varList.GetVariable(varIndex);
			IF (variable.parameters.Length() > 0) OR 
					CCIR.IsComponentType(variable.type) OR (variable.type = CCIR.textType) THEN
				GenerateVariable(scope, variable);
				CG.LoadInteger4(NilValue);
				CG.Store;
				CG.EndInstruction;
				IF (variable.parameters.Length() = 0) & CCIR.IsComponentType(variable.type) THEN
					(* used communication buffers *)
					FOR bufferIndex := 0 TO variable.usedCommunications.Length()-1 DO
						GenerateVariable(scope, variable);
						CG.CommunicationBufferForVariable(bufferIndex);
						CG.LoadInteger4(NilValue);
						CG.Store;
						CG.EndInstruction
					END
				END
			END
		END;
		IF scope IS CCIR.Component THEN
			(* external required interface communication buffers *)
			FOR bufferIndex := 0 TO scope(CCIR.Component).usedCommunications.Length()-1 DO
				CG.CommunicationBufferForComponent(componentVariables.offset, bufferIndex);
				CG.LoadInteger4(NilValue);
				CG.Store;
				CG.EndInstruction
			END
		END
	END InitializeVariables;
			
	PROCEDURE DeleteAllSubComponents(scope: CCIR.Node);
	VAR index: LONGINT; varList: CCIR.VariableList; var: CCIR.Variable; closeFixup: SystemCallFixup;
	BEGIN
		varList := GetVariableList(scope);
		IF scope IS CCIR.Implementation THEN
			CG.AdrOfCommSetInImplementation;
			CG.ProcessPointer;
			NEW(closeFixup, codeFixups, CBC.FCloseAndDeleteCommSet);
			CG.Call(closeFixup, 2, SimpleCallStackSize);
			CG.EndInstruction
		END;
		(* close communications and finalize *)
		FOR index := 0 TO varList.Length()-1 DO
			var := varList.GetVariable(index);
			IF CCIR.IsComponentType(var.type) THEN
				IF var.parameters.Length() > 0 THEN
					ForAllSubComponents(scope, var, FinalizeElementDelegate)
				ELSE
					FinalizeSingle(scope, var)
				END
			END
		END;
		(* delete *)
		FOR index := 0 TO varList.Length()-1 DO
			var := varList.GetVariable(index);
			IF CCIR.IsComponentType(var.type) OR (var.type = CCIR.textType) THEN
				IF var.parameters.Length() > 0 THEN
					ForAllSubComponents(scope, var, DeleteElementDelegate)
				ELSIF CCIR.IsComponentType(var.type) OR (var.type = CCIR.textType) THEN
					DeleteSingle(scope, var)
				END
			END
		END
	END DeleteAllSubComponents;
		
	PROCEDURE FinalizeElementDelegate(scope: CCIR.Node; var: CCIR.Variable);
	BEGIN
		ASSERT(CCIR.IsComponentType(var.type));
		(* element already generated by ForAllSubComponents *)
		InternalFinalizeComponent(var)
	END FinalizeElementDelegate;
	
	PROCEDURE DeleteElementDelegate(scope: CCIR.Node; var: CCIR.Variable);
	BEGIN
		(* element already generated by ForAllSubComponents *)
		IF var.type = CCIR.textType THEN
			InternalDeleteText
		ELSIF CCIR.IsComponentType(var.type) THEN
			InternalDeleteComponent
		ELSE HALT(111)
		END
	END DeleteElementDelegate;
	
	PROCEDURE DeleteAllValueProcedureParams(proc: CCIR.Procedure);
	VAR index: LONGINT; par: CCIR.ProcedureParameter;
	BEGIN
		FOR index := 0 TO proc.parameters.Length()-1 DO
			par := proc.parameters.GetProcedureParameter(index);
			IF ~par.variable THEN
				IF CCIR.IsComponentType(par.type) THEN
					(* no communications with parameters supported *)
					FinalizeSingle(proc, par)
				END
			END
		END;
		FOR index := 0 TO proc.parameters.Length()-1 DO
			par := proc.parameters.GetProcedureParameter(index);
			IF ~par.variable THEN
				IF CCIR.IsComponentType(par.type) OR (par.type = CCIR.textType) THEN
					DeleteSingle(proc, par)
				END
			END
		END
	END DeleteAllValueProcedureParams;
	
	PROCEDURE FinalizeSingle(scope: CCIR.Node; var: CCIR.Variable);
	BEGIN
		ASSERT(var.parameters.Length() = 0);
		ASSERT(CCIR.IsComponentType(var.type));
		GenerateVariable(scope, var);
		InternalFinalizeComponent(var)
	END FinalizeSingle;
	
	PROCEDURE DeleteSingle(scope: CCIR.Node; var: CCIR.Variable);
	BEGIN
		ASSERT(var.parameters.Length() = 0);
		GenerateVariable(scope, var);
		IF var.type = CCIR.textType THEN
			InternalDeleteText
		ELSIF CCIR.IsComponentType(var.type) THEN
			InternalDeleteComponent
		ELSE HALT(111)
		END
	END DeleteSingle;
		
	PROCEDURE InternalDeleteText;
	VAR delTextFixup: SystemCallFixup;
	BEGIN
		CG.GetAddress;
		NEW(delTextFixup, codeFixups, CBC.FDeleteText);
		CG.SaveTemporary(1);
		CG.Call(delTextFixup, 1, SimpleCallStackSize)
	END InternalDeleteText;
	
	PROCEDURE CreateCollections(scope: CCIR.Node);
	VAR varList: CCIR.VariableList; index: LONGINT; var: CCIR.Variable;
	BEGIN
		varList := GetVariableList(scope);
		FOR index := 0 TO varList.Length()-1 DO
			var := varList.GetVariable(index);
			IF var.parameters.Length() > 0 THEN
				IF ~CCIR.IsArrayCollection(var) THEN
					CreateCollection(scope, var)
				END
			END
		END		
	END CreateCollections;
	
	PROCEDURE CreateCollection(scope: CCIR.Node; var: CCIR.Variable);
	VAR i, nofKeys: LONGINT; par: CCIR.Parameter; varAlloc: VariableAllocation; createCollFixup: SystemCallFixup;
	BEGIN
		ASSERT(~CCIR.IsArrayCollection(var));
		nofKeys := var.parameters.Length();
		FOR i := 0 TO nofKeys-1 DO
			par := var.parameters.GetParameter(i);
			CG.LoadInteger4(TypeCode(par.type))
		END;
		GenerateVariable(scope, var); 
		CG.GetAddress;
		CG.LoadInteger4(nofKeys);
		varAlloc := GetVariableAllocation(var); ASSERT(varAlloc # NIL);
		CG.LoadInteger4(varAlloc.elemSize);
		CG.ProcessPointer;
		NEW(createCollFixup, codeFixups, CBC.FCreateCollection);
		CG.CallWithAdditionalParameters(createCollFixup, 4, nofKeys, CollectionCallStackSize);
		CG.EndInstruction
	END CreateCollection;
	
	PROCEDURE TypeCode(type: CCIR.Type): LONGINT;
	VAR code: LONGINT;
	BEGIN
		IF type = CCIR.characterType THEN code := CharacterTypeCode
		ELSIF type = CCIR.booleanType THEN code := BooleanTypeCode
		ELSIF type = CCIR.integerType THEN code := IntegerTypeCode
		ELSIF type = CCIR.realType THEN code := RealTypeCode
		ELSIF type = CCIR.textType THEN code := TextTypeCode
		ELSE HALT(111)
		END;
		RETURN code
	END TypeCode;
	
	PROCEDURE DeleteCollections(scope: CCIR.Node);
	VAR index: LONGINT; varList: CCIR.VariableList; var: CCIR.Variable;
	BEGIN
		varList := GetVariableList(scope);
		FOR index := 0 TO varList.Length()-1 DO
			var := varList.GetVariable(index);
			IF var.parameters.Length() > 0 THEN
				IF CCIR.IsArrayCollection(var) THEN 
					DeleteArray(scope, var)
				ELSE
					DeleteCollection(scope, var)
				END
			END
		END
	END DeleteCollections;
	
	PROCEDURE DeleteCollection(scope: CCIR.Node; var: CCIR.Variable);
	VAR delCollFixup: SystemCallFixup;
	BEGIN
		ASSERT(~CCIR.IsArrayCollection(var));
		GenerateVariable(scope, var);
		CG.GetAddress;
		CG.ProcessPointer;
		NEW(delCollFixup, codeFixups, CBC.FDeleteCollection);
		CG.Call(delCollFixup, 2, CollectionCallStackSize);
		CG.EndInstruction
	END DeleteCollection;
	
	PROCEDURE DeleteArray(scope: CCIR.Node; var: CCIR.Variable);
	VAR delArrFixup: SystemCallFixup;
	BEGIN
		ASSERT(CCIR.IsArrayCollection(var));
		GenerateVariable(scope, var);
		CG.GetAddress;
		NEW(delArrFixup, codeFixups, CBC.FDeleteArray);
		CG.Call(delArrFixup, 1, SimpleCallStackSize);
		CG.EndInstruction
	END DeleteArray;
	
	PROCEDURE CreateCommunicationBufferLists(com: CCIR.Component);
	VAR index: LONGINT; decl: CCIR.InterfaceDeclaration; createFixup: SystemCallFixup;
	BEGIN
		FOR index := 0 TO com.requiredInterfaces.Length()-1 DO
			decl := com.requiredInterfaces.GetInterfaceDeclaration(index);
			IF (decl.minNumber # 1) OR (decl.maxNumber # 1) THEN
				IF com.usedCommunications.Contains(decl) THEN
					SelectCommunication0(com, com, FALSE, decl, NIL);
					CG.GetAddress;
					CG.LoadInteger4(decl.minNumber);
					CG.LoadInteger4(decl.maxNumber);
					NEW(createFixup, codeFixups, CBC.FCreateCommBufferList);
					CG.Call(createFixup, 3, SimpleCallStackSize);
					CG.EndInstruction
				END
			END
		END
	END CreateCommunicationBufferLists;
	
	PROCEDURE DeleteCommunicationBufferLists(com: CCIR.Component);
	VAR index: LONGINT; decl: CCIR.InterfaceDeclaration; deleteFixup: SystemCallFixup;
	BEGIN
		FOR index := 0 TO com.requiredInterfaces.Length()-1 DO
			decl := com.requiredInterfaces.GetInterfaceDeclaration(index);
			IF (decl.minNumber # 1) OR (decl.maxNumber # 1) THEN
				IF com.usedCommunications.Contains(decl) THEN
					SelectCommunication0(com, com, FALSE, decl, NIL);
					CG.GetAddress;
					NEW(deleteFixup, codeFixups, CBC.FDeleteCommBufferList);
					CG.Call(deleteFixup, 1, SimpleCallStackSize);
					CG.EndInstruction
				END
			END
		END
	END DeleteCommunicationBufferLists;
	
	PROCEDURE SelectCommunication(intDes: CCIR.InterfaceDesignator);
	VAR scope, target: CCIR.Node;
	BEGIN
		scope := CCIR.GetCurrentScope(intDes); ASSERT(scope # NIL);
		IF intDes IS CCIR.ExternalInterfaceDesignator THEN
			target := CCIR.GetSurroundingComponent(scope)
		ELSIF intDes IS CCIR.InternalInterfaceDesignator THEN
			target := intDes(CCIR.InternalInterfaceDesignator).variableDes
		ELSE HALT(111)
		END;
		SelectCommunication0(scope, target, intDes.isOffered, intDes.declaration, intDes.index)
	END SelectCommunication;
	
	(* target IS CCIR.Component if external component is required
		target IS CCIR.Designator if internal component is accessed
		indexExpr = NIL if no index is used *)
	PROCEDURE SelectCommunication0(scope: CCIR.Node; target: CCIR.Node; offered: BOOLEAN; 
		interfaceDecl: CCIR.InterfaceDeclaration; indexExpr: CCIR.Expression);
	VAR com: CCIR.Component; varDes: CCIR.Designator; var: CCIR.Variable; bufferIndex: LONGINT;
		selectFixup, selectFromSetFixup: SystemCallFixup;
	BEGIN
		IF target IS CCIR.Component THEN
			ASSERT(CCIR.GetSurroundingComponent(scope) = target);
			IF offered THEN (* server communication with external offered interface *)
				ASSERT(scope IS CCIR.Implementation);
				CG.ServedCommunicationBuffer
			ELSE (* client communication with external required interface *)
				com := target(CCIR.Component);
				bufferIndex := com.usedCommunications.IndexOf(interfaceDecl); ASSERT(bufferIndex >= 0);
				CG.CommunicationBufferForComponent(componentVariables.offset, bufferIndex)
			END
		ELSE (* client communication with offered interface of sub-component *)
			ASSERT(offered);
			varDes := target(CCIR.Designator); var := varDes.node(CCIR.Variable);
			bufferIndex := var.usedCommunications.IndexOf(interfaceDecl); ASSERT(bufferIndex >= 0);

			IF (var.scope IS CCIR.Component) & ~(scope IS CCIR.Component) THEN
				(* select from communication set *)
				GenerateVariableDesignator(varDes);
				CG.GetAddress;
				AddressOfCommunicationSet(scope);
				CG.LoadInteger4(bufferIndex);
				CG.SaveTemporary(3);
				NEW(selectFromSetFixup, codeFixups, CBC.FSelectFromCommSet);
				CG.Call(selectFromSetFixup, 3, SimpleCallStackSize);
				CG.GetProcedureResult(4);
				CG.MakeDeref(4)
			ELSE
				GenerateVariableDesignator(varDes);
				CG.CommunicationBufferForVariable(bufferIndex)
			END
		END;
		IF indexExpr # NIL THEN
			ASSERT((interfaceDecl.minNumber # 1) OR (interfaceDecl.maxNumber # 1));
			GenerateExpression(indexExpr);
			CG.SaveTemporary(2);
			NEW(selectFixup, codeFixups, CBC.FSelectIndexedCommunication);
			CG.Call(selectFixup, 2, SimpleCallStackSize);
			CG.GetProcedureResult(4);
			CG.MakeDeref(4)
		END
	END SelectCommunication0;
	
	PROCEDURE SelectInterface(interfaceDes: CCIR.InterfaceDesignator);
	VAR varDes: CCIR.Designator; comDef: CCIR.ComponentDefinition; index, offset: LONGINT;
		selectFixup, selectInterfaceFixup: SystemCallFixup; interfaceFixup: InterfaceSpecificationFixup;
	BEGIN
		IF interfaceDes IS CCIR.ExternalInterfaceDesignator THEN
			CG.ComponentPointer;
			comDef := CCIR.GetSurroundingComponent(interfaceDes)
		ELSIF interfaceDes IS CCIR.InternalInterfaceDesignator THEN
			varDes := interfaceDes(CCIR.InternalInterfaceDesignator).variableDes;
			GenerateVariableDesignator(varDes);
			IF varDes.type IS CCIR.ComponentType THEN
				comDef := varDes.type(CCIR.ComponentType).componentDefinition; ASSERT(comDef # NIL)
			ELSIF varDes.type IS CCIR.AnyType THEN
				comDef := NIL
			ELSE HALT(111)
			END
		ELSE HALT(111)
		END;
		IF comDef # NIL THEN
			IF interfaceDes.isOffered THEN
				index := comDef.offeredInterfaces.IndexOf(interfaceDes.declaration); ASSERT(index >= 0);
				offset := ComponentHeaderSize + index * InterfaceConnectionSize
			ELSE
				index := comDef.requiredInterfaces.IndexOf(interfaceDes.declaration); ASSERT(index >= 0);
				offset := ComponentHeaderSize + (comDef.offeredInterfaces.Length() + index) * InterfaceConnectionSize
			END;
			CG.LoadInteger4(offset);
			CG.AddInteger
		ELSE
			IF interfaceDes.isOffered THEN CG.LoadInteger1(TrueValue) ELSE CG.LoadInteger1(FalseValue) END;
			NEW(interfaceFixup, codeFixups, interfaceDes.declaration.interface);
			CG.LoadAddress(interfaceFixup, 0);
			CG.SaveTemporary(3);
			NEW(selectInterfaceFixup, codeFixups, CBC.FSelectInterface);
			CG.Call(selectInterfaceFixup, 3, SimpleCallStackSize);
			CG.GetProcedureResult(4)
		END;
		IF interfaceDes.index # NIL THEN
			GenerateExpression(interfaceDes.index);
			CG.ProcessPointer;
			CG.SaveTemporary(3);
			NEW(selectFixup, codeFixups, CBC.FSelectIndexedConnection);
			CG.Call(selectFixup, 3, SimpleCallStackSize);
			CG.GetProcedureResult(4)
		END
	END SelectInterface;
	
	PROCEDURE EndServerProcess(impl: CCIR.Implementation);
	VAR intDes: CCIR.ExternalInterfaceDesignator;
	BEGIN
		(* await finish message *)
		NEW(intDes, -1, CCIR.GetSurroundingComponent(impl), impl.interfaceDecl, TRUE);
		intDes.SetOuter(impl);
		WaitToReceive(intDes);
		InternalCheckMessage(intDes.declaration.interface, CCIR.NewIdentifier(-1, CCIR.FinishMessage))
	END EndServerProcess;
			
	PROCEDURE MessageParameterSize(list: CCIR.ParameterList): LONGINT;
	VAR size, i: LONGINT; par: CCIR.Parameter;
	BEGIN
		size := 0;
		FOR i := 0 TO list.Length()-1 DO
			par := list.GetParameter(i);
			ASSERT(TypeSize(par.type) <= 4);
			INC(size, 4)
		END;
		RETURN size
	END MessageParameterSize;
		
	PROCEDURE SetLifeState(state: SHORTINT);
	VAR signalFixup: SystemCallFixup;
	BEGIN 
		CG.ComponentVariable(ComponentLifeStateOffset, 1);
		CG.LoadInteger1(state);
		CG.Store;
		
		CG.ComponentPointer;
		NEW(signalFixup, codeFixups, CBC.FSignalExternal);
		CG.Call(signalFixup, 1, SimpleCallStackSize);
		CG.EndInstruction
	END SetLifeState;

	PROCEDURE AwaitInitializationEnd;
	VAR awaitFixup: SystemCallFixup;
	BEGIN
		CG.ProcessPointer;
		NEW(awaitFixup, codeFixups, CBC.FAwaitInitializationEnd);
		CG.Call(awaitFixup, 1, SimpleCallStackSize);
		CG.EndInstruction
	END AwaitInitializationEnd;
	
	PROCEDURE AwaitFinalizationStart;
	VAR awaitFixup: SystemCallFixup;
	BEGIN
		CG.ProcessPointer;
		NEW(awaitFixup, codeFixups, CBC.FAwaitFinalizationStart);
		CG.Call(awaitFixup, 1, SimpleCallStackSize);
		CG.EndInstruction
	END AwaitFinalizationStart;
		
	PROCEDURE GenerateExternalInterface(com: CCIR.Component; offered: BOOLEAN; index: LONGINT);
	VAR offset: LONGINT;
	BEGIN
		offset := ComponentHeaderSize;
		IF ~offered THEN INC(offset, com.offeredInterfaces.Length() * InterfaceConnectionSize) END;
		INC(offset, index * InterfaceConnectionSize);
		CG.ComponentPointer;
		CG.LoadInteger4(offset);
		CG.AddInteger
	END GenerateExternalInterface;
	
	PROCEDURE DisconnectOfferedInterfaces(com: CCIR.Component);
	VAR i: LONGINT; decl: CCIR.InterfaceDeclaration; disconnectFixup: SystemCallFixup;
	BEGIN
		FOR i := 0 TO com.offeredInterfaces.Length()-1 DO
			decl := com.offeredInterfaces.GetInterfaceDeclaration(i);
			IF com.implementations.FindImplementation(decl.name) = NIL THEN (* redirected *)
				GenerateExternalInterface(com, TRUE, i);
				CG.ProcessPointer;
				NEW(disconnectFixup, codeFixups, CBC.FDisconnect);
				CG.Call(disconnectFixup, 2, SimpleCallStackSize);
				CG.EndInstruction
			END
		END
	END DisconnectOfferedInterfaces;
	
	PROCEDURE DisconnectRequiredInterfaces(com: CCIR.Component);
	VAR i: LONGINT; disconnectFixup: SystemCallFixup;
	BEGIN
		FOR i := 0 TO com.requiredInterfaces.Length()-1 DO
			GenerateExternalInterface(com, FALSE, i);
			CG.ProcessPointer;
			NEW(disconnectFixup, codeFixups, CBC.FDisconnect);
			CG.Call(disconnectFixup, 2, SimpleCallStackSize);
			CG.EndInstruction
		END
	END DisconnectRequiredInterfaces;
	
	PROCEDURE AwaitDisconnectedInterfaces(com: CCIR.Component);
	VAR i: LONGINT; awaitDisFixup: SystemCallFixup;
	BEGIN
		FOR i := 0 TO com.offeredInterfaces.Length()-1 DO
			CG.ProcessPointer;
			GenerateExternalInterface(com, TRUE, i);
			NEW(awaitDisFixup, codeFixups, CBC.FAwaitDisconnected);
			CG.Call(awaitDisFixup, 2, SimpleCallStackSize);
			CG.EndInstruction
		END;
		FOR i := 0 TO com.requiredInterfaces.Length()-1 DO
			CG.ProcessPointer;
			GenerateExternalInterface(com, FALSE, i);
			NEW(awaitDisFixup, codeFixups, CBC.FAwaitDisconnected);
			CG.Call(awaitDisFixup, 2, SimpleCallStackSize);
			CG.EndInstruction
		END
	END AwaitDisconnectedInterfaces;
	
	PROCEDURE CloseAllRequiredExternalComm(com: CCIR.Component);
	VAR index: LONGINT; decl: CCIR.InterfaceDeclaration;
	BEGIN
		FOR index := 0 TO com.usedCommunications.Length()-1 DO
			decl := com.usedCommunications.GetInterfaceDeclaration(index);
			CG.CommunicationBufferForComponent(componentVariables.offset, index);
			InternalCloseCommunication(decl, FALSE)
		END
	END CloseAllRequiredExternalComm;

	PROCEDURE ExtendStackOnProcedureEntry(proc: CCIR.Procedure; sizeFixup: SizeFixup);
	VAR endFixup: CodeFixup; extensionSize: LONGINT; extendStackFixup: SystemCallFixup;
	BEGIN 
		(* IF size > stackReserve THEN *)
		NEW(endFixup, codeFixups);
		CG.LoadAddress(sizeFixup, 0);
		CG.ProcedureStackReserveParam;
		CG.GreaterInteger;
		CG.ConditionalBranch(FALSE, endFixup);
		
		(* ExtendStack(ADR(@stackext), ExtensionSize) *)
		extensionSize := StackExtensionSize;
		GenerateVariable(proc, stackExtensionVariable); 
		CG.GetAddress;
		CG.LoadInteger4(extensionSize);
		NEW(extendStackFixup, codeFixups, CBC.FExtendStack);
		CG.Call(extendStackFixup, 2, SimpleCallStackSize);
		CG.EndInstruction;
		
		(* stackReserve := ExtensionSize *)
		CG.ProcedureStackReserveParam;
		CG.LoadInteger4(extensionSize);
		CG.Store;
		CG.EndInstruction;
						
		(* END *)
		BranchEntry(endFixup)
	END ExtendStackOnProcedureEntry;
	
	PROCEDURE ReduceStackOnProcedureExit(proc: CCIR.Procedure);
	VAR endFixup: CodeFixup; reduceStackFixup: SystemCallFixup;
	BEGIN
		(* IF @stackext # NIL THEN *)
		NEW(endFixup, codeFixups);
		GenerateVariable(proc, stackExtensionVariable); CG.Load;
		CG.LoadInteger4(NilValue);
		CG.UnequalInteger;
		CG.ConditionalBranch(FALSE, endFixup);
		
		(* ReduceStack(@stackext) *)
		GenerateVariable(proc, stackExtensionVariable); CG.Load;
		NEW(reduceStackFixup, codeFixups, CBC.FReduceStack);
		CG.Call(reduceStackFixup, 1, SimpleCallStackSize);
		CG.EndInstruction;
		
		(* END *)
		BranchEntry(endFixup)
	END ReduceStackOnProcedureExit;
	
	(* heuristics for pre-allocated procedure stack size *)
	PROCEDURE ProcedureStackReserve(): LONGINT;
	VAR size, i: LONGINT; procAlloc: ProcedureAllocation;
	BEGIN
		size := 0;
		FOR i := 0 TO procedureAllocations.Length()-1 DO
			procAlloc := procedureAllocations.GetProcedureAllocation(i);
			ASSERT(procAlloc.stackSizeFixup # NIL);
			ASSERT(procAlloc.stackSizeFixup.size > 0);
			INC(size, procAlloc.stackSizeFixup.size)
		END;
		RETURN size
	END ProcedureStackReserve;
	
	PROCEDURE RemainingStackSize(scope: CCIR.Node; currentStackSize: LONGINT);
	BEGIN
		IF (scope IS CCIR.Component) OR (scope IS CCIR.Implementation) THEN
			ASSERT((currentProcessAllocation # NIL) & (currentProcessAllocation.stackSizeFixup # NIL));
			CG.LoadAddress(currentProcessAllocation.stackSizeFixup, 0)
		ELSIF scope IS CCIR.Procedure THEN
			CG.ProcedureStackReserveParam
		ELSE HALT(111)
		END;
		CG.LoadInteger4(currentStackSize);
		CG.SubtractInteger
	END RemainingStackSize;
																		
	PROCEDURE AddressOfCommunicationSet(scope: CCIR.Node);
	BEGIN
		IF scope IS CCIR.Implementation THEN
			CG.AdrOfCommSetInImplementation
		ELSIF scope IS CCIR.Procedure THEN
			CG.AdrOfCommSetInProcedure
		ELSE HALT(111)
		END
	END AddressOfCommunicationSet;
	
	PROCEDURE GenerateComponentName(out: CCBasic.DataSequence; 
		component: CCIR.ComponentDefinition);
	VAR qualIdent: CCIR.Identifier;
	BEGIN
		qualIdent := component.QualIdent(); 
		out.Text(qualIdent.name^)
	END GenerateComponentName;
	
	PROCEDURE GenerateInterfaceName(out: CCBasic.DataSequence; interface: CCIR.Interface);
	VAR qualIdent: CCIR.Identifier;
	BEGIN
		qualIdent := interface.QualIdent(); 
		out.Text(qualIdent.name^)
	END GenerateInterfaceName;

	PROCEDURE GenerateProcedureName(out: CCBasic.DataSequence; procedure: CCIR.Procedure);
	VAR qualIdent: CCIR.Identifier;
	BEGIN 
		qualIdent := procedure.QualIdent();
		out.Text(qualIdent.name^)
	END GenerateProcedureName;
		
	PROCEDURE ResolveLocalFixups(list: CG.FixupList);
	VAR i: LONGINT; fixup: CG.Fixup; procAlloc: ProcedureAllocation; implAlloc: ImplementationAllocation;
	BEGIN
		FOR i := 0 TO list.Length()-1 DO
			fixup := list.GetFixup(i);
			IF fixup.reference IS CodeFixup THEN
				ASSERT(fixup.reference.list = codeFixups);
				Fixup(code, fixup, fixup.reference(CodeFixup).targetPos)
			ELSIF fixup.reference IS ConstFixup THEN
				ASSERT(fixup.reference.list = codeFixups);
				Fixup(code, fixup, fixup.reference(ConstFixup).constPos)
			ELSIF fixup.reference IS SizeFixup THEN
				ASSERT(~fixup.relative);
				ASSERT(fixup.reference.list = codeFixups);
				Fixup(code, fixup, fixup.reference(SizeFixup).size)
			ELSIF fixup.reference IS ComponentSizeFixup THEN
				ASSERT(~fixup.relative);
				ASSERT(fixup.reference.list = headerFixups);
				Fixup(header, fixup, fixup.reference(ComponentSizeFixup).size)
			ELSIF fixup.reference IS ProcessFixup THEN
				ASSERT(fixup.reference.list = headerFixups);
				Fixup(header, fixup, fixup.reference(ProcessFixup).targetPos)
			ELSIF fixup.reference IS ProcedureCallFixup THEN 
				ASSERT(fixup.reference.list = codeFixups);
				procAlloc := procedureAllocations.FindProcedureAllocation(fixup.reference(ProcedureCallFixup).procedure);
				ASSERT(procAlloc # NIL);
				Fixup(code, fixup, procAlloc.startPos)
			ELSIF fixup.reference IS ImplementationFixup THEN
				ASSERT(fixup.reference.list = codeFixups);
				implAlloc := 
					implementationAllocations.FindImplementationAllocation(fixup.reference(ImplementationFixup).implementation);
				ASSERT(implAlloc # NIL);
				Fixup(code, fixup, implAlloc.startPos)
			ELSIF fixup.reference IS SystemCallFixup THEN (* ok *)
			ELSIF fixup.reference IS ComponentTemplateFixup THEN (* ok *)
				ASSERT(~fixup.relative)
			ELSIF fixup.reference IS InterfaceSpecificationFixup THEN (* ok *)
				ASSERT(~fixup.relative)
			ELSE HALT(111)
			END
		END	
	END ResolveLocalFixups;
		
	PROCEDURE Fixup(section: CCBasic.DataSequence; fixup: CG.Fixup; value: LONGINT);
	VAR x, v: LONGINT;
	BEGIN
		IF (fixup.reference IS CodeFixup) OR (fixup.reference IS ConstFixup) OR 
				(fixup.reference IS ProcessFixup) OR (fixup.reference IS SizeFixup) OR 
				(fixup.reference IS ComponentSizeFixup) OR (fixup.reference IS ProcedureCallFixup) OR
				(fixup.reference IS ImplementationFixup) THEN
			x := section.GetInteger4(fixup.codePos);
			IF fixup.relative THEN
				v := value - (fixup.codePos + 4)
			ELSE
				v := value
			END;
			section.ChangeInteger4(fixup.codePos, x + v)
		ELSE
			HALT(111) (* must occur in FixupSection of binary file *)
		END
	END Fixup;
	
	PROCEDURE FindProcessFixup(list: CG.FixupList; com: CCIR.Component; name: CCIR.Identifier): ProcessFixup;
	VAR i: LONGINT; fixup: CG.Fixup; pf: ProcessFixup;
	BEGIN
		FOR i := 0 TO list.Length()-1 DO
			fixup := list.GetFixup(i);
			IF fixup.reference IS ProcessFixup THEN
				pf := fixup.reference(ProcessFixup);
				IF (pf.component = com) & pf.processName.Equal(name) THEN RETURN pf END
			END
		END;
		RETURN NIL
	END FindProcessFixup;
	
	PROCEDURE FindComponentSizeFixup(list: CG.FixupList; com: CCIR.Component): ComponentSizeFixup;
	VAR i: LONGINT; fixup: CG.Fixup; csf: ComponentSizeFixup;
	BEGIN
		FOR i := 0 TO list.Length()-1 DO
			fixup := list.GetFixup(i);
			IF fixup.reference IS ComponentSizeFixup THEN
				csf := fixup.reference(ComponentSizeFixup);
				IF csf.component = com THEN RETURN csf END
			END
		END;
		RETURN NIL
	END FindComponentSizeFixup;
		
	PROCEDURE CollectFixups(input: CG.FixupList; output: FixupTypeList; VAR absConstFixups, absCodeFixups: LONGINT);
	VAR i: LONGINT; fixup: CG.Fixup; callCode: CHAR; relative: BOOLEAN; comDef: CCIR.ComponentDefinition;
		int: CCIR.Interface;
	BEGIN
		FOR i := 0 TO input.Length()-1 DO
			fixup := input.GetFixup(i);
			IF (fixup.reference IS ConstFixup) & ~fixup.relative THEN INC(absConstFixups)
			ELSIF (fixup.reference IS CodeFixup) & ~fixup.relative THEN INC(absCodeFixups)
			ELSIF fixup.reference IS SystemCallFixup THEN
				callCode := fixup.reference(SystemCallFixup).callCode; relative := fixup.relative;
				output.RegisterSystemCall(callCode, relative)
			ELSIF fixup.reference IS ComponentTemplateFixup THEN
				comDef := fixup.reference(ComponentTemplateFixup).com; 
				output.RegisterComponentTemplate(comDef)
			ELSIF fixup.reference IS InterfaceSpecificationFixup THEN
				int := fixup.reference(InterfaceSpecificationFixup).interface;
				output.RegisterInterfaceSpecification(int)
			ELSIF (fixup.reference IS ImplementationFixup) & ~fixup.relative THEN INC(absCodeFixups)
			END
		END
	END CollectFixups;
	
	PROCEDURE BeginOutput;
	BEGIN 
		NEW(header); NEW(constants); NEW(code); NEW(tail); 
		NEW(headerFixups); NEW(codeFixups); 
		NEW(procedureAllocations);
		NEW(implementationAllocations);
		CG.Initialize(code);
		header.Char(CBC.FTag); 
		header.Char(CBC.FVersion)
	END BeginOutput;
	
	PROCEDURE EndOutput(name: ARRAY OF CHAR; isComponent: BOOLEAN);
	BEGIN
		IF ~breakRequired THEN
			EmitFile(name, isComponent)
		END;
		FreeOutput
	END EndOutput;
	
	PROCEDURE EmitFile(name: ARRAY OF CHAR; isComponent: BOOLEAN;);
	VAR name2, filename: AosFS.FileName; file: AosFS.File; writer: AosFS.Writer;
	BEGIN
		filename := "";
		IF outPartition # "" THEN
			Utilities.Append(filename, outPartition);
			Utilities.Append(filename, ":")
		END;
		Utilities.Append(filename, name);
		Utilities.Append(filename, ".");
		Utilities.Append(filename, CBC.FileSuffix);
		file := AosFS.New(filename);
		AosFS.OpenWriter(writer, file, 0);
		IF isComponent THEN CCBasic.OutText(" component ") ELSE CCBasic.OutText(" interface ") END;
		CCBasic.OutText(name);
		header.Integer4(constants.Length()); 
		header.Write(writer);
		constants.Integer4(code.Length());
		constants.Write(writer);
		code.Write(writer);
		tail.Write(writer);
		writer.Update;
		AosFS.Register(file);
		IF isComponent THEN CCBasic.OutText(" "); CCBasic.OutInteger(code.Length()); END;
		CCBasic.OutText(" done"); CCBasic.OutLine
	END EmitFile;

	PROCEDURE FreeOutput;
	BEGIN 
		header := NIL; constants := NIL; code :=  NIL; tail := NIL; CG.Finish; 
		headerFixups := NIL; codeFixups := NIL; 
		componentVariables := NIL; 
		procedureAllocations := NIL; implementationAllocations := NIL;
		currentProcessAllocation := NIL
	END FreeOutput;

	BEGIN
		ASSERT(ProcessParameterOffset = CG.ProcessParameterOffset);
		ASSERT(ComponentParameterOffset = CG.ComponentParameterOffset);
		ASSERT(CommunicationSetParamOffset = CG.CommunicationSetParamOffset);
		ASSERT(StackReserveParameterOffset = CG.StackReserveParameterOffset);
		ASSERT(StaticLinkParameterOffset = CG.StaticLinkParameterOffset);
		ASSERT(ProcessTailCommBufferOffset = CG.ProcessTailCommBufferOffset);
		
		NEW(initializer, -1, "@INITIALIZER"); NEW(finalizer, -1, "@FINALIZER");
		NEW(procedureResultVariable, -1, NIL, CCIR.NewIdentifier(-1, "@RESULT"));
		procedureResultVariable.SetType(CCIR.integerType); (* at most 4 byte *)
		NEW(stackExtensionVariable, -1, NIL, CCIR.NewIdentifier(-1, "@STACKEXT"));
		stackExtensionVariable.SetType(CCIR.integerType)
END CCGenerator.
