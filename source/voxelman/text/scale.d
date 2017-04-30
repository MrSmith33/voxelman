/**
Copyright: Copyright (c) 2015-2017 Andrey Penechko.
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

int numDigitsInNumber(Num)(Num val)
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
	assert(numDigitsInNumber(ushort.max) == 5);
	assert(numDigitsInNumber(uint.max) == 10); // 4294967295
	assert(numDigitsInNumber(long.max) == 19);
	assert(numDigitsInNumber(ulong.max) == 20);
}

int calcScale(Num)(Num val)
{
	import std.algorithm: clamp;
	import std.math: abs, floor, pow, log10;
	auto maxValue = abs(val);
	int scale = clamp((cast(int) floor(log10(maxValue))/3)*3, -24, 24);
	return scale;
}

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
