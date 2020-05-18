COMPONENT City REQUIRES SystemTime;
	CONSTANT 
		N = 1000; (* houses *)
		K = 10; (* consumptions per house *)
		C = 100; (* maximum electricity reserve *)

	INTERFACE House;
		IN Construct IN Destruct
	END House;
	
	INTERFACE Garage;
		{ IN ParkCar }
	END Garage;
	
	INTERFACE Electricity;
		{ IN Request OUT Electricity }
	END Electricity;
	
	INTERFACE Water;
		{ IN Request OUT Water }
	END Water;
	
	COMPONENT StandardHouse OFFERS House, Garage REQUIRES Water, Electricity;
		IMPLEMENTATION House;
		VARIABLE i: INTEGER;
		BEGIN {EXCLUSIVE}
			?Construct;
			FOR i := 1 TO K DO
				Electricity!Request; Water!Request; 
				Electricity?Electricity; Water?Water
			END;
			?Destruct;
		END House;
		
		IMPLEMENTATION Garage;
		BEGIN WHILE ?ParkCar DO ?ParkCar END
		END Garage;
	END StandardHouse;
	
	COMPONENT HydroelectricPowerPlant OFFERS Electricity REQUIRES Water;
		VARIABLE energy, customers: INTEGER;
	
		IMPLEMENTATION Electricity;
		BEGIN
			BEGIN {EXCLUSIVE} INC(customers) END;
			WHILE ?Request DO {EXCLUSIVE}
				?Request; 
				AWAIT(energy > 0); DEC(energy);
				!Electricity 
			END;
			BEGIN {EXCLUSIVE} DEC(customers) END
		END Electricity;
		
		BEGIN energy := 0; customers := 0;
		ACTIVITY {EXCLUSIVE} 
			AWAIT(customers > 0);
			REPEAT
				AWAIT((energy = 0) OR (customers = 0));
				IF energy = 0 THEN
					Water!Request; Water?Water; INC(energy)
				END
			UNTIL customers = 0
	END HydroelectricPowerPlant;
	
	COMPONENT River OFFERS Water;
		IMPLEMENTATION Water;
		BEGIN 
			WHILE ?Request DO 
				?Request; !Water 
			END
		END Water;
	END River;
	
	PROCEDURE SystemTime(): INTEGER;
	VARIABLE t: INTEGER;
	BEGIN SystemTime!GetSystemTime; SystemTime?SystemTime(t); RETURN t
	END SystemTime;
	
	VARIABLE 
		house[number: INTEGER]: ANY(House | Water, Electricity);
		powerPlant: HydroelectricPowerPlant;
		river: River;
		i, startTime: INTEGER;
	BEGIN
		startTime := SystemTime();
		NEW(river); NEW(powerPlant); CONNECT(Water(powerPlant), river);
		FOR i := 1 TO N DO
			NEW(house[i], StandardHouse); 
			CONNECT(Electricity(house[i]), powerPlant); 
			CONNECT(Water(house[i]), river)
		END;
		FOREACH i OF house DO house[i]!Construct END;
		FOREACH i OF house DO house[i]!Destruct END;	
		(* just for time measurement *)
		FOR i := 1 TO N DO DELETE(house[i]) END;
		WRITE(SystemTime()-startTime); WRITE("ms"); WRITELINE
END City;

