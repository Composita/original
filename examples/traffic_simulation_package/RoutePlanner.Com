INTERFACE RoadMap; 
	{ IN ListAllNodes { OUT Node(id, x, y: INTEGER) } OUT NoMoreNodes
	| IN ListAllLinks { OUT Link(id, from, to: INTEGER; distance, freeSpeed, capacity: REAL; lanes: INTEGER; transport: BOOLEAN) } OUT NoMoreLinks
	| IN GetLinkDestination(linkId: INTEGER) OUT Destination(nodeId: INTEGER)
	| IN FindLink(fromNodeId, toNodeId: INTEGER) ( OUT Result(linkId: INTEGER) | OUT Inexistent )
	| IN ListOutgoingLinks(nodeId: INTEGER) { OUT LinkEntry(linkId: INTEGER) } OUT NoMoreOutLinks 
	| IN GetLinkLocation(linkId: INTEGER) OUT LinkLocation(fromNode, toNode: INTEGER; fromX, fromY, toX, toY: REAL) 
	| IN IsTransportLink(linkId: INTEGER) ( OUT TransportBasedLink | OUT NormalLink ) 
	| IN ListAllTransportLinks { OUT TransportLink(id: INTEGER; distance, freeSpeed, capacity: REAL) } OUT NoMoreTransportLinks }
END RoadMap;

INTERFACE RoutePlan;
	IN CalculateRoute(departureLinkId, arrivalLinkId, departureTime: INTEGER) 
	( OUT BestRoute(arrivalTime: INTEGER)
		( IN GiveRoute { OUT Link(id: INTEGER) } OUT EndOfRoute 
		| IN DiscardRoute )
	|  OUT NoRoute  )
END RoutePlan;

INTERFACE PlanAdjustment;
	IN TravelTime(linkId, departTime, travelTime: INTEGER)
END PlanAdjustment;

COMPONENT RoutePlanner OFFERS RoutePlan, PlanAdjustment REQUIRES RoadMap;
	CONSTANT TimeBinDuration = 15*60; (* 15min *)
	VARIABLE 
		node[id: INTEGER]: BOOLEAN;
		link[fromNode, toNode: INTEGER]: INTEGER;
		fromNode[link: INTEGER], toNode[link: INTEGER]: INTEGER; 
		freeTravelTime[link: INTEGER]: INTEGER;
		travelTimeSum[link, timeBin: INTEGER]: INTEGER; 
		travelTimeCount[link, timeBin: INTEGER]: INTEGER;
		routeLength: INTEGER; linkOnRoute[position: INTEGER]: INTEGER;

	IMPLEMENTATION RoutePlan;
	VARIABLE depLink, arrLink, depTime, arrTime, i: INTEGER;
	BEGIN {EXCLUSIVE}
		?CalculateRoute(depLink, arrLink, depTime);
		ShortestPath(depLink, arrLink, depTime, arrTime);
		IF routeLength = 0 THEN !NoRoute 
		ELSE 
			!BestRoute(arrTime);
			IF ?GiveRoute THEN
				?GiveRoute;
				FOR i := 1 TO routeLength DO !Link(linkOnRoute[i]) END; 
				!EndOfRoute
			ELSE ?DiscardRoute
			END;
			FOR i := 1 TO routeLength DO DELETE(linkOnRoute[i]) END;
			routeLength := 0
		END
	END RoutePlan;
	
	IMPLEMENTATION PlanAdjustment;
	VARIABLE linkId, departTime, travelTime, bin: INTEGER;
	BEGIN {EXCLUSIVE}
		?TravelTime(linkId, departTime, travelTime); bin := TimeBin(departTime);
		IF EXISTS(travelTimeSum[linkId, bin]) THEN
			INC(travelTimeSum[linkId, bin], travelTime); INC(travelTimeCount[linkId, bin])
		ELSE
			travelTimeSum[linkId, bin] := travelTime; travelTimeCount[linkId, bin] := 1
		END
	END PlanAdjustment;
	
	PROCEDURE TimeBin(time: INTEGER): INTEGER;
	BEGIN RETURN time DIV TimeBinDuration
	END TimeBin;
	
	PROCEDURE TravelTime(linkId, currentTime: INTEGER): INTEGER;
	VARIABLE bin, sum, count: INTEGER;
	BEGIN 
		bin := TimeBin(currentTime);
		IF EXISTS(travelTimeSum[linkId, bin]) THEN
			sum := travelTimeSum[linkId, bin]; count := travelTimeCount[linkId, bin];
			RETURN INTEGER(sum / count)
		ELSE
			RETURN freeTravelTime[linkId]
		END
	END TravelTime;
	
	PROCEDURE ShortestPath(startLink, finalLink, startTime: INTEGER; VARIABLE endTime: INTEGER);
	CONSTANT NoNode = 0;
	VARIABLE 
		arrTime[node: INTEGER]: INTEGER; isDone[node: INTEGER]: BOOLEAN;
		bestFromNode[toNode: INTEGER]: INTEGER; inverseRoute[position: INTEGER]: INTEGER;
		nodeId, linkId, from, to, startNode, finalNode, current, now, time, k: INTEGER;
	BEGIN
		endTime := MAX(INTEGER);
		FOREACH nodeId OF node DO 
			arrTime[nodeId] := MAX(INTEGER); isDone[nodeId] := FALSE 
		END;
		startNode := toNode[startLink]; finalNode := fromNode[finalLink];
		current := startNode; arrTime[current] := startTime + TravelTime(startLink, startTime);
		WHILE (current # finalNode) AND (current # NoNode) DO
			isDone[current] := TRUE; now := arrTime[current];
			FOREACH from, to OF link DO
				IF from = current THEN
					linkId := link[from, to];
					time := now + TravelTime(linkId, now);
					IF time < arrTime[to] THEN
						arrTime[to] := time; bestFromNode[to] := current
					END
				END
			END;
			time := MAX(INTEGER); current := NoNode;
			FOREACH nodeId OF node DO
				IF ~isDone[nodeId] AND (arrTime[nodeId] < time) THEN 
					time := arrTime[nodeId]; current := nodeId
				END
			END
		END;
		routeLength := 0;
		IF current # NoNode THEN
			now := arrTime[current]; endTime := now; (* stop at the beginning of finalLink *)
			WHILE current # startNode DO
				from := bestFromNode[current];
				INC(routeLength); inverseRoute[routeLength] := link[from, current];
				current := from
			END;
			INC(routeLength); inverseRoute[routeLength] := startLink;
			FOR k := 1 TO routeLength DO linkOnRoute[k] := inverseRoute[routeLength-(k-1)] END
		END
	END ShortestPath;
	
	PROCEDURE ReadMap;
	VARIABLE id, from, to: INTEGER; distance, freeSpeed, capacity: REAL; lanes: INTEGER; transport: BOOLEAN;
	BEGIN
		RoadMap!ListAllLinks; 
		WHILE RoadMap?Link DO 
			RoadMap?Link(id, from, to, distance, freeSpeed, capacity, lanes, transport); 
			link[from, to] := id; fromNode[id] := from; toNode[id] := to;
			node[from] := TRUE; node[to] := TRUE;
			freeTravelTime[id] := INTEGER(distance / freeSpeed)
		END;
		RoadMap?NoMoreLinks
	END ReadMap;
		
	BEGIN ReadMap
END RoutePlanner;

