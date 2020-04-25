COMPONENT Eratosthenes REQUIRES SystemTime; 
	CONSTANT 
		N = 10000; (* number limit *)
		Output = FALSE;
	
	INTERFACE NumberStream;
		{ OUT Number(x: INTEGER) } OUT Finished
	END NumberStream;
	
	INTERFACE Prime;
		OUT PrimeNumber(x: INTEGER) | OUT Finished
	END Prime;
	
	COMPONENT Sieve OFFERS NumberStream, Prime REQUIRES NumberStream;
		VARIABLE prime: INTEGER; 
		
		IMPLEMENTATION Prime;
		BEGIN {EXCLUSIVE} 
			IF prime # 0 THEN !PrimeNumber(prime) ELSE !Finished END
		END Prime;
	
		IMPLEMENTATION NumberStream;
		VARIABLE i: INTEGER;
		BEGIN {EXCLUSIVE}
			WHILE NumberStream?Number DO
				NumberStream?Number(i);
				IF i MOD prime # 0 THEN !Number(i) END
			END;
			IF NumberStream?Finished THEN NumberStream?Finished END; 
			!Finished
		END NumberStream;
		
	BEGIN
		IF NumberStream?Number THEN NumberStream?Number(prime) 
		ELSE NumberStream?Finished; prime := 0 
		END
	END Sieve;
	
	COMPONENT NumberGenerator OFFERS NumberStream;
		IMPLEMENTATION NumberStream;
		VARIABLE i: INTEGER;
		BEGIN FOR i := 2 TO N DO !Number(i) END; !Finished
		END NumberStream;
	END NumberGenerator;
	
	PROCEDURE SystemTime(): INTEGER;
	VARIABLE t: INTEGER;
	BEGIN SystemTime!GetSystemTime; SystemTime?SystemTime(t); RETURN t
	END SystemTime;
	
	VARIABLE generator: NumberGenerator; sieve[i: INTEGER]: Sieve; i, p, start: INTEGER; 
	BEGIN
		start := SystemTime();
		NEW(generator); NEW(sieve[1]); CONNECT(NumberStream(sieve[1]), generator); i := 1;
		WHILE Prime(sieve[i])?PrimeNumber DO
			Prime(sieve[i])?PrimeNumber(p);
			IF Output THEN WRITE(p); WRITE(" ") END;
			INC(i); NEW(sieve[i]); CONNECT(NumberStream(sieve[i]), sieve[i-1])
		END;
		Prime(sieve[i])?Finished;
		WRITE(SystemTime()-start); WRITE("ms"); WRITELINE
END Eratosthenes;

