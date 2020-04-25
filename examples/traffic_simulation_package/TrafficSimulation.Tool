			Traffic Simulation Study
			   Luc Blaeser, August 2007

1. List of Program Sources

TrafficSimulation.Com
TrafficWithCarTransport.Com
RoadLayout.Com
PlanReader.Com
ActivityReader.Com
TextInput.Com
NetworkReader.Com
XMLParser.Com
SnapshotWriter.Com
EventWriter.Com
TextTransformer.Com
XMLOutput.Com
TripPlanner.Com
RoutePlanner.Com

2. Development System (Oberon System)

(needs the installed component system)

ComponentCompiler.Compile SystemTime.Com FileSystem.Com 
	RoutePlanner.Com TripPlanner.Com XMLOutput.Com TextTransformer.Com EventWriter.Com XMLParser.Com 
	NetworkReader.Com TextInput.Com ActivityReader.Com PlanReader.Com RoadLayout.Com TrafficSimulation.Com 
	TrafficWithCarTransport.Com ~


3. Runtime System (Component System)

(copy binary code to the partition of the component runtime system)

OFSTools.Mount COM AosFS IDEdev#part ~
System.CopyFiles
	TextParser.CBC => COM:TextParser.CBC
	TextGenerator.CBC => COM:TextGenerator.CBC
	TextTransformer.CBC => COM:TextTransformer.CBC
	XMLWriter.CBC => COM:XMLWriter.CBC
	XMLOutput.CBC => COM:XMLOutput.CBC
	EventOutput.CBC => COM:EventOutput.CBC
	WriterControl.CBC => COM:WriterControl.CBC
	BufferedEventWriter.CBC => COM:BufferedEventWriter.CBC
	NormalEventWriter.CBC => COM:NormalEventWriter.CBC
	SnapshotOutput.CBC => COM:SnapshotOutput.CBC
	SnapshotWriter.CBC => COM:SnapshotWriter.CBC
	XMLReader.CBC => COM:XMLReader.CBC 
	XMLParser.CBC => COM:XMLParser.CBC 
	TextReader.CBC => COM:TextReader.CBC
	TextInput.CBC => COM:TextInput.CBC
	RoadData.CBC => COM:RoadData.CBC
	RoadNetworkReader.CBC => COM:RoadNetworkReader.CBC
	ActivityData.CBC => COM:ActivityData.CBC
	ActivityReader.CBC => COM:ActivityReader.CBC
	PlanData.CBC => COM:PlanData.CBC
	PlanReader.CBC => COM:PlanReader.CBC
	RoadMap.CBC => COM:RoadMap.CBC
	RoutePlan.CBC => COM:RoutePlan.CBC
	PlanAdjustment.CBC => COM:PlanAdjustment.CBC
	RoutePlanner.CBC => COM:RoutePlanner.CBC
	RoadSetup.CBC => COM:RoadSetup.CBC
	RoadLayout.CBC => COM:RoadLayout.CBC
	TripPlan.CBC => COM:TripPlan.CBC
	TripPlanner.CBC => COM:TripPlanner.CBC
	TrafficSimulation.CBC => COM:TrafficSimulation.CBC
	TrafficWithCarTransport.CBC => COM:TrafficWithCarTransport.CBC
	net.xml => COM:net.xml
	plans.xml => COM:plans.xml
	plansmini.xml => COM:plansmini.xml
	activitieslarge.txt => COM:activitieslarge.txt 
	activitiesnormal.txt => COM:activitiesnormal.txt
	activitiessmall.txt => COM:activitiessmall.txt 
~
OFSTools.Unmount COM AosFS IDEdev#part ~

3.3 Run simulation

Boot the runtime system and enter:
	NEW(sim1, TrafficSimulation)
	CONNECT(FileSystem(sim1), SYSTEM)
	CONNECT(SystemTime(sim1), SYSTEM)
or 
	NEW(sim2, TrafficWithCarTransport)
	CONNECT(FileSystem(sim2), SYSTEM)
	CONNECT(SystemTime(sim2), SYSTEM)

visualize traffic flow
	NEW(x, RoadAnimator)
	CONNECT(FileSystem(x), SYSTEM)
	CONNECT(SystemTime(x), SYSTEM)
	CONNECT(GraphicView(x), SYSTEM)
and
	check result output events1.txt




