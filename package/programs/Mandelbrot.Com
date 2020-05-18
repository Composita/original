COMPONENT Mandelbrot REQUIRES SystemTime;
	CONSTANT 
		K = 5000; H = 10; V = 10;
		Resolution = 0.05; 
		Left = -2.0; Top = -1.0; 
		Right = 2.0; Bottom = 1.0;
		Output = FALSE;

	INTERFACE MandelbrotSet;
		IN Start(N, M: INTEGER; x0, y0, dx, dy: REAL)
		{ OUT Value(x, y: INTEGER; zreal, zimag: REAL) }
		OUT Finish
	END MandelbrotSet;
	
	COMPONENT MandelbrotTask OFFERS MandelbrotSet;
		IMPLEMENTATION MandelbrotSet;
		VARIABLE 
			N, M: INTEGER; x0, y0, dx, dy: REAL;
			zreal[x, y: INTEGER]: REAL {ARRAY};
			zimag[x, y: INTEGER]: REAL {ARRAY};
			x, y, k: INTEGER; zreal2, zimag2, zri, creal, cimag, a, b: REAL;
		BEGIN
			?Start(N, M, x0, y0, dx, dy);
			NEW(zreal, N, M); NEW(zimag, N, M);
			FOR x := 0 TO N-1 DO 
				FOR y := 0 TO M-1 DO
					zreal[x, y] := 0.0; zimag[x, y] := 0.0
				END
			END;
			FOR k := 1 TO K DO
				FOR x := 0 TO N-1 DO
					FOR y := 0 TO M-1 DO
						zreal2 := zreal[x, y] * zreal[x, y]; zimag2 := zimag[x, y] * zimag[x, y];
						IF SQRT(zreal2 + zimag2) <= 2.0 THEN
							creal := x0 + dx * x; cimag := y0 + dy * y; zri := zreal[x, y] * zimag[x, y];
							a := zreal2 - zimag2 + creal;
							b := 2 * zri + cimag;
							zreal[x, y] := a; zimag[x, y] := b
						END
					END
				END
			END;
			FOR x := 0 TO N-1 DO
				FOR y := 0 TO M-1 DO
					!Value(x, y, zreal[x, y], zimag[x, y])
				END
			END;
			!Finish
		END MandelbrotSet;
	END MandelbrotTask;
	
	PROCEDURE SystemTime(): INTEGER;
	VARIABLE t: INTEGER;
	BEGIN SystemTime!GetSystemTime; SystemTime?SystemTime(t); RETURN t
	END SystemTime;
	
	VARIABLE 
		N, M, i, j, x, y: INTEGER; L, T, a, b: REAL;
		task[i, j: INTEGER]: MandelbrotTask;
		zreal[x, y: INTEGER]: REAL {ARRAY}; 
		zimag[x, y: INTEGER]: REAL {ARRAY};
		start: INTEGER;
	BEGIN
		start := SystemTime();
		N := INTEGER((Right-Left) / (Resolution * H));
		M := INTEGER((Bottom-Top) / (Resolution * V));
		FOR i := 0 TO H-1 DO
			FOR j := 0 TO V-1 DO
				L := Left + i * N * Resolution; T := Top + j * M * Resolution;
				NEW(task[i, j]); task[i, j]!Start(N, M, L, T, Resolution, Resolution)
			END
		END;
		NEW(zreal, H*N, V*M); NEW(zimag, H*N, V*M);
		FOR i := 0 TO H-1 DO
			FOR j := 0 TO V-1 DO
				WHILE task[i, j]?Value DO
					task[i, j]?Value(x, y, a, b);
					zreal[i * N + x, j * M + y] := a;
					zimag[i* N + x, j * M + y] := b
				END;
				task[i, j]?Finish
			END
		END;
		WRITE(SystemTime()-start); WRITE("ms"); WRITELINE;
		IF Output THEN
			FOR y := 0 TO V*M-1 DO
				FOR x := 0 TO H*N-1 DO
					a := zreal[x, y] * zreal[x, y]; b := zimag[x, y] * zimag[x, y];
					IF SQRT(a + b) <= 2 THEN WRITE(".") ELSE WRITE(" ") END
				END;
				WRITELINE
			END
		END
END Mandelbrot;

