COMPONENT ProducerConsumer REQUIRES SystemTime;
	CONSTANT 
		N = 1; (* producers *)
		M = 1; (* consumers *)
		K = 1000000; (* amount per producer *)
		C = 10; (* buffer capacity *)
		Output = FALSE;

	COMPONENT Producer REQUIRES DataAcceptor;
		VARIABLE i: INTEGER;
		BEGIN
			FOR i := 1 TO K DO
				DataAcceptor!Element(i)
			END;
			DataAcceptor!Finished
	END Producer;
	
	COMPONENT Consumer REQUIRES DataSource;
		VARIABLE x: INTEGER;
		BEGIN
			WHILE DataSource?Element DO 
				DataSource?Element(x);
				IF Output AND (x MOD (K DIV 10) = 0) THEN WRITE(x); WRITELINE END
			END;
			DataSource?Finished
	END Consumer;
	
	INTERFACE DataAcceptor;
		{ IN Element(x: INTEGER) } IN Finished
	END DataAcceptor;
	
	INTERFACE DataSource;
		{ OUT Element(x: INTEGER) } OUT Finished
	END DataSource;

	COMPONENT BoundedBuffer OFFERS DataAcceptor, DataSource;
		VARIABLE 
			a[position: INTEGER]: INTEGER {ARRAY}; 
			first, last: INTEGER; 
			nofProducers: INTEGER;
	
		IMPLEMENTATION DataAcceptor;
			BEGIN
				WHILE ?Element DO {EXCLUSIVE}
					AWAIT(last-first < C);
					?Element(a[last MOD C]); INC(last)
				END;
				?Finished; 
				BEGIN {EXCLUSIVE} DEC(nofProducers) END
		END DataAcceptor;
		
		IMPLEMENTATION DataSource;
			VARIABLE stop: BOOLEAN;
			BEGIN
				stop := FALSE;
				REPEAT {EXCLUSIVE}
					AWAIT((first < last) OR (nofProducers = 0));
					IF first < last THEN
						!Element(a[first MOD C]); INC(first)
					ELSE stop := TRUE
					END
				UNTIL stop;
				!Finished
		END DataSource;
		
		BEGIN
			NEW(a, C); first := 0; last := 0; nofProducers := N
	END BoundedBuffer;

	PROCEDURE SystemTime(): INTEGER;
	VARIABLE t: INTEGER;
	BEGIN SystemTime!GetSystemTime; SystemTime?SystemTime(t); RETURN t
	END SystemTime;

	VARIABLE 
		buffer: BoundedBuffer; 
		producer[number: INTEGER]: Producer; 
		consumer[number: INTEGER]: Consumer; 
		i, start: INTEGER; 
	BEGIN
		WRITE(N); WRITE(" producers "); WRITE(M); WRITE(" consumers"); WRITELINE;
		start := SystemTime();
		NEW(buffer); 
		FOR i := 1 TO N DO 
			NEW(producer[i]); CONNECT(DataAcceptor(producer[i]), buffer)
		END;
		FOR i := 1 TO M DO
			NEW(consumer[i]); CONNECT(DataSource(consumer[i]), buffer)
		END;
		FOR i := 1 TO M DO DELETE(consumer[i]) END;
		WRITE(SystemTime()-start); WRITE("ms"); WRITELINE
END ProducerConsumer;

