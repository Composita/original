COMPONENT TrafficWithCarTransport REQUIRES FileSystem, SystemTime;
	CONSTANT
		UseActivities = FALSE;
		CarOutput = TRUE; 
		Snapshots = TRUE;
		NofIterations = 1;
		QueueBased = FALSE;
		BufferedOutput = FALSE;
		SnapshotBegin = 25000;
		SnapshotEnd = 27000;
		SnapshotIntervall = 60;
		TimeReport = TRUE;
		TimeReportIntervall = 60;
		TimeOut = 15 * 60;
	
		NetworkDataFile = "net.xml";
		PlanDataFile = "plans.xml";
		ActivityDataFile = "activitieslarge.txt";
		EventFilePrefix = "events"; 
		SnapshotFilePrefix = "snapshot";
				
		CarLength = 7.5; (* m *) Day = 24 * 60 * 60;
		NoLink = 0; NoCar = 0;
		MaxPlansPerCar = 2; 
		
	INTERFACE Vehicle;
		IN Depart OUT Departed
	END Vehicle;
	
	INTERFACE VehicleActivitySetup;
		IN Initialize(carId, startLinkId: INTEGER)
		{ IN Destination(linkId, desiredArrivalTime: INTEGER) }
		IN End
	END VehicleActivitySetup;
	
	INTERFACE VehiclePlanSetup;
		IN Initialize(carId: INTEGER)
		{  
		   IN BeginRoute(startLinkId, endLinkId, departureTime: INTEGER)
			{ IN Link(linkId: INTEGER; transport: BOOLEAN) } IN EndRoute 
		}
		IN End
	END VehiclePlanSetup;
	
	COMPONENT Car 
		OFFERS Vehicle, VehicleActivitySetup, VehiclePlanSetup 
		REQUIRES Road, CarReactions, RoadMap, EventOutput;
		
		VARIABLE
			carId, nofDestinations: INTEGER; initialized: BOOLEAN;
			planner: TripPlanner; planningRequired: BOOLEAN;
			endLink[destinationNo: INTEGER]: INTEGER {ARRAY}; 
			desiredArrivalTime[destinationNo: INTEGER]: INTEGER {ARRAY};
			bestDepartTime[destinationNo: INTEGER]: INTEGER {ARRAY};
			routeLength[destinationNo: INTEGER]: INTEGER {ARRAY}; 
			linkOnRoute[destinationNo, position: INTEGER]: INTEGER;
			needsTransport[linkId: INTEGER]: BOOLEAN;
			i, k: INTEGER; stopped: BOOLEAN;

		IMPLEMENTATION Vehicle;
		VARIABLE linkId, departTime, arrivalTime: INTEGER;
		BEGIN {EXCLUSIVE}
			AWAIT(initialized); 
			IF CarOutput THEN EventOutput!Initialize(carId) END;
			Road!Prepare(carId);
			IF ~stopped THEN PlanDay ELSE stopped := FALSE END;
			?Depart; !Departed;
			WHILE ~stopped AND (i <= nofDestinations) DO
				departTime := bestDepartTime[i];
				IF departTime > TIME MOD Day THEN
					PASSIVATE(departTime - TIME MOD Day)
				END;
				Road!Start;
				WHILE ~stopped AND (k <= routeLength[i]) DO
					linkId := linkOnRoute[i, k];
					IF needsTransport[linkId] THEN
						stopped := TRUE; CarReactions!PutOnTransport(carId, linkId)
					ELSE
						Road!Drive(linkId); 
						AWAIT(INPUT(Road, Departed)); 
						Road?Departed; departTime := TIME MOD Day;
						IF CarOutput THEN EventOutput!Departure(departTime, linkId) END;
						AWAIT(INPUT(Road, Arrived)); 
						Road?Arrived; arrivalTime := TIME MOD Day;
						IF CarOutput THEN EventOutput!Arrival(arrivalTime, linkId) END;
						RecordTravelTime(linkId, departTime, arrivalTime)
					END;
					INC(k)
				END;
				Road!Stop;
				IF k > routeLength[i] THEN INC(i); k := 1 END
			END;
			Road!Finish;
			IF i > nofDestinations THEN
				PASSIVATE(Day - TIME MOD Day);
				IF CarOutput THEN EventOutput!EndOfDay END;
				planningRequired := UseActivities AND (RANDOM(1, 10) = 1);
				CarReactions!Arrived(carId)
			END
		END Vehicle;
		
		IMPLEMENTATION VehicleActivitySetup;
		BEGIN {EXCLUSIVE}
			ASSERT(~initialized); initialized := TRUE; planningRequired := TRUE; 
			?Initialize(carId, endLink[0]); nofDestinations := 0; 
			WHILE ?Destination DO
				INC(nofDestinations);
				?Destination(endLink[nofDestinations], desiredArrivalTime[nofDestinations])
			END;
			?End
		END VehicleActivitySetup;
		
		IMPLEMENTATION VehiclePlanSetup;
		VARIABLE start, end, depTime, node, k, linkId: INTEGER; transport: BOOLEAN;
		BEGIN {EXCLUSIVE}
			ASSERT(~initialized); initialized := TRUE;
			?Initialize(carId); nofDestinations := 0; planningRequired := FALSE;
			WHILE ?BeginRoute DO
				?BeginRoute(start, end, depTime);
				INC(nofDestinations); endLink[nofDestinations-1] := start;
				endLink[nofDestinations] := end; bestDepartTime[nofDestinations] := depTime; 
				k := 0; WHILE ?Link DO 
					INC(k); ?Link(linkId, transport); 
					linkOnRoute[nofDestinations, k] := linkId;
					needsTransport[linkId] := transport
				END;
				?EndRoute;
				routeLength[nofDestinations] := k
			END;
			?End
		END VehiclePlanSetup;
		
		PROCEDURE RecordTravelTime(linkId, departTime, arrivalTime: INTEGER);
		BEGIN
			IF UseActivities THEN 
				PlanAdjustment(planner)!TravelTime(linkId, departTime, arrivalTime-departTime) 
			END
		END RecordTravelTime;

		PROCEDURE PlanDay;
		VARIABLE i, k, linkId: INTEGER; transport: BOOLEAN;
		BEGIN
			IF UseActivities AND planningRequired THEN
				FOR i := 1 TO nofDestinations DO
					TripPlan(planner)!Compute(endLink[i-1], endLink[i], desiredArrivalTime[i]);
					TripPlan(planner)?Plan(bestDepartTime[i]);
					k := 0;
					WHILE TripPlan(planner)?LinkOnRoute DO
						INC(k); TripPlan(planner)?LinkOnRoute(linkId, transport);
						linkOnRoute[i, k] := linkId; needsTransport[linkOnRoute[i, k]] := transport
					END;
					routeLength[i] := k;
					TripPlan(planner)?End
				END
			END
		END PlanDay;
						
		BEGIN
			initialized := FALSE; i := 1; k := 1; stopped := FALSE;
			IF UseActivities THEN NEW(planner); CONNECT(RoadMap(planner), RoadMap) END;
			NEW(endLink, MaxPlansPerCar+1); NEW(desiredArrivalTime, MaxPlansPerCar+1);
			NEW(bestDepartTime, MaxPlansPerCar+1); NEW(routeLength, MaxPlansPerCar+1);
			IF UseActivities THEN NEW(desiredArrivalTime, MaxPlansPerCar) END
	END Car;
	
	INTERFACE Road;
		IN Prepare(carId: INTEGER)
		{  
			IN Start
			{  IN Drive(linkId: INTEGER) OUT Departed OUT Arrived }
			IN Stop 
		}
		IN Finish
	END Road;
	
	INTERFACE RoadSnapshot;
		IN Start
	END RoadSnapshot;

	COMPONENT RoadNetwork OFFERS Road, RoadMap, RoadSnapshot REQUIRES RoadData, SnapshotOutput;
		VARIABLE 
			link[id: INTEGER]: ANY(Link, LinkConfig, LinkSnapshot) {SYNCHRONOUS};
			map: RoadLayout; 
			
		IMPLEMENTATION Road;
		VARIABLE carId, from, to: INTEGER; 
		BEGIN {SHARED}
			?Prepare(carId); AWAIT(INPUT(ANY)); 
			WHILE ?Start DO
				?Start; from := NoLink; AWAIT(INPUT(ANY));
				WHILE ?Drive DO
					?Drive(to); 
					Link(link[to])!Enter(carId); 
					AWAIT(INPUT(Link(link[to]), Entered));
					Link(link[to])?Entered;
					!Departed;
					IF from # NoLink THEN Link(link[from])!Exit END;
					AWAIT(INPUT(Link(link[to]), EndReached));
					Link(link[to])?EndReached; 
					from := to;
					!Arrived;
					AWAIT(INPUT(ANY))
				END;
				IF from # NoLink THEN Link(link[from])!Exit END; 
				?Stop;
				AWAIT(INPUT(ANY))
			END;
			?Finish
		END Road;
		
		IMPLEMENTATION RoadSnapshot;
		VARIABLE startTime, linkId, fromNode, toNode, carId: INTEGER; fromX, fromY, toX, toY, distance: REAL;
		BEGIN {SHARED}
			?Start; startTime := TIME;
			IF Snapshots THEN SnapshotOutput!Start END;
			REPEAT 
				PASSIVATE(SnapshotIntervall);
				IF TimeReport AND (TIME MOD TimeReportIntervall = 0) THEN WRITE("TIME="); WRITE(TIME); WRITELINE END;
				IF Snapshots AND (TIME - startTime >= SnapshotBegin) AND (TIME - startTime <= SnapshotEnd) THEN
					FOREACH linkId OF link DO
						LinkSnapshot(link[linkId])!GetCarPositions;
						IF LinkSnapshot(link[linkId])?CarPosition THEN
							RoadMap(map)!GetLinkLocation(linkId);
							RoadMap(map)?LinkLocation(fromNode, toNode, fromX, fromY, toX, toY);
							WHILE LinkSnapshot(link[linkId])?CarPosition DO
								LinkSnapshot(link[linkId])?CarPosition(carId, distance);
								SnapshotOutput!CarPosition(TIME MOD Day, carId, linkId, fromNode, fromX, fromY, toX, toY, distance)
							END
						END;
						LinkSnapshot(link[linkId])?Finish
					END
				END
			UNTIL TIME >= startTime + Day;
			IF Snapshots THEN SnapshotOutput!Stop END
		END RoadSnapshot;
		
		VARIABLE id, x, y, from, to: INTEGER; fromX, toX, fromY, toY, length, speed, capacity: REAL; 
			lanes: INTEGER; transport: BOOLEAN;
		BEGIN
			NEW(map); CONNECT(RoadMap, map); 
			CONNECT(RoadData(map), RoadData);
			RoadSetup(map)!Read(NetworkDataFile);
			RoadMap(map)!ListAllLinks;
			WHILE RoadMap(map)?Link DO
				RoadMap(map)?Link(id, from, to, length, speed, capacity, lanes, transport);
				IF QueueBased THEN NEW(link[id], RoadLinkQB) ELSE NEW(link[id], RoadLinkCA) END;
				LinkConfig(link[id])!Initialize(id, from , to, length, speed, capacity, lanes)
			END;
			RoadMap(map)?NoMoreLinks
	END RoadNetwork;

	INTERFACE Link;
		IN Enter(carId: INTEGER) OUT Entered OUT EndReached IN Exit
	END Link;
	
	INTERFACE LinkConfig;
		IN Initialize(id, from, to: INTEGER; length, freeSpeed, capacity: REAL; lanes: INTEGER)
	END LinkConfig;
	
	INTERFACE LinkSnapshot;
		IN GetCarPositions { OUT CarPosition(carId: INTEGER; distance: REAL) } OUT Finish
	END LinkSnapshot;
	
	(* cellular automaton *)
	COMPONENT RoadLinkCA OFFERS Link, LinkConfig, LinkSnapshot;
		VARIABLE
			initialized: BOOLEAN; 
			linkId, from, to, lanes: INTEGER; 
			length, freeSpeed, capacity: REAL;
			exit, maxSpeed: INTEGER; 
			cell[position: INTEGER]: INTEGER {ARRAY}; 

		IMPLEMENTATION Link;
		VARIABLE carId, pos, speed, k: INTEGER;
		BEGIN {EXCLUSIVE}
			AWAIT(initialized);
			?Enter(carId);
			AWAIT(cell[0] = NoCar);
			cell[0] := carId; 
			!Entered; 
			pos := 0; speed := 0;
			WHILE pos < exit DO
				IF cell[pos + 1] # NoCar THEN
					speed := 0;
					AWAIT(cell[pos + 1] = NoCar)
				END;
				IF speed < maxSpeed THEN INC(speed) END;
				PASSIVATE(1);
				k := 1; 
				WHILE (pos + k < exit) AND (k < speed) 
					AND (cell[pos + k + 1] = NoCar) DO INC(k) 
				END;
				speed := k;
				cell[pos + speed] := carId; 
				cell[pos] := NoCar; 
				INC(pos, speed)
			END;
			!EndReached;
			AWAIT(INPUT(Exit));
			cell[exit] := NoCar; 
			?Exit
		END Link;
				
		IMPLEMENTATION LinkConfig;
		VARIABLE i: INTEGER;
		BEGIN 
			BEGIN {EXCLUSIVE}
				?Initialize(linkId, from, to, length, freeSpeed, capacity, lanes);
				maxSpeed := 1 + INTEGER(freeSpeed / CarLength);
				exit := INTEGER(length / CarLength);
				NEW(cell, exit + 1); FOR i := 0 TO exit DO cell[i] := NoCar END;
				initialized := TRUE
			END
		END LinkConfig;
		
		IMPLEMENTATION LinkSnapshot;
		VARIABLE i: INTEGER;
		BEGIN {SHARED}
			?GetCarPositions;
			FOR i := 0 TO exit DO
				IF cell[i] # NoCar THEN !CarPosition(cell[i], i * CarLength) END
			END;
			!Finish
		END LinkSnapshot;
		
		BEGIN initialized := FALSE
	END RoadLinkCA;
	
	(* queue-based *)
	COMPONENT RoadLinkQB OFFERS Link, LinkConfig, LinkSnapshot;
		VARIABLE
			initialized: BOOLEAN; 
			linkId, from, to, lanes: INTEGER; 
			length, freeSpeed, capacity: REAL;
			freeTravelTime, maxCars: INTEGER;
			canEnter: BOOLEAN; lastEntered, lastExited, cars: INTEGER;
			queue[location: INTEGER]: INTEGER;
		
		IMPLEMENTATION Link;
		VARIABLE carId, current, k: INTEGER;
		BEGIN {EXCLUSIVE}
			AWAIT(initialized);
			?Enter(carId);
			AWAIT(canEnter); canEnter := FALSE;
			INC(lastEntered); current := lastEntered;
			queue[current] := carId;
			INC(cars); 
			(* timeouted AWAIT(cars < maxCars), open if jamed *)
			k := 0; WHILE (k < TimeOut) AND (cars = maxCars) DO PASSIVATE(1); INC(k) END;
			IF k = TimeOut THEN WRITE("jam on link "); WRITE(linkId); WRITELINE END;
			!Entered;
			PASSIVATE(1);
			canEnter := TRUE; 
			PASSIVATE(freeTravelTime);
			AWAIT(lastExited = current - 1);
			!EndReached;
			AWAIT(INPUT(Exit));
			lastExited := current; DEC(cars);
			DELETE(queue[current]);
			?Exit
		END Link;
		
		IMPLEMENTATION LinkConfig;
		VARIABLE i: INTEGER;
		BEGIN 
			BEGIN {EXCLUSIVE}
				?Initialize(linkId, from, to, length, freeSpeed, capacity, lanes);
				freeTravelTime := INTEGER(length / freeSpeed);
				maxCars := lanes * INTEGER(length / CarLength);
				lastExited := 0; lastEntered := 0; canEnter := TRUE; 
				cars := 0; initialized := TRUE
			END
		END LinkConfig;
		
		IMPLEMENTATION LinkSnapshot;
		VARIABLE k: INTEGER; distance: REAL;
		BEGIN {SHARED}
			?GetCarPositions;
			FOREACH k OF queue DO
				distance := length - (k - lastExited) * CarLength; 
				IF distance < 0 THEN distance := 0.0 END;
				!CarPosition(queue[k], distance)
			END;
			!Finish
		END LinkSnapshot;
		
		BEGIN initialized := FALSE
	END RoadLinkQB;
	
	INTERFACE CarTransport;
		IN Enter(carId: INTEGER; car: Car) | 
		IN Exit { OUT ExitingCar(carId: INTEGER; car: Car) } OUT NoMoreCars
	END CarTransport;
	
	INTERFACE TransportConfig;
		IN Initialize(linkId: INTEGER; length, speed, capacity: REAL)
	END TransportConfig;
	
	COMPONENT CarTransportSystem OFFERS CarTransport, TransportConfig REQUIRES CarReactions;
		CONSTANT Departing = 1; UnderWay = 2; Arrived = 3;
		VARIABLE linkId, travelTime, state, nofCars: INTEGER; capacity: REAL; car[carId: INTEGER]: Car; 
			
		IMPLEMENTATION CarTransport;
		VARIABLE carId: INTEGER; x: Car;
		BEGIN {EXCLUSIVE}
			IF ?Enter THEN
				?Enter(carId, x); 
				AWAIT((state = Departing) AND (nofCars < capacity)); 
				INC(nofCars); MOVE(x, car[carId])
			ELSE
				?Exit;
				AWAIT(state = Arrived); 
				FOREACH carId OF car DO
					!ExitingCar(carId, car[carId]); DEC(nofCars)
				END;
				!NoMoreCars
			END
		END CarTransport;
		
		IMPLEMENTATION TransportConfig;
		VARIABLE length, speed: REAL; 
		BEGIN {EXCLUSIVE}
			?Initialize(linkId, length, speed, capacity);
			travelTime := INTEGER(length / speed); state := Departing
		END TransportConfig;
			
		BEGIN state := 0
		ACTIVITY {EXCLUSIVE}
			AWAIT(state = Departing);
			REPEAT
				AWAIT((nofCars > 0) OR TERMINATED());
				IF nofCars > 0 THEN
					state := UnderWay; PASSIVATE(travelTime); state := Arrived;
					CarReactions!RemoveFromTransport(linkId);
					AWAIT(nofCars = 0); state := Departing
				END
			UNTIL TERMINATED()
	END CarTransportSystem;
	
	INTERFACE CarReactions;
		IN PutOnTransport(carId, linkId: INTEGER) | 
		IN RemoveFromTransport(carId: INTEGER) |
		IN Arrived(carId: INTEGER)
	END CarReactions;
	
	VARIABLE 
		car[id: INTEGER]: Car {SYNCHRONOUS};
		transport[id: INTEGER]: CarTransportSystem {SYNCHRONOUS};
		road: RoadNetwork {SYNCHRONOUS}; 
		networkReader: RoadNetworkReader;
		eventWriter: ANY(EventOutput, WriterControl | XMLWriter);
		snapshotWriter: SnapshotWriter;
		xmlWriter: XMLOutput;
		nofCars: INTEGER;
		
	IMPLEMENTATION CarReactions;
	VARIABLE carId, linkId: INTEGER; x: Car;
	BEGIN {EXCLUSIVE}
		IF ?PutOnTransport THEN
			?PutOnTransport(carId, linkId);
			CarTransport(transport[linkId])!Enter(carId, car[carId]);
			WRITE("Car "); WRITE(carId); WRITE(" put on transport "); WRITE(linkId); WRITELINE
		ELSIF ?RemoveFromTransport THEN
			?RemoveFromTransport(linkId);
			CarTransport(transport[linkId])!Exit;
			WHILE CarTransport(transport[linkId])?ExitingCar DO
				CarTransport(transport[linkId])?ExitingCar(carId, x); MOVE(x, car[carId]);
				CONNECT(Road(car[carId]), road); CONNECT(RoadMap(car[carId]), road);
				IF CarOutput THEN CONNECT(EventOutput(car[carId]), eventWriter) END;
				CONNECT(CarReactions(car[carId]), CarReactions);
				Vehicle(car[carId])!Depart; Vehicle(car[carId])?Departed;
				WRITE("Car "); WRITE(carId); WRITE(" removed from transport "); WRITE(linkId); WRITELINE
			END;
			CarTransport(transport[linkId])?NoMoreCars
		ELSE 
			?Arrived(carId); INC(arrived)
		END
	END CarReactions; 
	
	PROCEDURE BuildTransports;
	VARIABLE id: INTEGER; distance, freeSpeed, capacity: REAL; 
	BEGIN
		RoadMap(road)!ListAllTransportLinks;
		WHILE RoadMap(road)?TransportLink DO
			RoadMap(road)?TransportLink(id, distance, freeSpeed, capacity);
			NEW(transport[id]);
			CONNECT(CarReactions(transport[id]), CarReactions);
			TransportConfig(transport[id])!Initialize(id, distance, freeSpeed, capacity)
		END;
		RoadMap(road)?NoMoreTransportLinks
	END BuildTransports;
	
	PROCEDURE ReadActivities;
	VARIABLE activityReader: ActivityReader; carId, linkId, desArrTime: INTEGER; type: TEXT;
	BEGIN
		NEW(activityReader); CONNECT(FileSystem(activityReader), FileSystem);
		ActivityData(activityReader)!Read(ActivityDataFile); nofCars := 0;
		WHILE ActivityData(activityReader)?Activity DO
			ActivityData(activityReader)?Activity(carId, type, linkId, desArrTime); ASSERT(carId # NoCar);
			IF ~EXISTS(car[carId]) THEN
				NEW(car[carId]); INC(nofCars); 
				CONNECT(Road(car[carId]), road); CONNECT(RoadMap(car[carId]), road); 
				IF CarOutput THEN CONNECT(EventOutput(car[carId]), eventWriter) END;
				CONNECT(CarReactions(car[carId]), CarReactions);
				VehicleActivitySetup(car[carId])!Initialize(carId, linkId);
				IF nofCars MOD 1000 = 0 THEN WRITE("Car "); WRITE(nofCars); WRITE(" created"); WRITELINE END
			ELSE
				VehicleActivitySetup(car[carId])!Destination(linkId, desArrTime)
			END
		END;
		ActivityData(activityReader)?Finish;
		FOREACH carId OF car DO VehicleActivitySetup(car[carId])!End END;
		WRITE("Activities read "); WRITELINE
	END ReadActivities;
	
	PROCEDURE ReadPlans;
	VARIABLE 
		planReader: PlanReader; nodeId[pos: INTEGER]: INTEGER;
		i, c, carId, linkId, startLinkId, endLinkId, departTime: INTEGER; 
	BEGIN
		NEW(planReader); CONNECT(FileSystem(planReader), FileSystem);
		PlanData(planReader)!Read(PlanDataFile); nofCars := 0;
		WHILE PlanData(planReader)?BeginPlan DO
			PlanData(planReader)?BeginPlan(carId); ASSERT(carId # NoCar);
			NEW(car[carId]); INC(nofCars);
			CONNECT(Road(car[carId]), road); CONNECT(RoadMap(car[carId]), road);
			CONNECT(CarReactions(car[carId]), CarReactions);
			IF CarOutput THEN CONNECT(EventOutput(car[carId]), eventWriter) END;
			VehiclePlanSetup(car[carId])!Initialize(carId);
			WHILE PlanData(planReader)?BeginLeg DO
				PlanData(planReader)?BeginLeg(startLinkId, departTime);
				c := 0;
				WHILE PlanData(planReader)?RouteNode DO
					INC(c); PlanData(planReader)?RouteNode(nodeId[c])
				END;
				PlanData(planReader)?EndLeg(endLinkId);
				VehiclePlanSetup(car[carId])!BeginRoute(startLinkId, endLinkId, departTime);
				FOR i := 1 TO c-1 DO 
					RoadMap(road)!FindLink(nodeId[i], nodeId[i+1]);
					IF RoadMap(road)?Result THEN
						RoadMap(road)?Result(linkId);
						VehiclePlanSetup(car[carId])!Link(linkId, EXISTS(transport[linkId]))
					ELSE
						RoadMap(road)?Inexistent;
						WRITE("Inexistent link from node "); WRITE(nodeId[i]);
						WRITE(" to "); WRITE(nodeId[i+1]); WRITELINE
					END
				END;
				VehiclePlanSetup(car[carId])!EndRoute
			END;
			PlanData(planReader)?EndPlan;
			VehiclePlanSetup(car[carId])!End;
			IF nofCars MOD 1000 = 0 THEN WRITE("Car "); WRITE(nofCars); WRITE(" created"); WRITELINE END;
		END;
		PlanData(planReader)?Finish;
		WRITE("Plans read"); WRITELINE
	END ReadPlans;
	
	PROCEDURE PrepareOutput;
	BEGIN
		IF CarOutput THEN 
			NEW(xmlWriter); CONNECT(FileSystem(xmlWriter), FileSystem);
			IF BufferedOutput THEN NEW(eventWriter, BufferedEventWriter) ELSE NEW(eventWriter, NormalEventWriter) END;
			CONNECT(XMLWriter(eventWriter), xmlWriter)
		END;
		IF Snapshots THEN
			NEW(snapshotWriter); CONNECT(FileSystem(snapshotWriter), FileSystem);
			CONNECT(SnapshotOutput(road), snapshotWriter)
		END
	END PrepareOutput;
	
	PROCEDURE StartOutput;
	BEGIN
		IF CarOutput THEN WriterControl(eventWriter)!Start(EventFilePrefix, iteration) END;
		IF Snapshots THEN WriterControl(snapshotWriter)!Start(SnapshotFilePrefix, iteration) END;
		IF TimeReport OR Snapshots THEN RoadSnapshot(road)!Start END
	END StartOutput;
	
	PROCEDURE StopOutput;
	BEGIN
		IF CarOutput THEN WriterControl(eventWriter)!Stop; WriterControl(eventWriter)?Done END;
		IF Snapshots THEN WriterControl(snapshotWriter)!Stop; WriterControl(snapshotWriter)?Done END
	END StopOutput;
	
	PROCEDURE SystemTime(): INTEGER;
	VARIABLE t: INTEGER;
	BEGIN SystemTime!GetSystemTime; SystemTime?SystemTime(t); RETURN t
	END SystemTime;
		
	VARIABLE carId, start, totalStart, iteration, arrived: INTEGER;
	ACTIVITY {EXCLUSIVE}
		totalStart := SystemTime();
		NEW(networkReader); CONNECT(FileSystem(networkReader), FileSystem);
		NEW(road); CONNECT(RoadData(road), networkReader); 
		BuildTransports; 
		PrepareOutput;
		IF UseActivities THEN ReadActivities ELSE ReadPlans END;
		FOR iteration := 1 TO NofIterations DO
			WRITE("Iteration "); WRITE(iteration); WRITELINE;
			StartOutput; arrived := 0;
			WRITE("Start planning "); WRITELINE; start := SystemTime();
			FOREACH carId OF car DO Vehicle(car[carId])!Depart END;
			FOREACH carId OF car DO Vehicle(car[carId])?Departed END;
			WRITE("Planning end "); WRITE(SystemTime()-start); WRITE("ms"); WRITELINE;
			WRITE("Start simulation"); WRITELINE; start := SystemTime();
			AWAIT(arrived = nofCars);
			WRITE("Simulation end "); WRITE(SystemTime()-start); WRITE("ms"); WRITELINE;
			StopOutput
		END;
		WRITE("Total time "); WRITE(SystemTime()-totalStart); WRITE("ms"); WRITELINE
END TrafficWithCarTransport;

