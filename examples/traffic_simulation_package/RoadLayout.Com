INTERFACE RoadSetup;
	IN Read(xmlFilename: TEXT)
END RoadSetup;

COMPONENT RoadLayout OFFERS RoadMap, RoadSetup REQUIRES RoadData;
	CONSTANT NoLink = 0;
	VARIABLE
		initialized: BOOLEAN;
		nodeX[nodeId: INTEGER]: INTEGER; nodeY[nodeId: INTEGER]: INTEGER;
		linkFrom[linkId: INTEGER]: INTEGER; linkTo[linkId: INTEGER]: INTEGER;
        linkLength[linkId: INTEGER]: REAL; linkCapacity[linkId: INTEGER]: REAL;
		linkFreeSpeed[linkId: INTEGER]: REAL; linkId[fromNode, toNode: INTEGER]: INTEGER; 
		linkLanes[linkId: INTEGER]: INTEGER; linkTransport[linkId: INTEGER]: BOOLEAN;
	
	IMPLEMENTATION RoadMap;
	VARIABLE id, from, to: INTEGER;
	BEGIN
		BEGIN {SHARED} AWAIT(initialized) END;
		WHILE ?ListAllNodes OR ?ListAllLinks OR ?GetLinkDestination OR ?FindLink OR 
				?ListOutgoingLinks OR ?GetLinkLocation OR ?IsTransportLink OR ?ListAllTransportLinks DO {SHARED}
			IF ?ListAllNodes THEN
				?ListAllNodes; 
				FOREACH id OF nodeX DO !Node(id, nodeX[id], nodeY[id]) END; 
				!NoMoreNodes
			ELSIF ?ListAllLinks THEN
				?ListAllLinks;
				FOREACH from, to OF linkId DO
					id := linkId[from, to]; 
					!Link(id, from, to, linkLength[id], linkFreeSpeed[id], linkCapacity[id], 
						linkLanes[id], linkTransport[id]) 
				END;
				!NoMoreLinks 
			ELSIF ?GetLinkDestination THEN
				?GetLinkDestination(id); 
				!Destination(linkTo[id])
			ELSIF ?FindLink THEN
				?FindLink(from, to);
				IF EXISTS(linkId[from, to]) THEN !Result(linkId[from, to]) 
				ELSE !Inexistent 
				END
			ELSIF ?ListOutgoingLinks THEN
				?ListOutgoingLinks(id);
				FOREACH from, to OF linkId DO
					IF from = id THEN !LinkEntry(to) END
				END;
				!NoMoreOutLinks
			ELSIF ?GetLinkLocation THEN
				?GetLinkLocation(id);
				from := linkFrom[id]; to := linkTo[id];
				!LinkLocation(from, to, nodeX[from], nodeY[from], nodeX[to], nodeY[to])
			ELSIF ?IsTransportLink THEN
				?IsTransportLink(id);
				IF linkTransport[id] THEN !TransportBasedLink ELSE !NormalLink END
			ELSE
				?ListAllTransportLinks;
				FOREACH from, to OF linkId DO
					id := linkId[from, to];
					IF linkTransport[id] THEN 
						!TransportLink(id, linkLength[id], linkFreeSpeed[id], linkCapacity[id])
					END
				END;
				!NoMoreTransportLinks
			END
		END
	END RoadMap;
	
	IMPLEMENTATION RoadSetup;
	VARIABLE filename: TEXT; k, id, x, y, from, to, lanes: INTEGER; capacity, length, speed: REAL;
		transport: BOOLEAN;
	BEGIN {EXCLUSIVE}
		?Read(filename);
		RoadData!Read(filename);
		WHILE RoadData?Node DO
			RoadData?Node(id, x, y); nodeX[id] := x; nodeY[id] := y
		END;
		k := 0;
		WHILE RoadData?Link DO
			RoadData?Link(id, from, to, length, capacity, lanes, speed, transport); ASSERT(id # NoLink);	
			linkFrom[id] := from; linkTo[id] := to; linkLength[id] := length; linkCapacity[id] := capacity;
			linkFreeSpeed[id] := speed; linkId[from, to] := id; linkLanes[id] := lanes; linkTransport[id] := transport;
			INC(k); IF k MOD 1000 = 0 THEN WRITE("Link "); WRITE(k); WRITE(" read"); WRITELINE END
		END;
		RoadData?Finish;
		WRITE("Road network read "); WRITELINE;
		initialized := TRUE
	END RoadSetup;
		
	BEGIN initialized := FALSE
END RoadLayout;

