/**
Copyright: Copyright (c) 2015-2018 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.text.scale;

immutable string[int] scales;
shared static this(){
	scales = [
	-24 : "y",
	-21 : "z",
	-18 : "a",
	-15 : "f",
	-12 : "p",
	-9  : "n",
	-6  : "u",
	-3  : "m",
	 0  : "",
	 3  : "K",
	 6  : "M",
	 9  : "G",
	 12 : "T",
	 15 : "P",
	 18 : "E",
	 21 : "Z",
	 24 : "Y",];
}

int numDigitsInNumber(Num)(const Num val)
{
	import std.math: abs;
	ulong absVal = cast(ulong)abs(val);
	int numDigits = 1;

	while (absVal >= 10)
	{
		absVal /= 10;
		++numDigits;
	}

	return numDigits;
}

unittest
{
	assert(numDigitsInNumber(0) == 1);
	assert(numDigitsInNumber(-1) == 1);
	assert(numDigitsInNumber(1) == 1);
	assert(numDigitsInNumber(ubyte.max) == 3);
	assert(numDigitsInNumber(9) == 1);
	assert(numDigitsInNumber(10) == 2);
	assert(numDigitsInNumber(11) == 2);
	assert(numDigitsInNumber(100) == 3);
	assert(numDigitsInNumber(ushort.max) == 5);
	assert(numDigitsInNumber(uint.max) == 10); // 4294967295
	assert(numDigitsInNumber(long.max) == 19);
	assert(numDigitsInNumber(ulong.max) == 20);
}

int calcScale(Num)(Num val)
{
	import std.algorithm: clamp;
	import std.math: abs, floor, ceil, log10;
	import voxelman.math : sign;

	auto lg = log10(abs(val));
	int logSign = sign(lg);
	double absLog = abs(lg);

	int scale;
	if (lg < 0)
		scale = cast(int)(ceil(absLog/3.0))*3;
	else
		scale = cast(int)(floor(absLog/3.0))*3;

	int clampedScale = clamp(scale * logSign, -24, 24);

	return clampedScale;
}

unittest
{
	assert(calcScale(0.000_000_001) == -9);
	assert(calcScale(0.000_000_01) == -9);
	assert(calcScale(0.000_000_1) == -9);

	assert(calcScale(0.000_001) == -6);
	assert(calcScale(0.000_01) == -6);
	assert(calcScale(0.000_1) == -6);

	assert(calcScale(0.001) == -3);
	assert(calcScale(0.01) == -3);
	assert(calcScale(0.1) == -3);

	assert(calcScale(1.0) == 0);
	assert(calcScale(10.0) == 0);
	assert(calcScale(100.0) == 0);

	assert(calcScale(1_000.0) == 3);
	assert(calcScale(10_000.0) == 3);
	assert(calcScale(100_000.0) == 3);

	assert(calcScale(1_000_000.0) == 6);
	assert(calcScale(10_000_000.0) == 6);
	assert(calcScale(100_000_000.0) == 6);

	assert(calcScale(1_000_000_000.0) == 9);
	assert(calcScale(10_000_000_000.0) == 9);
	assert(calcScale(100_000_000_000.0) == 9);
}

struct ScaledNumberFmt(T)
{
	T value;
	void toString()(scope void delegate(const(char)[]) sink)
	{
		import std.format : formattedWrite;
		int scale = calcScale(value);
		auto scaledValue = scaled(value, scale);
		int digits = numDigitsInNumber(scaledValue);
		sink.formattedWrite("%*.*f%s", digits, 3-digits, scaledValue, scales[scale]);
	}
}

/// Display number as
/// d.dds (1.23m)
/// dd.ds (12.3K)
/// ddds  (123G)
/// Where d is digit, s is SI suffix
auto scaledNumberFmt(T)(T value)
{
	return ScaledNumberFmt!T(value);
}

import std.datetime : Duration;
auto scaledNumberFmt(Duration value)
{
	double seconds = value.total!"hnsecs" / 10_000_000.0;
	return ScaledNumberFmt!double(seconds);
}
/*
unittest
{
	import std.stdio;
	0.000_000_001234.scaledNumberFmt.writeln;
	0.000_000_01234.scaledNumberFmt.writeln;
	0.000_000_1234.scaledNumberFmt.writeln;
	0.000_001234.scaledNumberFmt.writeln;
	0.000_01234.scaledNumberFmt.writeln;
	0.000_1234.scaledNumberFmt.writeln;
	0.001234.scaledNumberFmt.writeln;
	0.01234.scaledNumberFmt.writeln;
	0.1234.scaledNumberFmt.writeln;
	1.234.scaledNumberFmt.writeln;
	12.34.scaledNumberFmt.writeln;
	123.4.scaledNumberFmt.writeln;
	1_234.0.scaledNumberFmt.writeln;
	12_340.0.scaledNumberFmt.writeln;
	123_400.0.scaledNumberFmt.writeln;
	1_234_000.0.scaledNumberFmt.writeln;
	12_340_000.0.scaledNumberFmt.writeln;
	123_400_000.0.scaledNumberFmt.writeln;
	1_234_000_000.0.scaledNumberFmt.writeln;
	12_340_000_000.0.scaledNumberFmt.writeln;
	123_400_000_000.0.scaledNumberFmt.writeln;

	0.000_000_001.scaledNumberFmt.writeln;
	0.000_000_01.scaledNumberFmt.writeln;
	0.000_000_1.scaledNumberFmt.writeln;
	0.000_001.scaledNumberFmt.writeln;
	0.000_01.scaledNumberFmt.writeln;
	0.000_1.scaledNumberFmt.writeln;
	0.001.scaledNumberFmt.writeln;
	0.01.scaledNumberFmt.writeln;
	0.1.scaledNumberFmt.writeln;
	1.0.scaledNumberFmt.writeln;
	10.0.scaledNumberFmt.writeln;
	100.0.scaledNumberFmt.writeln;
	1_000.0.scaledNumberFmt.writeln;
	10_000.0.scaledNumberFmt.writeln;
	100_000.0.scaledNumberFmt.writeln;
	1_000_000.0.scaledNumberFmt.writeln;
	10_000_000.0.scaledNumberFmt.writeln;
	100_000_000.0.scaledNumberFmt.writeln;
	1_000_000_000.0.scaledNumberFmt.writeln;
	10_000_000_000.0.scaledNumberFmt.writeln;
	100_000_000_000.0.scaledNumberFmt.writeln;
}
*/
double scaled(Num)(Num num, int scale)
{
	import std.math: pow;
	return num * pow(10.0, -scale);
}

int stepPrecision(float step)
{
	import std.algorithm : clamp;
	import std.math: floor, log10;
	return clamp(-cast(int)floor(log10(step)), 0, 3);
}
