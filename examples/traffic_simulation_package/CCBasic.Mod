MODULE CCBasic; (** Component Compiler, Basic Functionality, 2005-2007 by Luc Blaeser *)
	IMPORT SYSTEM, Out, Utilities, AosModules, AosIO, AosLocks;
	
	CONST 
		Pi* = 3.14159265358979323846E0;
		
		InitListSize* = 4;

	TYPE
		Address* = LONGINT;
	
		String* = POINTER TO ARRAY OF CHAR;
		
		RawSection* = POINTER TO ARRAY OF CHAR;
	
		ObjectArray = POINTER TO ARRAY OF PTR;
		
		List* = OBJECT 
			VAR
				list : ObjectArray;
				count : LONGINT;
				multipleAllowed*: BOOLEAN;
				nilAllowed*: BOOLEAN;
			
			PROCEDURE &InitList*;
			BEGIN NEW(list, InitListSize); count := 0; multipleAllowed := FALSE; nilAllowed := FALSE
			END InitList;
			
			PROCEDURE Length*(): LONGINT;
			BEGIN RETURN count
			END Length;
			
			PROCEDURE Grow;
			VAR old: ObjectArray; i: LONGINT;
			BEGIN 
				old := list; 
				NEW(list, LEN(list)*2);
				FOR i := 0 TO count-1 DO list[i] := old[i] END
			END Grow;
		
			PROCEDURE Add*(x: PTR);
			BEGIN
				IF ~nilAllowed THEN ASSERT(x # NIL) END;
				IF ~multipleAllowed THEN ASSERT(~Contains(x)) END; (* already contained *)
				IF count = LEN(list) THEN Grow END;
				list[count] := x;
				INC(count)
			END Add;
			
			PROCEDURE Replace*(x, y: PTR);
			VAR i : LONGINT;
			BEGIN 
				IF ~nilAllowed THEN ASSERT(x # NIL); ASSERT(y # NIL) END;
				i := IndexOf(x);
				IF i >= 0 THEN list[i] := y END
			END Replace;
			
			PROCEDURE ReplaceByIndex*(i: LONGINT; x: PTR);
			BEGIN
				IF ~nilAllowed THEN ASSERT(x # NIL) END;
				IF (i >= 0) & (i < count) THEN
					list[i] := x
				ELSE HALT(101) (* out of boundaries *)
				END
			END ReplaceByIndex;
			
			(** If the object is not present, -1 is returned *)
			PROCEDURE IndexOf*(x: PTR): LONGINT;
			VAR i : LONGINT;
			BEGIN 
				i := 0 ; WHILE i < count DO IF list[i] = x THEN RETURN i END; INC(i) END;
				RETURN -1
			END IndexOf;
			
			PROCEDURE Contains*(x: PTR): BOOLEAN;
			BEGIN RETURN IndexOf(x) # -1
			END Contains;
			
			PROCEDURE Remove*(x : PTR);
			VAR i: LONGINT;
			BEGIN
				i := 0; WHILE (i < count) & (list[i] # x) DO INC(i) END;
				IF i < count THEN 
					WHILE (i < count-1) DO list[i] := list[i+1]; INC(i) END;
					DEC(count); 
					list[count] := NIL
				END
			END Remove;
		
			PROCEDURE Clear*;
			VAR i: LONGINT;
			BEGIN
				FOR i := 0 TO count - 1 DO list[i] := NIL END;
				count := 0
			END Clear;
			
			PROCEDURE GetItem*(i: LONGINT): PTR;
			BEGIN
				IF (i < 0) OR (i >= count) THEN HALT(101) END;
				RETURN list[i]	
			END GetItem;
		END List;
		
		(* not protected by {EXCLUSIVE}, as AosActive/AosMemory does not support customized fine-grained stacks *)
		ProtectedList* = OBJECT 
			VAR
				list : ObjectArray;
				count : LONGINT;
				locked: BOOLEAN;
			
			PROCEDURE &InitList*;
			BEGIN NEW(list, InitListSize); count := 0; locked := FALSE
			END InitList;
			
			PROCEDURE Length*(): LONGINT;
			BEGIN RETURN count
			END Length;
			
			PROCEDURE Grow;
			VAR old: ObjectArray; i: LONGINT;
			BEGIN 
				ASSERT(locked);
				old := list; 
				NEW(list, LEN(list)*2);
				FOR i := 0 TO count-1 DO list[i] := old[i] END
			END Grow;
			
			PROCEDURE Add*(x: PTR);
			BEGIN
				AosLocks.AcquireObject(locked);
				ASSERT(x # NIL);
				IF count = LEN(list) THEN Grow END;
				list[count] := x;
				INC(count);
				AosLocks.ReleaseObject(locked)
			END Add;
			
			(** If the object is not present, -1 is returned *)
			PROCEDURE IndexOf*(x: PTR): LONGINT;
			VAR i : LONGINT; result: LONGINT;
			BEGIN
				AosLocks.AcquireObject(locked);
				result := -1;
				i := 0 ; WHILE i < count DO IF list[i] = x THEN result := i END; INC(i) END;
				AosLocks.ReleaseObject(locked);
				RETURN result
			END IndexOf;
			
			PROCEDURE Contains*(x: PTR): BOOLEAN;
			BEGIN RETURN IndexOf(x) # -1
			END Contains;
			
			PROCEDURE Remove*(x : PTR);
			VAR i: LONGINT;
			BEGIN
				AosLocks.AcquireObject(locked);
				i := 0; WHILE (i < count) & (list[i] # x) DO INC(i) END;
				IF i < count THEN 
					WHILE (i < count-1) DO list[i] := list[i+1]; INC(i) END;
					DEC(count); 
					list[count] := NIL
				END;
				AosLocks.ReleaseObject(locked)
			END Remove;
		
			PROCEDURE Clear*;
			VAR i: LONGINT;
			BEGIN
				AosLocks.AcquireObject(locked);
				FOR i := 0 TO count - 1 DO list[i] := NIL END;
				count := 0;
				AosLocks.ReleaseObject(locked)
			END Clear;
			
			PROCEDURE GetItem*(i: LONGINT): PTR;
			VAR result: PTR;
			BEGIN
				AosLocks.AcquireObject(locked);
				IF (i < 0) OR (i >= count) THEN HALT(101) END;
				result := list[i];
				AosLocks.ReleaseObject(locked);
				RETURN result	
			END GetItem;
		END ProtectedList;
		
		StringArray = POINTER TO ARRAY OF String;
		
		StringList* = OBJECT 
			VAR
				list : StringArray;
				count : LONGINT;
				multipleAllowed*: BOOLEAN;
			
			(** initSize = 0 for default capacity *)
			PROCEDURE &InitList*(initSize: LONGINT);
			BEGIN
				IF initSize <= 0 THEN initSize := InitListSize END;
				NEW(list, initSize); count := 0; multipleAllowed := FALSE
			END InitList;
			
			PROCEDURE Length*(): LONGINT;
			BEGIN RETURN count
			END Length;
			
			PROCEDURE Grow;
			VAR old: StringArray; i: LONGINT;
			BEGIN 
				old := list; 
				NEW(list, LEN(list)*2);
				FOR i := 0 TO count-1 DO list[i] := old[i] END
			END Grow;
		
			PROCEDURE Add*(x: String);
			BEGIN
				ASSERT(x # NIL);
				IF ~multipleAllowed THEN ASSERT(~Contains(x)) END; (* already contained *)
				IF count = LEN(list) THEN Grow END;
				list[count] := x;
				INC(count)
			END Add;
			
			PROCEDURE Replace*(x, y: String);
			VAR i : LONGINT;
			BEGIN 
				i := IndexOf(x);
				IF i >= 0 THEN list[i] := y END
			END Replace;
			
			PROCEDURE ReplaceByIndex*(i: LONGINT; x: String);
			BEGIN
				IF (i >= 0) & (i < count) THEN
					list[i] := x
				ELSE HALT(101) (* out of boundaries *)
				END
			END ReplaceByIndex;
			
			(** If the object is not present, -1 is returned *)
			PROCEDURE IndexOf*(x: String): LONGINT;
			VAR i : LONGINT;
			BEGIN 
				i := 0 ; WHILE i < count DO IF list[i]^ = x^ THEN RETURN i END; INC(i) END;
				RETURN -1
			END IndexOf;
			
			PROCEDURE Contains*(x: String): BOOLEAN;
			BEGIN RETURN IndexOf(x) # -1
			END Contains;
			
			PROCEDURE Remove*(x : String);
			VAR i: LONGINT;
			BEGIN
				i := 0; WHILE (i < count) & (list[i]^ # x^) DO INC(i) END;
				IF i<count THEN 
					WHILE (i < count-1) DO list[i] := list[i+1]; INC(i) END;
					DEC(count); 
					list[count] := NIL
				END
			END Remove;
		
			PROCEDURE Clear*;
			VAR i: LONGINT;
			BEGIN
				FOR i := 0 TO count - 1 DO list[i] := NIL END;
				count := 0
			END Clear;
			
			PROCEDURE GetString*(i: LONGINT): String;
			BEGIN
				IF (i < 0) OR (i >= count) THEN HALT(101) END;
				RETURN list[i]	
			END GetString;
			
			PROCEDURE Equal*(x: StringList): BOOLEAN;
			VAR i: LONGINT; a, b: String;
			BEGIN
				IF Length() = x.Length() THEN
					FOR i := 0 TO Length()-1 DO
						a := GetString(i); b := x.GetString(i);
						IF a^ # b^ THEN RETURN FALSE END
					END;
					RETURN TRUE
				ELSE RETURN FALSE
				END
			END Equal;
		END StringList;
		
		LongIntArray = POINTER TO ARRAY OF LONGINT;
		
		LongIntList* = OBJECT
			VAR
				list : LongIntArray;
				count : LONGINT;
				multipleAllowed*: BOOLEAN;
			
			PROCEDURE &InitList*;
			BEGIN NEW(list, InitListSize); count := 0; multipleAllowed := FALSE
			END InitList;

			PROCEDURE Length*(): LONGINT;
			BEGIN RETURN count
			END Length;
			
			PROCEDURE Grow;
			VAR old: LongIntArray; i: LONGINT;
			BEGIN 
				old := list; 
				NEW(list, LEN(list)*2);
				FOR i := 0 TO count-1 DO list[i] := old[i] END
			END Grow;

			PROCEDURE Add*(x: LONGINT);
			BEGIN
				IF ~multipleAllowed THEN ASSERT(~Contains(x)) END; (* already contained *)
				IF count = LEN(list) THEN Grow END;
				list[count] := x;
				INC(count)
			END Add;
			
			PROCEDURE Replace*(x, y: LONGINT);
			VAR i : LONGINT;
			BEGIN 
				i := IndexOf(x);
				IF i >= 0 THEN list[i] := y END
			END Replace;

			PROCEDURE ReplaceByIndex*(i: LONGINT; x: LONGINT);
			BEGIN
				IF (i >= 0) & (i < count) THEN
					list[i] := x
				ELSE HALT(101) (* out of boundaries *)
				END
			END ReplaceByIndex;
			
			(** If the object is not present, -1 is returned *)
			PROCEDURE IndexOf*(x: LONGINT): LONGINT;
			VAR i : LONGINT;
			BEGIN 
				i := 0 ; WHILE i < count DO IF list[i] = x THEN RETURN i END; INC(i) END;
				RETURN -1
			END IndexOf;
			
			PROCEDURE Contains*(x: LONGINT): BOOLEAN;
			BEGIN RETURN IndexOf(x) # -1
			END Contains;
			
			PROCEDURE Remove*(x : LONGINT);
			VAR i: LONGINT;
			BEGIN
				i := 0; WHILE (i < count) & (list[i] # x) DO INC(i) END;
				IF i<count THEN 
					WHILE (i < count-1) DO list[i] := list[i+1]; INC(i) END;
					DEC(count); 
					list[count] := 0
				END
			END Remove;

			PROCEDURE Clear*;
			VAR i: LONGINT;
			BEGIN
				FOR i := 0 TO count - 1 DO list[i] := 0 END;
				count := 0
			END Clear;
			
			PROCEDURE GetItem*(i: LONGINT): LONGINT;
			BEGIN
				IF (i < 0) OR (i >= count) THEN HALT(101) END;
				RETURN list[i]	
			END GetItem;
						
			PROCEDURE Equal*(x: LongIntList): BOOLEAN;
			VAR i: LONGINT;
			BEGIN
				IF Length() = x.Length() THEN
					FOR i := 0 TO Length()-1 DO
						IF GetItem(i) # x.GetItem(i) THEN RETURN FALSE END
					END;
					RETURN TRUE
				ELSE
					RETURN FALSE
				END
			END Equal;
			
			PROCEDURE Print*;
			VAR i: LONGINT;
			BEGIN
				OutText("("); 
				FOR i := 0 TO Length()-1 DO 
					OutInteger(GetItem(i)); 
					IF i < Length()-1 THEN OutText(", ") END
				END;
				OutText(")"); OutLine
			END Print;
		END LongIntList;
					
	CONST 
		DataBlockSize = 32;
	
	TYPE
		Integer4Byte* = ARRAY 4 OF CHAR;
		Integer2Byte* = ARRAY 2 OF CHAR;
	
		DataBlock = OBJECT
			VAR
				next: DataBlock;
				data: ARRAY DataBlockSize OF CHAR;
		END DataBlock;

		DataSequence* = OBJECT
			VAR
				length: LONGINT;
				firstBlock, lastBlock: DataBlock;

			PROCEDURE &InitDataSequence;
			BEGIN length := 0; NEW(firstBlock); lastBlock := firstBlock; firstBlock.next := NIL
			END InitDataSequence;
			
			PROCEDURE Length*(): LONGINT;
			BEGIN RETURN length
			END Length;
			
			PROCEDURE LocalPos(): LONGINT;
			VAR p: DataBlock;
			BEGIN
				IF (length > 0) & (length MOD DataBlockSize = 0) THEN
					NEW(p); p.next := NIL; lastBlock.next := p; lastBlock := p
				END;
				RETURN length MOD DataBlockSize
			END LocalPos;
		
			PROCEDURE Char*(x: CHAR);
			VAR pos: LONGINT;
			BEGIN pos := LocalPos(); lastBlock.data[pos] := x; INC(length)
			END Char;
			
			PROCEDURE GetInternalPosition(pos: LONGINT; VAR block: DataBlock; VAR localOffset: LONGINT);
			VAR p: DataBlock;
			BEGIN
				IF (pos < 0) OR (pos >= length) THEN HALT(105) (* invalid position *) END;
				p := firstBlock;
				WHILE pos >= DataBlockSize DO
					p := p.next; DEC(pos, DataBlockSize)
				END;
				block := p; localOffset := pos
			END GetInternalPosition;
			
			PROCEDURE ChangeChar*(pos: LONGINT; x: CHAR);
			VAR block: DataBlock; offset: LONGINT;
			BEGIN
				GetInternalPosition(pos, block, offset); block.data[offset] := x
			END ChangeChar;
			
			PROCEDURE GetChar*(pos: LONGINT): CHAR;
			VAR block: DataBlock; offset: LONGINT;
			BEGIN GetInternalPosition(pos, block, offset); RETURN block.data[offset]
			END GetChar;
			
			PROCEDURE GetInteger4*(pos: LONGINT): LONGINT;
			VAR i: LONGINT; a: Integer4Byte; x: LONGINT;
			BEGIN
				FOR i := 0 TO LEN(a)-1 DO
					a[i] := GetChar(pos + i)
				END;
				Decode4ByteInteger(a, x);
				RETURN x
			END GetInteger4;
			
			PROCEDURE GetInteger2*(pos: LONGINT): INTEGER;
			VAR i: LONGINT; a: Integer2Byte; x: INTEGER;
			BEGIN
				FOR i := 0 TO LEN(a)-1 DO
					a[i] := GetChar(pos + i)
				END;
				Decode2ByteInteger(a, x);
				RETURN x
			END GetInteger2;
			
			PROCEDURE Text*(a: ARRAY OF CHAR);
			VAR i: LONGINT;
			BEGIN
				i := 0; WHILE (i < LEN(a)) & (a[i] # 0X) DO Char(a[i]); INC(i) END;
				Char(0X)
			END Text;
			
			PROCEDURE Integer1*(x: SHORTINT);
			BEGIN Char(CHR(x))
			END Integer1;
			
			PROCEDURE Integer2*(x: INTEGER);
			VAR a: Integer2Byte; i: LONGINT;
			BEGIN
				Encode2ByteInteger(x, a);
				FOR i := 0 TO LEN(a)-1 DO Char(a[i]) END
			END Integer2;
			
			PROCEDURE Integer4*(x: LONGINT);
			VAR a: Integer4Byte; i: LONGINT;
			BEGIN
				Encode4ByteInteger(x, a);
				FOR i := 0 TO LEN(a)-1 DO Char(a[i]) END
			END Integer4;
			
			PROCEDURE Real4*(x: REAL);
			BEGIN Integer4(SYSTEM.VAL(LONGINT, x))
			END Real4;
			
			PROCEDURE ChangeInteger4*(pos: LONGINT; x: LONGINT);
			VAR a: Integer4Byte; i: LONGINT;
			BEGIN
				Encode4ByteInteger(x, a);
				FOR i := 0 TO LEN(a)-1 DO ChangeChar(pos+i, a[i]) END
			END ChangeInteger4;
						
			PROCEDURE Write*(w: AosIO.Writer);
			VAR b: DataBlock; k, m: LONGINT;
			BEGIN 
				b := firstBlock; 
				FOR k := 0 TO (length DIV DataBlockSize)-1 DO
					FOR m := 0 TO DataBlockSize-1 DO w.Char(b.data[m]) END;
					b := b.next
				END;
				FOR m := 0 TO (length MOD DataBlockSize)-1 DO w.Char(b.data[m]) END
			END Write;
			
			PROCEDURE GetRawSection*(): RawSection;
			VAR b: DataBlock; i, k, m: LONGINT; section: RawSection;
			BEGIN
				NEW(section, length);
				b := firstBlock; 
				i := 0;
				FOR k := 0 TO (length DIV DataBlockSize)-1 DO
					FOR m := 0 TO DataBlockSize-1 DO 
						section[i] := b.data[m]; INC(i)
					END;
					b := b.next
				END;
				FOR m := 0 TO (length MOD DataBlockSize)-1 DO 
					section[i] := b.data[m]; INC(i)
				END;
				RETURN section
			END GetRawSection;
		END DataSequence;
		
	VAR RandomZ: LONGINT;
	
	PROCEDURE RandomUniform*(): REAL;
	CONST a = 16807; m = 2147483647; q = m DIV a; r = m MOD a;
	VAR g: LONGINT;
	BEGIN
		g := a*(RandomZ MOD q) - r*(RandomZ DIV q);
		IF g > 0 THEN RandomZ := g ELSE RandomZ := g + m END;
		RETURN SHORT(RandomZ*1.0D0/m)	(* must compute this in double precision, e.g. (m-1)/m *)
	END RandomUniform;
	
	PROCEDURE RandomInitSeed*(seed: LONGINT);
	BEGIN RandomZ := seed
	END RandomInitSeed;

	PROCEDURE NewString*(name: ARRAY OF CHAR): String;
	VAR str: String;
	BEGIN NEW(str, Utilities.Length(name) + 1); COPY(name, str^); RETURN str
	END NewString;
	
	PROCEDURE Length*(name: ARRAY OF CHAR): LONGINT;
	VAR i: LONGINT;
	BEGIN
		i := 0; WHILE (i < LEN(name)) & (name[i] # 0X) DO INC(i) END;
		IF i < LEN(name) THEN INC(i) END;
		RETURN i
	END Length;
	
	PROCEDURE CopyString*(x: String): String;
	VAR y: String; i: LONGINT;
	BEGIN NEW(y, LEN(x)); FOR i := 0 TO LEN(x)-1 DO y[i] := x[i] END; RETURN y
	END CopyString;
	
	(** a.b *)
	PROCEDURE ConcatWithDot*(a, b: ARRAY OF CHAR): String;
	BEGIN RETURN ConcatWithSeparator(a, ".", b)
	END ConcatWithDot;
	
	PROCEDURE ConcatWithSeparator*(a, separator, b: ARRAY OF CHAR): String;
	VAR str: String; 
	BEGIN 
		NEW(str, Utilities.Length(a) + Utilities.Length(b) + 2); 
		COPY(a, str^); Utilities.Append(str^, separator); Utilities.Append(str^, b);
		RETURN str
	END ConcatWithSeparator;
	
	PROCEDURE ConcatWithNumber*(a: ARRAY OF CHAR; b: LONGINT): String;
	VAR str: String; bs: ARRAY 12 OF CHAR;
	BEGIN
		Utilities.IntToStr(b, bs); NEW(str, Utilities.Length(a) + Utilities.Length(bs) + 1);
		COPY(a, str^); Utilities.Append(str^, bs); RETURN str
	END ConcatWithNumber;
			
	PROCEDURE Error*(pos: LONGINT; text: ARRAY OF CHAR);
	BEGIN Error3(pos, text, "", "")
	END Error;
	
	PROCEDURE Error3*(pos: LONGINT; x, y, z: ARRAY OF CHAR);
	BEGIN
		Out.String(" pos "); Out.Int(pos, 0); Out.String(" error "); 
		Out.String(x); Out.String(y); Out.String(z); Out.Ln
	END Error3;
	
	(* synchronization because Out is not concurrency-safe *)
	
	PROCEDURE OutText*(text: ARRAY OF CHAR);
	BEGIN Out.String(text)
	END OutText;
		
	PROCEDURE OutCharacter*(c: CHAR);
	BEGIN Out.Char(c)
	END OutCharacter;
	
	PROCEDURE OutInteger*(i: LONGINT);
	BEGIN Out.Int(i, 0)
	END OutInteger;
	
	PROCEDURE OutReal*(r: REAL);
	BEGIN Out.Real(r, 15)
	END OutReal;
	
	PROCEDURE OutHex*(i: LONGINT);
	BEGIN Out.Hex(i)
	END OutHex;
	
	PROCEDURE OutLine*;
	BEGIN Out.Ln
	END OutLine;
	
	PROCEDURE TextToInteger*(text: ARRAY OF CHAR; VAR val: LONGINT);
	VAR i, d: LONGINT; neg: BOOLEAN;
	BEGIN
		i := 0;
		neg := FALSE; 
		IF text[i] = "+" THEN INC(i)
		ELSIF text[i] = "-" THEN neg := TRUE; INC(i)
		END;
		val := 0;
		WHILE (text[i] >= "0") & (text[i] <= "9") DO
			d := ORD(text[i])-ORD("0");
			IF (val <= ((MAX(LONGINT)-d) DIV 10)) THEN val := 10*val + d
			ELSIF neg & (val = MAX(LONGINT) DIV 10) & (d = 8) & ((text[i] < "0") OR (text[i] > "9")) THEN
				val := MIN(LONGINT); neg := FALSE
			ELSE
				HALT(100)
			END;
			INC(i)
		END;
		IF neg THEN val := -val END
	END TextToInteger;
	
	PROCEDURE UnsignedInt*(x: INTEGER): LONGINT;
	BEGIN RETURN SYSTEM.LSH(SYSTEM.LSH(LONG(x), 16), -16)
	END UnsignedInt;
								
	PROCEDURE IsPowerOf2*(x: LONGINT): BOOLEAN;
	BEGIN
		IF x < 0 THEN RETURN FALSE
		ELSE
			WHILE x > 1 DO
				IF x MOD 2 = 0 THEN x := x DIV 2
				ELSE RETURN FALSE
				END
			END;
			RETURN TRUE
		END
	END IsPowerOf2;
	
	PROCEDURE LogarithmBasis2*(x: LONGINT): SHORTINT;
	VAR i: SHORTINT;
	BEGIN
		ASSERT(x >= 0);
		i := 0;
		WHILE x > 1 DO
			IF x MOD 2 = 0 THEN INC(i); x := x DIV 2
			ELSE HALT(104) (* x is not a power of 2 *)
			END
		END;
		RETURN i
	END LogarithmBasis2;
	
	PROCEDURE BitMaskWithLowerSetBits*(bits: SHORTINT): LONGINT;
	VAR k, m, x: LONGINT;
	BEGIN
		x := 0; m := 1;
		FOR k := 1 TO bits DO INC(x, m); m := m*2 END;
		RETURN x
	END BitMaskWithLowerSetBits;
	
	PROCEDURE BitMask*(bits: SET): LONGINT;
	BEGIN RETURN SYSTEM.VAL(LONGINT, bits)
	END BitMask;

	PROCEDURE TextLength*(x: String): LONGINT;
	BEGIN RETURN Utilities.Length(x^)
	END TextLength;
	
	PROCEDURE Encode1ByteInteger*(x: SHORTINT; VAR c: CHAR);
	BEGIN c := CHR(x)
	END Encode1ByteInteger;
	
	PROCEDURE Encode2ByteInteger*(x: INTEGER; VAR a: Integer2Byte);
	VAR i: LONGINT;
	BEGIN FOR i := 0 TO LEN(a)-1 DO a[i] := CHR(x MOD 100H); x := SYSTEM.LSH(x, -8) END
	END Encode2ByteInteger;
	
	PROCEDURE Decode2ByteInteger*(a: Integer2Byte; VAR x: INTEGER);
	VAR i: LONGINT;
	BEGIN x := 0; FOR i := LEN(a)-1 TO 0 BY -1 DO x := SYSTEM.LSH(x, 8) + ORD(a[i]) END
	END Decode2ByteInteger;
	
	PROCEDURE Encode4ByteInteger*(x: LONGINT; VAR a: Integer4Byte);
	VAR i: LONGINT;
	BEGIN FOR i := 0 TO LEN(a)-1 DO a[i] := CHR(x MOD 100H); x := SYSTEM.LSH(x, -8) END
	END Encode4ByteInteger;
	
	PROCEDURE Decode4ByteInteger*(a: Integer4Byte; VAR x: LONGINT);
	VAR i: LONGINT;
	BEGIN x := 0; FOR i := LEN(a)-1 TO 0 BY -1 DO x := SYSTEM.LSH(x, 8) + ORD(a[i]) END
	END Decode4ByteInteger;
	
	PROCEDURE EncodeReal*(x: REAL): LONGINT;
	BEGIN RETURN SYSTEM.VAL(LONGINT, x)
	END EncodeReal;
	
	PROCEDURE -Arctan*(x: REAL): REAL;
	CODE {SYSTEM.i386, SYSTEM.FPU}
		DB 0D9H, 004H, 024H	(* FLD [ESP] *)
		DB 0D9H, 0E8H	(* FLD1 *)
		DB 0D9H, 0F3H	(* FPATAN ST(1)/ST(0) *)
		DB 058H	(* POP EAX *)
	END Arctan;
	
	PROCEDURE -Sqrt*(x: REAL): REAL;
	CODE {SYSTEM.i386, SYSTEM.FPU}
		DB 0D9H, 004H, 024H	(* FLD [ESP] *)
		DB 0D9H, 0FAH	(* FSQRT ST(0) *)
		DB 058H	(* POP EAX *)
	END Sqrt;
	
	PROCEDURE -AtomicIncByAdr*(adr: Address);
	CODE {SYSTEM.i386}
		POP EAX	; ADR(x)
		LOCK
		INC DWORD [EAX]
	END AtomicIncByAdr;
	
	PROCEDURE -AtomicDecByAdr*(adr: Address);
	CODE {SYSTEM.i386}
		POP EAX	; ADR(x)
		LOCK
		DEC DWORD [EAX]
	END AtomicDecByAdr;
	
	PROCEDURE -AtomicInc*(VAR x: LONGINT);
	CODE {SYSTEM.i386}
		POP EAX	; ADR(x)
		LOCK
		INC DWORD [EAX]
	END AtomicInc;
	
	PROCEDURE -AtomicDec*(VAR x: LONGINT);
	CODE {SYSTEM.i386}
		POP EAX	; ADR(x)
		LOCK
		DEC DWORD [EAX]
	END AtomicDec;
			
BEGIN RandomInitSeed(1344)
END CCBasic.
