INTERFACE SystemTime;
	IN GetSystemTime OUT SystemTime(ticks: INTEGER) |
	IN Wait(ms: INTEGER) OUT Passed
END SystemTime;
