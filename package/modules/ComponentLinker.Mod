MODULE ComponentLinker; (* Boot Image Linker, 2006-2010 by Luc Blaeser *)
	IMPORT 
		Basic := CCBasic, 
		AosFS := Files, 
		AosIO := Streams, 
		Utilities := Strings,
		In := Commands;

	(* See symbol and object file format *)
			
	CONST 
		Trace = FALSE;
		InfoOutput = TRUE;
		
		ObjectFileSuffix = ".Obx";
		CBCFileSuffix = ".CBC";
		
		StartModule = "Concurrency"; StartCommand = "TerminateProcess";
		(* kernel calls *)
		NewRecordModule = "Heap"; NewRecordProcedure = "SystemNewRecord";
		NewArrayModule = "Heap"; NewArrayProcedure = "SystemNewArray";
		DeleteBlockModule = "Heap"; DeleteBlockProcedure = "SystemDeleteBlock";
		LockModule = "Concurrency"; LockProcedure = "Lock";
		UnlockModule = "Concurrency"; UnlockProcedure = "Unlock";
		AwaitModule = "Concurrency"; AwaitProcedure = "Await";
		
		RegisterCBCModule = "ComConsole"; RegisterCBCProcedure = "LinkerRegisterLoadSource";
		CreateComponentModule = "ComConsole"; CreateComponentProcedure = "LinkerCreateComponent";
		ConnectComponentModule = "ComConsole"; ConnectComponentProcedure = "LinkerConnectComponents";
		LoadSystemComponentModule = "ComConsole"; LoadSystemComponentProcedure = "LinkerLoadSystemComponent";
		
		RegDefaultPartitionModule = "ComConsole"; RegDefaultPartitionProcedure = "LinkerRegisterDefaultPartition";
		LoadLastPartitionModule = "ComConsole"; LoadLastPartitionProcedure = "LinkerLoadLastPartition";
		
		LoadAddress = 1000H;
		BaseAddress = 1000H;
	
		NilValue = SHORT(0FFFFF800H); (* outside the valid segment range *)
		Alignment = 256; (* lock variables must be 32-byte aligned for better performance *)
	
	CONST
		MaxBaseTypes = 16;
	
	TYPE
		Identifier = ARRAY 32 OF CHAR;
		ModuleName = Identifier;
		CommandName = Identifier;
		VariableName = Identifier;
		ProcedureName = Identifier;
		TypeName = Identifier;
	
		(* object file intermediate representation *)
		Header = RECORD
			refSize, nofEntries, nofCommands, nofPointers: LONGINT;
			nofTypes, nofImports, nofVarConsLinks, nofLinks: LONGINT;
			dataSize, exTableLen, constSize, codeSize: LONGINT; 
			moduleName: ModuleName;
		END;
		
		Entry = RECORD
			entryOffset: LONGINT;
		END;
		
		Entries = POINTER TO ARRAY OF Entry;
		
		Command = RECORD
			cmdName: CommandName;
			cmdOffset: LONGINT;
		END;
		
		Commands = POINTER TO ARRAY OF Command;
		
		Import = RECORD
			moduleName: ModuleName;
		END;
		
		Pointer = RECORD
			offset: LONGINT;
		END;
		
		Pointers = POINTER TO ARRAY OF Pointer;
		
		Imports = POINTER TO ARRAY OF Import;
		
		Offsets  = POINTER TO ARRAY OF LONGINT;
	
		VarConstLink = RECORD
			module: LONGINT;(* 0 for current module, other represent index in import list *)
			entry: LONGINT;
			offsets: Offsets;
		END;
		
		VarConstLinks = POINTER TO ARRAY OF VarConstLink;
		
		Link = RECORD
			module, entry, offset: LONGINT;
		END;
		
		Links = POINTER TO ARRAY OF Link;
		
		RawData = POINTER TO ARRAY OF CHAR;
		
		ExportRecord = POINTER TO RECORD
			tdentry: LONGINT; (* or oldref if negative *)
			super: ExportRecord; 
			list: ExportRecordWithFPList;
		END;
		
		ExportRecordList = OBJECT(Basic.List)
			PROCEDURE Add(x: ANY);
			BEGIN ASSERT(x IS ExportRecord); Add^(x)
			END Add;
			
			PROCEDURE GetExportRecord(index: LONGINT): ExportRecord;
			VAR ptr: ANY;
			BEGIN ptr := GetItem(index); RETURN ptr(ExportRecord)
			END GetExportRecord;
		END ExportRecordList;
		
		ExportRecordWithFP = RECORD
			fingerprint: LONGINT;
			record: ExportRecord;
		END;
		
		ExportRecordWithFPList = POINTER TO ARRAY OF ExportRecordWithFP;
		
		Export = RECORD
			fingerprint: LONGINT;
			fixup: LONGINT;
			record: ExportRecord;
		END;
		
		Exports = POINTER TO ARRAY OF Export;
		
		UsedRecord = OBJECT
			VAR
				tdentry: LONGINT;
				fingerprint: LONGINT;
		END UsedRecord;
		
		UsedVar = OBJECT
			VAR
				fingerprint: LONGINT;
				varName: VariableName;
				fixlist: LONGINT;
				usedRecord: UsedRecord;
		END UsedVar;
		
		UsedVars = OBJECT(Basic.List)
			PROCEDURE Add(x: ANY);
			BEGIN ASSERT(x IS UsedVar); Add^(x)
			END Add;
			
			PROCEDURE GetUsedVar(index: LONGINT): UsedVar;
			VAR ptr: ANY;
			BEGIN ptr := GetItem(index); RETURN ptr(UsedVar)
			END GetUsedVar;
		END UsedVars;
		
		UsedProc = OBJECT
			VAR 
				fingerprint: LONGINT;
				procName: ProcedureName;
				offset: LONGINT;
		END UsedProc;
		
		UsedProcs = OBJECT(Basic.List)
			PROCEDURE Add(x: ANY);
			BEGIN ASSERT(x IS UsedProc); Add^(x)
			END Add;
			
			PROCEDURE GetUsedProc(index: LONGINT): UsedProc;
			VAR ptr: ANY;
			BEGIN ptr := GetItem(index); RETURN ptr(UsedProc)
			END GetUsedProc;
		END UsedProcs;
		
		UsedType = OBJECT
			VAR
				fingerprint: LONGINT;
				typeName: TypeName;
				usedRecord: UsedRecord;
		END UsedType;
		
		UsedTypes = OBJECT(Basic.List)
			PROCEDURE Add(x: ANY);
			BEGIN ASSERT(x IS UsedType); Add^(x)
			END Add;
			
			PROCEDURE GetUsedType(index: LONGINT): UsedType;
			VAR ptr: ANY;
			BEGIN ptr := GetItem(index); RETURN ptr(UsedType)
			END GetUsedType;
		END UsedTypes;
		
		UsedModule = OBJECT
			VAR
				moduleName: ModuleName;
				usedVars: UsedVars;
				usedProcs: UsedProcs;
				usedTypes: UsedTypes;
			
			PROCEDURE &InitUsedModule(module: ModuleName);
			BEGIN COPY(module, moduleName); NEW(usedVars); NEW(usedProcs); NEW(usedTypes)
			END InitUsedModule;
		END UsedModule;
		
		UsedModules = OBJECT(Basic.List)
			PROCEDURE Add(x: ANY);
			BEGIN ASSERT(x IS UsedModule); Add^(x)
			END Add;
			
			PROCEDURE GetUsedModule(index: LONGINT): UsedModule;
			VAR ptr: ANY;
			BEGIN ptr := GetItem(index); RETURN ptr(UsedModule)
			END GetUsedModule;
		END UsedModules;
		
		Method = RECORD
			methodNumber, entryNumber: LONGINT;
		END;
		
		Methods = POINTER TO ARRAY OF Method;
		
		Type = RECORD
			size, tdaddr, baseModule, baseEntry: LONGINT;
			nofMethods, nofInheritedMethods, nofNewMethods, nofPointers: LONGINT;
			name: TypeName;
			methods: Methods;
			pointers: Pointers;
		END;
		
		Types = POINTER TO ARRAY OF Type;
		
		Variable = OBJECT
			VAR
				varMode: CHAR;
				type: CHAR;
				typeTdAdrDim: LONGINT; (* tdAdr for type = RecordVar, dim for type = ArrayVar *)
				offset: LONGINT;
				name: VariableName
		END Variable;
		
		Variables = OBJECT(Basic.List)
			PROCEDURE Add(x: ANY);
			BEGIN ASSERT(x IS Variable); Add^(x)
			END Add;
			
			PROCEDURE GetVariable(index: LONGINT): Variable;
			VAR ptr: ANY; 
			BEGIN ptr := GetItem(index); RETURN ptr(Variable)
			END GetVariable;
		END Variables;
		
		BodyReference = OBJECT
			VAR
				offset: LONGINT;
				name: Identifier;
				variables: Variables;
				
			PROCEDURE &InitBodyReference;
			BEGIN NEW(variables)
			END InitBodyReference;
		END BodyReference;
				
		ProcedureReference = OBJECT
			VAR
				offset: LONGINT;
				nofPars: LONGINT;
				retType: CHAR;
				retTypeTdAdrDim: LONGINT; (* tdAdr for retType = RecordVar, dim for retType = ArrayVar *)
				procLevel: LONGINT;
				slFlag: CHAR;
				name: ProcedureName;
				variables: Variables;
			
			PROCEDURE &InitProcedureReference;
			BEGIN NEW(variables)
			END InitProcedureReference;
		END ProcedureReference;
		
		ProcedureReferences = OBJECT(Basic.List)
			PROCEDURE Add(x: ANY);
			BEGIN ASSERT(x IS ProcedureReference); Add^(x)
			END Add;
			
			PROCEDURE GetProcedureReference(index: LONGINT): ProcedureReference;
			VAR ptr: ANY;
			BEGIN ptr := GetItem(index); RETURN ptr(ProcedureReference)
			END GetProcedureReference;
			
			(* NIL if not present *)
			PROCEDURE FindProcedureReference(name: ARRAY OF CHAR): ProcedureReference;
			VAR i: LONGINT; x: ProcedureReference;
			BEGIN
				FOR i := 0 TO Length()-1 DO
					x := GetProcedureReference(i);
					IF x.name = name THEN RETURN x END
				END;
				RETURN NIL
			END FindProcedureReference;
		END ProcedureReferences;
		
		References = OBJECT
			VAR
				bodyReference: BodyReference;
				procReferences: ProcedureReferences;
			
			PROCEDURE &InitReferences;
			BEGIN NEW(bodyReference); NEW(procReferences)
			END InitReferences;
		END References;	
		
		TypeDescAllocation = RECORD
			startPos, endPos: LONGINT;
			typeDescHeaderPos: LONGINT; (* pointer position for type descriptor header *)
			typeDescNormalPos: LONGINT; (* pointer position for type descriptor tag *)
		END;
					
		TypeDescAllocations = POINTER TO ARRAY OF TypeDescAllocation;
		
		(* allocation offsets relative to image file, used for relocation *)
		Allocation = RECORD
			startPos, endPos: LONGINT;
			codeBasePos, staticBasePos: LONGINT; 
			typeDescAllocations: TypeDescAllocations; (* ordered according to Module.types *)
		END;
		
		Module = OBJECT
			VAR
				header: Header;
				entries: Entries;
				commands: Commands;
				pointers: Pointers;
				imports: Imports;
				varConstLinks: VarConstLinks;
				links: Links;
				consts: RawData;
				exports: Exports;
				code: RawData;
				use: UsedModules;
				types: Types;
				references: References;
				
				allocation: Allocation;
				importCount: LONGINT; (* number of imports from external modules, for topological sort *)
				
			PROCEDURE &Initialize;
			BEGIN 
				NEW(use); NEW(references);
				allocation.codeBasePos := -1; allocation.staticBasePos := -1;
				importCount := 0
			END Initialize;
		END Module;
		
		ModuleList = OBJECT(Basic.List)
			PROCEDURE Add(x: ANY);
			BEGIN ASSERT(x IS Module); Add^(x)
			END Add;
			
			PROCEDURE GetModule(index: LONGINT): Module;
			VAR ptr: ANY;
			BEGIN ptr := GetItem(index); RETURN ptr(Module)
			END GetModule;
			
			(* NIL if not present *)
			PROCEDURE FindModule(name: ARRAY OF CHAR): Module;
			VAR i: LONGINT; m: Module;
			BEGIN
				FOR i := 0 TO Length()-1 DO
					m := GetModule(i); 
					IF m.header.moduleName = name THEN RETURN m END
				END;
				RETURN NIL
			END FindModule;
		END ModuleList;

		FixupPos = LONGINT;
		FixupList = POINTER TO ARRAY OF FixupPos;

		ImageFixupData = RECORD
			lengthFixupInDWordPos: FixupPos; (* absolute *)
			moduleBodyFixupPos: FixupList; (* relative, ith entry corresponds to modules[i] *)
			startCommandFixupPos: FixupPos; (* relative *)
			cbcNameAdrFixupPos: FixupList; (* absolute, ith entry corresponds to cbc[i] *)
			cbcCodeAdrFixupPos: FixupList; (* absolute *)
			cbcRegisterCallFixupPos: FixupList; (* relative *)
			setupCmdName1AdrFixup: FixupList; (* absolute, ith entry corresponds to setupScript[i] *)
			setupCmdName2AdrFixup: FixupList; (* absolute *)
			setupCmdName3AdrFixup: FixupList; (* absolute *)
			setupCmdCallFixupPos: FixupList; (* relative *)
			loadSystemComCallFixupPos: FixupPos; (* relative *)
			partitionNameAdrFixupPos: FixupPos; (* absolute *)
			partitionRegCallFixupPos: FixupPos; (* relative *)
		END;
		
		SetupStatement = POINTER TO RECORD
		END;
		
		SetupNewStatementAllocation = RECORD
			instanceNamePos, typeNamePos: LONGINT
		END;
		
		SetupNewStatement = POINTER TO RECORD(SetupStatement)
			instanceName, typeName: Identifier;
			allocation: SetupNewStatementAllocation
		END;
		
		SetupConnectStatementAllocation = RECORD
			interfaceNamePos, fromInstanceNamePos, toInstanceNamePos: LONGINT
		END;
		
		SetupConnectStatement = POINTER TO RECORD(SetupStatement)
			interfaceName, fromInstanceName, toInstanceName: Identifier;
			allocation: SetupConnectStatementAllocation;
		END;
		
		SetupScript = OBJECT(Basic.List)
			PROCEDURE Add(x: ANY);
			BEGIN ASSERT(x IS SetupStatement); Add^(x)
			END Add;
			
			PROCEDURE GetSetupStatement(index: LONGINT): SetupStatement;
			VAR ptr: ANY;
			BEGIN ptr := GetItem(index); RETURN ptr(SetupStatement)
			END GetSetupStatement;
		END SetupScript;
		
		CBCElementAllocation = RECORD
			namePos, codePos: LONGINT;
		END;
		
		CBCElement = POINTER TO RECORD
			isComponent: BOOLEAN;
			name: Identifier;
			code: RawData;
			allocation: CBCElementAllocation
		END;
		
		CBCList = OBJECT(Basic.List)
			PROCEDURE Add(x: ANY);
			BEGIN ASSERT(x IS CBCElement); Add^(x)
			END Add;
			
			PROCEDURE GetCBCElement(index: LONGINT): CBCElement;
			VAR ptr: ANY;
			BEGIN ptr := GetItem(index); RETURN ptr(CBCElement)
			END GetCBCElement;
			
			(* NIL if not present *)
			PROCEDURE FindComponent(name: ARRAY OF CHAR): CBCElement;
			VAR i: LONGINT; x: CBCElement;
			BEGIN
				FOR i := 0 TO Length()-1 DO
					x := GetCBCElement(i);
					IF x.isComponent & (x.name = name) THEN RETURN x END
				END;
				RETURN NIL
			END FindComponent;
			
			PROCEDURE FindInterface(name: ARRAY OF CHAR): CBCElement;
			VAR i: LONGINT; x: CBCElement;
			BEGIN
				FOR i := 0 TO Length()-1 DO
					x := GetCBCElement(i);
					IF ~x.isComponent & (x.name = name) THEN RETURN x END
				END;
				RETURN NIL
			END FindInterface;
		END CBCList;
								
	VAR
		error: BOOLEAN;
		out: Basic.DataSequence;
		modules: ModuleList;
		partitionName: Identifier;
		partitionNameAllocationPos: LONGINT;
		cbc: CBCList;
		setupScript: SetupScript;
	
	PROCEDURE ReadToken(in: AosIO.Reader; VAR x: ARRAY OF CHAR);
	VAR i: LONGINT; ch: CHAR;
	BEGIN
       	in.SkipWhitespace();
		i := 0; ch := in.Peek();
	  	WHILE (i < LEN(x)) & 
		  		((ch >= "A") & (ch <= "Z")) OR ((ch >= "a") & (ch <= "z")) OR ((ch >= "0") & (ch <= "9")) DO
			in.Char(x[i]); INC(i);
			ch := in.Peek()
		END;
		IF (i < LEN(x)) THEN x[i] := 0X END
	END ReadToken;
	
	PROCEDURE ReadSymbol(in: AosIO.Reader; VAR ch: CHAR);
	BEGIN
		in.SkipWhitespace();
		in.Char(ch)
	END ReadSymbol;
	
	PROCEDURE ReadPartitionName(in: AosIO.Reader; VAR x: ARRAY OF CHAR);
	VAR i: LONGINT; ch: CHAR;
	BEGIN
		i := 0; 
		REPEAT
			in.Char(ch); 
			IF (ch > " ") & (i < LEN(x)) THEN x[i] := ch; INC(i) END
		UNTIL in.EOLN() OR (ch <= " ");
		IF i < LEN(x) THEN x[i] := 0X END
	END ReadPartitionName;
	
	(** 
		LinkBootImage imageFile { ( ModuleList | InterfaceList | ComponentList ) } ~
		ModuleList = "Modules={" module { "," module } "}".
		InterfaceList = "Interfaces={" interface { "," interface } "}".
		ComponentList = "Components={" component { "," component } "}". 
	*)
	PROCEDURE LinkBootImage*(context: In.Context);
	VAR in: AosIO.Reader; outputFile, listName, itemName: ARRAY 64 OF CHAR; ch: CHAR;
	BEGIN
	       in := context.arg;
	       in.SkipWhitespace();
		in.String(outputFile);
		IF outputFile # "" THEN
			Initialize;
			ReadToken(in, listName);
			WHILE ~in.EOLN() & (listName # "") DO
				ReadSymbol(in, ch);
				IF (ch = "=") & ~in.EOLN() THEN
					IF listName = "Partition" THEN
						ReadPartitionName(in, partitionName);
						Basic.OutText("Default partition "); Basic.OutText(partitionName); Basic.OutLine
					ELSE
						ReadSymbol(in, ch);
						IF (ch = "{") & ~in.EOLN() THEN
							IF listName = "Setup" THEN 
								ReadSetup(in)
							ELSE
								REPEAT
									ReadToken(in, itemName);
									IF ~in.EOLN() THEN
										IF listName = "Modules" THEN 
											ReadModule(itemName)
										ELSIF listName = "Components" THEN
											ReadCBC(TRUE, itemName)
										ELSIF listName = "Interfaces" THEN
											ReadCBC(FALSE, itemName)
										ELSE
											Basic.OutText("Undefined list "); Basic.OutText(listName); Basic.OutLine
										END;
										ReadSymbol(in, ch)
									ELSE ch := 0X
									END
								UNTIL ch # ",";
								IF ch # "}" THEN Basic.OutText("'}' missing"); Basic.OutLine END
							END
						END 
					END
				ELSE Basic.OutText("'=' missing"); Basic.OutLine
				END;
				ReadToken(in, listName)
			END;
			IF ~error THEN ReadImportedModules END;
			IF ~error THEN GenerateLinkCode END;
			IF ~error THEN WriteOutput(outputFile) END;
			IF error THEN Basic.OutText("Failed"); Basic.OutLine END;
			Free
		ELSE
			Basic.OutText("Missing output file name"); Basic.OutLine
		END
	END LinkBootImage;
	
	PROCEDURE ReadSetup(in: AosIO.Reader);
	VAR statement: ARRAY 64 OF CHAR; ch: CHAR; 
		newStatement: SetupNewStatement; connectStatement: SetupConnectStatement;
	BEGIN
		REPEAT
			ReadToken(in, statement);
			ReadSymbol(in, ch);
			IF ch = "(" THEN
				IF statement = "NEW" THEN
					NEW(newStatement);
					ReadToken(in, newStatement.instanceName); 
					ReadSymbol(in, ch);
					IF ch # "," THEN Basic.OutText("',' missing"); Basic.OutLine END;
					ReadToken(in, newStatement.typeName);
					setupScript.Add(newStatement)
				ELSIF statement = "CONNECT" THEN
					NEW(connectStatement);
					ReadToken(in, connectStatement.interfaceName);
					ReadSymbol(in, ch);
					IF ch # "(" THEN error := TRUE; Basic.OutText("interface selection missing"); Basic.OutLine END;
					ReadToken(in, connectStatement.fromInstanceName);
					ReadSymbol(in, ch);
					IF ch # ")" THEN error := TRUE; Basic.OutText("')' missing"); Basic.OutLine END;
					ReadSymbol(in, ch);
					IF ch # "," THEN error := TRUE; Basic.OutText("',' missing"); Basic.OutLine END;
					ReadToken(in, connectStatement.toInstanceName);
					setupScript.Add(connectStatement)
				ELSE error := TRUE; Basic.OutText("Undefined statement in setup script"); Basic.OutLine
				END;
				ReadSymbol(in, ch);
				IF ch # ")" THEN error := TRUE; Basic.OutText("')' missing"); Basic.OutLine END
			ELSE Basic.OutText("'(' missing"); Basic.OutLine
			END;
			ReadSymbol(in, ch)
		UNTIL (ch # ";") OR in.EOLN();
		IF ch # "}" THEN error := TRUE; Basic.OutText("'}' missing"); Basic.OutLine END
	END ReadSetup;
	
	PROCEDURE ReadImportedModules;
	VAR name: ModuleName;
	BEGIN
		FindModuleToImport(name);
		WHILE (name # "") & ~error DO
			ReadModule(name);
			FindModuleToImport(name)
		END;
		SortModulesByImport
	END ReadImportedModules;
	
	(* topological sort of acyclic import relation, consider also kernel call dependencies *)
	PROCEDURE SortModulesByImport;
	VAR i, k: LONGINT; from, to: Module; sorted: ModuleList; x: ModuleName;
	BEGIN
		FOR i := 0 TO modules.Length()-1 DO
			from := modules.GetModule(i);
			(* import dependencies *)
			FOR k := 0 TO LEN(from.imports)-1 DO
				to := modules.FindModule(from.imports[k].moduleName); ASSERT(to # NIL);
				INC(to.importCount)
			END;
			(* kernel call dependencies *)
			FOR k := 0 TO LEN(from.links)-1 DO
				GetKernelCallModule(from.links[k], x);
				IF x # "" THEN
					to := modules.FindModule(x); ASSERT(to # NIL);
					INC(to.importCount)
				END
			END
		END;
		NEW(sorted);
		WHILE (modules.Length() > 0) & ~error DO
			from := FindLeafModule();
			IF from # NIL THEN
				modules.Remove(from); sorted.Add(from);
				(* import dependencies *)
				FOR k := 0 TO LEN(from.imports)-1 DO
					to := modules.FindModule(from.imports[k].moduleName); ASSERT(to # NIL);
					DEC(to.importCount)
				END;
				(* kernel call dependencies *)
				FOR k := 0 TO LEN(from.links)-1 DO
					GetKernelCallModule(from.links[k], x);
					IF x # "" THEN
						to := modules.FindModule(x); ASSERT(to # NIL);
						DEC(to.importCount)
					END
				END
			END
		END;
		modules := sorted
	END SortModulesByImport;
	
	(* NIL if cyclic import *)
	PROCEDURE FindLeafModule(): Module;
	VAR i: LONGINT; m: Module;
	BEGIN
		FOR i := 0 TO modules.Length()-1 DO
			m := modules.GetModule(i); ASSERT(m.importCount >= 0);
			IF m.importCount = 0 THEN RETURN m END
		END;
		Error(0, "Cyclic module import");
		RETURN NIL
	END FindLeafModule;
	
	(* name = "" if none to import *)
	PROCEDURE FindModuleToImport(VAR name: ModuleName);
	VAR i, k: LONGINT; from, imported: Module; x: ModuleName;
	BEGIN
		FOR i := 0 TO modules.Length()-1 DO
			from := modules.GetModule(i);
			FOR k := 0 TO LEN(from.imports)-1 DO
				imported := modules.FindModule(from.imports[k].moduleName);
				IF imported = NIL THEN
					COPY(from.imports[k].moduleName, name);
					RETURN
				END
			END;
			FOR k := 0 TO LEN(from.links)-1 DO
				GetKernelCallModule(from.links[k], x);
				IF x # "" THEN
					imported := modules.FindModule(x);
					IF imported = NIL THEN
						COPY(x, name);
						RETURN
					END
				END
			END
		END;
		COPY("", name)
	END FindModuleToImport;
	
	(* moduleName = "" if no kernel call *)
	PROCEDURE GetKernelCallModule(link: Link; VAR moduleName: ModuleName);
	BEGIN
		IF link.entry = 254 THEN (* local procedure assignment *)
			COPY("", moduleName)
		ELSIF link.entry = 253 THEN (* Heap.SystemNewRecord *)
			COPY(NewRecordModule, moduleName)
		ELSIF link.entry = 251 THEN (* Heap.NewArray *)
			COPY(NewArrayModule, moduleName)
		ELSIF link.entry = 243 THEN (* Heap.SystemDeleteBlock *)
			COPY(DeleteBlockModule, moduleName)
		ELSIF link.entry = 247 THEN (* Concurrency.Lock *)
			COPY(LockModule, moduleName)
		ELSIF link.entry = 246 THEN (* Concurrency.Unlock *)
			COPY(UnlockModule, moduleName)
		ELSIF link.entry = 249 THEN (* Concurrency.Await *)
			COPY(AwaitModule, moduleName)
		ELSE
			Basic.OutText("Undefined kernel call "); Basic.OutInteger(link.entry); Basic.OutLine;
			HALT(111) (* not yet supported *)
		END
	END GetKernelCallModule;
	
	PROCEDURE ReadTextPart(VAR a: ARRAY OF CHAR; VAR i: LONGINT; VAR x: ARRAY OF CHAR);
	VAR k: LONGINT;
	BEGIN
		k := 0; 
		WHILE (i < LEN(a)) & (k < LEN(x)) & (((a[i] >= "A") & (a[i] <= "Z")) OR ((a[i] >= "a") & (a[i] <= "z"))) DO 
			x[k] := a[i]; INC(i); INC(k)
		END;
		IF k < LEN(x) THEN x[k] := 0X END
	END ReadTextPart;
	
	PROCEDURE ReadIntegerPart(VAR a: ARRAY OF CHAR; VAR i: LONGINT; VAR x: LONGINT);
	BEGIN
		x := 0;
		WHILE (i < LEN(a)) & ((a[i] >= "0") & (a[i] <= "9")) DO
			x := x * 10 + ORD(a[i]) - ORD("0"); INC(i)
		END
	END ReadIntegerPart;
			
	PROCEDURE ReadModule(moduleName: ARRAY OF CHAR);
	VAR fileName: AosFS.FileName; file: AosFS.File; reader: AosFS.Reader; module: Module; 
	BEGIN
		ASSERT(modules.FindModule(moduleName) = NIL); (* not yet loaded *)
		Utilities.Concat(moduleName, ObjectFileSuffix, fileName);
		file := AosFS.Old(fileName);
		IF file # NIL THEN
			NEW(module);
			AosFS.OpenReader(reader, file, 0);
			ReadHeader(reader, module.header);
			ASSERT(module.header.moduleName = moduleName);
			ReadEntries(reader, module);
			ReadCommands(reader, module);
			ReadPointers(reader, module);
			ReadImports(reader, module);
			ReadVarConstLinks(reader, module);
			ReadLinks(reader, module);
			ReadConsts(reader, module);
			ReadExports(reader, module);
			ReadCode(reader, module);
			ReadUse(reader, module);
			ReadTypes(reader, module);
			ReadReferences(reader, module);
			IF ~reader.EOLN() THEN Error(reader.Pos(), "end of file expected") END;
			(* read references *)
			modules.Add(module)
		ELSE Basic.OutText(moduleName); Basic.OutText(" object file not present"); Basic.OutLine
		END
	END ReadModule;
	
	PROCEDURE ReadHeader(reader: AosIO.Reader; VAR header: Header);
	VAR tag, c: CHAR; symSize: LONGINT; x: INTEGER; i: LONGINT;
	BEGIN
		reader.Char(tag);
		IF tag = 0BBX THEN
			reader.Char(tag);
			IF tag = 0ADX THEN reader.Char(tag) END; (* no zero compression in symbol file *)
			IF (tag = 0AFX) OR (tag = 0B0X) THEN
				reader.RawNum(symSize);
				FOR i := 1 TO symSize DO reader.Char(c) END; (* skip symbol file section *)
				reader.RawLInt(header.refSize);
				reader.RawInt(x); header.nofEntries := x; ASSERT(x >= 0);
				reader.RawInt(x); header.nofCommands := x; ASSERT(x >= 0);
				reader.RawInt(x); header.nofPointers := x; ASSERT(x >= 0);
				reader.RawInt(x); header.nofTypes := x; ASSERT(x >= 0);
				reader.RawInt(x); header.nofImports := x; ASSERT(x >= 0);
				reader.RawInt(x); header.nofVarConsLinks := x; ASSERT(x >= 0);
				reader.RawInt(x); header.nofLinks := x; ASSERT(x >= 0);
				reader.RawLInt(header.dataSize);
				reader.RawInt(x);  header.constSize := LONG(x) MOD 10000H;
				reader.RawInt(x);  header.codeSize := LONG(x) MOD 10000H;
				IF tag = 0B0X THEN
					reader.RawLInt(header.exTableLen)
				ELSE
					header.exTableLen := 0
				END;
				reader.RawString(header.moduleName);
				IF Trace THEN PrintHeader(header) END
			END
		ELSE
			Error(reader.Pos(), "Invalid tag")
		END
	END ReadHeader;
	
	PROCEDURE ReadEntries(reader: AosIO.Reader; module: Module);
	VAR tag: CHAR; i: LONGINT; x: INTEGER;
	BEGIN
		reader.Char(tag);
		IF tag = 82X THEN 
			NEW(module.entries, module.header.nofEntries);
			FOR i := 0 TO module.header.nofEntries-1 DO
				reader.RawInt(x);
				module.entries[i].entryOffset := LONG(x) MOD 10000H
			END;
			IF Trace THEN PrintEntries(module.entries) END
		ELSE
			Error(reader.Pos(), "Invalid entry section tag ")
		END
	END ReadEntries;
		
	PROCEDURE ReadCommands(reader: AosIO.Reader; module: Module);
	VAR tag: CHAR; i: LONGINT; x: INTEGER;
	BEGIN
		reader.Char(tag);
		IF tag = 83X THEN
			NEW(module.commands, module.header.nofCommands);
			FOR i := 0 TO module.header.nofCommands-1 DO
				reader.RawString(module.commands[i].cmdName);
				reader.RawInt(x);
				module.commands[i].cmdOffset := LONG(x) MOD 10000H
			END;
			IF Trace THEN PrintCommands(module.commands) END
		ELSE
			Error(reader.Pos(), "Invalid command section tag")
		END
	END ReadCommands;
	
	PROCEDURE ReadPointers(reader: AosIO.Reader; module: Module);
	VAR tag: CHAR; i: LONGINT;
	BEGIN
		reader.Char(tag);
		IF tag = 84X THEN
			NEW(module.pointers, module.header.nofPointers);
			FOR i := 0 TO module.header.nofPointers-1 DO
				reader.RawLInt(module.pointers[i].offset)
			END;
			IF Trace THEN PrintPointers(module.pointers) END
		ELSE
			Error(reader.Pos(), "Invalid pointer section tag")
		END
	END ReadPointers;
	
	PROCEDURE ReadImports(reader: AosIO.Reader; module: Module);
	VAR tag: CHAR; i: LONGINT;
	BEGIN
		reader.Char(tag);
		IF tag = 85X THEN
			NEW(module.imports, module.header.nofImports);
			FOR i := 0 TO module.header.nofImports-1 DO
				reader.RawString(module.imports[i].moduleName)
			END;
			IF Trace THEN PrintImports(module.imports) END
		ELSE
			Error(reader.Pos(), "Invalid import section tag")
		END
	END ReadImports;
	
	PROCEDURE ReadVarConstLinks(reader: AosIO.Reader; module: Module);
	VAR tag: CHAR; i, count, k: LONGINT; s: SHORTINT; x: INTEGER;
	BEGIN
		reader.Char(tag);
		IF tag = 8DX THEN
			NEW(module.varConstLinks, module.header.nofVarConsLinks);
			FOR i := 0 TO module.header.nofVarConsLinks-1 DO
				reader.RawSInt(s); module.varConstLinks[i].module := s;
				reader.RawInt(x); module.varConstLinks[i].entry := x;
				reader.RawInt(x); count := x;
				NEW(module.varConstLinks[i].offsets, count);
				FOR k := 0 TO count-1 DO
					reader.RawInt(x); 
					module.varConstLinks[i].offsets[k] := Basic.UnsignedInt(x)
				END
			END;
			IF Trace THEN PrintVarConstLinks(module.varConstLinks) END
		ELSE
			Error(reader.Pos(), "Invalid varConstLink section tag")
		END
	END ReadVarConstLinks;
	
	PROCEDURE ReadLinks(reader: AosIO.Reader; module: Module);
	VAR tag: CHAR; i: LONGINT; c: CHAR; x: INTEGER;
	BEGIN
		reader.Char(tag);
		IF tag = 86X THEN
			NEW(module.links, module.header.nofLinks);
			FOR i := 0 TO module.header.nofLinks-1 DO
				reader.Char(c); module.links[i].module := ORD(c);
				reader.Char(c); module.links[i].entry := ORD(c);
				reader.RawInt(x); module.links[i].offset := Basic.UnsignedInt(x)
			END;
			IF Trace THEN PrintLinks(module.links) END
		ELSE
			Error(reader.Pos(), "Invalid link section tag")
		END
	END ReadLinks;
	
	PROCEDURE ReadConsts(reader: AosIO.Reader; module: Module);
	VAR tag: CHAR; i: LONGINT;
	BEGIN
		reader.Char(tag);
		IF tag = 87X THEN
			NEW(module.consts, module.header.constSize);
			FOR i := 0 TO module.header.constSize-1 DO
				reader.Char(module.consts[i])
			END
		ELSE
			Error(reader.Pos(), "Invalid const section tag")
		END
	END ReadConsts;
	
	PROCEDURE ReadExports(reader: AosIO.Reader; module: Module);
	VAR tag: CHAR; x: INTEGER; nofExports, fp, i: LONGINT; previous: ExportRecordList;
	BEGIN
		reader.Char(tag);
		IF tag = 88X THEN
			NEW(previous);
			reader.RawInt(x); nofExports := x;
			NEW(module.exports, nofExports);
			i := 0; reader.RawNum(fp);
			WHILE (i < nofExports) & (fp # 0) DO
				ASSERT(fp # 1);
				module.exports[i].fingerprint := fp;
				reader.RawNum(module.exports[i].fixup);
				reader.RawNum(fp);
				IF fp = 1 THEN
					ReadExportRecord(reader, module.exports[i].record, previous);
					reader.RawNum(fp)
				ELSE
					module.exports[i].record := NIL
				END;
				INC(i)
			END;
			IF fp # 0 THEN
				Error(reader.Pos(), "End tag of export section missing")
			END;
			IF Trace THEN PrintExports(module.exports) END
		ELSE
			Error(reader.Pos(), "Invalid export section tag")
		END
	END ReadExports;
	
	PROCEDURE ReadExportRecord(reader: AosIO.Reader; VAR record: ExportRecord; previous: ExportRecordList);
	VAR n: INTEGER; i, fp, oldref: LONGINT; old: ExportRecord;
	BEGIN
		NEW(record); previous.Add(record);
		reader.RawNum(record.tdentry);
		IF record.tdentry > 0 THEN
			reader.RawInt(n);
			NEW(record.list, n);
			reader.RawNum(fp);
			IF fp = 1 THEN
				ReadExportRecord(reader, record.super, previous);
				reader.RawNum(fp)
			ELSE
				record.super := NIL
			END;
			i := 0;
			WHILE (fp # 0) & (i < n) DO
				ASSERT(fp # 1);
				record.list[i].fingerprint := fp;
				reader.RawNum(fp);
				IF fp = 1 THEN
					ReadExportRecord(reader, record.list[i].record, previous);
					reader.RawNum(fp)
				ELSE
					record.list[i].record := NIL
				END;
				INC(i)
			END;
			IF (fp # 0) OR (i < n) THEN Error(reader.Pos(), "Invalid exported record list") END
		ELSIF record.tdentry < 0 THEN
			oldref := -record.tdentry;
			ASSERT(oldref <= previous.Length());
			old := previous.GetExportRecord(oldref-1);
			record.tdentry := old.tdentry;
			record.super := old.super;
			record.list := old.list
		ELSE Error(reader.Pos(), "ExportRecord: Invalid tdentry/oldref")
		END
	END ReadExportRecord;
	
	PROCEDURE ReadCode(reader: AosIO.Reader; module: Module);
	VAR tag: CHAR; i: LONGINT;
	BEGIN
		reader.Char(tag);
		IF tag = 89X THEN
			NEW(module.code, module.header.codeSize);
			FOR i := 0 TO module.header.codeSize-1 DO
				reader.Char(module.code[i])
			END
		ELSE
			Error(reader.Pos(), "Invalid code section tag")
		END
	END ReadCode;
	
	PROCEDURE ReadUse(reader: AosIO.Reader; module: Module);
	VAR tag: CHAR; moduleName: ModuleName; usedModule: UsedModule;
	BEGIN
		reader.Char(tag);
		IF tag = 8AX THEN
			ReadString8(reader, moduleName);
			WHILE moduleName # "" DO
				NEW(usedModule, moduleName); module.use.Add(usedModule);
				ReadUseEntries(reader, usedModule);
				ReadString8(reader, moduleName)
			END;
			IF Trace THEN PrintUse(module.use) END
		ELSE
			Error(reader.Pos(), "Invalid use section tag")
		END
	END ReadUse;
	
	PROCEDURE ReadUseEntries(reader: AosIO.Reader; usedModule: UsedModule);
	VAR fingerprint: LONGINT; name: Identifier; fixOffset: LONGINT; usedVar: UsedVar; usedProc: UsedProc; usedType: UsedType;
		tdentry: LONGINT; recordName: TypeName;
	BEGIN
		reader.RawNum(fingerprint);
		WHILE fingerprint # 0 DO
			usedVar := NIL; usedProc := NIL; usedType := NIL;
			ReadString8(reader, name);
			reader.RawNum(fixOffset);
			IF fixOffset > 0 THEN (* variable *)
				NEW(usedVar); usedVar.fingerprint := fingerprint; COPY(name, usedVar.varName); 
				usedVar.fixlist := fixOffset; usedVar.usedRecord := NIL;
				usedModule.usedVars.Add(usedVar)
			ELSIF fixOffset < 0 THEN (* procedure *)
				NEW(usedProc); usedProc.fingerprint := fingerprint; COPY(name, usedProc.procName); 
				usedProc.offset := fixOffset - MIN(LONGINT);
				usedModule.usedProcs.Add(usedProc)
			ELSE (* fixOffset = 0, type *)
				NEW(usedType); usedType.fingerprint := fingerprint; COPY(name, usedType.typeName);
				usedType.usedRecord := NIL;
				usedModule.usedTypes.Add(usedType)
			END;
			reader.RawNum(fingerprint);
			IF fingerprint = 1 THEN (* UsedRecord *)
				reader.RawNum(tdentry);
				IF usedVar # NIL THEN 
					NEW(usedVar.usedRecord); usedVar.usedRecord.tdentry := tdentry
				ELSIF usedType # NIL THEN
					NEW(usedType.usedRecord); usedType.usedRecord.tdentry := tdentry
				ELSE
					Error(reader.Pos(), "UsedRecord is not defined for used procedure")
				END;
				reader.RawNum(fingerprint);
				IF fingerprint # 0 THEN
					IF usedVar # NIL THEN
						usedVar.usedRecord.fingerprint := fingerprint
					ELSIF usedType # NIL THEN
						usedType.usedRecord.fingerprint := fingerprint
					ELSE
						Error(reader.Pos(), "UsedRecord is not defined for used procedure")
					END;
					reader.RawString(recordName); 
					IF recordName # "@" THEN Error(reader.Pos(), "@ missing in UsedRecord") END;
					reader.RawNum(fingerprint)
				END;
				IF fingerprint # 0 THEN Error(reader.Pos(), "0X missing at the end of UsedRecord") END;
				reader.RawNum(fingerprint)
			END
		END
	END ReadUseEntries;
	
	PROCEDURE ReadMethods(reader: AosIO.Reader; VAR type: Type);
	VAR i: LONGINT; x: INTEGER;
	BEGIN
		NEW(type.methods, type.nofNewMethods);
		FOR i := 0 TO type.nofNewMethods-1 DO
			reader.RawInt(x); type.methods[i].methodNumber := x;
			reader.RawInt(x); type.methods[i].entryNumber := x
		END
	END ReadMethods;
	
	PROCEDURE ReadPointersInType(reader: AosIO.Reader; VAR type: Type);
	VAR i: LONGINT;
	BEGIN
		NEW(type.pointers, type.nofPointers);
		FOR i := 0 TO type.nofPointers-1 DO
			reader.RawLInt(type.pointers[i].offset)
		END
	END ReadPointersInType;
	
	PROCEDURE ReadTypes(reader: AosIO.Reader; module: Module);
	VAR tag: CHAR; i: LONGINT; x: INTEGER;
	BEGIN
		reader.Char(tag);
		IF tag = 8BX THEN
			NEW(module.types, module.header.nofTypes);
			FOR i := 0 TO module.header.nofTypes-1 DO
				reader.RawLInt(module.types[i].size);
				reader.RawInt(x); module.types[i].tdaddr := x;
				reader.RawInt(x); module.types[i].baseModule := x;
				reader.RawLInt(module.types[i].baseEntry);
				reader.RawInt(x); module.types[i].nofMethods := x;
				reader.RawInt(x); module.types[i].nofInheritedMethods := x;
				reader.RawInt(x); module.types[i].nofNewMethods := x;
				reader.RawInt(x); module.types[i].nofPointers := x;
				reader.RawString(module.types[i].name);
				ReadMethods(reader, module.types[i]);
				ReadPointersInType(reader, module.types[i])
			END;
			IF Trace THEN PrintTypes(module.types) END
		ELSE
			Error(reader.Pos(), "Invalid types section tag")
		END
	END ReadTypes;
			
	PROCEDURE ReadReferenceType(reader: AosIO.Reader; VAR type: CHAR; VAR tdAdrDim: LONGINT);
	BEGIN
		reader.Char(type);
		IF (type = 16X) OR (type = 1DX) OR ((ORD(type) >= 81H) & (ORD(type) <= 8EH)) THEN
			reader.RawNum(tdAdrDim)
		END
	END ReadReferenceType;

	PROCEDURE ReadVariableReferences(reader: AosIO.Reader; variables: Variables; VAR tag: CHAR);
	VAR varRef: Variable;
	BEGIN
		WHILE (tag = 01X) OR (tag = 03X) DO
			(* Variable *)
			NEW(varRef);
					
			varRef.varMode := tag;
			ReadReferenceType(reader, varRef.type, varRef.typeTdAdrDim);
			reader.RawNum(varRef.offset);
			reader.RawString(varRef.name);
					
			variables.Add(varRef);					
			IF ~reader.EOLN() THEN reader.Char(tag) ELSE tag := 0X END
		END;
	END ReadVariableReferences;
			
	PROCEDURE ReadReferences(reader: AosIO.Reader; module: Module);
	VAR tag: CHAR; procRef: ProcedureReference; si: SHORTINT;
	BEGIN
		reader.Char(tag);
		IF tag = 8EX THEN (* ignore exception table *) reader.Char(tag) END;
		IF tag = 8CX THEN
			(* BodyRef *)
			reader.Char(tag);
			IF tag # 0F8X THEN Error(reader.Pos(), "body reference expected") END;
			reader.RawNum(module.references.bodyReference.offset);
			reader.RawString(module.references.bodyReference.name);
			IF module.references.bodyReference.name # "$$" THEN Error(reader.Pos(), "body reference name must be $$") END;
			
			IF ~reader.EOLN() THEN reader.Char(tag) ELSE tag := 0X END;
			ReadVariableReferences(reader, module.references.bodyReference.variables, tag);
			
			(* { ProcRef } *)
			WHILE tag # 0X DO
				IF tag # 0F9X THEN Error(reader.Pos(), "procedure reference expected") END;
				NEW(procRef);
				
				reader.RawNum(procRef.offset);
				reader.RawSInt(si); procRef.nofPars := si;
				ReadReferenceType(reader, procRef.retType, procRef.retTypeTdAdrDim);
				reader.RawSInt(si); procRef.procLevel := si;
				reader.Char(procRef.slFlag);
				reader.RawString(procRef.name);
				
				IF ~reader.EOLN() THEN reader.Char(tag) ELSE tag := 0X END;
				ReadVariableReferences(reader, procRef.variables, tag);
						
				module.references.procReferences.Add(procRef)
			END;
			IF Trace THEN PrintReferences(module.references) END
		ELSE
			Error(reader.Pos(), "Invalid reference section tag")
		END
	END ReadReferences;
	
	(* zero compressed strings don't like UTF-8 encoding *)
	PROCEDURE ReadString8(reader: AosIO.Reader; VAR a: ARRAY OF CHAR);
	VAR i: LONGINT; ch: CHAR;
	BEGIN
		i := 0;
		reader.Char(ch);
		WHILE ch # 0X DO
			a[i] := ch; INC(i);
			reader.Char(ch)
		END;
		a[i] := 0X
	END ReadString8;
	
	PROCEDURE GenerateLinkCode;
	VAR fixup: ImageFixupData;
	BEGIN
		InitSequence(fixup);
		AllocateModules;
		FixupModules;
		AllocateCBC;
		AllocateDefaultPartition;
		FinalImageFixup(fixup)
	END GenerateLinkCode;
	
	PROCEDURE Initialize;
	BEGIN NEW(modules); COPY("", partitionName); NEW(cbc); NEW(setupScript); NEW(out); error := FALSE
	END Initialize;
	
	PROCEDURE Free;
	BEGIN modules := NIL; COPY("", partitionName); cbc := NIL; setupScript := NIL; out := NIL; error := FALSE
	END Free;
	
	PROCEDURE WriteOutput(fileName: ARRAY OF CHAR);
	VAR file: AosFS.File; writer: AosFS.Writer;
	BEGIN
		file := AosFS.New(fileName); AosFS.OpenWriter(writer, file, 0);
		out.Write(writer); writer.Update;
		AosFS.Register(file);
		Basic.OutText(fileName); Basic.OutText(" written"); Basic.OutLine
	END WriteOutput;
	
	PROCEDURE InitSequence(VAR fixup: ImageFixupData);
	VAR i: LONGINT; 
	BEGIN
		ASSERT(out.Length() = 0); 
		IF BaseAddress # LoadAddress THEN
			(* relocate image from load to base address *)
			out.Char(060X); (* PUSHAD *)
			
			out.Char(0BEX); (* MOV ESI, imageLoadAdr *)
			out.Integer4(LoadAddress);
			
			out.Char(0BFX); (* MOV EDI, imageBaseAdr *)
			out.Integer4(BaseAddress);
			
			out.Char(0B9X); (* MOV ECX, length of image in double words *)
			fixup.lengthFixupInDWordPos := out.Length();
			out.Integer4(0); (* fixup image length later *)
			
			out.Char(0FCX); (* CLD *)
			out.Char(0F3X); (* REP *)
			out.Char(0A5X); (* MOVSD *)
			
			out.Char(061X); (* POPAD *)
		ELSE
			fixup.lengthFixupInDWordPos := -1
		END;
				
		(* execute module bodies *)
		NEW(fixup.moduleBodyFixupPos, modules.Length());
		FOR i := modules.Length()-1 TO 0 BY -1 DO
			out.Char(0E8X); (* CALL rel32 *)
			fixup.moduleBodyFixupPos[i] := out.Length();
			out.Integer4(0); (* fixup later *)
		END;

		InitDefaultPartition(fixup);

		InitRegisterCBCCode(fixup);		
		
		(* execute start procedure *)
		out.Char(0E8X); (* CALL rel 32 *)
		fixup.startCommandFixupPos := out.Length();
		out.Integer4(0); (* fixup later *)
				
		(* this code should not be reached *)
		out.Char(6AX); (* PUSH imm8 *)
		out.Char(0FFX);
		out.Char(0CCX); (* INT 3 *)
		
		IF Trace OR InfoOutput THEN
			Basic.OutText("InitSequence endPos="); Basic.OutInteger(out.Length()); Basic.OutLine
		END
	END InitSequence;
	
	PROCEDURE FinalImageFixup(VAR fixups: ImageFixupData);
	VAR imageSizeDW, i: LONGINT; m: Module; fixupPos, relValue, cmdPos: LONGINT; 
	BEGIN
		ASSERT(out.Length() <= (512 - 4 - 4 - 8)*1024); (* boot image must not be too large *)
		(* low 4KB is reserved, 4K page for boot stack, 8KB for multi-processor boot code and stack *)
		
		(* fixup image size *)
		IF fixups.lengthFixupInDWordPos >= 0 THEN
			imageSizeDW := out.Length()+3 DIV 4;
			(* at the end *)
			out.ChangeInteger4(fixups.lengthFixupInDWordPos, imageSizeDW);
		END;
		
		(* fixup module bodies *)
		FOR i := modules.Length()-1 TO 0 BY -1 DO
			m := modules.GetModule(i);
			fixupPos := fixups.moduleBodyFixupPos[i];
			relValue := m.allocation.codeBasePos - (fixupPos + 4);
			out.ChangeInteger4(fixupPos, relValue)
		END;
		
		FinalDefaultPartitionFixups(fixups);
		
		FinalRegisterCBCFixups(fixups);
		
		(* fixup start command *)
		fixupPos := fixups.startCommandFixupPos;
		cmdPos := FindCommandPosition(StartModule, StartCommand);
		IF cmdPos >= 0 THEN
			relValue := cmdPos - (fixupPos + 4);
			out.ChangeInteger4(fixupPos, relValue)
		END
	END FinalImageFixup;
	
	(* -1 if not present *)
	PROCEDURE FindCommandPosition(moduleName, cmdName: ARRAY OF CHAR): LONGINT;
	VAR module: Module; i: LONGINT;
	BEGIN
		module := modules.FindModule(moduleName);
		IF module # NIL THEN
			ASSERT(module.allocation.codeBasePos >= 0);
			FOR i := 0 TO LEN(module.commands)-1 DO
				IF module.commands[i].cmdName = cmdName THEN
					ASSERT(module.commands[i].cmdOffset >= 0);
					RETURN module.allocation.codeBasePos + module.commands[i].cmdOffset
				END
			END;
			Error4(0, moduleName, ".", cmdName," not defined");
			RETURN -1
		ELSE
			Error4(0, "module ", moduleName, " not defined", "");
			RETURN -1
		END
	END FindCommandPosition;
								
	PROCEDURE AllocateModules;
	VAR i: LONGINT; module: Module;
	BEGIN
		Align(1024 + 512); (* performance optimization *)
		(* start with hierarchical lower modules *)
		FOR i := modules.Length()-1 TO 0 BY -1 DO
			module := modules.GetModule(i);
			AllocateModule(module)
		END
	END AllocateModules;
	
	PROCEDURE AllocateModule(module: Module);
	BEGIN
		ASSERT(module.header.exTableLen = 0); (* not supported *)
		Align(Alignment);
		module.allocation.startPos := out.Length();
		AllocateEmptySection(module.header.dataSize); (* global data section before static base, negative offsets *)
		Align(Alignment); 
		AllocateEmptySection(8); (* offset for 32-byte alignment of module spin lock => performance optimization on IA32 *)
		module.allocation.staticBasePos := out.Length(); (* object file format specification is wrong, it is just the opposite *)
		AllocateRawData(module.consts); (* constant section after static base, positive offsets *)
		Align(Alignment);
		module.allocation.codeBasePos := out.Length();
		AllocateRawData(module.code);
		AllocateTypeDescriptors(module);
		module.allocation.endPos := out.Length();
		IF Trace OR InfoOutput THEN 
			Basic.OutText(module.header.moduleName); Basic.OutText(" codePos="); Basic.OutInteger(module.allocation.codeBasePos); 
			Basic.OutText(" staticBase="); Basic.OutInteger(module.allocation.staticBasePos); Basic.OutLine
		END
	END AllocateModule;
	
	PROCEDURE AllocateRawData(d: RawData);
	VAR i: LONGINT;
	BEGIN FOR i := 0 TO LEN(d)-1 DO out.Char(d[i]) END
	END AllocateRawData;
	
	PROCEDURE AllocateTypeDescriptors(module: Module);
	VAR i: LONGINT;
	BEGIN
		NEW(module.allocation.typeDescAllocations, module.header.nofTypes);
		FOR i := 0 TO module.header.nofTypes-1 DO
			AllocateTypeDescriptor(module, module.types[i], module.allocation.typeDescAllocations[i])
		END
	END AllocateTypeDescriptors;
	
	(* Refer to Oberon memory layout specification, Heap.Mod *)
	PROCEDURE AllocateTypeDescriptor(module: Module; type: Type; VAR alloc: TypeDescAllocation);
	CONST TdBitMask = 1; (* bit 0 *)
	VAR tdSize, i, baseTdPos: LONGINT;
	BEGIN
		Align(Alignment);	
		alloc.startPos := out.Length();
		out.Integer4(BaseAddress + alloc.startPos + 4 + TdBitMask); (* type desc header tag with Td bit flag *)
		alloc.typeDescHeaderPos := out.Length();
		tdSize := 44 + type.nofMethods * 4 + 16 * 4 +  8 + type.nofPointers * 4 + 4;
		out.Integer4(tdSize);
		out.Integer4(BaseAddress + alloc.typeDescHeaderPos + tdSize - 4); (* self *)
		out.Integer4(NilValue); (* moduleAdr, later fixup *)
		ASSERT(LEN(type.name) = 32);
		FOR i := 0 TO LEN(type.name)-1 DO out.Char(type.name[i]) END;
		(* space for method entries *)
		FOR i := 0 TO type.nofMethods-1 DO out.Integer4(0) END; 
		(* space for base type entries *)
		FOR i := 0 TO MaxBaseTypes-1 DO out.Integer4(0) END;
		out.Integer4(BaseAddress + alloc.typeDescHeaderPos + TdBitMask); (* indirect *)
		alloc.typeDescNormalPos := out.Length();
		out.Integer4(type.size);
		(* pointer offsets *)
		FOR i := 0 TO type.nofPointers-1 DO out.Integer4(type.pointers[i].offset) END;
		(* sentinel *)
		out.Integer4(-1);
		alloc.endPos := out.Length();
		ASSERT(alloc.endPos - alloc.typeDescHeaderPos = tdSize)
	END AllocateTypeDescriptor;
	
	PROCEDURE Align(bytes: LONGINT);
	BEGIN WHILE out.Length() MOD bytes # 0 DO out.Char(0X) END
	END Align;
		
	PROCEDURE AllocateEmptySection(length: LONGINT);
	VAR i: LONGINT;
	BEGIN FOR i := 0 TO length-1 DO out.Char(0X) END
	END AllocateEmptySection;
	
	PROCEDURE FixupModules;
	VAR i: LONGINT;
	BEGIN
		FOR i := modules.Length()-1 TO 0 BY -1 DO
			FixupModule(modules.GetModule(i))
		END
	END FixupModules;
	
	PROCEDURE FixupModule(module: Module);
	VAR i: LONGINT;
	BEGIN
		FOR i := 0 TO LEN(module.links)-1 DO
			FixupLink(module, module.links[i])
		END;
		FOR i := 0 TO LEN(module.varConstLinks)-1 DO
			FixupVarConstLink(module, module.varConstLinks[i])
		END;
		FOR i := 0 TO module.use.Length()-1 DO
			FixupUsedModule(module, module.use.GetUsedModule(i))
		END;
		(* fixup base types before sub-types, base types are declared after sub-types in object file *)
		FOR i := LEN(module.types)-1 TO 0 BY -1 DO 
			FixupTypeDescriptor(module, module.types[i], module.allocation.typeDescAllocations[i])
		END
	END FixupModule;
	
	PROCEDURE FixupLink(module: Module; link: Link);
	VAR codeBaseAdr, kernelCallPos, nextFixupOfs, fixupPos, entryIndex, fixupValue: LONGINT; 
	BEGIN
		nextFixupOfs := link.offset;
		(* fixup chain embedded in the code *)
		REPEAT
			ASSERT(nextFixupOfs >= 0);
			fixupPos := module.allocation.codeBasePos + nextFixupOfs;
			nextFixupOfs := Basic.UnsignedInt(out.GetInteger2(fixupPos + 2));
			IF link.entry = 254 THEN (* local procedure assignment *)
				codeBaseAdr := BaseAddress + module.allocation.codeBasePos;
				entryIndex := Basic.UnsignedInt(out.GetInteger2(fixupPos));
				ASSERT(module.entries[entryIndex].entryOffset >= 0);
				fixupValue := codeBaseAdr + module.entries[entryIndex].entryOffset
			ELSE
				IF link.entry = 253 THEN (* Heap.SystemNewRecord *)
					kernelCallPos := GetKernelCallPos(module, NewRecordModule, NewRecordProcedure)
				ELSIF link.entry = 251 THEN (* Heap.NewArray *)
					kernelCallPos := GetKernelCallPos(module, NewArrayModule, NewArrayProcedure)
				ELSIF link.entry = 243 THEN (* Heap.SystemDeleteBlock *)
					kernelCallPos := GetKernelCallPos(module, DeleteBlockModule, DeleteBlockProcedure)
				ELSIF link.entry = 247 THEN (* Concurrency.Lock *)
					kernelCallPos := GetKernelCallPos(module, LockModule, LockProcedure)
				ELSIF link.entry = 246 THEN (* Concurrency.Unlock *)
					kernelCallPos := GetKernelCallPos(module, UnlockModule, UnlockProcedure)
				ELSIF link.entry = 249 THEN (* Concurrency.Await *)
					kernelCallPos := GetKernelCallPos(module, AwaitModule, AwaitProcedure)
				ELSE
					HALT(111) (* not yet supported *)
				END;
				fixupValue := kernelCallPos - (fixupPos + 4); (* relative fixup *)
			END;
			out.ChangeInteger4(fixupPos, fixupValue)
		UNTIL nextFixupOfs = 0FFFFH
	END FixupLink;
	
	PROCEDURE FixupVarConstLink(module: Module; link: VarConstLink);
	VAR i: LONGINT; entry: Entry; fixupPos, staticBaseAdr: LONGINT;
	BEGIN
		IF link.module = 0 THEN (* current module *)
			ASSERT(link.entry = -1); (* defined by object file format *)
			staticBaseAdr := BaseAddress + module.allocation.staticBasePos;
			FOR i := 0 TO LEN(link.offsets)-1 DO
				ASSERT(link.offsets[i] >= 0);
				fixupPos := module.allocation.codeBasePos + link.offsets[i];
				Fixup(fixupPos, staticBaseAdr)
			END
		ELSE (* link to imported module, resolved by use section *)
		END
	END FixupVarConstLink;
	
	PROCEDURE FixupUsedModule(source: Module; usedModule: UsedModule);
	VAR target: Module; i: LONGINT;
	BEGIN
		target := modules.FindModule(usedModule.moduleName); ASSERT(target # NIL);
		ASSERT(target.allocation.codeBasePos >= 0); (* must be allocated *)
	
		(* relocate used variables *)
		FOR i := 0 TO usedModule.usedVars.Length()-1 DO
			FixupUsedVariable(source, target, usedModule.usedVars.GetUsedVar(i))
		END;
		
		(* relocate used procedures *)
		FOR i := 0 TO usedModule.usedProcs.Length()-1 DO
			FixupUsedProcedure(source, target, usedModule.usedProcs.GetUsedProc(i))
		END;
		
		(* check used types *)
		FOR i := 0 TO usedModule.usedTypes.Length()-1 DO
			FixupUsedType(source, target, usedModule.usedTypes.GetUsedType(i))
		END
	END FixupUsedModule;
	
	PROCEDURE FixupUsedVariable(source, target: Module; usedVar: UsedVar);
	VAR export: Export; offsets: Offsets; targetPos, fixupPos, absValue, i: LONGINT;
	BEGIN
		FindExport(target, usedVar.fingerprint, export);
		IF export.fingerprint # 0 THEN
			ASSERT(export.fixup < 0);
			targetPos := target.allocation.staticBasePos + export.fixup;
			offsets := source.varConstLinks[usedVar.fixlist].offsets;
			FOR i := 0 TO LEN(offsets)-1 DO
				ASSERT(offsets[i] >= 0);
				fixupPos := source.allocation.codeBasePos + offsets[i];
				absValue := BaseAddress + targetPos;
				Fixup(fixupPos, absValue)
			END;
			IF usedVar.usedRecord # NIL THEN
				FixupUsedRecord(source, target, usedVar.usedRecord, export.record)
			END
		ELSE
			Error4(0, source.header.moduleName, " incompatible with ", target.header.moduleName, "")
		END
	END FixupUsedVariable;
	
	PROCEDURE FixupUsedProcedure(source, target: Module; usedProc: UsedProc);
	VAR export: Export; targetPos: LONGINT; fixupPos, nextFixupOfs, fixupValue: LONGINT; code: CHAR;
	BEGIN
		FindExport(target, usedProc.fingerprint, export);
		IF export.fingerprint # 0 THEN
			ASSERT(export.fixup >= 0);
			targetPos := target.allocation.codeBasePos + export.fixup;
			nextFixupOfs := usedProc.offset;
			(* fixup chain list embedded in code *)
			REPEAT
				ASSERT(nextFixupOfs >= 0);
				fixupPos := source.allocation.codeBasePos + nextFixupOfs;
				code := out.GetChar(fixupPos-1);
				ASSERT(out.GetInteger2(fixupPos) = 0);
				nextFixupOfs := Basic.UnsignedInt(out.GetInteger2(fixupPos + 2)); 
				IF code = 0E8X THEN (* call instruction => relative address *)
					fixupValue := targetPos - (fixupPos + 4)
				ELSE (* absolute address *)
					fixupValue := BaseAddress + targetPos
				END;
				out.ChangeInteger4(fixupPos, fixupValue)
			UNTIL nextFixupOfs = 0FFFFH
		ELSE
			Error4(0, source.header.moduleName, " incompatible with ", target.header.moduleName, "")
		END
	END FixupUsedProcedure;
	
	PROCEDURE FixupTypeDescriptor(module: Module; type: Type; alloc: TypeDescAllocation);
	VAR baseTDPos, baseTagPos, i, fixupPos, fixupValue: LONGINT; meth: Method;
	BEGIN
		(* Fixup base types *)
		baseTDPos := GetBaseTypePosition(module, type.baseModule, type.baseEntry);
		fixupPos := alloc.typeDescNormalPos - 8;
		IF baseTDPos # 0 THEN
			(* copy base types (tag section of base type) *)
			baseTagPos := baseTDPos - 8;
			WHILE out.GetInteger4(baseTagPos) # 0 DO
				fixupValue := out.GetInteger4(baseTagPos); 
				ASSERT(fixupValue >= BaseAddress);
				out.ChangeInteger4(fixupPos, fixupValue);
				DEC(fixupPos, 4); DEC(baseTagPos, 4)
			END
		END;
		ASSERT(fixupPos >= alloc.typeDescNormalPos - 4 - 4 * MaxBaseTypes); (* too many base types *)
		
		(* set current type desc *)
		fixupValue := BaseAddress + alloc.typeDescNormalPos;
		out.ChangeInteger4(fixupPos, fixupValue); (* direct base type tag *)
		
		IF baseTDPos # 0 THEN
			(* copy inherited method fields first in virtual method table *)
			fixupPos := alloc.typeDescNormalPos - 4 - 4*MaxBaseTypes - 4;
			baseTagPos := baseTDPos - 4 - 4*MaxBaseTypes - 4;
			FOR i := 0 TO type.nofInheritedMethods-1 DO
				fixupValue := out.GetInteger4(baseTagPos);
				ASSERT(fixupValue # 0); (* base type's virtual method table must already be fixed *)
				out.ChangeInteger4(fixupPos, fixupValue);
				DEC(fixupPos, 4); DEC(baseTagPos, 4)
			END
		END;
		
		(* Set new method fields in virtual table, includding overridden methods *)
		FOR i := 0 TO type.nofNewMethods-1 DO
			meth := type.methods[i];
			fixupPos := alloc.typeDescNormalPos - 4 - 4*MaxBaseTypes - 4*(meth.methodNumber + 1);
			ASSERT(module.entries[meth.entryNumber].entryOffset >= 0);
			fixupValue := BaseAddress + module.allocation.codeBasePos + module.entries[meth.entryNumber].entryOffset;
			out.ChangeInteger4(fixupPos, fixupValue)
		END;
		
		(* fixup tag address in constant section *)
		fixupPos := module.allocation.staticBasePos + type.tdaddr;
		fixupValue := BaseAddress + alloc.typeDescNormalPos;
		out.ChangeInteger4(fixupPos, fixupValue);
		IF Trace THEN 
			Basic.OutText("Type desc fixup "); Basic.OutText(module.header.moduleName); Basic.OutText(".");
			Basic.OutText(type.name); Basic.OutText(" pos="); Basic.OutInteger(fixupPos); Basic.OutText(" tdadr="); 
			Basic.OutInteger(fixupValue, 0); Basic.OutLine
		END
	END FixupTypeDescriptor;
	
	(* 0 if no base type *)
	PROCEDURE GetBaseTypePosition(current: Module; baseModuleId, baseEntry: LONGINT): LONGINT;
	VAR i: LONGINT; modName: ModuleName; baseModule: Module; rec: ExportRecord; tdPos: LONGINT;
	BEGIN
		IF (baseModuleId = -1) & (baseEntry = -1) THEN 
			RETURN 0
			(* none *)
		ELSIF baseModuleId = 0 THEN
			(* local type *)
			tdPos:= out.GetInteger4(current.allocation.staticBasePos + baseEntry) - BaseAddress;
			ASSERT(tdPos >= 0); (* type descriptor must be already fixed *)
			RETURN tdPos
		ELSE
			(* imported type *)
			modName := current.imports[baseModuleId-1].moduleName;
			baseModule := modules.FindModule(modName);
			IF baseModule # NIL THEN
				FOR i := 0 TO LEN(baseModule.exports)-1 DO
					IF baseModule.exports[i].fingerprint = baseEntry THEN
						rec := baseModule.exports[i].record;
						IF rec # NIL THEN
							tdPos := out.GetInteger4(baseModule.allocation.staticBasePos + rec.tdentry) - BaseAddress;
							ASSERT(tdPos >= 0); (* type descriptor must be already fixed *)
							RETURN tdPos
						ELSE
							Error(0, "Incompatible imported base type")
						END
					END
				END;
				Error4(0, "Undefined imported base type entry in module ", modName, "", "")
			ELSE
				Error4(0, "Module ", modName, " not imported for base type", "")
			END
		END;
		RETURN 0
	END GetBaseTypePosition;

	PROCEDURE FixupUsedType(source, target: Module; usedType: UsedType);
	VAR export: Export; 
	BEGIN
		FindExport(target, usedType.fingerprint, export);
		IF export.fingerprint = 0 THEN
			Error4(0, source.header.moduleName, " incompatible with ", target.header.moduleName, "")
		END;
		IF usedType.usedRecord # NIL THEN
			FixupUsedRecord(source, target, usedType.usedRecord, export.record)
		END
	END FixupUsedType;
	
	PROCEDURE FixupUsedRecord(source, target: Module; usedRecord: UsedRecord; export: ExportRecord);
	VAR fixupPos, tdAdr: LONGINT;
	BEGIN
		ASSERT(usedRecord.tdentry < 0); ASSERT(export # NIL);
		fixupPos := source.allocation.staticBasePos - usedRecord.tdentry;
		ASSERT(export # NIL); ASSERT(export.tdentry >= 0);
		tdAdr := out.GetInteger4(target.allocation.staticBasePos + export.tdentry);
		out.ChangeInteger4(fixupPos, tdAdr);
		IF Trace THEN
			Basic.OutText("Fixup used type descriptor "); Basic.OutText(target.header.moduleName); 
			Basic.OutText(" fp="); Basic.OutHex(usedRecord.fingerprint); Basic.OutText(" in module ");
			Basic.OutText(source.header.moduleName); Basic.OutText(" tdentry="); 
			Basic.OutInteger(usedRecord.tdentry, 0); Basic.OutText(" fixupPos=");
			Basic.OutInteger(fixupPos, 0); Basic.OutText(" tdAdr="); Basic.OutHex(tdAdr); Basic.OutLine
		END
	END FixupUsedRecord;
	
	(* export.fingerprint = 0 if not exported *)
	PROCEDURE FindExport(module: Module; fingerprint: LONGINT; VAR export: Export);
	VAR i: LONGINT;
	BEGIN
		export.fingerprint := 0; export.fixup := 0;
		FOR i := 0 TO LEN(module.exports)-1 DO
			IF module.exports[i].fingerprint = fingerprint THEN
				export := module.exports[i]
			END
		END;
		IF export.fingerprint = 0 THEN
			Error(0, "Incompatible modules: element not exported")
		END
	END FindExport;
	
	PROCEDURE Fixup(pos: LONGINT; value: LONGINT);
	VAR a: Basic.Integer4Byte; i, x: LONGINT;
	BEGIN
		FOR i := 0 TO LEN(a)-1 DO
			a[i] := out.GetChar(pos + i)
		END;
		Basic.Decode4ByteInteger(a, x);
		INC(x, value);
		Basic.Encode4ByteInteger(x, a);
		FOR i := 0 TO LEN(a)-1 DO
			out.ChangeChar(pos + i, a[i])
		END
	END Fixup;
	
	(* current may be NIL if not used by a module *)
	PROCEDURE GetKernelCallPos(current: Module; module, procedure: ARRAY OF CHAR): LONGINT;
	VAR m: Module; pos: LONGINT; procRef: ProcedureReference;
	BEGIN
		pos := -1;
		m := modules.FindModule(module);
		IF m # NIL THEN
			IF (current = NIL) OR (modules.IndexOf(current) < modules.IndexOf(m)) THEN
				procRef := m.references.procReferences.FindProcedureReference(procedure);
				IF procRef # NIL THEN
					ASSERT(procRef.offset >= 0);
					pos := m.allocation.codeBasePos + procRef.offset
				ELSE
					Error4(0, "kernel call procedure ", procedure, " not defined in module ", module)
				END
			ELSE
				Error4(0, "kernel call to ", module, " not yet available in module ", current.header.moduleName)
			END 
		ELSE
			Error4(0, "kernel call to ", module, " not available", "")
		END;
		RETURN pos
	END GetKernelCallPos;
	
	(* Component System Support *)	
	PROCEDURE ReadCBC(isComponent: BOOLEAN; name: ARRAY OF CHAR);
	VAR fileName: AosFS.FileName; file: AosFS.File; reader: AosFS.Reader; cbcElement: CBCElement; len, i: LONGINT;
	BEGIN
		IF isComponent THEN ASSERT(cbc.FindComponent(name) = NIL) 
		ELSE ASSERT(cbc.FindInterface(name) = NIL)
		END;
		Utilities.Concat(name, CBCFileSuffix, fileName);
		file := AosFS.Old(fileName);
		IF file # NIL THEN
			len := file.Length();
			AosFS.OpenReader(reader, file, 0);
			NEW(cbcElement); 
			cbcElement.isComponent := isComponent; COPY(name, cbcElement.name);
			NEW(cbcElement.code, len);
			FOR i := 0 TO len-1 DO 
				reader.Char(cbcElement.code[i]) 
			END;
			cbc.Add(cbcElement)
		END
	END ReadCBC;
	
	PROCEDURE InitDefaultPartition(VAR fixup: ImageFixupData);
	BEGIN
		IF partitionName # "" THEN
			out.Char(068X); (* PUSH LEN(partition) *)
			out.Integer4(LEN(partitionName));
		
			out.Char(068X); (* PUSH ADR(partition) *)
			fixup.partitionNameAdrFixupPos := out.Length();
			out.Integer4(0); (* later fixup *)
		END;
		out.Char(0E8X); (* CALL VM.RegisterDefaultPartition or VM.LoadLastPartition *)
		fixup.partitionRegCallFixupPos := out.Length();
		out.Integer4(0) (* fixup later *)
	END InitDefaultPartition;
	
	PROCEDURE InitRegisterCBCCode(VAR fixup: ImageFixupData);
	VAR i, len: LONGINT; elem: CBCElement;
	BEGIN
		len := cbc.Length();
		NEW(fixup.cbcNameAdrFixupPos, len);
		NEW(fixup.cbcCodeAdrFixupPos, len);
		NEW(fixup.cbcRegisterCallFixupPos, len);
		FOR i := 0 TO len-1 DO
			elem := cbc.GetCBCElement(i);
			
			out.Char(06AX); (* PUSH elem.isComponent *)
			IF elem.isComponent THEN out.Char(01X) ELSE out.Char(00X) END;
			
			out.Char(068X); (* PUSH LEN(elem.name) *)
			out.Integer4(LEN(elem.name));
			
			out.Char(068X); (* PUSH ADR(elem.name) *)
			fixup.cbcNameAdrFixupPos[i] := out.Length();
			out.Integer4(0); (* fixup later *)
			
			out.Char(068X); (* PUSH codeAddress *)
			fixup.cbcCodeAdrFixupPos[i] := out.Length();
			out.Integer4(0); (* fixup later *)
			
			out.Char(068X); (* PUSH codeLength *)
			out.Integer4(LEN(elem.code));
			
			out.Char(0E8X); (* CALL VM.RegisterLoadSource *)
			fixup.cbcRegisterCallFixupPos[i] := out.Length();
			out.Integer4(0) (* fixup later *)
		END;
		InitSetupScript(fixup)		
	END InitRegisterCBCCode;
	
	PROCEDURE FinalRegisterCBCFixups(VAR fixup: ImageFixupData);
	VAR i: LONGINT; elem: CBCElement; regProcPos, fixupPos, absValue, relValue: LONGINT;
	BEGIN
		IF cbc.Length() > 0 THEN
			regProcPos := GetKernelCallPos(NIL, RegisterCBCModule, RegisterCBCProcedure);
			FOR i := 0 TO cbc.Length()-1 DO
				elem := cbc.GetCBCElement(i);
				
				fixupPos := fixup.cbcNameAdrFixupPos[i];
				absValue := BaseAddress + elem.allocation.namePos;
				out.ChangeInteger4(fixupPos, absValue);
				
				fixupPos := fixup.cbcCodeAdrFixupPos[i];
				absValue := BaseAddress + elem.allocation.codePos;
				out.ChangeInteger4(fixupPos, absValue);
				
				fixupPos := fixup.cbcRegisterCallFixupPos[i];
				relValue := regProcPos - (fixupPos + 4);
				out.ChangeInteger4(fixupPos, relValue)
			END;
		END;		
		FinalSetupScriptFixups(fixup)
	END FinalRegisterCBCFixups;
	
	PROCEDURE FinalDefaultPartitionFixups(VAR fixup: ImageFixupData);
	VAR regProcPos, fixupPos, relValue, absValue: LONGINT;
	BEGIN
		IF partitionName # "" THEN
			regProcPos := GetKernelCallPos(NIL, RegDefaultPartitionModule, RegDefaultPartitionProcedure);
							
			fixupPos := fixup.partitionNameAdrFixupPos;
			absValue := BaseAddress + partitionNameAllocationPos;
			out.ChangeInteger4(fixupPos, absValue);
		ELSE
			regProcPos := GetKernelCallPos(NIL, LoadLastPartitionModule, LoadLastPartitionProcedure)
		END;
		fixupPos := fixup.partitionRegCallFixupPos;
		relValue := regProcPos - (fixupPos + 4);
		out.ChangeInteger4(fixupPos, relValue)
	END FinalDefaultPartitionFixups;
	
	PROCEDURE InitSetupScript(VAR fixup: ImageFixupData);
	VAR len, i: LONGINT; x: SetupStatement; newStatement: SetupNewStatement; connectStatement: SetupConnectStatement;
	BEGIN
		out.Char(0E8X); (* CALL VM.LinkerLoadSystemComponent *)
		fixup.loadSystemComCallFixupPos := out.Length();
		out.Integer4(0); (* fixup later *)
	
		len := setupScript.Length();
		NEW(fixup.setupCmdName1AdrFixup, len);
		NEW(fixup.setupCmdName2AdrFixup, len);
		NEW(fixup.setupCmdName3AdrFixup, len);
		NEW(fixup.setupCmdCallFixupPos, len);
		FOR i := 0 TO len-1 DO
			x := setupScript.GetSetupStatement(i);
			IF x IS SetupNewStatement THEN
				newStatement := x(SetupNewStatement);
				PushTextParameter(newStatement.instanceName, fixup.setupCmdName1AdrFixup[i]);
				PushTextParameter(newStatement.typeName, fixup.setupCmdName2AdrFixup[i]);
				
				out.Char(0E8X); (* CALL VM.LinkerCreateComponent *)
				fixup.setupCmdCallFixupPos[i] := out.Length();
				out.Integer4(0) (* fixup later *)
			ELSIF x IS SetupConnectStatement THEN
				connectStatement := x(SetupConnectStatement);
				PushTextParameter(connectStatement.interfaceName, fixup.setupCmdName1AdrFixup[i]);
				PushTextParameter(connectStatement.fromInstanceName, fixup.setupCmdName2AdrFixup[i]);
				PushTextParameter(connectStatement.toInstanceName, fixup.setupCmdName3AdrFixup[i]);
				
				out.Char(0E8X); (* CALL VM.LinkerConnectComponents *)
				fixup.setupCmdCallFixupPos[i] := out.Length();
				out.Integer4(0) (* fixup later *)
			ELSE HALT(111)
			END
		END
	END InitSetupScript;
	
	PROCEDURE PushTextParameter(name: Identifier; VAR fixupPos: LONGINT);
	BEGIN
		out.Char(068X); (* PUSH LEN(name) *)
		out.Integer4(LEN(name));
		
		out.Char(068X); (* PUSH ADR(name) *)
		fixupPos := out.Length();
		out.Integer4(0); (* fixup later *)
	END PushTextParameter;
	
	PROCEDURE FinalSetupScriptFixups(VAR fixup: ImageFixupData);
	VAR i: LONGINT; x: SetupStatement; newStatement: SetupNewStatement; connectStatement: SetupConnectStatement;
		loadProcPos, createProcPos, connectProcPos, fixupPos, absValue, relValue: LONGINT;
	BEGIN
		loadProcPos := GetKernelCallPos(NIL, LoadSystemComponentModule, LoadSystemComponentProcedure);
		fixupPos := fixup.loadSystemComCallFixupPos;
		relValue  := loadProcPos - (fixupPos + 4);
		out.ChangeInteger4(fixupPos, relValue);
		
		IF setupScript.Length() > 0 THEN
			createProcPos := GetKernelCallPos(NIL, CreateComponentModule, CreateComponentProcedure);
			connectProcPos := GetKernelCallPos(NIL, ConnectComponentModule, ConnectComponentProcedure);
			FOR i := 0 TO setupScript.Length()-1 DO
				x := setupScript.GetSetupStatement(i);
				IF x IS SetupNewStatement THEN
					newStatement := x(SetupNewStatement);
					
					fixupPos := fixup.setupCmdName1AdrFixup[i];
					absValue := BaseAddress + newStatement.allocation.instanceNamePos;
					out.ChangeInteger4(fixupPos, absValue);
					
					fixupPos := fixup.setupCmdName2AdrFixup[i];
					absValue := BaseAddress + newStatement.allocation.typeNamePos;
					out.ChangeInteger4(fixupPos, absValue);
					
					fixupPos := fixup.setupCmdCallFixupPos[i];
					relValue := createProcPos - (fixupPos + 4);
					out.ChangeInteger4(fixupPos, relValue)
				ELSIF x IS SetupConnectStatement THEN
					connectStatement := x(SetupConnectStatement);
					
					fixupPos := fixup.setupCmdName1AdrFixup[i];
					absValue := BaseAddress + connectStatement.allocation.interfaceNamePos;
					out.ChangeInteger4(fixupPos, absValue);
					
					fixupPos := fixup.setupCmdName2AdrFixup[i];
					absValue := BaseAddress + connectStatement.allocation.fromInstanceNamePos;
					out.ChangeInteger4(fixupPos, absValue);
										
					fixupPos := fixup.setupCmdName3AdrFixup[i];
					absValue := BaseAddress + connectStatement.allocation.toInstanceNamePos;
					out.ChangeInteger4(fixupPos, absValue);
					
					fixupPos := fixup.setupCmdCallFixupPos[i];
					relValue := connectProcPos - (fixupPos + 4);
					out.ChangeInteger4(fixupPos, relValue)
				ELSE HALT(111)
				END
			END
		END
	END FinalSetupScriptFixups;
		
	PROCEDURE AllocateDefaultPartition;
	BEGIN
		IF partitionName # "" THEN
			Align(4);
			partitionNameAllocationPos := out.Length();
			AllocateString(partitionName)
		ELSE
			partitionNameAllocationPos := -1
		END
	END AllocateDefaultPartition;
		
	PROCEDURE AllocateCBC;
	VAR i: LONGINT; cbcElement: CBCElement; statement: SetupStatement; 
	BEGIN
		FOR i := 0 TO cbc.Length()-1 DO
			cbcElement := cbc.GetCBCElement(i);
			AllocateCBCElement(cbcElement)
		END;
		FOR i := 0 TO setupScript.Length()-1 DO
			statement := setupScript.GetSetupStatement(i);
			AllocateSetupStatement(statement)
		END
	END AllocateCBC;
	
	PROCEDURE AllocateCBCElement(element: CBCElement);
	BEGIN
		Align(4);
		element.allocation.namePos := out.Length();
		AllocateString(element.name);
		element.allocation.codePos := out.Length();
		AllocateRawData(element.code);
		IF Trace OR InfoOutput THEN 
			IF element.isComponent THEN Basic.OutText("Component ") ELSE Basic.OutText("Interface ") END;
			Basic.OutText(element.name); Basic.OutText(" codePos="); Basic.OutInteger(element.allocation.codePos); Basic.OutLine
		END
	END AllocateCBCElement;
	
	PROCEDURE AllocateSetupStatement(statement: SetupStatement);
	VAR newStatement: SetupNewStatement; connectStatement: SetupConnectStatement;
	BEGIN
		Align(4);
		IF statement IS SetupNewStatement THEN
			newStatement := statement(SetupNewStatement);
			newStatement.allocation.instanceNamePos := out.Length();
			AllocateString(newStatement.instanceName);
			newStatement.allocation.typeNamePos := out.Length();
			AllocateString(newStatement.typeName)
		ELSIF statement IS SetupConnectStatement THEN
			connectStatement := statement(SetupConnectStatement);
			connectStatement.allocation.interfaceNamePos := out.Length();
			AllocateString(connectStatement.interfaceName);
			connectStatement.allocation.fromInstanceNamePos := out.Length();
			AllocateString(connectStatement.fromInstanceName);
			connectStatement.allocation.toInstanceNamePos := out.Length();
			AllocateString(connectStatement.toInstanceName)
		ELSE HALT(111)
		END
	END AllocateSetupStatement;
	
	PROCEDURE AllocateString(x: ARRAY OF CHAR);
	VAR i: LONGINT;
	BEGIN FOR i := 0 TO LEN(x)-1 DO out.Char(x[i]) END
	END AllocateString;
							
	PROCEDURE Error(pos: LONGINT; text: ARRAY OF CHAR);
	BEGIN Error4(pos, text, "", "", "")
	END Error;
	
	PROCEDURE Error4(pos: LONGINT; a, b, c, d: ARRAY OF CHAR);
	BEGIN 
		error := TRUE; Basic.OutText("Error pos "); Basic.OutInteger(pos); Basic.OutText(" ");
		Basic.OutText(a); Basic.OutText(b); Basic.OutText(c); Basic.OutText(d); Basic.OutLine; HALT(111)
	END Error4;
	
	PROCEDURE PrintHeader(VAR h: Header);
	BEGIN
		Basic.OutText("Header:"); Basic.OutLine;
		Basic.OutText(" refSize="); Basic.OutInteger(h.refSize); Basic.OutLine;
		Basic.OutText(" nofEntries="); Basic.OutInteger(h.nofEntries); Basic.OutLine;
		Basic.OutText(" nofCommands="); Basic.OutInteger(h.nofCommands); Basic.OutLine;
		Basic.OutText(" nofPointers="); Basic.OutInteger(h.nofPointers); Basic.OutLine;
		Basic.OutText(" nofTypes="); Basic.OutInteger(h.nofTypes); Basic.OutLine;
		Basic.OutText(" nofImports="); Basic.OutInteger(h.nofImports); Basic.OutLine;
		Basic.OutText(" nofVarConsLinks="); Basic.OutInteger(h.nofVarConsLinks); Basic.OutLine;
		Basic.OutText(" nofLinks="); Basic.OutInteger(h.nofLinks); Basic.OutLine;
		Basic.OutText(" dataSize="); Basic.OutInteger(h.dataSize); Basic.OutLine;
		Basic.OutText(" exTableLen="); Basic.OutInteger(h.exTableLen); Basic.OutLine;
		Basic.OutText(" constSize="); Basic.OutInteger(h.constSize); Basic.OutLine;
		Basic.OutText(" codeSize="); Basic.OutInteger(h.codeSize); Basic.OutLine;
		Basic.OutText(" moduleName="); Basic.OutText(h.moduleName); Basic.OutLine
	END PrintHeader;
	
	PROCEDURE PrintEntries(entries: Entries);
	VAR i: LONGINT;
	BEGIN
		Basic.OutText("Entries:"); Basic.OutLine;
		FOR i := 0 TO LEN(entries)-1 DO
			Basic.OutText(" entryOffset["); Basic.OutInteger(i); Basic.OutText("]="); Basic.OutHex(entries[i].entryOffset); Basic.OutText("H"); Basic.OutLine
		END
	END PrintEntries;
	
	PROCEDURE PrintCommands(commands: Commands);
	VAR i: LONGINT;
	BEGIN
		Basic.OutText("Commands:"); Basic.OutLine;
		FOR i := 0 TO LEN(commands)-1 DO
			Basic.OutText(" cmdName="); Basic.OutText(commands[i].cmdName);
			Basic.OutText(" cmdOffset="); Basic.OutHex(commands[i].cmdOffset); Basic.OutText("H"); Basic.OutLine
		END
	END PrintCommands;

	PROCEDURE PrintPointers(pointers: Pointers);
	VAR i: LONGINT;
	BEGIN
		Basic.OutText("Pointers:"); Basic.OutLine;
		FOR i := 0 TO LEN(pointers)-1 DO
			Basic.OutText(" offset="); Basic.OutHex(pointers[i].offset); Basic.OutText("H"); Basic.OutLine
		END
	END PrintPointers;
			
	PROCEDURE PrintImports(imports: Imports);
	VAR i: LONGINT;
	BEGIN
		Basic.OutText("Imports:"); Basic.OutLine;
		FOR i := 0 TO LEN(imports)-1 DO
			Basic.OutText(" imports["); Basic.OutInteger(i); Basic.OutText("]="); Basic.OutText(imports[i].moduleName); Basic.OutLine
		END
	END PrintImports;
	
	PROCEDURE PrintVarConstLinks(links: VarConstLinks);
	VAR i, k: LONGINT;
	BEGIN
		Basic.OutText("VarConstLinks:"); Basic.OutLine;
		FOR i := 0 TO LEN(links)-1 DO
			Basic.OutText(" mod="); Basic.OutInteger(links[i].module); Basic.OutText(" entry="); Basic.OutInteger(links[i].entry);
			Basic.OutText(" offsets={");
			FOR k := 0 TO LEN(links[i].offsets)-1 DO
				Basic.OutHex(links[i].offsets[k]); Basic.OutText("H ");
			END;
			Basic.OutText("}"); Basic.OutLine
		END
	END PrintVarConstLinks;
	
	PROCEDURE PrintLinks(links: Links);
	VAR i: LONGINT;
	BEGIN
		Basic.OutText("Links:"); Basic.OutLine;
		FOR i := 0 TO LEN(links)-1 DO
			Basic.OutText(" mod="); Basic.OutInteger(links[i].module); Basic.OutText(" entry="); Basic.OutInteger(links[i].entry);
			Basic.OutText(" offset="); Basic.OutHex(links[i].offset); Basic.OutText("H"); Basic.OutLine
		END
	END PrintLinks;
	
	PROCEDURE PrintExports(exports: Exports);
	VAR i: LONGINT;
	BEGIN
		Basic.OutText("Exports:"); Basic.OutLine;
		FOR i := 0 TO LEN(exports)-1 DO
			Basic.OutText(" fingerprint="); Basic.OutHex(exports[i].fingerprint); 
			Basic.OutText("H fixup="); Basic.OutHex(exports[i].fixup); Basic.OutText("H "); 
			PrintExportRecord(exports[i].record); Basic.OutLine
		END;
	END PrintExports;
	
	PROCEDURE PrintExportRecord(record: ExportRecord);
	VAR i: LONGINT;
	BEGIN
		IF record # NIL THEN
			Basic.OutText(" [ExportRecord tdentry/oldref="); Basic.OutInteger(record.tdentry);
			Basic.OutText(" super="); PrintExportRecord(record.super); 
			IF record.list # NIL THEN
				Basic.OutText(" list={"); 
				FOR i := 0 TO LEN(record.list)-1 DO
					Basic.OutText(" fp="); Basic.OutHex(record.list[i].fingerprint);
					PrintExportRecord(record.list[i].record);
				END;
				Basic.OutText("}");
			END;
			Basic.OutText("]")
		END
	END PrintExportRecord;
	
	PROCEDURE PrintUse(use: UsedModules);
	VAR i, k: LONGINT; usedModule: UsedModule; usedVar: UsedVar; usedProc: UsedProc; usedType: UsedType;
	BEGIN
		Basic.OutText("Use:"); Basic.OutLine;
		FOR i := 0 TO use.Length()-1 DO
			usedModule := use.GetUsedModule(i);
			Basic.OutText(" moduleName="); Basic.OutText(usedModule.moduleName); Basic.OutLine;
			FOR k := 0 TO usedModule.usedVars.Length()-1 DO
				usedVar := usedModule.usedVars.GetUsedVar(k);
				Basic.OutText("  usedVar fingerprint="); Basic.OutHex(usedVar.fingerprint);
				Basic.OutText(" varName="); Basic.OutText(usedVar.varName); 
				Basic.OutText(" fixlist="); Basic.OutInteger(usedVar.fixlist); 
				IF usedVar.usedRecord # NIL THEN PrintUsedRecord(usedVar.usedRecord) END;
				Basic.OutLine
			END;
			FOR k :=  0 TO usedModule.usedProcs.Length()-1 DO
				usedProc := usedModule.usedProcs.GetUsedProc(k);
				Basic.OutText("  usedProc fingerprint="); Basic.OutHex(usedProc.fingerprint);
				Basic.OutText(" procName="); Basic.OutText(usedProc.procName);
				Basic.OutText(" offset="); Basic.OutHex(usedProc.offset); Basic.OutLine
			END;
			FOR k := 0 TO usedModule.usedTypes.Length()-1 DO
				usedType := usedModule.usedTypes.GetUsedType(k);
				Basic.OutText("  usedType fingerprint="); Basic.OutHex(usedType.fingerprint);
				Basic.OutText(" typeName="); Basic.OutText(usedType.typeName); 
				IF usedType.usedRecord # NIL THEN PrintUsedRecord(usedType.usedRecord) END;
				Basic.OutLine
			END
		END
	END PrintUse;
	
	PROCEDURE PrintUsedRecord(usedRecord: UsedRecord);
	BEGIN
		Basic.OutText(" UsedRecord ( tdentry="); Basic.OutHex(usedRecord.tdentry); 
		Basic.OutText(" fingerprint="); Basic.OutHex(usedRecord.fingerprint); 
		Basic.OutText(")"); Basic.OutLine
	END PrintUsedRecord;
	
	PROCEDURE PrintMethods(methods: Methods);
	VAR i: LONGINT;
	BEGIN
		Basic.OutText("methods={");
		FOR i := 0 TO LEN(methods)-1 DO
			Basic.OutText(" methodNumber="); Basic.OutInteger(methods[i].methodNumber);
			Basic.OutText(" entryNumber="); Basic.OutInteger(methods[i].entryNumber);
			IF i < LEN(methods)-1 THEN Basic.OutText(", ") END
		END;
		Basic.OutText("}"); Basic.OutLine
	END PrintMethods;
	
	PROCEDURE PrintTypes(types: Types);
	VAR i: LONGINT;
	BEGIN
		Basic.OutText("Types:"); Basic.OutLine;
		FOR i := 0 TO LEN(types)-1 DO
			Basic.OutText(" size="); Basic.OutInteger(types[i].size);
			Basic.OutText(" tdaddr="); Basic.OutHex(types[i].tdaddr);
			Basic.OutText(" baseModule="); Basic.OutInteger(types[i].baseModule);
			Basic.OutText(" baseEntry="); Basic.OutInteger(types[i].baseEntry);
			Basic.OutText(" nofMethods="); Basic.OutInteger(types[i].nofMethods);
			Basic.OutText(" nofInheritedMethods="); Basic.OutInteger(types[i].nofInheritedMethods);
			Basic.OutText(" nofNewMethods="); Basic.OutInteger(types[i].nofNewMethods);
			Basic.OutText(" nofPointers="); Basic.OutInteger(types[i].nofPointers); Basic.OutLine;
			Basic.OutText(" name="); Basic.OutText(types[i].name); Basic.OutLine;
			PrintMethods(types[i].methods);
			PrintPointers(types[i].pointers)
		END
	END PrintTypes;
	
	PROCEDURE PrintVariableReferences(variables: Variables);
	VAR i: LONGINT; varRef: Variable;
	BEGIN
		FOR i := 0 TO variables.Length()-1 DO
			varRef := variables.GetVariable(i);
			Basic.OutText("  variable varMode="); Basic.OutHex(ORD(varRef.varMode));
			Basic.OutText(" type="); Basic.OutHex(ORD(varRef.type));
			Basic.OutText(" typeTdAdrDim="); Basic.OutInteger(varRef.typeTdAdrDim);
			Basic.OutText(" offset="); Basic.OutHex(varRef.offset);
			Basic.OutText(" name="); Basic.OutText(varRef.name); Basic.OutLine
		END
	END PrintVariableReferences;
	
	PROCEDURE PrintReferences(references: References);
	VAR i: LONGINT; procRef: ProcedureReference;
	BEGIN
		Basic.OutText("References: "); Basic.OutLine;
		Basic.OutText(" BodyRef offset="); Basic.OutHex(references.bodyReference.offset); 
		Basic.OutText(" name="); Basic.OutText(references.bodyReference.name); Basic.OutLine;
		PrintVariableReferences(references.bodyReference.variables);
		FOR i := 0 TO references.procReferences.Length()-1 DO
			procRef := references.procReferences.GetProcedureReference(i);
			Basic.OutText(" ProcRef offset="); Basic.OutHex(procRef.offset);
			Basic.OutText(" nofPars="); Basic.OutInteger(procRef.nofPars);
			Basic.OutText(" retType="); Basic.OutHex(ORD(procRef.retType));
			Basic.OutText(" retTypeTdAdrDim="); Basic.OutInteger(procRef.retTypeTdAdrDim);
			Basic.OutText(" offset="); Basic.OutHex(procRef.offset);
			Basic.OutText(" name="); Basic.OutText(procRef.name); Basic.OutLine;
			PrintVariableReferences(procRef.variables)
		END
	END PrintReferences;
END ComponentLinker.

SystemTools.Free ComponentLinker ~

