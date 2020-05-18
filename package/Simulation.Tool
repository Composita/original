		Component Language
	     Luc Blaeser, March 2010

1. List of Program Sources

Simulation.Com
Eratosthenes.Com
TokenRing.Com
TrafficSimulation.Com
RoutePlanner.Com
ActivityReader.Com
NetworkReader.Com

EditTools.OpenAscii zurich_net.falsified.xml ~
EditTools.OpenAscii zurich_plans.falsified.xml ~

2. Compilation (Oberon)

ComponentCompiler.Compile SystemTime.Com FileSystem.Com GraphicView.Com Simulation.Com 
	Eratosthenes.Com TokenRing.Com RoutePlanner.Com TripPlanner.Com XMLOutput.Com 
	TextTransformer.Com EventWriter.Com SnapshotWriter.Com XMLParser.Com NetworkReader.Com 
	TextInput.Com ActivityReader.Com PlanReader.Com SnapshotReader.Com 
	RoadLayout.Com RoadViewer.Com RoadAnimator.Com TrafficSimulation.Com
	  ~

3. Installation (Component OS)

Configuration.DoCommands
OFSTools.Mount COM AosFS IDE1#2 ~
System.CopyFiles
	Simulation.CBC => COM:Simulation.CBC
	Eratosthenes.CBC => COM:Eratosthenes.CBC
	TokenRing.CBC => COM:TokenRing.CBC
	RoadMap.CBC => COM:RoadMap.CBC
	RoutePlan.CBC => COM:RoutePlan.CBC
	PlanAdjustment.CBC => COM:PlanAdjustment.CBC
	RoutePlanner.CBC => COM:RoutePlanner.CBC
	TripPlan.CBC => COM:TripPlan.CBC
	TripPlanner.CBC => COM:TripPlanner.CBC
	TextParser.CBC => COM:TextParser.CBC
	TextGenerator.CBC => COM:TextGenerator.CBC
	TextTransformer.CBC => COM:TextTransformer.CBC
	XMLWriter.CBC => COM:XMLWriter.CBC
	XMLOutput.CBC => COM:XMLOutput.CBC
	EventOutput.CBC => COM:EventOutput.CBC
	WriterControl.CBC => COM:WriterControl.CBC
	BufferedEventWriter.CBC => COM:BufferedEventWriter.CBC
	NormalEventWriter.CBC => COM:NormalEventWriter.CBC
	XMLReader.CBC => COM:XMLReader.CBC 
	XMLParser.CBC => COM:XMLParser.CBC 
	TextReader.CBC => COM:TextReader.CBC
	TextInput.CBC => COM:TextInput.CBC
	RoadData.CBC => COM:RoadData.CBC
	RoadNetworkReader.CBC => COM:RoadNetworkReader.CBC
	ActivityData.CBC => COM:ActivityData.CBC
	ActivityReader.CBC => COM:ActivityReader.CBC
	SnapshotOutput.CBC => COM:SnapshotOutput.CBC
	SnapshotWriter.CBC => COM:SnapshotWriter.CBC
	SnapshotInput.CBC => COM:SnapshotInput.CBC
	SnapshotReader.CBC => COM:SnapshotReader.CBC
	RoutePlan.CBC => COM:RoutePlan.CBC
	PlanAdjustment.CBC => COM:PlanAdjustment.CBC
	RoutePlanner.CBC => COM:RoutePlanner.CBC
	TrafficSimulation.CBC => COM:TrafficSimulation.CBC
	RoadViewer.CBC => COM:RoadViewer.CBC
	RoadAnimator.CBC => COM:RoadAnimator.CBC
	net.xml => COM:net.xml
	planssmall.xml => COM:planssmall.xml
	zurich_net.falsified.xml => COM:zurich_net.falsified.xml
	zurich_plans.falsified.xml => COM:zurich_plans.falsified.xml
	~
OFSTools.Unmount COM AosFS IDE1#2 ~
~


