COMPONENT Simulation;
	COMPONENT Producer REQUIRES DataInput;
		VARIABLE i: INTEGER;
		CONSTANT Runs = 1000000
	BEGIN
		WRITE("Producer Started");
		FOR i := 1 TO Runs DO
			DataInput!Element(i); (* no semicolon in original? *)
		END;
		DataInput!Finished;
		WRITE("Producer finished")
	END Producer;

	COMPONENT Consumer REQUIRES DataOutput;
		VARIABLE x: INTEGER;
	BEGIN
		WRITE("Consumer started"); WRITELINE;
		WHILE DataOutput?Element DO
			DataOutput?Element(x);
			IF x MOD 100000 = 0 THEN WRITE(x); WRITELINE (* again no semicolon? *) END
		END;
		DataOutput?Finished;
		WRITE("Consumer finished"); WRITELINE
	END Consumer;

	INTERFACE DataInput;
		{ IN ELEMENT(x: INTEGER) } IN FINISHED
	END DataInput;

	INTERFACE DataOutput;
		{ OUT Element(x: INTEGER) } OUT FINISHED
	END DataOutput;

	COMPONENT BoundedBuffer OFFERS DataInput, DataOutput;
		CONSTANT Capacity = 100;
		VARIABLE
			a[position: INTEGER]: INTEGER { ARRAY };
			first, last: INTEGER; finished: BOOLEAN;

		IMPLEMENTATION DataInput;
		BEGIN
			WHILE ?Element DO { EXCLUSIVE }
				AWAIT(last - first < Capacity);
				?ELEMENT(a[last MOD Capacity]); INC(last)
			END
			?Finished;
			BEGIN { EXCLUSIVE } finished := TRUE END
		END DataInput;

		IMPLEMENTATION DataOutput
		BEGIN { EXCLUSIVE }
			REPEAT
				AWAIT((first < last) OR finished);
				IF first < last THEN
					!Element(a[first MOD Capacity]); INC(first)
				END
			UNTIL (first >= last AND finished;
		END DataOutput;

		BEGIN
			NEW(a, Capacity);
			first := 0; last := 0; finished := FALSE;
	END BoundedBuffer;

	VARIABLE consumer: Consuemr; producer: Producer; buffer: BoundedBuffer;
BEGIN
	NEW(buffer); NEW(consumer); NEW(producer);
	CONNECT(DataInput(producer), buffer);
	CONNECT(DataOutput(consumer), buffer);
END Simulation;

