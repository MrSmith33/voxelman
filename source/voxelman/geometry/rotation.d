/**
Copyright: Copyright (c) 2016-2017 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.geometry.rotation;

// rotates around Y axis clocwise or counter clockwise
// rotType is 0 for 0, 1 for 90, 2 for 180, 3 for 270 degrees
T rotatePointCCW(T)(T point, ubyte rotType)
{
	if (rotType == 1) return rotateCCW90(point);
	else if (rotType == 2) return rotateCCW180(point);
	else if (rotType == 3) return rotateCCW270(point);
	return point;
}

// ditto
T rotatePointCW(T)(T point, ubyte rotType)
{
	if (rotType == 1) return rotateCCW270(point);
	else if (rotType == 2) return rotateCCW180(point);
	else if (rotType == 3) return rotateCCW90(point);
	return point;
}

// ditto
T rotatePointShiftOriginCW(T)(T point, T size, ubyte rotType)
{
	if (rotType == 1) return rotateCCW270ShiftOrigin(point, size);
	else if (rotType == 2) return rotateCCW180ShiftOrigin(point, size);
	else if (rotType == 3) return rotateCCW90ShiftOrigin(point, size);
	return point;
}

T function(T) getCCWRotationFunction(T)(ubyte rotType)
{
	if (rotType == 1) return &rotateCCW90!T;
	else if (rotType == 2) return &rotateCCW180!T;
	else if (rotType == 3) return &rotateCCW270!T;
	return &rotateCCW0!T;
}

T function(T, T) getCCWRotationShiftOriginFunction(T)(ubyte rotType)
{
	if (rotType == 1) return &rotateCCW90ShiftOrigin!T;
	else if (rotType == 2) return &rotateCCW180ShiftOrigin!T;
	else if (rotType == 3) return &rotateCCW270ShiftOrigin!T;
	return &rotateCCW0ShiftOrigin!T;
}

T rotateCCW0(T)(T point)
{
	return point;
}

T rotateCCW90(T)(T point)
{
	T res = point;
	res.x =  point.z;
	res.z = -point.x;
	return res;
}

T rotateCCW180(T)(T point)
{
	T res = point;
	res.x = -point.x;
	res.z = -point.z;
	return res;
}

T rotateCCW270(T)(T point)
{
	T res = point;
	res.x = -point.z;
	res.z =  point.x;
	return res;
}

T rotateCCW90ShiftOrigin(T)(T point, T size)
{
	T res = point;
	res.x =  point.z;
	res.z = -point.x + size.x;
	return res;
}

T rotateCCW180ShiftOrigin(T)(T point, T size)
{
	T res = point;
	res.x = -point.x + size.x;
	res.z = -point.z + size.z;
	return res;
}

T rotateCCW270ShiftOrigin(T)(T point, T size)
{
	T res = point;
	res.x = -point.z + size.z;
	res.z =  point.x;
	return res;
}

T rotateCCW0ShiftOrigin(T)(T point, T size)
{
	return point;
}
