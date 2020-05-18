INTERFACE FileSystem;
	( IN New(name: TEXT) | IN Open(name: TEXT) )
	( OUT Done
		{ IN SetPosition(position: INTEGER) 
		| IN GetPosition OUT Position(pos: INTEGER)
		| IN GetLength OUT Length(len: INTEGER)
		| ( IN ReadByte | IN ReadLine ) ( OUT Byte(x: CHARACTER) | OUT Line(x: TEXT) | OUT EOF )
		| IN Write(x: CHARACTER) | IN WriteText(x: TEXT)
		| IN Update }
		IN Close
	| OUT Failed )
END FileSystem;

