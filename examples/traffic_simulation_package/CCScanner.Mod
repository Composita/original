MODULE CCScanner; (** Component Compiler, Symbol Scanner, 2005-2007 by Luc Blaeser *)
	IMPORT CCBasic, AosIO, Utilities;
	
	CONST
		(* Token types *)
		EndOfText* = 1;
		LeftParenthesis* = 2; RightParenthesis* = 3;
		Semicolon* = 4; 
		ExclamationMark* = 5;
		Component* = 6;
		Interface* = 7;
		Begin* = 8; End* = 9;
		Dot* = 10;
		Colon* = 11;
		Star* = 12; 
		Plus* = 13; 
		Minus* = 14; 
		DivToken* = 15; (* DIV *)
		Mod* = 16;
		Variable* = 17;
		Comma* = 18;
		Assign* = 19; (* := *)
		Tilde* = 20; (* ~ *)
		True* = 21; False* = 22;
		And* = 23; 
		Or* = 24;
		Equal* = 25;
		Unequal* = 26; (* # *)
		Less* = 27;
		Greater* = 28;
		LessEqual* = 29;
		GreaterEqual* = 30;
		LeftBracket* = 31; RightBracket* = 32;
		If* = 33; Elsif* = 34; Else* = 35; Then* = 36;
		While* = 37; Do* = 38;
		Repeat* = 39; Until* = 40;
		For* = 41; To* = 42; By* = 43;
		VerticalLine* = 44;
		In* = 45; Out* = 46;
		LeftBrace* = 47; RightBrace* = 48;
		QuestionMark* = 49;
		Implementation* = 50;
		Offers* = 51; Requires* = 52;
		Any* = 53;
		Input* = 54;
		Await* = 55;
		New* = 56;
		Connect* = 57;
		Disconnect* = 58;
		Foreach* = 59;
		Of* = 60;
		Finally* = 61;
		Constant* = 62;
		Finish* = 63;
		Is* = 64;
		Slash* = 65;
		Activity* = 66;
		Procedure* = 67;
		Return* = 68;
		
		MaxStringSize = 1024; (* maximum string size in program text *)
		MaxNumberSize = 10; (* maximum length of number representation in program text *)
	TYPE 
		Symbol* = OBJECT 
		END Symbol;
		
		Identifier* = OBJECT(Symbol)
		  VAR s-: CCBasic.String;
		END Identifier;
		
		Token* = OBJECT(Symbol)
		  VAR type-: LONGINT; (* Token type *)
		END Token;
		
		Value* = OBJECT(Symbol)
		END Value;
				
		TextValue* = OBJECT(Value)
			VAR s-: CCBasic.String;
		END TextValue;
		
		IntegerValue* = OBJECT(Value)
			VAR i-: LONGINT;
		END IntegerValue;
		
		RealValue* = OBJECT(Value)
			VAR r-: REAL;
		END RealValue;
		
		CharacterValue* = OBJECT(Value)
			VAR c-: CHAR;
		END CharacterValue;

	VAR
		position-, symbolBeginPosition-: LONGINT; 
		reader: AosIO.Reader; length: LONGINT; eot: BOOLEAN; ch: CHAR;
		error-: BOOLEAN;
	
	PROCEDURE NextSymbol*(): Symbol;
	VAR str: ARRAY MaxStringSize OF CHAR; s: Symbol;
	BEGIN
		s := NIL;
		REPEAT
			WHILE ~eot & (ch <= " ") DO NextChar END; (* ignore control characters *)
			symbolBeginPosition := position;
			IF eot THEN
				s := CreateToken(EndOfText)
			ELSE
				CASE ch OF 
					  22X: s := ReadString();
				|	"0" .. "9": s := ReadNumber(FALSE);
				|	"+": s := CreateToken(Plus); NextChar;
				|	"-": s := CreateToken(Minus); NextChar;
				|	"(": NextChar;
								IF ~eot & (ch = "*") THEN ReadComment ELSE s := CreateToken(LeftParenthesis) END
				|	")": s := CreateToken(RightParenthesis); NextChar
				|	";": s := CreateToken(Semicolon); NextChar
				|	"!": s := CreateToken(ExclamationMark); NextChar
				|	"?": s := CreateToken(QuestionMark); NextChar
				|	".": s := CreateToken(Dot); NextChar
				|	":": NextChar;
								IF ~eot & (ch = "=") THEN s := CreateToken(Assign); NextChar
								ELSE s := CreateToken(Colon) 
								END
				|	"*": s := CreateToken(Star); NextChar
				|	"/": s := CreateToken(Slash); NextChar
				|	",": s := CreateToken(Comma); NextChar
				|	"~": s := CreateToken(Tilde); NextChar
				|	"=": s := CreateToken(Equal); NextChar
				|	"#": s := CreateToken(Unequal); NextChar
				|	"|": s := CreateToken(VerticalLine); NextChar
				|	"[": s := CreateToken(LeftBracket); NextChar
				|	"]": s := CreateToken(RightBracket); NextChar
				|	"{": s := CreateToken(LeftBrace); NextChar
				|	"}": s := CreateToken(RightBrace); NextChar
				|	"<": NextChar;
								IF ~eot & (ch = "=") THEN s := CreateToken(LessEqual); NextChar
								ELSE s := CreateToken(Less)
								END
				|	">": NextChar;
								IF ~eot & (ch = "=") THEN s := CreateToken(GreaterEqual); NextChar
								ELSE s := CreateToken(Greater)
								END
				|	"A": ReadIdentifier(str);
								IF str = "ACTIVITY" THEN s := CreateToken(Activity)
								ELSIF str = "AND" THEN s := CreateToken(And)
								ELSIF str = "ANY" THEN s := CreateToken(Any)
								ELSIF str = "AWAIT" THEN s := CreateToken(Await)
								ELSE s := CreateIdentifier(str)
								END
				|    "B": ReadIdentifier(str);
								IF str = "BEGIN" THEN s := CreateToken(Begin)
								ELSIF str = "BY" THEN s := CreateToken(By)
								ELSE s := CreateIdentifier(str)
								END
				|	"C": ReadIdentifier(str);
								IF str = "COMPONENT" THEN s := CreateToken(Component)
								ELSIF str = "CONNECT" THEN s := CreateToken(Connect)
								ELSIF str = "CONSTANT" THEN s := CreateToken(Constant)
								ELSE s := CreateIdentifier(str) 
								END
				|	"D": ReadIdentifier(str);
								IF str = "DIV" THEN s := CreateToken(DivToken)
								ELSIF str = "DO" THEN s := CreateToken(Do)
								ELSIF str = "DISCONNECT" THEN s := CreateToken(Disconnect)
								ELSE s := CreateIdentifier(str)
								END
				|	"E": ReadIdentifier(str);
								IF str = "END" THEN s := CreateToken(End)
								ELSIF str = "ELSIF" THEN s := CreateToken(Elsif)
								ELSIF str = "ELSE" THEN s := CreateToken(Else)
								ELSE s := CreateIdentifier(str)
								END
				|	"F": ReadIdentifier(str);
								IF str = "FALSE" THEN s := CreateToken(False)
								ELSIF str = "FINALLY" THEN s := CreateToken(Finally)
								ELSIF str = "FOR" THEN s := CreateToken(For)
								ELSIF str = "FOREACH" THEN s := CreateToken(Foreach)
								ELSIF str = "FINISH" THEN s := CreateToken(Finish)
								ELSE s := CreateIdentifier(str)
								END
				|	"I": ReadIdentifier(str);
								IF str = "IF" THEN s := CreateToken(If)
								ELSIF str = "INTERFACE" THEN s := CreateToken(Interface)
								ELSIF str = "IN" THEN s := CreateToken(In)
								ELSIF str = "IMPLEMENTATION" THEN s := CreateToken(Implementation)
								ELSIF str = "INPUT" THEN s := CreateToken(Input)
								ELSIF str = "IS" THEN s := CreateToken(Is)
								ELSE s := CreateIdentifier(str)
								END
				|    "M": ReadIdentifier(str);
								IF str = "MOD" THEN s := CreateToken(Mod)
								ELSE s := CreateIdentifier(str)
								END
				|	"N": ReadIdentifier(str);
								IF str = "NEW" THEN s := CreateToken(New)
								ELSE s := CreateIdentifier(str)
								END
				|	"O": ReadIdentifier(str);
								IF str = "OR" THEN s := CreateToken(Or)
								ELSIF str = "OUT" THEN s := CreateToken(Out)
								ELSIF str = "OFFERS" THEN s := CreateToken(Offers)
								ELSIF str = "OF" THEN s := CreateToken(Of)
								ELSE s := CreateIdentifier(str)
								END
				|	"P": ReadIdentifier(str);
								IF str = "PROCEDURE" THEN s := CreateToken(Procedure)
								ELSE s := CreateIdentifier(str)
								END
				|	"R": ReadIdentifier(str);
								IF str = "REPEAT" THEN s := CreateToken(Repeat)
								ELSIF str = "REQUIRES" THEN s := CreateToken(Requires)
								ELSIF str = "RETURN" THEN s := CreateToken(Return)
								ELSE s := CreateIdentifier(str)
								END
				|	"T": ReadIdentifier(str);
								IF str = "TRUE" THEN s := CreateToken(True)
								ELSIF str = "THEN" THEN s := CreateToken(Then)
								ELSIF str = "TO" THEN s := CreateToken(To)
								ELSE s := CreateIdentifier(str)
								END
				|	"U": ReadIdentifier(str);
								IF str = "UNTIL" THEN s := CreateToken(Until)
								ELSE s := CreateIdentifier(str)
								END
				|	"V": ReadIdentifier(str);
								IF str = "VARIABLE" THEN s := CreateToken(Variable)
								ELSE s := CreateIdentifier(str)
								END
				|	"W": ReadIdentifier(str);
								IF str = "WHILE" THEN s := CreateToken(While)
								ELSE s := CreateIdentifier(str)
								END
				| 	"G", "H", "J", "K", "L", "Q", "S", "X", "Y", "Z", "a" .. "z": 
								ReadIdentifier(str); s := CreateIdentifier(str) (* identifier only start with a letter *)
				ELSE 
					Error(symbolBeginPosition, "Invalid symbol "); CCBasic.OutCharacter(ch); (* not implemented *)
					NextChar
				END
			END
		UNTIL s # NIL;
		RETURN s
	END NextSymbol;
	
	PROCEDURE ReadComment;
	VAR exit: BOOLEAN;
	BEGIN
		exit := FALSE;
		REPEAT 
			NextChar;
			IF ~eot THEN
				IF ch = "*" THEN
					NextChar; 
					IF ~eot & (ch = ")") THEN exit := TRUE END
				ELSIF ch = "(" THEN
					NextChar;
					IF ~eot & (ch = "*") THEN ReadComment END
				END
			END
		UNTIL eot OR exit;
		IF eot THEN Error(position, "Invalid end of text")
		ELSE NextChar 
		END
	END ReadComment;
	
	PROCEDURE ReadIdentifier(VAR str: ARRAY OF CHAR);
	VAR i: LONGINT;
	BEGIN
		i := 0;
		REPEAT
			str[i] := ch; INC(i); NextChar;
		UNTIL eot OR (i = LEN(str)-1) OR ~IsIdentifierChar(ch);
		str[i] := 0X;
		IF ~eot & (i = LEN(str)-1) & IsIdentifierChar(ch) THEN
			Error(position, "Too long text value"); Stop
		END
	END ReadIdentifier;
	
	PROCEDURE IsIdentifierChar(ch: CHAR): BOOLEAN;
	BEGIN RETURN ((ch >= "0") & ("9" >= ch)) OR ((CAP(ch) >= "A") & ("Z" >= CAP(ch)))
	END IsIdentifierChar;
	
	PROCEDURE ReadString(): Symbol;
	VAR a: ARRAY MaxStringSize OF CHAR; i: LONGINT; tv: TextValue; cv: CharacterValue; s: Symbol;
	BEGIN 
		i := 0; NextChar; (* skip opening double quotation mark *)
		WHILE ~eot & (i < LEN(a)-1) & (ch # 22X) DO a[i] := ch; INC(i); NextChar END;
		a[i] := 0X;
		IF eot THEN 
			Error(position, "Invalid end of program");
			s := CreateToken(EndOfText)
		ELSIF i = LEN(a)-1 THEN 
			Error(position, "Too long text value");
			s := CreateToken(EndOfText); Stop
		ELSE
			IF i = 1 THEN
				NEW(cv); cv.c := a[0]; s := cv
			ELSE
				NEW(tv); NEW(tv.s, i+1); COPY(a, tv.s^); s := tv
			END;
			NextChar (* skip closing quote mark *)
		END;
		RETURN s
	END ReadString;

	PROCEDURE ReadNumber(negative: BOOLEAN): Symbol;
	VAR a: ARRAY MaxNumberSize OF SHORTINT; i, k, v, d, scale: LONGINT; r, m: REAL; b: SHORTINT; isHex, isChar: BOOLEAN; 
		iv: IntegerValue; cv: CharacterValue; rv: RealValue; negativeScale: BOOLEAN;
	BEGIN
		i := 0; isHex := FALSE; isChar := FALSE;
		WHILE ~eot & (i < LEN(a)) & (((ch >= "0") & (ch <= "9")) OR  
				((ch >= "A") & (ch <= "F"))) DO
			IF (ch >= "A") & (ch <= "F") THEN 
				isHex := TRUE; 
				a[i] := SHORT(ORD(ch)-ORD("A")+10)
			ELSE 
				a[i] := SHORT(ORD(ch)-ORD("0"))
			END;
			INC(i); NextChar
		END;
		IF isHex THEN
			IF ch = "H" THEN NextChar
			ELSIF ch = "X" THEN NextChar; isChar := TRUE
			ELSE Error(symbolBeginPosition, "'H' or 'X' after hexadecimal number missing")
			END
		ELSIF ch = "H" THEN 
			NextChar; isHex := TRUE
		ELSIF ch = "X" THEN
			NextChar; isHex := TRUE; isChar := TRUE
		END;
		
		v := 0;
		FOR k := 0 TO i-1 DO
			IF isHex THEN d := 16 ELSE d := 10 END;
			(* 	static overflow check:
				d*v + a[k] > m (where 0 <= a[k] < d)
			  <=> (v > m DIV d) OR ((v = m DIV d) & (a[k] > m MOD d))
			*)
			IF negative THEN
				IF (v < (MIN(LONGINT)+d-1) DIV d) OR ((v = (MIN(LONGINT)+d-1) DIV d) & 
						(-a[k] < MIN(LONGINT)-d*((MIN(LONGINT)+d-1) DIV d))) THEN
					Error(symbolBeginPosition, "Not representable integer number")
				END;	
				v := v*d - a[k]
			ELSE (* positive *)
				IF (v > MAX(LONGINT) DIV d) OR ((v = MAX(LONGINT) DIV d) & (a[k] > MAX(LONGINT) MOD d)) THEN 
					Error(symbolBeginPosition, "Not representable integer number") 
				END;
				v := v*d + a[k]
			END
		END;
		IF i = 0 THEN Error(position, "Invalid number, missing digits") END;
		IF ~isChar & ~isHex & (ch = ".") & (PeekNext() # ".") THEN (* real *)
			NextChar;
			r := v;
			m := 1.0;
			WHILE ~eot & (ch >= "0") & (ch <= "9") DO
				b := SHORT(ORD(ch) - ORD("0"));
				m := m / 10;
				r := r + b * m;
				NextChar
			END;
			IF ch = "E" THEN (* scale factor *)
				NextChar;
				negativeScale := FALSE;
				IF ch = "+" THEN NextChar
				ELSIF ch = "-" THEN NextChar; negativeScale := TRUE
				END;
				scale := 0;
				WHILE ~eot & (ch >= "0") & (ch <= "9") DO
					b := SHORT(ORD(ch) - ORD("0"));
					scale := scale * 10 + b;
					NextChar
				END;
				FOR k := 1 TO scale DO
					IF negativeScale THEN r := r / 10
					ELSE r := r * 10
					END
				END
			END;
			NEW(rv); rv.r := r;
			RETURN rv
		ELSIF isChar THEN (* character *)
			IF (v < 0) OR (v > 0FFH) THEN
				Error(symbolBeginPosition, "Invalid character number")
			END;
			NEW(cv); cv.c := CHR(SHORT(SHORT(v)));
			RETURN cv
		ELSE (* integer *)
			NEW(iv); iv.i := v;
			RETURN iv
		END
	END ReadNumber;
	
	PROCEDURE NextChar;
	BEGIN
		IF eot THEN HALT(111)
		ELSIF reader.Pos() = length THEN eot := TRUE; ch := 0X
		ELSE reader.Char(ch); INC(position)
		END
	END NextChar;
	
	PROCEDURE PeekNext(): CHAR;
	BEGIN
		IF eot THEN HALT(111)
		ELSIF reader.Pos() = length THEN RETURN 0X
		ELSE RETURN reader.Peek()
		END
	END PeekNext;
	
	PROCEDURE CreateToken*(type: LONGINT): Symbol;
	VAR t: Token;
	BEGIN NEW(t); t.type := type; RETURN t
	END CreateToken;
	
	PROCEDURE CreateIdentifier*(str: ARRAY OF CHAR): Symbol;
	VAR id: Identifier;
	BEGIN NEW(id); NEW(id.s, Utilities.Length(str)+1); COPY(str, id.s^); RETURN id
	END CreateIdentifier;
	
	PROCEDURE Stop;
	BEGIN eot := TRUE; ch := 0X
	END Stop;
		
	PROCEDURE InitializeScanner*(r: AosIO.Reader; len: LONGINT);
	BEGIN 
		error := FALSE; reader := r; length := len; eot := FALSE; position := -1; symbolBeginPosition := -1;
		NextChar
	END InitializeScanner;
	
	PROCEDURE Error(pos: LONGINT; text: ARRAY OF CHAR);
	BEGIN error := TRUE; CCBasic.Error(pos, text)
	END Error;
END CCScanner.

