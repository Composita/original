INTERFACE GraphicView;
	{ IN Clear
	| IN GetSize OUT Size(width, height, bgColor: INTEGER)
	| IN Pixel(x, y, color: INTEGER)
	| IN Font(x, y: INTEGER; char: CHARACTER; color: INTEGER)
	| IN Fill(x, y, w, h, color: INTEGER) 
	| IN SetLayer(level: INTEGER) | IN DrawLayers }
END GraphicView;
