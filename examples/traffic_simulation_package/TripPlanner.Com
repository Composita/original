INTERFACE TripPlan;
	IN Compute(startLinkId, endLinkId, desiredArrivalTime: INTEGER)
	OUT Plan(bestDepartTime: INTEGER)
	{ OUT LinkOnRoute(linkId: INTEGER; transport: BOOLEAN) }
	OUT End
END TripPlan;

COMPONENT TripPlanner OFFERS TripPlan, PlanAdjustment REQUIRES RoadMap;
	VARIABLE
		planner: RoutePlanner;
		bestDepartTime: INTEGER;
		routeLength: INTEGER;
		linkOnRoute[position: INTEGER]: INTEGER;
		nodeOnRoute[position: INTEGER]: INTEGER;
		
	IMPLEMENTATION TripPlan;
	VARIABLE startLink, endLink, desArrTime, i: INTEGER; transport: BOOLEAN;
	BEGIN {EXCLUSIVE}
		?Compute(startLink, endLink, desArrTime);
		PlanActivity(startLink, endLink, desArrTime);
		!Plan(bestDepartTime);
		FOR i := 1 TO routeLength DO
			transport := UsesTransport(linkOnRoute[i]);
			!LinkOnRoute(linkOnRoute[i], transport)
		END;
		!End
	END TripPlan;
	
	IMPLEMENTATION PlanAdjustment;
	VARIABLE linkId, departTime, travelTime: INTEGER;
	BEGIN {SHARED}
		?TravelTime(linkId, departTime, travelTime); 
		IF EXISTS(planner) THEN
			PlanAdjustment(planner)!TravelTime(linkId, departTime, travelTime)
		END
	END PlanAdjustment;
		
	PROCEDURE PlanActivity(depLink, arrLink, desArrTime: INTEGER);
	CONSTANT PlanStepsPerRoute = 2;
	VARIABLE i, k, depTime, arrTime: INTEGER; utility, bestUtility: REAL;
	BEGIN
		IF ~EXISTS(planner) THEN 
			NEW(planner); CONNECT(RoadMap(planner), RoadMap)
		END;
		routeLength := 0; bestDepartTime := 0; 
		bestUtility := MIN(REAL); depTime := desArrTime;
		FOR i := 1 TO PlanStepsPerRoute DO
			RoutePlan(planner)!CalculateRoute(depLink, arrLink, depTime);
			IF RoutePlan(planner)?NoRoute THEN
				RoutePlan(planner)?NoRoute
			ELSE
				RoutePlan(planner)?BestRoute(arrTime); 
				utility := CalculateUtility(depTime, arrTime, desArrTime);
				IF utility > bestUtility THEN
					bestDepartTime := depTime; bestUtility := utility;
					RoutePlan(planner)!GiveRoute; k := 0;
					WHILE RoutePlan(planner)?Link DO
						INC(k); RoutePlan(planner)?Link(linkOnRoute[k])
					END;
					routeLength := k;
					RoutePlan(planner)?EndOfRoute
				ELSE
					RoutePlan(planner)!DiscardRoute
				END;
				INC(depTime, desArrTime - arrTime);
				IF depTime < 0 THEN depTime := 0 END
			END
		END
	END PlanActivity;
	
	PROCEDURE CalculateUtility(depTime, arrTime, desArrTime: INTEGER): REAL;
	CONSTANT UTrip = -0.4 / 60; UEarly = -0.25 / 60; ULate = -1.5 / 60;
	VARIABLE tripTime, earlyTime, lateTime: INTEGER;
	BEGIN
		tripTime := arrTime - depTime;
		IF desArrTime > arrTime THEN 
			earlyTime := desArrTime - arrTime; lateTime := 0 
		ELSE
			earlyTime := 0; lateTime := arrTime - desArrTime
		END;
		RETURN UTrip * tripTime + UEarly * earlyTime + ULate * lateTime
	END CalculateUtility;
	
	PROCEDURE UsesTransport(linkId: INTEGER): BOOLEAN;
	BEGIN 
		RoadMap!IsTransportLink(linkId);
		IF RoadMap?TransportBasedLink THEN
			RoadMap?TransportBasedLink; RETURN TRUE
		ELSE
			RoadMap?NormalLink; RETURN FALSE
		END
	END UsesTransport;
END TripPlanner;
