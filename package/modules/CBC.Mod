(**
									Component Binary Code
										      May 2007
										     Luc Blaeser
	
	File = FTag FVersion UsedInterfaceList UsedComponentList 
			  NewInterfaceList NewComponentList 
			  Constants Code FixupSection.
	UsedInterfaceList = nofInterfaces<4> { InterfaceSpecification }<nofInterfaces>.
	UsedComponentList = nofComponents<4> { ComponentDefinition }<nofComponents>.
	NewInterfaceList = nofInterfaces<4> { InterfaceSpecification ProtocolStateMatrix }<nofInterfaces>.
	InterfaceSpecification = name<s> MessageDeclList ( FNoProtocol | Protocol ).
	MessageDeclList = nofMessages<4> { MessageDecl }<nofMessages>.
	MessageDecl = ( FIn | FOut ) name<s> ParameterList.
	ParameterList = nofParameters<4> { Type }<nofParameters>.
	Type = FCharacterType | FBooleanType | FIntegerType | FRealType | FTextType 
			| FComponentType name<s> | FAnyType OfferedInterfaces RequiredInterfaces.
	Protocol = FMessageDecl index<4> | FSequence Protocol Protocol | FAlternative Protocol Protocol
					| FRepetition Protocol | FOption Protocol.
	ProtocolStateMatrix = length<4> { entry<1> }<length>.
	NewComponentList = nofComponents<4> { NewComponent }<nofComponents>.
	NewComponent = ComponentDefinition size<4> initializerOffset<4> finalizerOffset<4>.
	ComponentDefinition = name<s> OfferedInterfaces RequiredInterfaces.
	OfferedInterfaces = nofInterfaces<4> { name<s> }<nofInterfaces>.
	RequiredInterfaces = nofInterfaces<4> { name<s> min<4> max<4> }<nofInterfaces>.
	Constants = constantLength<4> { const<1> }<constantLength>.
	Code = codeLength<4> { code<1> }<codeLength>.
	FixupSection = LocalConstFixups LocalCodeFixups SystemCallFixups TemplateFixups InterfaceFixups.
	LocalConstFixups = FixupList.
	LocalCodeFixups = FixupList.
	SystemCallFixups = nofLists<4> { SystemCall (FAbsolute | FRelative) FixupList }<nofLists>.
	TemplateFixups = NamedFixupLists.
	InterfaceFixups = NamedFixupLists.
	NamedFixupLists = nofLists<4> { name<s> FixupList }<nofLists>.
	InterfaceFixups = nofLists
	FixupList = nofFixups<4> { codeOffset<4> }<nofFixups>.
	SystemCall = FCreateProcess | FDeleteProcess | FSuspendReady
						| FCreateComponent | FFinalizeComponent | FDeleteComponent 
						| FAttachComponent | FDetachComponent
						| FCreateText | FDeleteText | FCopyText | FSetTextLength 
						| FSelectTextCharacter | FTextLength | FCharacterToText
						| FCreateCollection | FDeleteCollection | FCreateArray | FDeleteArray
						| FCreateElement | FSelectElement | FExistsElement | FDeleteElement
						| FForeachStart | FForeachContinue | FForeachGetKey | FForeachGetValue | FForeachNext
						| FConnect | FDisconnect | FAwaitDisconnected | FSelectInterface
						| FInterfaceTest | FTypeTest
						| FCreateConnectionList | FDeleteConnectionList | FCountConnections | FSelectIndexedConnection
						| FCreateCommBufferList | FDeleteCommBufferList | FSelectIndexCommunication
						| FOpenCommunication | FCloseCommunication 
						| FSelectFromCommSet | FCloseAndDeleteCommSet
						| FInitCommunicationBuffer
						| FWaitToSend | FWaitToReceive | FCompleteSend | FCompleteReceive 
						| FInputMessage | FCheckProtocol | FAwaitMessage
						| FExtendStack | FReduceStack
						| FAwaitInitializationEnd | FAwaitFinalizationStart | FSignalExternal | FPassivate | FAwait 
						| FLock | FUnlock | FVirtualTime
						| FRandom | FArcSine | FArcCosine
					    | FWriteCharacter | FWriteInteger | FWriteReal | FWriteText | FWriteLine | FWriteHex.
*)

MODULE CBC; (** Component Compiler, Code Generator, 2006-2007 by Luc Blaeser *)
CONST
	FileSuffix* = "CBC";
	
	(* Prolog *)
	FTag* = 0DDX;
	FVersion* = 00DX;
	
	(* Fixups *)
	FAbsolute* = 001X;
	FRelative* = 002X;

	(* Messages *)
	FIn* = 001X;
	FOut* = 002X;
			
	(* Types *)	
	FCharacterType* = 001X;
	FBooleanType* = 002X;
	FIntegerType* = 003X;
	FRealType* = 004X;
	FTextType* = 005X;
	FComponentType* = 006X;
	FAnyType* = 007X;
	
	(* Protocol *)
	FNoProtocol* = 000X;
	FMessageDecl* = 001X;
	FSequence* = 002X;
	FAlternative* = 003X;
	FRepetition* = 004X;
	FOption* = 005X;
	
	(** System calls *)
	FRandom* = 000X; (** Random(low, high: LONGINT): LONGINT *)
	FArcSine* = 001X; (** ArcSine(x: REAL): LONGINT *)
	FArcCosine* = 002X; (** ArcCosine(x: REAL): LONGINT *)
	
	FCreateProcess* = 010X; (** CreateProcess(component: Address; processSize, ebpOffset, espOffset: LONGINT; 
		codePos: Address; servedInterface: InterfaceSpecification): Address *)
	FDeleteProcess* = 011X; (** DeleteProcess(VAR process: Address) *)
	
	FPreempt* = 020X; (** Preempt(process: Address) *)
	FExtendStack* = 021X; (** ExtendStack(VAR extStack: Address; size: LONGINT) *)
	FReduceStack* = 022X; (** ReduceStack(extStack: Address) *)

	FCreateComponent* = 030X; (** CreateComponent(template, superComponent: Address; timesynchronous: BOOLEAN): Address *)
	FFinalizeComponent* = 031X; (** FinalizeComponent(component: Address) *)
	FDeleteComponent* = 032X; (** DeleteComponent(VAR component: Address; currentProcess: Address) *)
	FAttachComponent* = 033X; (** AttachComponent(component, superComponent: Address; timesynchronous: BOOLEAN) *)
	FDetachComponent* = 034X; (** DetachComponent(component, currentProcess: Address) *)
	FInterfaceTest* = 035X; (** InterfaceTest(component: Address; offered: BOOLEAN; interface: InterfaceSpecification; 
												min, max: LONGINT): BOOLEAN *)
			
	FConnect* = 040X; (** Connect(sourceConn, targetConn: Address; currentProcess: Address)  *)
	FDisconnect* = 041X; (** Disconnect(conn: Address; currentProcess: Address) *)
	FAwaitDisconnected* = 042X; (** AwaitDisconnected(currentProcess: Address; conn: Address) *)
	FSelectInterface* = 043X; (** SelectInterface(com: Address; offered: BOOLEAN; interface: InterfaceSpecification): Address *)
	FCountConnections* = 046X; (** CountConnections(conn: Address): LONGINT *)
	FCreateConnectionList* = 047X; (** CreateConnectionList(conn: Address; min, max: LONGINT) *)
	FDeleteConnectionList* = 048X; (** DeleteConnectionList(conn: Address) *)
	FSelectIndexedConnection* = 049X; (** SelectedIndexedConnection(conn: Address; index: LONGINT; currentProcess: Address): Address *)
	FCreateCommBufferList* = 04AX; (** CreateCommBufferList(VAR list: PTR; min, max: LONGINT) *)
	FDeleteCommBufferList* = 04BX; (** DeleteCommBufferList(VAR list: PTR) *)
	FSelectIndexedCommunication* = 04CX; (** SelectIndexedCommunication(list: PTR; index: LONGINT): Address *)
	FCloseCommunicationList* = 04DX; (** CloseCommunicationList(VAR buffer: Address; currentProcess: Address) *)
	
	FCreateText* = 050X; (** CreateText(adr: Address): PTR *)
	FDeleteText* = 051X; (** DeleteText(VAR text: PTR) *)
	FCopyText* = 052X; (** CopyText(text: PTR): PTR *)
	FEqualText* = 053X; (** EqualText(a, b: PTR): BOOLEAN *)
	FLessText* = 054X; (** LessText(a, b: PTR): BOOLEAN *)
	FLessEqualText* = 055X; (** LessEqualText(a, b: PTR): BOOLEAN *)
	FSetTextLength* = 056X; (** SetTextLength(VAR text: PTR; size: LONGINT *)
	FSelectTextCharacter* = 057X; (** SelectTextCharacter(text: PTR; index: LONGINT): Address *)
	FTextLength* = 058X; (** TextLength(x: PTR): LONGINT *)
	FCharacterToText* = 059X; (** CharacterToText(x: CHAR): PTR *)
								
	FCreateCollection* = 060X; (** CreateCollection(keyType[0], .., keyType[nofKeys-1]: LONGINT; VAR coll: PTR; nofKeys, valSize: LONGINT; process: Address) *)
	FDeleteCollection* = 061X; (** DeleteCollection(VAR coll: PTR; process: Address) *)
	FCreateElement* = 062X; (** CreateElement(key[0], .., key[nofKeys-1]: Address; coll: PTR; nofKeys: LONGINT) *)
	FSelectElement* = 063X; (** SelectElement(key[0], .., key[nofKeys-1]: Address; coll: PTR; nofKeys: LONGINT): Address *)
	FExistsElement* = 064X; (** ExistsElement(key[0], .., key[nofKeys-1]: Address; coll: PTR; nofKeys: LONGINT): BOOLEAN *)
	FDeleteElement* = 065X; (** DeleteElement(key[0], .., key[nofKeys-1]: Address; coll: PTR; nofKeys: LONGINT) *)
	FForeachStart* = 066X; (** ForeachStart(coll: Address; VAR rider: LONGINT; isArray: BOOLEAN) *)
	FForeachContinue* = 067X; (** ForeachContinue(coll: Address; rider: LONGINT; isArray: BOOLEAN): BOOLEAN *)
	FForeachGetKey* = 068X; (** ForeachGetKey(keyAdr[0], .., keyAdr[nofKeys-1]: Address; coll: Address; rider: LONGINT; 
													nofKeys: LONGINT; isArray: BOOLEAN) *)
	FForeachGetValue* = 069X; (** ForeachGetValue(coll: Address; rider: LONGINT; isArray: BOOLEAN): Address *)
	FForeachNext* = 06AX; (** ForeachNext(coll: Address; VAR rider: LONGINT; isArray: BOOLEAN) *)
	
	FCreateArray* = 06BX; (** CreateArray(len[0], .., len[nofDims-1]: LONGINT; VAR coll: Address; nofDims, elemSize: LONGINT; nilInit: BOOLEAN) *)
	FDeleteArray* = 06CX; (** DeleteArray(VAR coll: Address) *)
	
	FWaitToSend* = 070X; (** WaitToSend(buffer: Address; currentProcess: Address): Address *)
	FWaitToReceive* = 071X; (** WaitToReceive(buffer: Address; currentProcess: Address): Address *)
	FCompleteSend* = 072X; (** CompleteSend(entryAdr: Address; buffer: Address; currentProcess: Address; messageId: LONGINT) *)
	FCompleteReceive* = 073X; (** CompleteReceive(buffer: Address) *)
	FInputMessage* = 074X; (** InputMessage(buffer: Address; currentProcess: Address): LONGINT *)
	FOpenCommunication* = 075X; (** OpenCommunication(conn: Address; VAR buffer: Address; currentProcess: Address) *)
	FCloseCommunication* = 076X; (** CloseCommunication(VAR buffer: Address; currentProcess: Address) *)
	FAwaitMessage* = 077X; (* AwaitMessage(buffer: Address; currentProcess: Address; exclusiveLock: BOOLEAN): Address *)
	FInitCommunicationBuffer* = 07DX; (** InitializeCommunicationBuffer(buffer: Address; interface: InterfaceSpecification) *)
	FSelectFromCommSet* = 07EX; (** SelectFromCommSet(instanceAdr, setAdr: Address; bufferIndex: LONGINT): Address *)
	FCloseAndDeleteCommSet* = 07FX; (** CloseAndDeleteCommSet(setAdr: Address; currentProcess: Address) *)
	
	FWriteLine* = 080X; (** WriteLine *)
	FWriteCharacter* = 081X; (** WriteCharacter(c: CHAR) *)
	FWriteInteger* = 082X; (** WriteInteger(x: LONGINT) *)
	FWriteReal* = 083X; (** WriteReal(x: REAL) *)
	FWriteText* = 084X; (** WriteText(x: PTR) *)
	FWriteHex* = 085X; (** WriteHex(x: LONGINT) *)

	FAwaitInitializationEnd* = 08DX; (* AwaitInitializationEnd(process: Address) *)
	FAwaitFinalizationStart* = 08EX; (* AwaitFinalizationStart(process: Address) *)
	FSignalExternal* = 08FX; (* SignalExternal(component: Address) *)

	FPassivate* = 093X; (* Passivate(process: Address; duration: LONGINT; lockType: SHORTINT) *)
	FAwait* = 094X; (* Await(process: Address; exclusiveLock: BOOLEAN; awaitEBP, awaitPC: Address) *)
	FLock* = 095X; (* Lock(process: Address; exclusiveLock: BOOLEAN) *)
	FUnlock* = 096X; (* Unlock(process: Address; exclusiveLock: BOOLEAN) *)
	FVirtualTime* = 099X; (* VirtualTime(component: Address): LONGINT *)
END CBC.

