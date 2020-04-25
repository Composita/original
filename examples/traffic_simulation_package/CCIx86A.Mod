MODULE CCIx86A; (** Component Compiler, Intel x86 Backend Assembler, 2005-2007 by Luc Blaeser *)
	IMPORT CCBasic;

	TYPE
		Register* = LONGINT;

		Operand* = RECORD
			type*: OperandType;
			reg*: Register; (** defined for OpTypeReg or OpTypeDeref *)
			const*: LONGINT; (** defined for OpTypeDeref and OpTypeImm *)
			bits*: SHORTINT; (** 8, 16, 32 *)
			fixup*: RECORD
				target*: PTR; (** generic fixup information *)
				relative*: BOOLEAN; (** relative code fixup *)
			END;
		END;
	
		OperandType* = SHORTINT;
	CONST
		(* values of OperandType *)
		OpTypeReg* = 1; OpTypeDeref* = 2; OpTypeImm* = 3; OpTypeFPU* = 4;
	
		(* register enumeration, arbitrary numbering *)
		NoReg* = 0;
		EAX* = 1; EBX* = 2; ECX* = 3; EDX* = 4; 
		EBP* = 5; ESP* = 6; ESI* = 7; EDI* = 8;
		AL* = 9; BL* = 10; CL* = 11; DL* = 12;
		AH* = 13; BH* = 14; CH* = 15; DH* = 16;
		AX* = 17; BX* = 18; CX* = 19; DX* = 20;
		BP* = 21; SP* = 22; SI* = 23; DI0* = 24; (* fingerprint collision *)
	
	TYPE
		Instruction* = LONGINT;
	CONST
		(** Instruction values *)
		ADD* = 0; AND* = 1; CALL* = 2; CDQ* = 3;
		CMP* = 4; IDIV* = 5; IMUL* = 6; JMP* = 7;
		JNL* = 8; JNZ* = 9; JZ* = 10; JNLE* = 11; JL* = 12;
		MOV* = 13; NEG* = 14; POP* = 15; PUSH* = 16;
		RET* = 17; SAL* = 18; SAR* = 19; SBB* = 20;
		SETL* = 21; SETLE* = 22; SETNL* = 23; SETNLE* = 24; SETNZ* = 25; SETZ* = 26;
		SUB* = 27; XOR* = 28; DECx* = 29; NOP* = 30;
		XCHG* = 31; PAUSE* = 32; INT* = 33; OUT* = 34;
		MOVSX* = 35; INCx* = 36; SHR* = 37;
		FLD* = 38; FILD* = 39; FSTP* = 40; 
		FADD* = 41; FSUB* = 42; FMUL* = 43; FDIV* = 44; 
		FADDP* = 45; FSUBP* = 46; FMULP* = 47; FDIVP* = 48;
		FCHS* = 49; FWAIT* = 50; FNSTCW* = 51; FLDCW* = 52; FISTP* = 53; 
		FXCH* = 54; FCOMP* = 55; FCOMPP* = 56; FNSTSW* = 57; 
		SAHF* = 58; SETB* = 59; SETBE* = 60; SETNBE* = 61; SETNB* = 62; 
		OR0* = 63; FSIN* = 64; FCOS* = 65; FSQRT* = 66; FPATAN* = 67;
		FSINCOS* = 68; FABS* = 69;
		
		TotalInstructions = 70;
		
	TYPE
		OpCodeOperand = RECORD
			type: OpCodeOperandType;
			bits: SHORTINT; (* 8, 16, 32 *)
			specificRegister: Register; (* NoReg if no specific register required *)
			specificConstant: RECORD
				used: BOOLEAN;
				imm: LONGINT;
			END
		END;
		
		OpCodeOperandType = SHORTINT;
		
	CONST
		(* values of OpCodeOperandType *)
		RegOCOperand = 1; RMOCOperand = 2;  ConstOCOperand = 3; MemOCOperand = 4; 
	
	TYPE
		OpCode = RECORD
			instruction: Instruction;
			nofCodes: SHORTINT; (* 1..2 *)
			code1, code2: CHAR;
			plusReg: BOOLEAN; (* code1 + register code *)
			digit: SHORTINT; (* -1 if not used *)
			nofOps: SHORTINT; (* 0..3 *)
			op1, op2, op3: OpCodeOperand;
		END;
	
	TYPE
		ModRMTable = ARRAY 8, 8 OF CHAR;
		OpCodeSequence = POINTER TO ARRAY OF OpCode;
		OpCodeTable = ARRAY TotalInstructions OF OpCodeSequence;
	
	CONST
		SIBNoScaleESP = 24X;
	
	VAR
		(* 32-Bit Addressing with ModR/M Byte (IA32 ref vol 2A, ch 2, table 2-2 *)
		ModRMRegCodeTable: ModRMTable; (* [R/m32, Reg32] *)
		ModRMDisp8RegCodeTable: ModRMTable; (* [[R/m32] disp 8, Reg32] *)
		ModRMDisp32RegCodeTable: ModRMTable; (* [[R/m32] disp 32, Reg32] *)
		ModRMDerefRegCodeTable: ModRMTable; (* [[R/m32], Reg32] *)	
		opCode: OpCodeTable;
	
	PROCEDURE InitializeOpCodes;
	VAR 
		instr: Instruction; opcPos: LONGINT;
		reg8, reg32, rm8, rm16, rm32, imm8, imm16, imm32, mem32: OpCodeOperand;
		
		PROCEDURE InitializeOpCodeOperands;
		BEGIN
			reg8.type := RegOCOperand; reg8.bits := 8; reg8.specificRegister := NoReg;
			reg32.type := RegOCOperand; reg32.bits := 32; reg32.specificRegister := NoReg;
			rm8.type := RMOCOperand; rm8.bits := 8; rm8.specificConstant.used := FALSE;
			rm16.type := RMOCOperand; rm16.bits := 16; rm16.specificConstant.used := FALSE;
			rm32.type := RMOCOperand; rm32.bits := 32; rm32.specificConstant.used := FALSE;
			imm8.type := ConstOCOperand; imm8.bits := 8; imm8.specificConstant.used := FALSE;
			imm16.type := ConstOCOperand; imm16.bits := 16; imm16.specificConstant.used := FALSE;
			imm32.type := ConstOCOperand; imm32.bits := 32; imm32.specificConstant.used := FALSE;
			mem32.type := MemOCOperand; mem32.bits := 32; mem32.specificConstant.used := FALSE
		END InitializeOpCodeOperands;
		
		PROCEDURE SpecRegOCO(reg: Register): OpCodeOperand;
		VAR o: OpCodeOperand;
		BEGIN 
			o.type := RegOCOperand; 
			IF Is8BitRegister(reg) THEN o.bits := 8 
			ELSIF Is16BitRegister(reg) THEN o.bits := 16;
			ELSE ASSERT(Is32BitRegister(reg)); o.bits := 32 
			END;
			o.specificRegister := reg; RETURN o
		END SpecRegOCO;
		
		PROCEDURE SpecImm8OCO(x: SHORTINT): OpCodeOperand;
		VAR o: OpCodeOperand;
		BEGIN
			o.type := ConstOCOperand; o.bits := 8; o.specificConstant.used := TRUE; o.specificConstant.imm := x;
			RETURN o
		END SpecImm8OCO;
		
		PROCEDURE NewInstruction(x: Instruction; nofOpCodes: LONGINT);
		BEGIN instr := x; NEW(opCode[instr], nofOpCodes); opcPos := -1
		END NewInstruction;
		
		PROCEDURE OpCode0(code1: CHAR);
		VAR o: OpCode;
		BEGIN
			o.instruction := instr; o.nofCodes := 1; o.code1 := code1; 
			o.nofOps := 0; o.digit := -1; o.plusReg := FALSE;
			INC(opcPos); opCode[instr][opcPos] := o
		END OpCode0;
		
		PROCEDURE OpCode02(code1, code2: CHAR);
		BEGIN OpCode0(code1); opCode[instr][opcPos].nofCodes := 2; opCode[instr][opcPos].code2 := code2
		END OpCode02;
		
		PROCEDURE OpCode1D(code1: CHAR; digit: SHORTINT; op: OpCodeOperand);
		BEGIN
			OpCode0(code1); opCode[instr][opcPos].digit := digit;
			opCode[instr][opcPos].nofOps := 1; opCode[instr][opcPos].op1 := op; 
		END OpCode1D;
		
		PROCEDURE OpCode1D2(code1, code2: CHAR; digit: SHORTINT; op: OpCodeOperand);
		BEGIN OpCode1D(code1, digit, op); opCode[instr][opcPos].nofCodes := 2; opCode[instr][opcPos].code2 := code2
		END OpCode1D2;
		
		PROCEDURE OpCode1(code1: CHAR; op: OpCodeOperand);
		BEGIN OpCode1D(code1, -1, op)
		END OpCode1;
		
		PROCEDURE OpCode12(code1, code2: CHAR; op: OpCodeOperand);
		BEGIN OpCode1D2(code1, code2, -1, op)
		END OpCode12;
		
		PROCEDURE OpCode2D(code1: CHAR; digit: SHORTINT; op1, op2: OpCodeOperand);
		BEGIN
			OpCode0(code1); opCode[instr][opcPos].digit := digit;
			opCode[instr][opcPos].nofOps := 2; opCode[instr][opcPos].op1 := op1; opCode[instr][opcPos].op2 := op2
		END OpCode2D;
		
		PROCEDURE OpCode2D2(code1, code2: CHAR; digit: SHORTINT; op1, op2: OpCodeOperand);
		BEGIN OpCode2D(code1, digit, op1, op2); opCode[instr][opcPos].nofCodes := 2; opCode[instr][opcPos].code2 := code2
		END OpCode2D2;
		
		PROCEDURE OpCode2(code1: CHAR; op1, op2: OpCodeOperand);
		BEGIN OpCode2D(code1, -1, op1, op2)
		END OpCode2;
		
		PROCEDURE OpCode22(code1, code2: CHAR; op1, op2: OpCodeOperand);
		BEGIN OpCode2D2(code1, code2, -1, op1, op2)
		END OpCode22;
		
		PROCEDURE OpCode3D(code1: CHAR; digit: SHORTINT; op1, op2, op3: OpCodeOperand);
		BEGIN
			OpCode0(code1); opCode[instr][opcPos].digit := digit;
			opCode[instr][opcPos].nofOps := 3; opCode[instr][opcPos].op1 := op1; 
			opCode[instr][opcPos].op2 := op2; opCode[instr][opcPos].op3 := op3
		END OpCode3D;
		
		PROCEDURE OpCode3(code1: CHAR; op1, op2, op3: OpCodeOperand);
		BEGIN OpCode3D(code1, -1, op1, op2, op3)
		END OpCode3;
		
	BEGIN
		InitializeOpCodeOperands;
		
		NewInstruction(ADD, 9);
		OpCode2(04X, SpecRegOCO(AL), imm8);
		OpCode2(05X, SpecRegOCO(EAX), imm32);
		OpCode2D(80X, 0, rm8, imm8);
		OpCode2D(81X, 0, rm32, imm32);
		OpCode2D(83X, 0, rm32, imm8);
		OpCode2(00X, rm8, reg8);
		OpCode2(01X, rm32, reg32);
		OpCode2(02X, reg8, rm8);
		OpCode2(03X, reg32, rm32);
		
		NewInstruction(AND, 9);
		OpCode2(24X, SpecRegOCO(AL), imm8);
		OpCode2(25X, SpecRegOCO(EAX), imm32);
		OpCode2D(80X, 4, rm8, imm8);
		OpCode2D(81X, 4, rm32, imm32);
		OpCode2D(83X, 4, rm32, imm8);
		OpCode2(20X, rm8, reg8);
		OpCode2(21X, rm32, reg32);
		OpCode2(22X, reg8, rm8);
		OpCode2(23X, reg32, rm32);
		
		NewInstruction(OR0, 9);
		OpCode2(0CX, SpecRegOCO(AL), imm8);
		OpCode2(0DX, SpecRegOCO(EAX), imm32);
		OpCode2D(80X, 1, rm8, imm8);
		OpCode2D(81X, 1, rm32, imm32);
		OpCode2D(83X, 1, rm32, imm8);
		OpCode2(08X, rm8, reg8);
		OpCode2(09X, rm32, reg32);
		OpCode2(0AX, reg8, rm8);
		OpCode2(0BX, reg32, rm32);
		
		NewInstruction(CALL, 2);
		OpCode1(0E8X, imm32);
		OpCode1D(0FFX, 2, rm32);
		
		NewInstruction(CDQ, 1);
		OpCode0(99X);
		
		NewInstruction(CMP, 9);
		OpCode2(3CX, SpecRegOCO(AL), imm8);
		OpCode2(3DX, SpecRegOCO(EAX), imm32);
		OpCode2D(80X, 7, rm8, imm8);
		OpCode2D(81X, 7, rm32, imm32);
		OpCode2D(83X, 7, rm32, imm8);
		OpCode2(38X, rm8, reg8);
		OpCode2(39X, rm32, reg32);
		OpCode2(3AX, reg8, rm8);
		OpCode2(3BX, reg32, rm32);

		NewInstruction(DECx, 3);
		OpCode1D(0FEX, 1, rm8);
		OpCode1D(0FFX, 1, rm32);
		OpCode1(48X, reg32); opCode[instr][opcPos].plusReg := TRUE;
						
		NewInstruction(IDIV, 2);
		OpCode1D(0F6X, 7, rm8);
		OpCode1D(0F7X, 7, rm32);
		
		NewInstruction(IMUL, 7);
		OpCode1D(0F6X, 5, rm8);
		OpCode1D(0F7X, 5, rm32);
		OpCode22(0FX, 0AFX, reg32, rm32);
		OpCode3(6BX, reg32, rm32, imm8);
		OpCode2(6BX, reg32, imm8);
		OpCode3(69X, reg32, rm32, imm32);
		OpCode2(69X, reg32, imm32);
		
		NewInstruction(INCx, 3);
		OpCode1D(0FEX, 0, rm8);
		OpCode1D(0FFX, 0, rm32);
		OpCode1(40X, reg32); opCode[instr][opcPos].plusReg := TRUE;
		
		NewInstruction(INT, 2);
		OpCode1(0CCX, SpecImm8OCO(3));
		OpCode1(0CDX, imm8);
		
		NewInstruction(JMP, 3);
		OpCode1(0EBX, imm8);
		OpCode1(0E9X, imm32);
		OpCode1D(0FFX, 4, rm32);
		
		NewInstruction(JNL, 2);
		OpCode1(7DX, imm8);
		OpCode12(0FX, 8DX, imm32);
		
		NewInstruction(JNZ, 2);
		OpCode1(75X, imm8);
		OpCode12(0FX, 85X, imm32);
		
		NewInstruction(JZ, 2);
		OpCode1(74X, imm8);
		OpCode12(0FX, 84X, imm32);
		
		NewInstruction(JNLE, 2);
		OpCode1(7FX, imm8);
		OpCode12(0FX, 8FX, imm32);
		
		NewInstruction(JL, 2);
		OpCode1(7CX, imm8);
		OpCode12(0FX, 8CX, imm32);
		
		NewInstruction(MOV, 8);
		OpCode2(88X, rm8, reg8);
		OpCode2(89X, rm32, reg32);
		OpCode2(8AX, reg8, rm8);
		OpCode2(8BX, reg32, rm32);
		OpCode2(0B0X, reg8, imm8); opCode[instr][opcPos].plusReg := TRUE;
		OpCode2(0B8X, reg32, imm32); opCode[instr][opcPos].plusReg := TRUE;
		OpCode2D(0C6X, 0, rm8, imm8);
		OpCode2D(0C7X, 0, rm32, imm32);		

		NewInstruction(MOVSX, 2);
		OpCode22(0FX, 0BEX, reg32, rm8);
		OpCode22(0FX, 0BFX, reg32, rm16);
							
		NewInstruction(NEG, 2);
		OpCode1D(0F6X, 3, rm8);
		OpCode1D(0F7X, 3, rm32);
		
		NewInstruction(NOP, 1);
		OpCode0(90X);
	
		NewInstruction(OUT, 4);
		OpCode2(0E6X, imm8, SpecRegOCO(AL));
		OpCode2(0E7X, imm8, SpecRegOCO(EAX));
		OpCode2(0EEX, SpecRegOCO(DX), SpecRegOCO(AL)); 
		OpCode2(0EFX, SpecRegOCO(DX), SpecRegOCO(EAX));
		
		NewInstruction(PAUSE, 1);
		OpCode02(0F3X, 90X);
	
		NewInstruction(POP, 2);
		OpCode1(58X, reg32); opCode[instr][opcPos].plusReg := TRUE;
		OpCode1D(8FX, 0, rm32);
		
		NewInstruction(PUSH, 4);
		OpCode1(050X, reg32); opCode[instr][opcPos].plusReg := TRUE;
		OpCode1D(0FFX, 6, rm32);
		OpCode1(06AX, imm8);
		OpCode1(068X, imm32);
		
		NewInstruction(RET, 2);
		OpCode0(0C3X);
		OpCode1(0C2X, imm16);
		
		NewInstruction(SAL, 6);
		OpCode1D(0D0X, 4, rm8);
		OpCode2D(0D2X, 4, rm8, SpecRegOCO(CL));
		OpCode2D(0C0X, 4, rm8, imm8);
		OpCode1D(0D1X, 4, rm32);
		OpCode2D(0D3X, 4, rm32, SpecRegOCO(CL));
		OpCode2D(0C1X, 4, rm32, imm8);
		
		NewInstruction(SAR, 6);
		OpCode1D(0D0X, 7, rm8);
		OpCode2D(0D2X, 7, rm8, SpecRegOCO(CL));
		OpCode2D(0C0X, 7, rm8, imm8);
		OpCode1D(0D1X, 7, rm32);
		OpCode2D(0D3X, 7, rm32, SpecRegOCO(CL));
		OpCode2D(0C1X, 7, rm32, imm8);
		
		NewInstruction(SHR, 6);
		OpCode1D(0D0X, 5, rm8);
		OpCode2D(0D2X, 5, rm8, SpecRegOCO(CL));
		OpCode2D(0C0X, 5, rm8, imm8);
		OpCode1D(0D1X, 5, rm32);
		OpCode2D(0D3X, 5, rm32, SpecRegOCO(CL));
		OpCode2D(0C1X, 5, rm32, imm8);
		
		NewInstruction(SBB, 9);
		OpCode2(1CX, SpecRegOCO(AL), imm8);
		OpCode2(1DX, SpecRegOCO(EAX), imm32);
		OpCode2D(80X, 3, rm8, imm8);
		OpCode2D(81X, 3, rm32, imm32);
		OpCode2D(83X, 3, rm32, imm8);
		OpCode2(18X, rm8, reg8);
		OpCode2(19X, rm32, reg32);
		OpCode2(1AX, reg8, rm8);
		OpCode2(1BX, reg32, rm32);
		
		NewInstruction(SETL, 1);
		OpCode1D2(0FX, 9CX, 0, rm8); (* use digit 0 *)
		NewInstruction(SETLE, 1);
		OpCode1D2(0FX, 9EX, 0, rm8);
		NewInstruction(SETNL, 1);
		OpCode1D2(0FX, 9DX, 0, rm8);
		NewInstruction(SETNLE, 1);
		OpCode1D2(0FX, 9FX, 0, rm8);
		NewInstruction(SETNZ, 1);
		OpCode1D2(0FX, 95X, 0, rm8);
		NewInstruction(SETZ, 1);
		OpCode1D2(0FX, 94X, 0, rm8); 
		NewInstruction(SETB, 1);
		OpCode1D2(0FX, 92X, 0, rm8);
		NewInstruction(SETBE, 1);
		OpCode1D2(0FX, 96X, 0, rm8);
		NewInstruction(SETNBE, 1);
		OpCode1D2(0FX, 97X, 0, rm8);
		NewInstruction(SETNB, 1);
		OpCode1D2(0FX, 93X, 0, rm8);
		
		NewInstruction(SUB, 9);
		OpCode2(2CX, SpecRegOCO(AL), imm8);
		OpCode2(2DX, SpecRegOCO(EAX), imm32);
		OpCode2D(80X, 5, rm8, imm8);
		OpCode2D(81X, 5, rm32, imm32);
		OpCode2D(83X, 5, rm32, imm8);
		OpCode2(28X, rm8, reg8);
		OpCode2(29X, rm32, reg32);
		OpCode2(2AX, reg8, rm8);
		OpCode2(2BX, reg32, rm32);
		
		NewInstruction(XCHG, 6);
		OpCode2(90X, SpecRegOCO(EAX), reg32); opCode[instr][opcPos].plusReg := TRUE;
		OpCode2(90X, reg32, SpecRegOCO(EAX)); opCode[instr][opcPos].plusReg := TRUE;
		OpCode2(86X, rm8, reg8);
		OpCode2(86X, reg8, rm8);
		OpCode2(87X, rm32, reg32);
		OpCode2(87X, reg32, rm32);
		
		NewInstruction(XOR, 9);
		OpCode2(34X, SpecRegOCO(AL), imm8);
		OpCode2(35X, SpecRegOCO(EAX), imm32);
		OpCode2D(80X, 6, rm8, imm8);
		OpCode2D(81X, 6, rm32, imm32);
		OpCode2D(83X, 6, rm32, imm8);
		OpCode2(30X, rm8, reg8);
		OpCode2(31X, rm32, reg32);
		OpCode2(32X, reg8, rm8);
		OpCode2(33X, reg32, rm32);
		
		NewInstruction(FLD, 1);
		OpCode1D(0D9X, 0, mem32);
		
		NewInstruction(FILD, 1);
		OpCode1D(0DBX, 0, mem32);
		
		NewInstruction(FSTP, 1);
		OpCode1D(0D9X, 3, mem32);
		
		NewInstruction(FADD, 1);
		OpCode1D(0D8X, 0, mem32);
		
		NewInstruction(FADDP, 1);
		OpCode02(0DEX, 0C1X);
		
		NewInstruction(FSUB, 1);
		OpCode1D(0D8X, 4, mem32);
		
		NewInstruction(FSUBP, 1);
		OpCode02(0DEX, 0E9X);
		
		NewInstruction(FMUL, 1);
		OpCode1D(0D8X, 1, mem32);
		
		NewInstruction(FMULP, 1);
		OpCode02(0DEX, 0C9X);
		
		NewInstruction(FDIV, 1);
		OpCode1D(0D8X, 6, mem32);
		
		NewInstruction(FDIVP, 1);
		OpCode02(0DEX, 0F9X);
		
		NewInstruction(FCHS, 1);
		OpCode02(0D9X, 0E0X);
		
		NewInstruction(FWAIT, 1);
		OpCode0(09BX);
		
		NewInstruction(FNSTCW, 1);
		OpCode1D(0D9X, 7, mem32);
		
		NewInstruction(FLDCW, 1);
		OpCode1D(0D9X, 5, mem32);
		
		NewInstruction(FISTP, 1);
		OpCode1D(0DBX, 3, mem32);
		
		NewInstruction(FXCH, 1);
		OpCode02(0D9X, 0C9X);
		
		NewInstruction(FCOMP, 1);
		OpCode1D(0D8X, 3, mem32);
		
		NewInstruction(FCOMPP, 1);
		OpCode02(0DEX, 0D9X);
		
		NewInstruction(FSIN, 1);
		OpCode02(0D9X, 0FEX);
		
		NewInstruction(FCOS, 1);
		OpCode02(0D9X, 0FFX);
		
		NewInstruction(FSQRT, 1);
		OpCode02(0D9X, 0FAX);
		
		NewInstruction(FPATAN, 1);
		OpCode02(0D9X, 0F3X);
		
		NewInstruction(FSINCOS, 1);
		OpCode02(0D9X, 0FBX);
		
		NewInstruction(FABS, 1);
		OpCode02(0D9X, 0E1X);
		
		NewInstruction(FNSTSW, 1);
		OpCode12(0DFX, 0E0X, SpecRegOCO(AX));
		
		NewInstruction(SAHF, 1);
		OpCode0(09EX)
	END InitializeOpCodes;
	
	PROCEDURE FindOpCode0(instr: Instruction): OpCode;
	VAR i: LONGINT;
	BEGIN
		FOR i := 0 TO LEN(opCode[instr])-1 DO
			IF opCode[instr][i].nofOps = 0 THEN RETURN opCode[instr][i] END
		END;
		HALT(111)
	END FindOpCode0;
	
	PROCEDURE MatchingOperand(x: Operand; y: OpCodeOperand; VAR use16Bit: BOOLEAN): BOOLEAN;
	BEGIN
		use16Bit := FALSE;
		IF (x.bits = y.bits) OR ((x.bits = 16) & (y.bits = 32)) THEN
			IF ((x.bits = 16) & (y.bits = 32)) THEN 
				use16Bit := TRUE;
				x := ConvertOpTo32Bit(x)
			END;
			IF x.type = OpTypeReg THEN
				IF (y.type = RegOCOperand) & (y.specificRegister # NoReg) THEN
					RETURN x.reg = y.specificRegister
				END;
				RETURN (y.type = RegOCOperand) OR (y.type = RMOCOperand)
			ELSIF x.type = OpTypeDeref THEN 
				IF (y.type = RMOCOperand) & y.specificConstant.used THEN
					RETURN x.const = y.specificConstant.imm
				END;
				RETURN (y.type = RMOCOperand) OR (y.type = MemOCOperand)
			ELSIF x.type = OpTypeImm THEN 
				IF (y.type = ConstOCOperand) & y.specificConstant.used THEN
					RETURN x.const = y.specificConstant.imm
				END;
				RETURN y.type = ConstOCOperand
			ELSE 
				WriteOperand(x); CCBasic.OutText(" to type="); CCBasic.OutInteger(x.type); 
				CCBasic.OutText(" bits="); CCBasic.OutInteger(y.bits); CCBasic.OutLine;
				HALT(111)
			END
		ELSE RETURN FALSE
		END
	END MatchingOperand;
	
	PROCEDURE FindOpCode1(instr: Instruction; op: Operand; VAR use16Bit: BOOLEAN): OpCode;
	VAR i: LONGINT;
	BEGIN
		use16Bit := FALSE;
		FOR i := 0 TO LEN(opCode[instr])-1 DO
			IF (opCode[instr][i].nofOps = 1) & MatchingOperand(op, opCode[instr][i].op1, use16Bit) THEN 
				RETURN opCode[instr][i] 
			END
		END;
		HALT(111)
	END FindOpCode1;
		
	PROCEDURE FindOpCode2(instr: Instruction; op1, op2: Operand; VAR use16Bit: BOOLEAN): OpCode;
	VAR i: LONGINT; a, b: BOOLEAN;
	BEGIN
		use16Bit := FALSE;
		FOR i := 0 TO LEN(opCode[instr])-1 DO
			IF (opCode[instr][i].nofOps = 2) & MatchingOperand(op1, opCode[instr][i].op1, a) & 
					MatchingOperand(op2, opCode[instr][i].op2, b) THEN 
				IF a = b THEN
					use16Bit := a;
					RETURN opCode[instr][i] 
				ELSE HALT(111)
				END
			END
		END;
		HALT(111)
	END FindOpCode2;
	
	PROCEDURE FindOpCode3(instr: Instruction; op1, op2, op3: Operand; VAR use16Bit: BOOLEAN): OpCode;
	VAR i: LONGINT; a, b, c: BOOLEAN;
	BEGIN
		use16Bit := FALSE;
		FOR i := 0 TO LEN(opCode[instr])-1 DO
			IF (opCode[instr][i].nofOps = 3) & MatchingOperand(op1, opCode[instr][i].op1, a) & 
					MatchingOperand(op2, opCode[instr][i].op2, b) & MatchingOperand(op3, opCode[instr][i].op3, c) THEN
				IF a = b THEN
					use16Bit := a;
					RETURN opCode[instr][i] 
				ELSE HALT(111)
				END
			END
		END;
		HALT(111)
	END FindOpCode3;
				
	PROCEDURE ExtractOperand(oco: OpCodeOperand; o: Operand; 
		VAR reg, rm, imm: Operand; VAR hasReg, hasRm, hasImm: BOOLEAN);
	BEGIN
		IF (oco.type = RegOCOperand) & (oco.specificRegister = NoReg) THEN 
			ASSERT(~hasReg); reg := o; hasReg := TRUE
		ELSIF (oco.type = RMOCOperand) & ~oco.specificConstant.used THEN
			ASSERT(~hasRm); rm := o; hasRm := TRUE
		ELSIF (oco.type = ConstOCOperand) & ~oco.specificConstant.used THEN
			ASSERT(~hasImm); imm := o; hasImm := TRUE
		ELSIF (oco.type = MemOCOperand) & ~oco.specificConstant.used THEN
			ASSERT(~hasRm); rm := o; hasRm := TRUE
		END
	END ExtractOperand;
	
	PROCEDURE EmitOpCode(code: CCBasic.DataSequence; o: OpCode; 
		reg, rm, imm: Operand; hasReg, hasRm, hasImm: BOOLEAN; use16Bit: BOOLEAN; VAR immPos: LONGINT);
	BEGIN
		IF use16Bit THEN 
			ASSERT(o.code1 # 0FX); (* use for SIMD *)
			code.Char(066X) (* operand override prefix *)
		END; 
		ASSERT(o.nofCodes IN {1, 2});
		IF o.plusReg THEN
			ASSERT(o.digit = -1); ASSERT(hasReg);
			code.Char(PlusChar(o.code1, CHR(RegCode(reg.reg))));
		ELSE
			code.Char(o.code1)
		END;
		IF o.nofCodes > 1 THEN code.Char(o.code2) END;
		IF hasRm & hasReg THEN
			ModRM(code, reg, rm); Disp(code, rm)
		ELSIF hasRm THEN
			ASSERT(o.digit # -1);
			ModRMByDigit(code, o.digit, rm); Disp(code, rm)
		ELSIF hasReg & ~o.plusReg THEN
			ASSERT(o.digit = -1);
			ModRM(code, reg, reg)
		END;
		IF hasImm THEN
			immPos := code.Length(); 
			IF imm.bits = 8 THEN AppendInt8(code, Imm8(imm.const)) 
			ELSIF imm.bits = 16 THEN AppendInt16(code, Imm16(imm.const))
			ELSIF imm.bits = 32 THEN AppendInt32(code, imm.const) 
			ELSE HALT(111)
			END
		ELSE
			immPos := -1
		END
	END EmitOpCode;
	
	(** Emit assembler instructions *)
		
	PROCEDURE Emit0*(code: CCBasic.DataSequence; instr: Instruction);
	VAR o: OpCode; d: Operand;
	BEGIN 
		o := FindOpCode0(instr);
		code.Char(o.code1); 
		IF o.nofCodes > 1 THEN code.Char(o.code2) END
	END Emit0;
		
	PROCEDURE Emit1*(code: CCBasic.DataSequence; instr: Instruction; x: Operand; VAR immPos: LONGINT);
	VAR o: OpCode; reg, rm, imm: Operand; hasReg, hasRm, hasImm, use16Bit: BOOLEAN; 
	BEGIN
		o := FindOpCode1(instr, x, use16Bit);
		hasReg := FALSE; hasRm := FALSE; hasImm := FALSE;
		ExtractOperand(o.op1, x, reg, rm, imm, hasReg, hasRm, hasImm);
		EmitOpCode(code, o, reg, rm, imm, hasReg, hasRm, hasImm, use16Bit, immPos)
	END Emit1;
	
	PROCEDURE Emit2*(code: CCBasic.DataSequence; instr: Instruction; x, y: Operand; VAR immPos: LONGINT);
	VAR o: OpCode; reg, rm, imm: Operand; hasReg, hasRm, hasImm, use16Bit: BOOLEAN;
	BEGIN
		o := FindOpCode2(instr, x, y, use16Bit);
		hasReg := FALSE; hasRm := FALSE; hasImm := FALSE;
		ExtractOperand(o.op1, x, reg, rm, imm, hasReg, hasRm, hasImm);
		ExtractOperand(o.op2, y, reg, rm, imm, hasReg, hasRm, hasImm);
		EmitOpCode(code, o, reg, rm, imm, hasReg, hasRm, hasImm, use16Bit, immPos)
	END Emit2;
		
	PROCEDURE Emit3*(code: CCBasic.DataSequence; instr: Instruction; x, y, z: Operand; VAR immPos: LONGINT);
	VAR o: OpCode; reg, rm, imm: Operand; hasReg, hasRm, hasImm, use16Bit: BOOLEAN;
	BEGIN
		o := FindOpCode3(instr, x, y, z, use16Bit);
		hasReg := FALSE; hasRm := FALSE; hasImm := FALSE;
		ExtractOperand(o.op1, x, reg, rm, imm, hasReg, hasRm, hasImm);
		ExtractOperand(o.op2, y, reg, rm, imm, hasReg, hasRm, hasImm);
		ExtractOperand(o.op3, z, reg, rm, imm, hasReg, hasRm, hasImm);
		EmitOpCode(code, o, reg, rm, imm, hasReg, hasRm, hasImm, use16Bit, immPos)
	END Emit3;
		
	PROCEDURE RegOp*(reg: Register): Operand;
	VAR op: Operand;
	BEGIN 
		op.type := OpTypeReg; op.reg := reg; 
		IF Is8BitRegister(reg) THEN op.bits := 8
		ELSIF Is16BitRegister(reg) THEN op.bits := 16
		ELSIF Is32BitRegister(reg) THEN op.bits := 32
		ELSE HALT(111)
		END;
		RETURN op
	END RegOp;
	
	PROCEDURE DerefOp*(base: Register; disp: LONGINT; bits: SHORTINT): Operand;
	VAR op: Operand;
	BEGIN op.type := OpTypeDeref; op.reg := base; op.const := disp; op.bits := bits; RETURN op
	END DerefOp;
	
	PROCEDURE Imm8Op*(imm: SHORTINT): Operand;
	VAR op: Operand;
	BEGIN op.type := OpTypeImm; op.const := imm; op.bits := 8; RETURN op
	END Imm8Op;
	
	PROCEDURE Imm16Op*(imm: INTEGER): Operand;
	VAR op: Operand;
	BEGIN op.type := OpTypeImm; op.const := imm; op.bits := 16; RETURN op
	END Imm16Op;
	
	PROCEDURE Imm32Op*(imm: LONGINT): Operand;
	VAR op: Operand;
	BEGIN op.type := OpTypeImm; op.const := imm; op.bits := 32; RETURN op
	END Imm32Op;
	
	PROCEDURE FPUOp*(): Operand;
	VAR op: Operand;
	BEGIN op.type := OpTypeFPU; op.bits := 32; RETURN op
	END FPUOp;
	
	PROCEDURE InitializeTable(VAR t: ModRMTable; start: CHAR);
	VAR rm, reg: LONGINT; x: CHAR;
	BEGIN
		x := start; 
		FOR reg := 0 TO 7 DO
			FOR rm := 0 TO 7 DO
				t[rm, reg] := x;
				ASSERT(ORD(x) >= 0);
				x := CHR(ORD(x) + 1)
			END
		END;
	END InitializeTable;
	
	PROCEDURE Initialize;
	BEGIN
		InitializeTable(ModRMDerefRegCodeTable, 000X);
		InitializeTable(ModRMDisp8RegCodeTable, 040X);
		InitializeTable(ModRMDisp32RegCodeTable, 080X);
		InitializeTable(ModRMRegCodeTable, 0C0X);
		InitializeOpCodes
	END Initialize;

	(* 32-Bit Addressing with ModR/M Byte (IA32 ref vol 2A, ch 2, table 2-2 *)
	(* Register encoding for Rb / Rd (IA32 ref vol 2A, ch 3, table 3-1) *)
	PROCEDURE RegCode(reg: Register): LONGINT;
	BEGIN
		IF reg IN {AL, AX, EAX} THEN RETURN 0 (* AL, AX, EAX, MM0, XMM0, digit 0 *)
		ELSIF reg IN {CL, CX, ECX} THEN RETURN 1 (* CL, CX, ECX, MM1, XMM1, digit 1 *)
		ELSIF reg IN {DL, DX, EDX} THEN RETURN 2 (* DL, DX, EDX, MM2, XMM2, digit 2 *)
		ELSIF reg IN {BL, BX, EBX} THEN RETURN 3 (* BL, BX, EBX, MM3, XMM3, digit 3 *)
		ELSIF reg IN {AH, SP, ESP} THEN RETURN 4 (* AH, SP, ESP, MM4, XMM4, digit 4 *)
		ELSIF reg IN {CH, BP, EBP} THEN RETURN 5 (* CH, BP, EBP, MM5, XMM5, digit 5 *)
		ELSIF reg IN {DH, SI, ESI} THEN RETURN 6 (* DH, SI, ESI, MM6, XMM6, digit 6 *)
		ELSIF reg IN {BH, DI0, EDI} THEN RETURN 7 (* BH, DI, EDI, MM7, XMM7, digit 7 *)
		ELSE HALT(101)
		END
	END RegCode;
	
	PROCEDURE ModRMByDigit(code: CCBasic.DataSequence; digit: LONGINT; rm: Operand);
	BEGIN
		IF rm.type = OpTypeReg THEN
			code.Char(ModRMRegCodeTable[RegCode(rm.reg), digit])
		ELSIF rm.type = OpTypeDeref THEN
			IF (rm.const = 0) & (rm.reg # EBP) THEN
				code.Char(ModRMDerefRegCodeTable[RegCode(rm.reg), digit])
			ELSIF Is8BitValue(rm.const) THEN
				code.Char(ModRMDisp8RegCodeTable[RegCode(rm.reg), digit])
			ELSE
				code.Char(ModRMDisp32RegCodeTable[RegCode(rm.reg), digit])
			END;
			IF rm.reg = ESP THEN (* special SIB meaning *)	
				SIBNoScale(code, ESP)
			END
		ELSE HALT(111)
		END
	END ModRMByDigit;
	
	PROCEDURE ModRM(code: CCBasic.DataSequence; reg, rm: Operand);
	BEGIN
		ASSERT(reg.type = OpTypeReg);
		ModRMByDigit(code, RegCode(reg.reg), rm)
	END ModRM;
	
	PROCEDURE SIBNoScale(code: CCBasic.DataSequence; reg: Register);
	BEGIN 
		IF reg = ESP THEN
			code.Char(SIBNoScaleESP)
		ELSE HALT(111)
		END
	END SIBNoScale;
	
	PROCEDURE RegisterSizeInBits*(reg: Register): LONGINT;
	BEGIN
		IF Is32BitRegister(reg) THEN RETURN 32
		ELSIF Is16BitRegister(reg) THEN RETURN 16
		ELSIF Is8BitRegister(reg) THEN RETURN 8
		ELSE HALT(111)
		END
	END RegisterSizeInBits;
	
	PROCEDURE Bits*(reg: Register): LONGINT;
	BEGIN
		IF Is8BitRegister(reg) THEN RETURN 8
		ELSIF Is16BitRegister(reg) THEN RETURN 16
		ELSIF Is32BitRegister(reg) THEN RETURN 32
		ELSE HALT(111)
		END
	END Bits;
			
	PROCEDURE Is32BitRegister*(reg: Register): BOOLEAN;
	BEGIN RETURN reg IN {EAX, EBX, ECX, EDX, EBP, ESP, EDI, ESI}
	END Is32BitRegister;
	
	PROCEDURE Is16BitRegister*(reg: Register): BOOLEAN;
	BEGIN RETURN reg IN {AX, BX, CX, DX, BP, SP, DI0, SI}
	END Is16BitRegister;
	
	PROCEDURE Is8BitRegister*(reg: Register): BOOLEAN;
	BEGIN RETURN reg IN {AH, BH, CH, DH, AL, BL, CL, DL}
	END Is8BitRegister;
	
	PROCEDURE IsLow8BitRegister*(reg: Register): BOOLEAN;
	BEGIN RETURN reg IN {AL, BL, CL, DL}
	END IsLow8BitRegister;
	
	PROCEDURE IsHigh8BitRegister*(reg: Register): BOOLEAN;
	BEGIN RETURN reg IN {AH, BH, CH, DH}
	END IsHigh8BitRegister;
	
	PROCEDURE Is8BitValue*(x: LONGINT): BOOLEAN;
	BEGIN RETURN (x >= MIN(SHORTINT)) & (x <= MAX(SHORTINT))
	END Is8BitValue;
	
	PROCEDURE Is16BitValue*(x: LONGINT): BOOLEAN;
	BEGIN RETURN (x >= MIN(INTEGER)) & (x <= MAX(INTEGER))
	END Is16BitValue;
	
	(* EAX => AL etc. *)
	PROCEDURE ConvertToLow*(reg: Register): Register;
	BEGIN
		IF reg IN {AL, AH, AX, EAX} THEN RETURN AL
		ELSIF reg IN {BL, BH, BX, EBX} THEN RETURN BL
		ELSIF reg IN {CL, CH, CX, ECX} THEN RETURN CL
		ELSIF reg IN {DL, DH, DX, EDX} THEN RETURN DL
		ELSE HALT(111)
		END
	END ConvertToLow;
	
	(* EAX => AH etc. *)
	PROCEDURE ConvertToHigh*(reg: Register): Register;
	BEGIN
		IF reg IN {AL, AH, AX, EAX} THEN RETURN AH
		ELSIF reg IN {BL, BH, BX, EBX} THEN RETURN BH
		ELSIF reg IN {CL, CH, CX, ECX} THEN RETURN CH
		ELSIF reg IN {DL, DH, DX, EDX} THEN RETURN DH
		ELSE HALT(111)
		END
	END ConvertToHigh;
	
	(* EAX => AX etc *)
	PROCEDURE ConvertTo16Reg*(reg: Register): Register;
	BEGIN
		IF reg IN {AL, AH, AX, EAX} THEN RETURN AX
		ELSIF reg IN {BL, BH, BX, EBX} THEN RETURN BX
		ELSIF reg IN {CL, CH, CX, ECX} THEN RETURN CX
		ELSIF reg IN {DL, DH, DX, EDX} THEN RETURN DX
		ELSE HALT(111)
		END
	END ConvertTo16Reg;
	
	(* AL/AH/AX => EAX etc. *)
	PROCEDURE ConvertToExtended*(reg: Register): Register;
	BEGIN
		IF reg IN {AL, AH, AX, EAX} THEN RETURN EAX
		ELSIF reg IN {BL, BH, BX, EBX} THEN RETURN EBX
		ELSIF reg IN {CL, CH, CX, ECX} THEN RETURN ECX
		ELSIF reg IN {DL, DH, DX, EDX} THEN RETURN EDX
		ELSE HALT(111)
		END
	END ConvertToExtended;
	
	PROCEDURE ConvertOpTo16Bit*(op: Operand): Operand;
	BEGIN
		IF op.type = OpTypeReg THEN
			op.reg := ConvertTo16Reg(op.reg)
		END;
		op.bits := 16;
		RETURN op
	END ConvertOpTo16Bit;
	
	PROCEDURE ConvertOpTo32Bit*(op: Operand): Operand;
	BEGIN
		IF op.type = OpTypeReg THEN
			op.reg := ConvertToExtended(op.reg)
		END;
		op.bits := 32;
		RETURN op
	END ConvertOpTo32Bit;
							
	(* Helper Procedures *)
	
	PROCEDURE BytesToBits*(bytes: LONGINT): SHORTINT;
	BEGIN RETURN SHORT(SHORT(bytes*8))
	END BytesToBits;
	
	PROCEDURE BitsToBytes*(bits: SHORTINT): LONGINT;
	BEGIN ASSERT(bits MOD 8 = 0); RETURN bits DIV 8
	END BitsToBytes;
	
	PROCEDURE Imm8*(value: LONGINT): SHORTINT;
	BEGIN ASSERT(Is8BitValue(value)); RETURN SHORT(SHORT(value))
	END Imm8;
	
	PROCEDURE Imm16*(value: LONGINT): INTEGER;
	BEGIN ASSERT(Is16BitValue(value)); RETURN SHORT(value)
	END Imm16;

	PROCEDURE Disp(code: CCBasic.DataSequence; op: Operand);
	BEGIN
		IF (op.const # 0) OR ((op.type = OpTypeDeref) & (op.reg = EBP)) THEN
			IF Is8BitValue(op.const) THEN 
				AppendInt8(code, SHORT(SHORT(op.const)))
			ELSE
				AppendInt32(code, op.const)
			END
		END
	END Disp;
	
	PROCEDURE PlusChar(x, y: CHAR): CHAR;
	BEGIN RETURN CHR(ORD(x)+ORD(y))
	END PlusChar;
		
	PROCEDURE AppendInt32(code: CCBasic.DataSequence; value: LONGINT);
	VAR i: LONGINT; a: CCBasic.Integer4Byte;
	BEGIN CCBasic.Encode4ByteInteger(value, a); FOR i := 0 TO LEN(a)-1 DO code.Char(a[i]) END
	END AppendInt32;
	
	PROCEDURE AppendInt16(code: CCBasic.DataSequence; value: INTEGER);
	VAR i: LONGINT; a: CCBasic.Integer2Byte;
	BEGIN CCBasic.Encode2ByteInteger(value, a); FOR i := 0 TO LEN(a)-1 DO code.Char(a[i]) END
	END AppendInt16;
	
	PROCEDURE AppendInt8(code: CCBasic.DataSequence; value: SHORTINT);
	BEGIN code.Char(CHR(value))
	END AppendInt8;
	
	PROCEDURE Align*(code: CCBasic.DataSequence; alignment: LONGINT);
	BEGIN WHILE code.Length() MOD alignment # 0 DO Emit0(code, NOP) END
	END Align;
	
	PROCEDURE WriteOperand*(op: Operand);
	BEGIN
		IF op.type = OpTypeReg THEN
			WriteRegister(op.reg)
		ELSIF op.type = OpTypeImm THEN
			CCBasic.OutInteger(op.const)
		ELSIF op.type = OpTypeDeref THEN
			CCBasic.OutInteger(op.const);
			CCBasic.OutCharacter("["); WriteRegister(op.reg); CCBasic.OutCharacter("]")
		ELSIF op.type = OpTypeFPU THEN
			CCBasic.OutText("FPU")
		ELSE HALT(111)
		END;
		CCBasic.OutText(" ("); CCBasic.OutInteger(op.bits); CCBasic.OutText(" bits)")
	END WriteOperand;
	
	PROCEDURE WriteRegister*(reg: Register);
	VAR x: ARRAY 5 OF CHAR;
	BEGIN
		IF reg = NoReg THEN x := "NONE"
		ELSIF reg = EAX THEN x := "EAX"
		ELSIF reg = EBX THEN x := "EBX"
		ELSIF reg = ECX THEN x := "ECX"
		ELSIF reg = EDX THEN x := "EDX"
		ELSIF reg = EBP THEN x := "EBP"
		ELSIF reg = ESP THEN x := "ESP"
		ELSIF reg = ESI THEN x := "ESI"
		ELSIF reg = EDI THEN x := "EDI"
		ELSIF reg = AL THEN x := "AL"
		ELSIF reg = BL THEN x := "BL"
		ELSIF reg = CL THEN x := "CL"
		ELSIF reg = DL THEN x := "DL"
		ELSIF reg = AH THEN x := "AH"
		ELSIF reg = BH THEN x := "BH"
		ELSIF reg = CH THEN x := "CH"
		ELSIF reg = DH THEN x := "DH"
		ELSIF reg = AX THEN x := "AX"
		ELSIF reg = BX THEN x := "BX"
		ELSIF reg = CX THEN x := "CX"
		ELSIF reg = DX THEN x := "DX"
		ELSIF reg = BP THEN x := "BP"
		ELSIF reg = SP THEN x := "SP"
		ELSIF reg = SI THEN x := "SI"
		ELSIF reg = DI0 THEN x := "DI"
		ELSE HALT(111)
		END;
		CCBasic.OutText(x)
	END WriteRegister;

BEGIN
	Initialize
END CCIx86A.
