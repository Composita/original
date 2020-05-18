COMPONENT Library REQUIRES SystemTime;
	CONSTANT
		N = 1000; (* customers *)
		M = 10; (* libraries *)
		K = 10;
		ISBNBasis = 54321;
		Output = FALSE;

	INTERFACE Book;
		{ IN GetISBN OUT ISBN(x: INTEGER)
		| IN GetTitle OUT Title(x: TEXT)
		| IN GetContent OUT Content(x: TEXT) }
	END Book;
	
	INTERFACE LibraryService;
		{ IN LendBook(isbn: INTEGER) ( OUT Book(b: ANY(Book)) | OUT Unavailable ) 
		| IN ReturnBook(b: ANY(Book))
		| IN ListCatalogue { OUT BookEntry(isbn: INTEGER) } OUT EndOfList }
	END LibraryService;
	
	COMPONENT PublicLibrary OFFERS LibraryService;
		VARIABLE book[isbn: INTEGER]: ANY(Book);
	
		IMPLEMENTATION LibraryService;
		VARIABLE isbn: INTEGER; b: ANY(Book); title: TEXT;
		BEGIN
			WHILE ?LendBook OR ?ReturnBook OR ?ListCatalogue DO
				IF ?LendBook THEN {EXCLUSIVE}
					?LendBook(isbn); 
					IF ~EXISTS(book[isbn]) THEN !Unavailable
					ELSE !Book(book[isbn]) (* book[isbn] is now empty *)
					END
				ELSIF ?ReturnBook THEN {EXCLUSIVE}
					?ReturnBook(b); b!GetISBN; b?ISBN(isbn); 
					MOVE(b, book[isbn])
				ELSE {SHARED}
					?ListCatalogue;
					FOREACH isbn OF book DO 
						!BookEntry(isbn)
					END;
					!EndOfList
				END
			END
		END LibraryService;
	
		CONSTANT ISBNBasis = 54321; K = 10;
		VARIABLE isbn: INTEGER; b: LibraryBook;
		BEGIN
			FOR isbn := ISBNBasis + 1 TO ISBNBasis + K DO
				NEW(b); BookInitialization(b)!Initialize(isbn, "Memoiren", " ... "); 
				BookInitialization(b)?Initialized; MOVE(b, book[isbn])
			END
	END PublicLibrary;
	
	INTERFACE BookInitialization;
		IN Initialize(isbn: INTEGER; title, content: TEXT) OUT Initialized
	END BookInitialization;
	
	COMPONENT LibraryBook OFFERS BookInitialization, Book;
		VARIABLE isbn: INTEGER; title, content: TEXT;
		
		IMPLEMENTATION BookInitialization;
		BEGIN {EXCLUSIVE} ?Initialize(isbn, title, content); !Initialized
		END BookInitialization;
		
		IMPLEMENTATION Book;
		BEGIN
			WHILE ?GetISBN OR ?GetTitle OR ?GetContent DO
				IF ?GetISBN THEN {SHARED} ?GetISBN; !ISBN(isbn)
				ELSIF ?GetTitle THEN {SHARED} ?GetTitle; !Title(title)
				ELSE {SHARED} ?GetContent; !Content(content)
				END
			END
		END Book;
	END LibraryBook;
	
	COMPONENT LibraryCustomer REQUIRES LibraryService [1..*];
		VARIABLE interested, count, k, isbn: INTEGER; title, content: TEXT; b: ANY(Book);
		
		BEGIN
			FOR k := 1 TO M DO
				LibraryService[k]!ListCatalogue;
				WHILE LibraryService[k]?BookEntry DO
					LibraryService[k]?BookEntry(isbn);
					IF Output THEN WRITE("Book "); WRITE(isbn); WRITELINE END;
					IF k MOD 10 = 1 THEN interested := isbn END
				END;
				LibraryService[k]?EndOfList;
				LibraryService[k]!LendBook(interested);
				IF LibraryService[k]?Book THEN 
					LibraryService[k]?Book(b); 
					IF Output THEN WRITE("Book lent "); WRITE(interested); WRITELINE END;
					b!GetISBN; b?ISBN(isbn); ASSERT(isbn = interested); 
					b!GetTitle; b?Title(title);
					b!GetContent; b?Content(content);
					LibraryService[k]!ReturnBook(b) (* b is now empty *);
					IF Output THEN WRITE("Book returned"); WRITELINE END
				ELSE
					LibraryService[k]?Unavailable;
					IF Output THEN WRITE("Book unavailable"); WRITELINE END
				END
			END
	END LibraryCustomer;

	PROCEDURE SystemTime(): INTEGER;
	VARIABLE t: INTEGER;
	BEGIN SystemTime!GetSystemTime; SystemTime?SystemTime(t); RETURN t
	END SystemTime;

	VARIABLE
		customer[number: INTEGER]: LibraryCustomer;
		library[number: INTEGER]: PublicLibrary;
		i, k, startTime: INTEGER;
	BEGIN
		startTime := SystemTime();
		FOR k := 1 TO M DO NEW(library[k]) END;
		FOR i := 1 TO N DO 
			NEW(customer[i]); 
			FOR k := 1 TO M DO
				CONNECT(LibraryService[k](customer[i]), library[k])
			END
		END;
		(* just for time measurement *)
		FOR i := 1 TO N DO DELETE(customer[i]) END;
		FOR k := 1 TO M DO DELETE(library[k]) END;
		WRITE(SystemTime()-startTime); WRITE(" ms"); WRITELINE
END Library;

