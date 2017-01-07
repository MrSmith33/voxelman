/**
Copyright: Copyright (c) 2015-2017 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.utils.scale;

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
