		Composita System - Kernel Builder
	       Copyright (c) Luc Blaeser, 2004-2013

1. Build New Oberon Compiler

PC.Compile \s
	CCPCDebug.Mod CCPCM.Mod CCPCS.Mod CCPCT.Mod CCPCBT.Mod CCPCLIR.Mod CCPCO.Mod CCPCG386.Mod 
	CCPCC.Mod CCPCV.Mod CCPCB.Mod CCPCP.Mod CCPCA386.Mod CCPCOM.Mod CCPCOF.Mod 	CCPC.Mod ~

2. Build linker

PC.Compile \s CCBasic.Mod ComponentLinker.Mod ~

3. Build kernel

CCPC.Compile \Ks 
	Processors.Sys Memory.Sys Output.Sys Interrupts.Sys Heap.Sys Concurrency.Sys 
	Keyboard.Sys DiskDriver.Sys FileSystem.Sys Basic.Sys Collections.Sys Runtime.Sys 
	BinaryCode.Sys Loader.Sys Console.Sys ~

4. Build component compiler

PC.Compile \s 
	CBC.Mod CCBasic.Mod CCScanner.Mod CCIR.Mod CCParser.Mod CCImporter.Mod CCChecker.Mod
	CCIx86A.Mod CCIx86CG.Mod CCGenerator.Mod ComponentCompiler.Mod  ~

5. Compile system interfaces

ComponentCompiler.Compile SystemTime.Com FileSystem.Com GraphicView.Com ~

6. Compile examples

ComponentCompiler.Compile Simulation.Com ProducerConsumer.Com Eratosthenes.Com TokenRing.Com
	City.Com News.Com Library.Com Mandelbrot.Com ~

7. Link kernel

ComponentLinker.LinkBootImage Kernel.Bin Modules={ComConsole} 
	Interfaces={FileSystem, SystemTime, GraphicView}  ~

or kernel with linked examples:
ComponentLinker.LinkBootImage Kernel.Bin Modules={ComConsole} 
	Interfaces={FileSystem, SystemTime, GraphicView}  
	Components={Simulation, ProducerConsumer, Eratosthenes, 
						   TokenRing, City, News, Library, Mandelbrot, MaxProcesses} ~

8. Install kernel

on hard disk:
Partitions.UpdateBootFile IDE0#2 Kernel.Bin ~
Partitions.SetConfig IDE0#2 Init="117" ~

9. Install examples

ComponentCompiler.Compile  Mandelbrot.Com ProducerConsumer.Com TokenRing.Com 
       Eratosthenes.Com City.Com News.Com Library.Com ~
FSTools.Mount COM AosFS IDE0#2 ~ 
FSTools.CopyFiles -io 
	Mandelbrot.CBC => COM:Mandelbrot.CBC
	ProducerConsumer.CBC => COM:ProducerConsumer.CBC
	TokenRing.CBC => COM:TokenRing.CBC
	Eratosthenes.CBC => COM:Eratosthenes.CBC
	City.CBC => COM:City.CBC
	News.CBC => COM:New.CBC
	Library.CBC => COM:Library.CBC
~
FSTools.Unmount COM ~
 
10. Boot and run examples

NEW(x, Mandelbrot);
CONNECT(SystemTime(x), SYSTEM)

11. Create Boot CD

SystemTools.DoCommands
	FSTools.Mount RAMDISK RamFS 2000 4096 ~
	FSTools.DeleteFiles RAMDISK:Composita.Dsk ~
	VirtualDisks.Create RAMDISK:Composita.Dsk 300 512 ~
	VirtualDisks.Install -c=80 -h=2 -s=18 -b=512 VDISK0 RAMDISK:Composita.Dsk  ~
	ComponentLinker.LinkBootImage Kernel.Bin Modules={ComConsole} 
		Interfaces={FileSystem, SystemTime, GraphicView}  ~
	Partitions.Format VDISK0#0 AosFS 1024 Kernel.Bin ~
	FSTools.Mount TEMP AosFS VDISK0#0 ~
	FSTools.CopyTo TEMP: 
		Mandelbrot.CBC ProducerConsumer.CBC TokenRing.CBC Eratosthenes.CBC 
		City.CBC News.CBC Library.CBC MaxProcesses.CBC GarbageTest.CBC ~
	FSTools.Watch TEMP ~
	FSTools.Unmount TEMP ~
	Partitions.SetConfig VDISK0#0 Init="118" ~
	VirtualDisks.Uninstall VDISK0 ~
	IsoImages.Make Composita.iso RAMDISK:Composita.Dsk ~
	FSTools.Unmount RAMDISK ~
~~

12. Locate kernel trap

Subtract PC base point by kernel linker minus ~ 3800

CCPC.Compile \Kf 15677Runtime.Sys  ~

