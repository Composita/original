MODULE CCIx86CG; (** Component Compiler, Intel x86 Backend Code Generator, 2005-2007 by Luc Blaeser *)
	IMPORT A := CCIx86A, CCBasic;
	
	CONST Trace = FALSE;
	
	CONST
		(* procedure-specific, relative to EBP *)
		ProcessParameterOffset* = 2*4;
		ComponentParameterOffset* = 3*4;
		(* for procedure *)
		CommunicationSetParamOffset* =  4*4; 
		StackReserveParameterOffset* = 5*4;
		StaticLinkParameterOffset* = 6*4;
		(* for implementation *)
		ProcessTailCommBufferOffset* = 4*4;
			
	CONST 
		MaxEvaluationStackSize = 128;
		MaxSwapElements = 4;
		
		TrueValue* = 1;
		FalseValue* = 0;
		
		NilValue* = 0;

	TYPE
		Register = A.Register;
		Operand = A.Operand;
		
	CONST
		OpTypeReg = A.OpTypeReg; OpTypeDeref = A.OpTypeDeref; 
		OpTypeImm = A.OpTypeImm; OpTypeFPU = A.OpTypeFPU;
		
		EAX = A.EAX; EBX = A.EBX; ECX = A.ECX; EDX = A.EDX; 
		EBP = A.EBP; ESP = A.ESP; ESI = A.ESI; EDI = A.EDI;
		AL = A.AL; BL = A.BL; CL = A.CL; DL = A.DL;
		AH = A.AH; BH = A.BH; CH = A.CH; DH = A.DH;
		AX = A.AX; BX = A.BX; CX = A.CX; DX = A.DX;
		BP = A.BP; SP = A.SP; SI = A.SI; DI = A.DI0;
		
		ADD = A.ADD; AND = A.AND; CALL = A.CALL; CDQ = A.CDQ;
		CMP = A.CMP; IDIV = A.IDIV; IMUL = A.IMUL; JMP = A.JMP;
		JNL = A.JNL; JNZ = A.JNZ; JZ = A.JZ; JNLE = A.JNLE; JL = A.JL;
		MOV = A.MOV; NEG = A.NEG; POP = A.POP; PUSH = A.PUSH; 
		RET = A.RET; SAL = A.SAL; SAR = A.SAR; SHR = A.SHR; SBB = A.SBB; 
		SETL = A.SETL; SETLE = A.SETLE; SETNL = A.SETNL; 
		SETNLE = A.SETNLE; SETNZ = A.SETNZ; SETZ = A.SETZ;
		SUB = A.SUB; XOR = A.XOR; DECx = A.DECx; INCx = A.INCx; 
		NOP = A.NOP; XCHG = A.XCHG; PAUSE = A.PAUSE; INT = A.INT; 
		OUT = A.OUT; MOVSX = A.MOVSX; 
		FLD = A.FLD; FILD = A.FILD; FSTP = A.FSTP; 
		FADD = A.FADD; FSUB = A.FSUB; FMUL = A.FMUL; FDIV = A.FDIV; 
		FADDP = A.FADDP; FSUBP = A.FSUBP; FMULP = A.FMULP; FDIVP = A.FDIVP;
		FCHS = A.FCHS; FWAIT = A.FWAIT; FNSTCW = A.FNSTCW; FLDCW = A.FLDCW; 
		FISTP = A.FISTP; FXCH = A.FXCH; FCOMP = A.FCOMP; FCOMPP = A.FCOMPP; 
		FNSTSW = A.FNSTSW; SAHF = A.SAHF; SETB = A.SETB; SETBE = A.SETBE; 
		SETNBE = A.SETNBE; SETNB = A.SETNB; OR0 = A.OR0;
		FSIN = A.FSIN; FCOS = A.FCOS; FSQRT = A.FSQRT; FPATAN = A.FPATAN;
		FSINCOS = A.FSINCOS; FABS = A.FABS;

	TYPE				
		RegisterSet = SET (* OF Register *);
		
		EvaluationStack = OBJECT
			VAR 
				stack: ARRAY MaxEvaluationStackSize OF Operand; 
				stackHeight, spillHeight: LONGINT;
				generalRegisters, reservedRegisters: RegisterSet;
				spillingAllowed: BOOLEAN;
			
			PROCEDURE &InitEvaluationStack;
			BEGIN 
				stackHeight := 0; spillHeight := 0;
				generalRegisters := {EAX, EBX, ECX, EDX, AX, BX, CX, DX, AH, AL, BH, BL, CH, CL, DH, DL}; reservedRegisters := {};
				spillingAllowed := TRUE
			END InitEvaluationStack;
						
			PROCEDURE ReserveRegister(reg: Register);
			BEGIN
				ASSERT(~(reg IN reservedRegisters)); ASSERT(reg IN generalRegisters);
				IF A.Is32BitRegister(reg) THEN
					INCL(reservedRegisters, reg);
					INCL(reservedRegisters, A.ConvertTo16Reg(reg));
					INCL(reservedRegisters, A.ConvertToLow(reg)); 
					INCL(reservedRegisters, A.ConvertToHigh(reg))
				ELSIF A.Is16BitRegister(reg) THEN
					INCL(reservedRegisters, A.ConvertToExtended(reg));
					INCL(reservedRegisters, reg);
					INCL(reservedRegisters, A.ConvertToLow(reg));
					INCL(reservedRegisters, A.ConvertToHigh(reg))
				ELSIF A.Is8BitRegister(reg) THEN
					INCL(reservedRegisters, A.ConvertToExtended(reg));
					INCL(reservedRegisters, A.ConvertTo16Reg(reg));
					INCL(reservedRegisters, reg);
					(* allow other low or high register part *)
				ELSE HALT(111)
				END
			END ReserveRegister;
			
			PROCEDURE FreeRegister(reg: Register);
			BEGIN
				ASSERT(reg IN reservedRegisters); ASSERT(reg IN generalRegisters);
				IF A.Is32BitRegister(reg) THEN
					EXCL(reservedRegisters, reg);
					EXCL(reservedRegisters, A.ConvertTo16Reg(reg));
					EXCL(reservedRegisters, A.ConvertToLow(reg));
					EXCL(reservedRegisters, A.ConvertToHigh(reg))
				ELSIF A.Is16BitRegister(reg) THEN
					EXCL(reservedRegisters, A.ConvertToExtended(reg));
					EXCL(reservedRegisters, reg);
					EXCL(reservedRegisters, A.ConvertToLow(reg));
					EXCL(reservedRegisters, A.ConvertToHigh(reg))
				ELSIF A.Is8BitRegister(reg) THEN
					EXCL(reservedRegisters, reg);
					(* free extended register if both low and high are free *)
					IF ~(A.ConvertToLow(reg) IN reservedRegisters) & ~(A.ConvertToHigh(reg) IN reservedRegisters) THEN
						EXCL(reservedRegisters, A.ConvertTo16Reg(reg));
						EXCL(reservedRegisters, A.ConvertToExtended(reg))
					END
				ELSE HALT(111)
				END;
				ASSERT(IsFree(reg));
			END FreeRegister;
			
			PROCEDURE Push(x: Operand);
			BEGIN
				IF (x.type IN {OpTypeReg, OpTypeDeref}) & (x.reg IN generalRegisters) THEN
					ASSERT(x.reg IN reservedRegisters) (* register must be reserved *)
				END;
				ASSERT(stackHeight < LEN(stack)); (* stack overflow, implementation restriction *)
				stack[stackHeight] := x;
				INC(stackHeight)
			END Push;
			
			PROCEDURE Pop(): Operand;
			VAR x: Operand;
			BEGIN
				ASSERT(stackHeight > 0); (* stack underflow, generator error *)
				IF spillHeight = stackHeight THEN Unspill END;
				DEC(stackHeight);
				x := stack[stackHeight];
				IF (x.type IN {OpTypeReg, OpTypeDeref}) & (x.reg IN generalRegisters) THEN
					ASSERT(x.reg IN reservedRegisters) (* register must be reserved *)
				END;
				RETURN x
			END Pop;
			
			PROCEDURE PopAndDiscard;
			VAR isSpilled: BOOLEAN; x: Operand;
			BEGIN
				ASSERT(stackHeight > 0);
				isSpilled := spillHeight = stackHeight;
				IF isSpilled THEN 
					ASSERT(spillingAllowed);
					IF Spillable(stack[spillHeight-1]) THEN
						Emit2(ADD, A.RegOp(ESP), A.Imm32Op(4));
						DecProcedureStackSize(4)
					END;
					DEC(spillHeight) 
				END;
				DEC(stackHeight);
				x := stack[stackHeight];
				IF ~isSpilled & (x.type IN {OpTypeReg, OpTypeDeref}) & (x.reg IN generalRegisters) THEN
					ASSERT(x.reg IN reservedRegisters);
					Free(x)
				END
			END PopAndDiscard;
			
			PROCEDURE Spill;
			BEGIN
				ASSERT(spillingAllowed); 
				IF Trace THEN
					CCBasic.OutText("Spill spillHeight="); CCBasic.OutInteger(spillHeight); 
					CCBasic.OutText(" stackHeight="); CCBasic.OutInteger(stackHeight); CCBasic.OutLine
				END;
				ASSERT(spillHeight < stackHeight);
				IF Spillable(stack[spillHeight]) THEN
					PushRegister(stack[spillHeight].reg);
					INC(spillHeight);
					FreeRegister(stack[spillHeight-1].reg)
				ELSIF stack[spillHeight].type = OpTypeFPU THEN 
					HALT(111) 
						(* saving FPU registers not implemented:
								determine depth of current FPU register in FPU
								FLD ST(depth) 
								SUB ESP, 4
								FSTP 0[ESP]
						*)
				ELSE
					INC(spillHeight)
				END
			END Spill;
			
			PROCEDURE PushRegister(reg: Register);
			VAR pushReg: Register;
			BEGIN
				IF ~A.Is32BitRegister(reg) THEN
					pushReg := A.ConvertToExtended(reg)
				ELSE
					pushReg := reg
				END;
				Emit1(PUSH, A.RegOp(pushReg));
				IncProcedureStackSize(4)
			END PushRegister;
						
			PROCEDURE Unspill;
			VAR newReg: Register;
			BEGIN
				ASSERT(spillingAllowed); 
				IF Trace THEN
					CCBasic.OutText("Unspill spillHeight="); CCBasic.OutInteger(spillHeight); 
					CCBasic.OutText(" stackHeight="); CCBasic.OutInteger(stackHeight); CCBasic.OutLine
				END;
				ASSERT(spillHeight > 0);
				IF Spillable(stack[spillHeight-1]) THEN
					PopRegister(stack[spillHeight-1].reg);
					ReserveRegister(stack[spillHeight-1].reg)
				ELSIF stack[spillHeight-1].type = OpTypeFPU THEN
					HALT(111)
						(* restoring FPU registers not implemented:
							determine current size of entire FPU stack:
							FLD 0[ESP]
							ADD ESP, 4
							FSTP ST(size)
						*)
				END;
				DEC(spillHeight)
			END Unspill;
			
			PROCEDURE PopRegister(VAR reg: Register);
			VAR popReg: Register;
			BEGIN
				IF ~A.Is32BitRegister(reg) THEN
					popReg := A.ConvertToExtended(reg)
				ELSE
					popReg := reg
				END;
				IF popReg IN reservedRegisters THEN
					(* evacuate to new register *)
					IF Trace THEN 
						CCBasic.OutText("Evacuate spilled element "); A.WriteRegister(reg)
					END;
					popReg := ReserveAnyRegister(32);
					FreeRegister(popReg);
					IF A.IsLow8BitRegister(reg) THEN
						reg := A.ConvertToLow(popReg)
					ELSIF A.IsHigh8BitRegister(reg) THEN
						reg := A.ConvertToHigh(popReg)
					ELSIF A.Is16BitRegister(reg) THEN	
						reg := A.ConvertTo16Reg(popReg)
					ELSE
						reg := popReg
					END;
					IF Trace THEN
						CCBasic.OutText(" -> "); CCBasic.OutInteger(reg); CCBasic.OutLine
					END;
				END;
				Emit1(POP, A.RegOp(popReg));
				DecProcedureStackSize(4)
			END PopRegister;
			
			PROCEDURE Spillable(op: Operand): BOOLEAN;
			BEGIN RETURN (op.type IN {OpTypeReg, OpTypeDeref}) & (op.reg IN generalRegisters)
			END Spillable;
			
			PROCEDURE IsFree(reg: Register): BOOLEAN;
			VAR i: LONGINT;
			BEGIN 
				IF ~(reg IN reservedRegisters) THEN
					FOR i := spillHeight TO stackHeight-1 DO
						IF stack[i].type IN {OpTypeReg, OpTypeDeref} THEN
							ASSERT(stack[i].reg # reg) (* register still used on stack *)
						END
					END
				END;
				RETURN ~(reg IN reservedRegisters)
			END IsFree;
			
			PROCEDURE ReserveSpecificRegister(reg: Register);
			BEGIN
				WHILE ~IsFree(reg) DO Spill END; (* spill until available *)
				ReserveRegister(reg)
			END ReserveSpecificRegister;
			
			PROCEDURE ReserveAnyRegister(bits: SHORTINT): Register;
			VAR r: Register; i: LONGINT;
			BEGIN
				FOR r := 0 TO 31 DO
					IF (r IN generalRegisters) & IsFree(r) & (A.RegisterSizeInBits(r) = bits) THEN
						ReserveSpecificRegister(r);
						RETURN r
					END
				END;
				FOR i := spillHeight TO stackHeight-1 DO (* look upwards starting from bottom of stack *)
					IF Spillable(stack[i]) THEN
						r := stack[i].reg;
						IF (r IN generalRegisters) & (A.RegisterSizeInBits(r) = bits) THEN
							ReserveSpecificRegister(r);
							RETURN r
						END
					END
				END;
				HALT(333) (* out of free registers *)
			END ReserveAnyRegister;
			
			PROCEDURE SaveAllRegisters(except: LONGINT);
			BEGIN WHILE spillHeight < stackHeight - except DO Spill END
			END SaveAllRegisters;
		
			PROCEDURE AllRegistersSaved(except: LONGINT): BOOLEAN;
			BEGIN RETURN spillHeight >= stackHeight - except
			END AllRegistersSaved;
		END EvaluationStack;
		
		FixupReference* = OBJECT (** abstract *)
			VAR 
				list-: FixupList;
				stackHeight: LONGINT;
			
			PROCEDURE &InitFixupReference(l: FixupList);
			BEGIN list := l; stackHeight := -1 (* uninitialized *)
			END InitFixupReference;
		END FixupReference;
		
		Fixup* = OBJECT
			VAR
				codePos-: LONGINT; 
				relative-: BOOLEAN;
				reference-: FixupReference;
			
			PROCEDURE &InitFixup*(pos: LONGINT; relFixup: BOOLEAN; ref: FixupReference);
			BEGIN codePos := pos; relative := relFixup; reference := ref
			END InitFixup;
		END Fixup;
		
		FixupList* = OBJECT(CCBasic.List)
			PROCEDURE Add*(x: ANY);
			BEGIN ASSERT(x IS Fixup); Add^(x)
			END Add;
			
			PROCEDURE GetFixup*(index: LONGINT): Fixup;
			VAR ptr: ANY;
			BEGIN ptr := GetItem(index); RETURN ptr(Fixup)
			END GetFixup;
			
			PROCEDURE SelectFixups*(relative: BOOLEAN): CCBasic.LongIntList;
			VAR i: LONGINT; x: Fixup; list: CCBasic.LongIntList;
			BEGIN
				NEW(list);
				FOR i := 0 TO Length()-1 DO
					x := GetFixup(i);
					IF x.relative = relative THEN list.Add(x.codePos) END
				END;
				RETURN list
			END SelectFixups;
		END FixupList;
		
		ProcedureStack = RECORD
			currentSize, maxSize: LONGINT
		END;
		
	VAR
		code: CCBasic.DataSequence;
		stack: EvaluationStack;
		procedureStack: ProcedureStack;

	PROCEDURE InitProcedureStack;
	BEGIN procedureStack.currentSize := 0; procedureStack.maxSize := 0
	END InitProcedureStack;
	
	PROCEDURE IncProcedureStackSize(size: LONGINT);
	BEGIN
		INC(procedureStack.currentSize, size);
		IF procedureStack.currentSize > procedureStack.maxSize THEN
			procedureStack.maxSize := procedureStack.currentSize
		END
	END IncProcedureStackSize;

	PROCEDURE DecProcedureStackSize(size: LONGINT);
	BEGIN 
		ASSERT(size >= 0); 
		DEC(procedureStack.currentSize, size);
		ASSERT(procedureStack.currentSize >= 0)
	END DecProcedureStackSize;
	
	PROCEDURE MaxStackSize*(): LONGINT;
	BEGIN RETURN procedureStack.maxSize
	END MaxStackSize;

	PROCEDURE Push(op: Operand);
	BEGIN stack.Push(op)
	END Push;
	
	PROCEDURE Pop(VAR op: Operand);
	BEGIN op := stack.Pop()
	END Pop;
	
	PROCEDURE Free(op: Operand);
	BEGIN
		IF (op.type IN {OpTypeReg, OpTypeDeref}) & (op.reg IN stack.generalRegisters) THEN
			stack.FreeRegister(op.reg)
		END
	END Free;
						
	(* Code Operations *)
	
	PROCEDURE CodePos*(): LONGINT;
	BEGIN RETURN code.Length()
	END CodePos;
		
	PROCEDURE Emit0(instr: A.Instruction);
	BEGIN A.Emit0(code, instr);
	END Emit0;
	
	PROCEDURE Emit1ForFixup(instr: A.Instruction; x: Operand; VAR immPos: LONGINT);
	BEGIN 
		A.Emit1(code, instr, x, immPos);
		AddFixup(x, immPos)
	END Emit1ForFixup;
	
	PROCEDURE Emit1(instr: A.Instruction; x: Operand);
	VAR immPos: LONGINT;
	BEGIN Emit1ForFixup(instr, x, immPos);
	END Emit1;
	
	PROCEDURE Emit2ForFixup(instr: A.Instruction; x, y: Operand; VAR immPos: LONGINT);
	BEGIN 
		A.Emit2(code, instr, x, y, immPos);
		AddFixup(x, immPos); AddFixup(y, immPos)
	END Emit2ForFixup;
	
	PROCEDURE Emit2(instr: A.Instruction; x, y: Operand);
	VAR immPos: LONGINT;
	BEGIN Emit2ForFixup(instr, x, y, immPos)
	END Emit2;
	
	PROCEDURE Emit3ForFixup(instr: A.Instruction; x, y, z: Operand; VAR immPos: LONGINT);
	BEGIN 
		A.Emit3(code, instr, x, y, z, immPos);
		AddFixup(x, immPos); AddFixup(y, immPos); AddFixup(z, immPos)
	END Emit3ForFixup;
	
	PROCEDURE Emit3(instr: A.Instruction; x, y, z: Operand);
	VAR immPos: LONGINT;
	BEGIN Emit3ForFixup(instr, x, y, z, immPos)
	END Emit3;
	
	PROCEDURE AddFixup(op: Operand; pos: LONGINT);
	VAR fixup: Fixup; ref: FixupReference;
	BEGIN
		IF op.fixup.target # NIL THEN
			ref := op.fixup.target(FixupReference);
			NEW(fixup, pos, op.fixup.relative, ref);
			ref.list.Add(fixup)
		END
	END AddFixup;

	PROCEDURE LoadToRegister*;
	VAR old, new: Operand; reg: Register;
	BEGIN
		Pop(old);
		IF old.type # OpTypeReg THEN
			Free(old);
			reg := stack.ReserveAnyRegister(old.bits);
			new := A.RegOp(reg);
			Emit2(MOV, new, old)
		ELSE
			new := old
		END;
		Push(new)
	END LoadToRegister;
	
	PROCEDURE LoadToNewRegister(old: Operand): Operand;
	VAR reg: Register; new: Operand;
	BEGIN
		reg := stack.ReserveAnyRegister(old.bits); 
		new := A.RegOp(reg);
		Emit2(MOV, new, old);
		RETURN new
	END LoadToNewRegister;
	
	PROCEDURE LoadToSpecificRegister(reg: Register);
	VAR old, new: Operand;
	BEGIN
		Pop(old);
		IF ~IsRegister(old, reg) THEN
			Free(old);
			stack.ReserveSpecificRegister(reg);
			new :=  A.RegOp(reg);
			Emit2(MOV, new, old)
		ELSE
			new := old
		END;
		Push(new)
	END LoadToSpecificRegister;
	
	PROCEDURE RegisterOrDeref;
	VAR op: Operand;
	BEGIN
		Pop(op);
		Push(op);
		IF ~(op.type IN {OpTypeReg, OpTypeDeref, OpTypeFPU}) THEN
			LoadToRegister
		END
	END RegisterOrDeref;

	PROCEDURE RegisterOrImm;
	VAR op: Operand;
	BEGIN
		Pop(op);
		Push(op);
		IF ~(op.type IN {OpTypeReg, OpTypeImm, OpTypeFPU}) THEN
			LoadToRegister
		END
	END RegisterOrImm;
	
	PROCEDURE AssertDeref;
	VAR op: Operand;
	BEGIN
		Pop(op);
		ASSERT(op.type = A.OpTypeDeref);
		Push(op)
	END AssertDeref;
						
	(** Main Generation Interface *)

	PROCEDURE Initialize*(codeSection: CCBasic.DataSequence);
	BEGIN code := codeSection; NEW(stack)
	END Initialize;
	
	PROCEDURE Finish*;
	BEGIN code := NIL; stack := NIL
	END Finish;
	
	PROCEDURE ProcedureProlog*(localSize: LONGINT);
	VAR words, i, startPos, fixupPos: LONGINT;
	BEGIN
		ASSERT(localSize MOD 4 = 0);
		InitProcedureStack;
		IncProcedureStackSize(localSize + 4); (* dynamic link, EBP backup *)
		Emit1(PUSH, A.RegOp(EBP));
		Emit2(MOV, A.RegOp(EBP), A.RegOp(ESP));
		
		(* clear stack area for local variables *)
		words := localSize DIV 4;
		IF words > 0 THEN
			Emit2(XOR, A.RegOp(EAX), A.RegOp(EAX));
			IF words <= 7 THEN
				FOR i := 1 TO words DO 
					Emit1(PUSH, A.RegOp(EAX))
				END
			ELSE
				Emit2(MOV, A.RegOp(ECX), A.Imm32Op(words DIV 4));
				FOR i := 1 TO words MOD 4 DO
					Emit1(PUSH, A.RegOp(EAX))
				END;
				startPos := code.Length();
				Emit1(DECx, A.RegOp(ECX));
				FOR i := 1 TO 4 DO
					Emit1(PUSH, A.RegOp(EAX))
				END;
				Emit1ForFixup(JNZ, A.Imm32Op(0), fixupPos);
				code.ChangeInteger4(fixupPos, startPos - code.Length())
			END
		END
	END ProcedureProlog;
	
	PROCEDURE ProcedureEpilog*(paramSize: LONGINT);
	BEGIN
		ASSERT(paramSize MOD 4 = 0);
		Emit2(MOV, A.RegOp(ESP), A.RegOp(EBP));
		Emit1(POP, A.RegOp(EBP));
		IF paramSize = 0 THEN
			Emit0(RET)
		ELSE 
			Emit1(RET, A.Imm16Op(A.Imm16(paramSize)))
		END
	END ProcedureEpilog;
	
	PROCEDURE EndInstruction*;
	BEGIN 
		ASSERT(stack.stackHeight = 0); 
		ASSERT(stack.reservedRegisters = {})
	END EndInstruction;
	
	PROCEDURE Duplicate*;
	VAR op, copy: Operand; reg: Register;
	BEGIN
		Pop(op);
		IF op.type = OpTypeReg THEN
			reg := stack.ReserveAnyRegister(op.bits);
			copy := A.RegOp(reg);
			Emit2(MOV, copy, op)
		ELSIF op.type = OpTypeDeref THEN
			reg := stack.ReserveAnyRegister(32);
			Emit2(MOV, A.RegOp(reg), A.RegOp(op.reg));
			copy := A.DerefOp(reg, op.const, op.bits)
		ELSIF op.type = OpTypeImm THEN
			copy := op
		ELSE HALT(111)
		END;
		Push(op);
		Push(copy)
	END Duplicate;
	
	PROCEDURE Swap*(nofElements: LONGINT);
	VAR i: LONGINT; op: ARRAY MaxSwapElements OF Operand;
	BEGIN
		FOR i := 0 TO nofElements-1 DO Pop(op[i]) END;
		FOR i := 0 TO nofElements-1 DO Push(op[i]) END
	END Swap;
	
	PROCEDURE Discard*;
	BEGIN stack.PopAndDiscard
	END Discard;
	
	PROCEDURE LoadAddress*(ref: FixupReference; offset: LONGINT);
	VAR op: Operand;
	BEGIN 
		op := A.Imm32Op(offset); op.fixup.target := ref; op.fixup.relative := FALSE;
		Push(op)
	END LoadAddress;
	
	(** Load 4-byte integer *)
	PROCEDURE LoadInteger4*(integer: LONGINT);
	VAR op: Operand;
	BEGIN op := A.Imm32Op(integer); Push(op)
	END LoadInteger4;
	
	(** Load 1-byte integer *)
	PROCEDURE LoadInteger1*(integer: SHORTINT);
	VAR op: Operand;
	BEGIN op := A.Imm8Op(integer); Push(op)
	END LoadInteger1;
		
	PROCEDURE GetAddress*;
	VAR op, temp: Operand;
	BEGIN 
		Pop(op); ASSERT(op.type = OpTypeDeref);
		Free(op);
		temp := A.RegOp(stack.ReserveAnyRegister(32));
		IF temp.reg # op.reg THEN
			Emit2(MOV, temp, A.RegOp(op.reg))
		END;
		IF op.const < 0 THEN
			Emit2(SUB, temp, A.Imm32Op(-op.const))
		ELSIF op.const > 0 THEN
			Emit2(ADD, temp, A.Imm32Op(op.const))
		ELSE (* ok *)
		END;
		Push(temp)
	END GetAddress;
	
	PROCEDURE Deref*(offset, derefSize: LONGINT);
	VAR op: Operand;
	BEGIN
		LoadToRegister;
		Pop(op); 
		op := A.DerefOp(op.reg, offset, A.BytesToBits(derefSize));
		Push(op)
	END Deref;
		
	PROCEDURE MakeDeref*(bytes: LONGINT);
	VAR op: Operand;
	BEGIN
		LoadToRegister;
		Pop(op); 
		op := A.DerefOp(op.reg, 0, A.BytesToBits(bytes));
		Push(op)
	END MakeDeref;
	
	PROCEDURE Convert*(bytes: LONGINT);
	VAR old, new: Operand; bits: SHORTINT;
	BEGIN
		Pop(old);
		bits := A.BytesToBits(bytes);
		IF old.bits < bits THEN
			new := A.RegOp(stack.ReserveAnyRegister(bits));
			Emit2(XOR, new, new); 
			Emit2(MOV, A.RegOp(A.ConvertToLow(new.reg)), old);
			Emit2(MOVSX, new, A.RegOp(A.ConvertTo16Reg(new.reg))); (* sign adjusting *)
			Free(old)
		ELSIF old.bits > bits THEN
			IF old.type = OpTypeReg THEN
				Free(old);
				new := A.RegOp(A.ConvertToLow(old.reg));
				stack.ReserveSpecificRegister(new.reg);
				ASSERT(~stack.IsFree(old.reg))
			ELSE
				new := old; new.bits := 8
			END
		ELSE new := old
		END;
		Push(new)
	END Convert;
	
	PROCEDURE ConvertIntegerToReal*;
	VAR op: Operand;
	BEGIN
		Pop(op);
		ASSERT(op.type # OpTypeFPU);
		LoadToFPU(FILD, op); 
		Free(op); op := A.FPUOp();
		Push(op)
	END ConvertIntegerToReal;
	
	PROCEDURE ConvertRealToInteger*;
	VAR old, new: Operand;
	BEGIN
		Pop(old);
		LoadToFPU(FLD, old); 
		Free(old); old := A.FPUOp();
		new := A.RegOp(stack.ReserveAnyRegister(32));
		Emit2(SUB, A.RegOp(ESP), A.Imm32Op(8));
		IncProcedureStackSize(8);
		Emit1(FNSTCW, A.DerefOp(ESP, 0, 32));
		Emit0(FWAIT);
		Emit2(MOV, new, A.DerefOp(ESP, 0, 32));
		Emit2(AND, new, A.Imm32Op(0000F3FFH));
		Emit2(OR0, new, A.Imm32Op(00000400H));
		Emit2(MOV, A.DerefOp(ESP, 4, 32), new);
		Emit1(FLDCW, A.DerefOp(ESP, 4, 32));
		Emit1(FISTP, A.DerefOp(ESP, 4, 32));
		Emit0(FWAIT);
		Emit1(FLDCW, A.DerefOp(ESP, 0, 32));
		Emit1(POP, new);
		Emit1(POP, new);
		DecProcedureStackSize(8);
		Push(new);
		Free(old)
	END ConvertRealToInteger;
	
	(** Save all temporary registers except a defined number of top most stack elements *)
	PROCEDURE SaveTemporary*(except: LONGINT);
	BEGIN stack.SaveAllRegisters(except)
	END SaveTemporary;

	PROCEDURE Call*(ref: FixupReference; nofParameters, calleeStackSize: LONGINT);
	BEGIN CallWithAdditionalParameters(ref, nofParameters, 0, calleeStackSize)
	END Call;

	(** additional parameters are not removed by callee and must be explicitly removed after call *)
	PROCEDURE CallWithAdditionalParameters*(ref: FixupReference; normalParameters, 
		additionalParameters, calleeStackSize: LONGINT);
	VAR op: Operand; nofParameters, i: LONGINT;
	BEGIN
		nofParameters := normalParameters + additionalParameters;
		ASSERT(stack.AllRegistersSaved(nofParameters));
		stack.spillingAllowed := FALSE;
		FOR i := 0 TO nofParameters-1 DO
			PushParameter(stack.stackHeight - nofParameters + i, i)
		END;
		IncProcedureStackSize(nofParameters * 4 + 4 + calleeStackSize); (* parameters, return PC, callee stack size *)
		DecProcedureStackSize(nofParameters * 4 + 4 + calleeStackSize);
		op := A.Imm32Op(0); op.fixup.target := ref; op.fixup.relative := TRUE;
		Emit1(CALL, op);
		IF additionalParameters > 0 THEN
			Emit2(ADD, A.RegOp(ESP), A.Imm32Op(4 * additionalParameters))
		END;
		DecProcedureStackSize(4 * nofParameters);
		stack.spillingAllowed := TRUE;
		FOR i := 1 TO nofParameters DO
			stack.PopAndDiscard
		END;
		ASSERT(stack.reservedRegisters = {})
	END CallWithAdditionalParameters;
	
	PROCEDURE PushParameter(stackPos: LONGINT; nofParameter: LONGINT);
	VAR k, spilled, offset: LONGINT; stackOp: Operand; reg: Register;
	BEGIN
		ASSERT(~stack.spillingAllowed);
		ASSERT((stackPos >= 0) & (stackPos < stack.stackHeight));
		stackOp := stack.stack[stackPos];
		IF (stackPos < stack.spillHeight) & stack.Spillable(stackOp) THEN
			spilled := 0;
			FOR k := stackPos + 1 TO stack.spillHeight - 1 DO
				IF stack.Spillable(stack.stack[k]) THEN INC(spilled) END
			END;
			offset := (nofParameter + spilled) * 4;
			IF stackOp.type = OpTypeReg THEN
				Emit1(PUSH, A.DerefOp(ESP, offset, 32 (* stackOp.bits*) ))
			ELSIF stackOp.type = OpTypeDeref THEN
				reg := stack.ReserveAnyRegister(32);
				Emit2(MOV, A.RegOp(reg), A.DerefOp(ESP, offset, 32));
				Emit1(PUSH, A.DerefOp(reg, stackOp.const, 32 (* stackOp.bits *)));
				Free(A.RegOp(reg))
			ELSIF stackOp.type = OpTypeImm THEN
				Emit1(PUSH, stackOp)
			ELSE HALT(111)
			END;
			IF Trace THEN
				CCBasic.OutText("PUSH spilled element "); CCBasic.OutInteger(offset); CCBasic.OutText("[ESP]"); CCBasic.OutLine 
			END
		ELSIF stackOp.type = OpTypeFPU THEN
			Emit2(SUB, A.RegOp(ESP), A.Imm32Op(4));
			Emit1(FSTP, A.DerefOp(ESP, 0, 32))
		ELSE
			IF (stackOp.type IN {OpTypeReg, OpTypeDeref}) & (stackOp.bits # 32) THEN
				stackOp.bits := 32;
				IF stackOp.type = OpTypeReg THEN
					stackOp.reg := A.ConvertToExtended(stackOp.reg)
				END
			END;
			Emit1(PUSH, stackOp)
		END;
		IncProcedureStackSize(4)
	END PushParameter;
	
	PROCEDURE AndBoolean*;
	BEGIN BinaryIntegerOperation(AND)
	END AndBoolean;
	
	PROCEDURE OrBoolean*;
	BEGIN BinaryIntegerOperation(OR0)
	END OrBoolean;
	
	PROCEDURE AddInteger*;
	BEGIN BinaryIntegerOperation(ADD)
	END AddInteger;
	
	PROCEDURE SubtractInteger*;
	BEGIN BinaryIntegerOperation(SUB)
	END SubtractInteger;
	
	PROCEDURE MultiplyInteger*;
	VAR left, right: Operand;
	BEGIN
		Pop(right);
		LoadToRegister;
		Pop(left);
		IF (right.type = OpTypeImm) & CCBasic.IsPowerOf2(right.const) THEN
			Emit2(SAL, left, A.Imm8Op(CCBasic.LogarithmBasis2(right.const)))
		ELSE
			Emit2(IMUL, left, right)
		END;
		Push(left);
		Free(right)
	END MultiplyInteger;
	
	PROCEDURE DivideInteger*;
	BEGIN GenerateDIVorMOD(TRUE)
	END DivideInteger;
	
	PROCEDURE ModuloInteger*;
	BEGIN GenerateDIVorMOD(FALSE)
	END ModuloInteger;
	
	PROCEDURE NegateInteger*;
	VAR op: Operand;
	BEGIN
		LoadToRegister;
		Pop(op);
		Emit1(NEG, op);
		Push(op)
	END NegateInteger;
		
	PROCEDURE EqualInteger*;
	BEGIN IntegerComparison(SETZ)
	END EqualInteger;
	
	PROCEDURE UnequalInteger*;
	BEGIN IntegerComparison(SETNZ)
	END UnequalInteger;
	
	PROCEDURE LessInteger*;
	BEGIN IntegerComparison(SETL)
	END LessInteger;
	
	PROCEDURE LessEqualInteger*;
	BEGIN IntegerComparison(SETLE)
	END LessEqualInteger;
	
	PROCEDURE GreaterInteger*;
	BEGIN IntegerComparison(SETNLE)
	END GreaterInteger;
	
	PROCEDURE GreaterEqualInteger*;
	BEGIN IntegerComparison(SETNL)
	END GreaterEqualInteger;
	
	PROCEDURE EqualReal*;
	BEGIN FloatComparison(SETZ)
	END EqualReal;
	
	PROCEDURE UnequalReal*;
	BEGIN FloatComparison(SETNZ)
	END UnequalReal;
	
	PROCEDURE LessReal*;
	BEGIN FloatComparison(SETB)
	END LessReal;
	
	PROCEDURE LessEqualReal*;
	BEGIN FloatComparison(SETBE)
	END LessEqualReal;
	
	PROCEDURE GreaterReal*;
	BEGIN FloatComparison(SETNBE)
	END GreaterReal;
	
	PROCEDURE GreaterEqualReal*;
	BEGIN FloatComparison(SETNB)
	END GreaterEqualReal;
	
	PROCEDURE NotBoolean*;
	VAR op: Operand;
	BEGIN
		LoadToRegister;
		Pop(op);
		Emit2(CMP, op, A.Imm8Op(FalseValue));
		Emit1(SETZ, op);
		Push(op)
	END NotBoolean;
	
	PROCEDURE AddReal*;
	BEGIN BinaryFloatOperation(FADD)
	END AddReal;
	
	PROCEDURE SubtractReal*;
	BEGIN BinaryFloatOperation(FSUB)
	END SubtractReal;
	
	PROCEDURE MultiplyReal*;
	BEGIN BinaryFloatOperation(FMUL)
	END MultiplyReal;
	
	PROCEDURE DivideReal*;
	BEGIN BinaryFloatOperation(FDIV)
	END DivideReal;
	
	PROCEDURE NegateReal*;
	BEGIN UnaryFloatOperation(FCHS)
	END NegateReal;
	
	PROCEDURE SquareRoot*;
	BEGIN UnaryFloatOperation(FSQRT)
	END SquareRoot;
	
	PROCEDURE Sine*;
	BEGIN UnaryFloatOperation(FSIN)
	END Sine;
	
	PROCEDURE Cosine*;
	BEGIN UnaryFloatOperation(FCOS)
	END Cosine;
	
	PROCEDURE Tangent*;
	BEGIN 
		UnaryFloatOperation(FSINCOS);
		Emit0(FDIVP)
	END Tangent;
	
	PROCEDURE ArcTangent*;
	VAR op: Operand; 
	BEGIN 
		Pop(op);
		LoadToFPU(FLD, op); Free(op);
		op := A.Imm32Op(CCBasic.EncodeReal(1.0));
		LoadToFPU(FLD, op); Free(op);
		Emit0(FPATAN);
		op := A.FPUOp(); Push(op)
	END ArcTangent;
		
	PROCEDURE LogicalShift*;
	VAR left, right: Operand; fixup1, fixup2, pos1, pos2, len1, len2: LONGINT;
	BEGIN
		Convert(1);
		Pop(right);
		IF right.type = OpTypeImm THEN
			Pop(left); ASSERT(left.type = OpTypeDeref);
			IF right.const > 0 THEN
				Emit2(SAL, left, right)
			ELSIF right.const < 0 THEN
				right := A.Imm8Op(-SHORT(SHORT(right.const)));
				Emit2(SHR, left, right)
			ELSE (* right.const = 0 => do nothing *)
			END
		ELSE
			Push(right); LoadToSpecificRegister(CL);
			Pop(right);
			Pop(left); ASSERT(left.type = OpTypeDeref);
			Emit2(CMP, right, A.Imm8Op(0));
			Emit1ForFixup(JL, A.Imm8Op(0), fixup1); pos1 := CodePos();
			Emit2(SAL, left, right);
			Emit1ForFixup(JMP, A.Imm8Op(0), fixup2); pos2 := CodePos();
			len1 := CodePos() - pos1;
			code.ChangeChar(fixup1, CHR(A.Imm8(len1)));
			Emit1(NEG, right);
			Emit2(SHR, left, right);
			len2 := CodePos() - pos2;
			code.ChangeChar(fixup2, CHR(A.Imm8(len2)))
		END;
		Free(right); Free(left)
	END LogicalShift;
	
	PROCEDURE ProcessPointer*;
	BEGIN Push(A.DerefOp(EBP, ProcessParameterOffset, 32))
	END ProcessPointer;
	
	PROCEDURE ProcessHeaderVariable*(offset, size: LONGINT);
	VAR op: Operand;
	BEGIN 
		ProcessPointer;
		LoadToRegister;
		Pop(op);
		op := A.DerefOp(op.reg, offset, A.BytesToBits(size));
		Push(op)
	END ProcessHeaderVariable;

	PROCEDURE ComponentPointer*;
	BEGIN Push(A.DerefOp(EBP, ComponentParameterOffset, 32))
	END ComponentPointer;
	
	PROCEDURE ComponentVariable*(offset, size: LONGINT);
	VAR op: Operand;
	BEGIN
		ComponentPointer;
		LoadToRegister;
		Pop(op);
		op := A.DerefOp(op.reg, offset, A.BytesToBits(size));
		Push(op)
	END ComponentVariable;
	
	PROCEDURE LoadEBPOfStaticScope(scopeIndex: LONGINT);
	VAR op: Operand;
	BEGIN
		Push(A.RegOp(EBP));
		WHILE scopeIndex > 0 DO
			LoadToRegister;
			Pop(op);
			Push(A.DerefOp(op.reg, StaticLinkParameterOffset, 32));
			DEC(scopeIndex)
		END
	END LoadEBPOfStaticScope;
	
	PROCEDURE LocalVariable*(scopeIndex, offset, varSize, accessSize: LONGINT);
	VAR op: Operand;
	BEGIN 
		LoadEBPOfStaticScope(scopeIndex);
		LoadToRegister;
		Pop(op);
		Push(A.DerefOp(op.reg, -(offset + varSize), A.BytesToBits(accessSize)))
	END LocalVariable;
	
	(* offset must include size of return PC *)
	PROCEDURE ProcedureParameter*(scopeIndex: LONGINT; isVariable: BOOLEAN; offset, accessSize: LONGINT);
	VAR op: Operand;
	BEGIN
		LoadEBPOfStaticScope(scopeIndex);
		LoadToRegister;
		Pop(op);
		IF isVariable THEN
			Push(A.DerefOp(op.reg, offset, 32));
			LoadToRegister;
			Pop(op);
			Push(A.DerefOp(op.reg, 0, A.BytesToBits(accessSize)))
		ELSE
			Push(A.DerefOp(op.reg, offset, A.BytesToBits(accessSize)))
		END
	END ProcedureParameter;
	
	PROCEDURE ProcessParameter*(offset, accessSize: LONGINT);
	VAR op: Operand;
	BEGIN 
		Push(A.DerefOp(EBP, offset, A.BytesToBits(accessSize)))
	END ProcessParameter;
	
	PROCEDURE ProcedureFrameBase*;
	BEGIN Push(A.RegOp(EBP))
	END ProcedureFrameBase;
	
	PROCEDURE ProcedureStaticLink*;
	BEGIN Push(A.DerefOp(EBP, StaticLinkParameterOffset, 32))
	END ProcedureStaticLink;
	
	PROCEDURE ServedCommunicationBuffer*;
	BEGIN 
		Push(A.DerefOp(EBP, ProcessTailCommBufferOffset, 32));
		GetAddress
	END ServedCommunicationBuffer;
	
	(** communication with required external interface *)
	PROCEDURE CommunicationBufferForComponent*(varSectionOffset, commId: LONGINT);
	BEGIN ComponentVariable(varSectionOffset + commId * 4, 4)
	END CommunicationBufferForComponent;
	
	(** communication with offered internal interface *)
	PROCEDURE CommunicationBufferForVariable*(commId: LONGINT);
	VAR op: Operand;
	BEGIN
		Pop(op);
		ASSERT(op.type = OpTypeDeref);
		INC(op.const, 4 + commId * 4);
		Push(op)
	END CommunicationBufferForVariable;
		
	PROCEDURE AdrOfCommSetInImplementation*;
	BEGIN 
		LocalVariable(0, 0, 4, 4); (* reserved space for communication variable *)
		GetAddress
	END AdrOfCommSetInImplementation;
	
	PROCEDURE AdrOfCommSetInProcedure*;
	BEGIN Push(A.DerefOp(EBP, CommunicationSetParamOffset, 32))
	END AdrOfCommSetInProcedure;
	
	PROCEDURE ProcedureStackReserveParam*;
	BEGIN Push(A.DerefOp(EBP, StackReserveParameterOffset, 32))
	END ProcedureStackReserveParam;
	
	PROCEDURE LoadESP*;
	BEGIN Push(A.RegOp(ESP))
	END LoadESP;
	
	PROCEDURE LoadEBP*;
	BEGIN Push(A.RegOp(EBP))
	END LoadEBP;
		
	PROCEDURE Load*;
	BEGIN AssertDeref
	END Load;
				
	PROCEDURE Store*;
	VAR source, target: Operand;
	BEGIN
		Pop(source);
		IF source.type = OpTypeFPU THEN
			AssertDeref;
			Pop(target);
			ASSERT(target.bits = source.bits);
			Emit1(FSTP, target);
			Emit0(FWAIT)
		ELSE
			Push(source);
			RegisterOrImm;
			Pop(source);
			AssertDeref;
			Pop(target); 
			ASSERT(target.bits = source.bits);
			Emit2(MOV, target, source)
		END;
		Free(source); Free(target)
	END Store;
			
	PROCEDURE PreemptionCheck*(ref: FixupReference);
	VAR fixupPos: LONGINT; fixup: Fixup;
	BEGIN
		Emit2(CMP, A.RegOp(EDI), A.Imm32Op(FalseValue));
		Emit1ForFixup(JZ, A.Imm32Op(0), fixupPos);
		NEW(fixup, fixupPos, TRUE, ref); ref.list.Add(fixup)
	END PreemptionCheck;
			
	PROCEDURE ConditionalBranch*(condition: BOOLEAN; ref: FixupReference);
	VAR left, oldLeft, right: Operand; fixupPos: LONGINT; fixup: Fixup;
	BEGIN
		RegisterOrDeref;
		Pop(left);
		IF (stack.stackHeight = 1) & (IsRegister(left, EAX) OR IsRegister(left, AL) OR IsRegister(left, AH)) THEN
			oldLeft := left;
			left := LoadToNewRegister(oldLeft);
			Free(oldLeft)
		END;
		StoreBranchState(ref, FALSE);
		IF condition THEN right := A.Imm8Op(TrueValue) ELSE right := A.Imm8Op(FalseValue) END;
		Emit2(CMP, left, right);
		Free(left);
		Emit1ForFixup(JZ, A.Imm32Op(0), fixupPos);
		NEW(fixup, fixupPos, TRUE, ref); ref.list.Add(fixup)
	END ConditionalBranch;

	PROCEDURE Branch*(ref: FixupReference);
	VAR fixupPos: LONGINT; fixup: Fixup;
	BEGIN
		StoreBranchState(ref, TRUE);
		Emit1ForFixup(JMP, A.Imm32Op(0), fixupPos);
		NEW(fixup, fixupPos, TRUE, ref); ref.list.Add(fixup)
	END Branch;
	
	PROCEDURE BranchEntry*(ref: FixupReference);
	BEGIN StoreBranchState(ref, FALSE)
	END BranchEntry;
			
	PROCEDURE GetProcedureResult*(bytes: LONGINT);
	VAR regResult: Register;
	BEGIN
		IF bytes = 1 THEN regResult := AL
		ELSIF bytes = 4 THEN regResult := EAX
		ELSE HALT(111)
		END;
		stack.ReserveSpecificRegister(regResult);
		Push(A.RegOp(regResult))
	END GetProcedureResult;
				
	PROCEDURE MakeProcedureResult*(bytes: LONGINT);
	VAR reg: Register; op: Operand;
	BEGIN
		IF bytes = 4 THEN reg := EAX
		ELSIF bytes = 1 THEN reg := AL
		ELSE HALT(111)
		END;
		LoadToSpecificRegister(reg);
		Pop(op);
		Free(op)
	END MakeProcedureResult;
	
	PROCEDURE BeginAwaitCondition*(VAR startPos, endFixupPos: LONGINT);
	BEGIN
		ASSERT(stack.stackHeight = 0);
		Emit1ForFixup(JMP, A.Imm32Op(0), endFixupPos);
		startPos := code.Length();
		Emit1(PUSH, A.RegOp(EBP));
		Emit2(MOV, A.RegOp(EBP), A.DerefOp(ESP, 8, 32))
	END BeginAwaitCondition;
	
	PROCEDURE EndAwaitCondition*(endFixupPos: LONGINT);
	VAR op: Operand; endPos: LONGINT;
	BEGIN
		LoadToSpecificRegister(AL);
		Pop(op); Free(op);
		ASSERT(stack.stackHeight = 0); ASSERT(stack.reservedRegisters = {});
		Emit1(POP, A.RegOp(EBP));
		Emit1(RET, A.Imm16Op(4));
		endPos := code.Length();
		code.ChangeInteger4(endFixupPos, endPos - (endFixupPos + 4))
	END EndAwaitCondition;
		
	(* Helper procedures *)
	
	PROCEDURE FloatComparison(instr: A.Instruction);
	VAR op: Operand;
	BEGIN
		BinaryFloatOperation(FCOMP);
		stack.ReserveSpecificRegister(EAX);
		op := A.RegOp(stack.ReserveAnyRegister(8));
		Emit1(FNSTSW, A.RegOp(AX));
		Emit0(SAHF);
		Emit1(instr, op);
		Free(A.RegOp(EAX));
		Push(op);
	END FloatComparison;
	
	PROCEDURE IntegerComparison(instr: A.Instruction);
	VAR op: Operand;
	BEGIN
		IntegerCompareValues;
		op := A.RegOp(stack.ReserveAnyRegister(8));
		Emit1(instr, op);
		Push(op)
	END IntegerComparison;
	
	PROCEDURE IntegerCompareValues;
	VAR right, left: Operand;
	BEGIN
		Pop(right);
		IF right.type IN {OpTypeImm, OpTypeDeref} THEN LoadToRegister END;
		Pop(left);
		Emit2(CMP, left, right);
		Free(left); Free(right)
	END IntegerCompareValues;
	
	PROCEDURE StoreBranchState(ref: FixupReference; free: BOOLEAN);
	VAR op: Operand;
	BEGIN
		IF ref.stackHeight = -1 THEN ref.stackHeight := stack.stackHeight
		ELSE ASSERT(ref.stackHeight = stack.stackHeight) 
		END;
		IF stack.stackHeight = 0 THEN (* ok *)
		ELSIF stack.stackHeight = 1 THEN
			Pop(op); Push(op);
			IF op.bits = 8 THEN
				LoadToSpecificRegister(AL)
			ELSIF op.bits = 32 THEN
				LoadToSpecificRegister(EAX)
			ELSE HALT(111)
			END;
			IF free THEN Pop(op); Free(op) END 
		ELSE 
			IF Trace THEN CCBasic.OutText("StoreBranchState "); CCBasic.OutInteger(stack.stackHeight); CCBasic.OutLine; END;
			stack.SaveAllRegisters(0);
			IF free THEN stack.InitEvaluationStack END
		END
	END StoreBranchState;
	
	PROCEDURE GenerateDIVorMOD(isDiv: BOOLEAN);
	VAR left, right: Operand; fixupPos, pos, len: LONGINT; result: Register;
	BEGIN
		Pop(right);
		IF (right.type = OpTypeImm) & CCBasic.IsPowerOf2(right.const) THEN
			LoadToRegister;
			Pop(left);
			IF isDiv THEN
				Emit2(SAR, left, A.Imm8Op(CCBasic.LogarithmBasis2(right.const)))
			ELSE
				Emit2(AND, left, A.Imm32Op(CCBasic.BitMaskWithLowerSetBits(CCBasic.LogarithmBasis2(right.const))))
			END;
			Push(left);
			Free(right)
		ELSE
			Pop(left);
			IF ~UsesRegister(left, EAX) & ~UsesRegister(right, EAX) THEN
				stack.ReserveSpecificRegister(EAX)
			END;
			IF ~UsesRegister(left, EDX) & ~UsesRegister(right, EDX) THEN
				stack.ReserveSpecificRegister(EDX)
			END;
			IF (right.type = OpTypeImm) OR UsesRegister(right, EAX) OR UsesRegister(right, EDX) THEN
				right := LoadToNewRegister(right) (* change to register which is neither EAX nor EDX *)
			END;
			IF ~IsRegister(left, EAX) THEN
				Emit2(MOV, A.RegOp(EAX), left)
			END;
			Emit0(CDQ);
			Emit1(IDIV, right);
			IF isDiv THEN
				Emit2(SAL, A.RegOp(EDX), A.Imm8Op(1));
				Emit2(SBB, A.RegOp(EAX), A.Imm32Op(0)); (* round to zero *)
				result := EAX
			ELSE
				Emit2(CMP, A.RegOp(EDX), A.Imm32Op(0));
				Emit1ForFixup(JNL, A.Imm8Op(0), fixupPos);
				pos := CodePos();
				Emit2(ADD, A.RegOp(EDX), right);
				len := CodePos() - pos;
				code.ChangeChar(fixupPos, CHR(A.Imm8(len)));
				result := EDX
			END;
			Push(A.RegOp(result));
			IF ~UsesRegister(left, result) THEN Free(left) END;
			IF ~UsesRegister(right, result) THEN Free(right) END;
			IF (result # EAX) & ~UsesRegister(left, EAX) THEN Free(A.RegOp(EAX)) END;
			IF result # EDX THEN Free(A.RegOp(EDX)) END
		END
	END GenerateDIVorMOD;
		
	PROCEDURE BinaryIntegerOperation(instr: A.Instruction);
	VAR left, right: Operand;
	BEGIN
		Pop(right);
		LoadToRegister;
		Pop(left);
		Emit2(instr, left, right);
		Push(left);
		Free(right);
	END BinaryIntegerOperation;
		
	PROCEDURE UnaryFloatOperation(instr: A.Instruction);
	VAR op: Operand;
	BEGIN
		Pop(op);
		LoadToFPU(FLD, op); Free(op); op := A.FPUOp();
		Emit0(instr);
		Push(op)
	END UnaryFloatOperation;
	
	PROCEDURE BinaryFloatOperation(instr: A.Instruction);
	VAR left, right: Operand;
	BEGIN
		Pop(right); 
		Pop(left); 
		IF left.type # OpTypeFPU THEN
			LoadToFPU(FLD, left); Free(left); left := A.FPUOp();
			IF right.type = OpTypeFPU THEN (* right is before left on the FPU stack *)
				Emit0(FXCH) (* swap *)
			END
		END;
		IF (right.type = OpTypeImm) OR (right.type = OpTypeReg) THEN
			LoadToFPU(FLD, right); Free(right); right := A.FPUOp()
		END;
		IF right.type = OpTypeDeref THEN
			ASSERT((instr = FADD) OR (instr = FSUB) OR (instr = FMUL) OR (instr = FDIV) OR (instr = FCOMP));
			Emit1(instr, right)
		ELSE
			ASSERT(right.type = OpTypeFPU);
			IF instr = FADD THEN instr := FADDP
			ELSIF instr = FSUB THEN instr := FSUBP
			ELSIF instr = FMUL THEN instr := FMULP
			ELSIF instr = FDIV THEN instr := FDIVP
			ELSIF instr = FCOMP THEN 
				Emit0(FXCH); (* top is compared with second top *)
				instr := FCOMPP
			ELSE HALT(111)
			END;
			Emit0(instr)
		END;
		Free(left); Free(right);
		IF (instr # FCOMP) & (instr # FCOMPP) THEN Push(A.FPUOp()) END
	END BinaryFloatOperation;
	
	PROCEDURE LoadToFPU(instr: A.Instruction; op: Operand);
	BEGIN
		ASSERT((instr = FLD) OR (instr = FILD));
		IF (op.type = OpTypeImm) OR (op.type = OpTypeReg) THEN
			Emit1(PUSH, op);
			IncProcedureStackSize(4);
			Emit1(instr, A.DerefOp(ESP, 0, 32));
			Emit2(ADD, A.RegOp(ESP), A.Imm32Op(4));
			DecProcedureStackSize(4)
		ELSIF op.type = OpTypeDeref THEN
			Emit1(instr, op)
		ELSE ASSERT(op.type = OpTypeFPU)
		END
	END LoadToFPU;
	
	PROCEDURE Interrupt*(number: SHORTINT; nofParameters: LONGINT);
	VAR i: LONGINT; op: Operand;
	BEGIN 
		ASSERT(stack.AllRegistersSaved(nofParameters));
		stack.spillingAllowed := FALSE;
		FOR i := 0 TO nofParameters-1 DO
			PushParameter(stack.stackHeight - nofParameters + i, i)
		END;
		Emit1(INT, A.Imm8Op(number));
		stack.spillingAllowed := TRUE;
		FOR i := 1 TO nofParameters DO
			Pop(op); Free(op)
		END
	END Interrupt;
	
	PROCEDURE UsesRegister(op: Operand; reg: Register): BOOLEAN;
	BEGIN RETURN (op.type IN {OpTypeReg, OpTypeDeref}) & (op.reg = reg)
	END UsesRegister;
	
	PROCEDURE IsRegister(op: Operand; reg: Register): BOOLEAN;
	BEGIN RETURN (op.type = OpTypeReg) & (op.reg = reg)
	END IsRegister;
END CCIx86CG.

