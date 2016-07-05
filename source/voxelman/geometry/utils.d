/**
Copyright: Copyright (c) 2016 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.geometry.utils;

// rotates around Y axis clocwise or counter clockwise
// rotType is 0 for 90, 1 for 180, 2 for 270 degrees
T rotatePointCCW(T)(T point, ubyte rotType)
{
	     if (rotType == 0) return rotateCCW90(point);
	else if (rotType == 1) return rotateCCW180(point);
	else if (rotType == 2) return rotateCCW270(point);
}

// ditto
T rotatePointCW(T)(T point, ubyte rotType)
{
	return rotatePointCCW(point, 2 - rotType);
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
	res.x =  point.z + size.z;
	res.z = -point.x;
	return res;
}

T rotateCCW180ShiftOrigin(T)(T point, T size)
{
	T res = point;
	res.x = -point.x + size.x;
	res.z = -point.z - size.z;
	return res;
}

T rotateCCW270ShiftOrigin(T)(T point, T size)
{
	T res = point;
	res.x = -point.z;
	res.z =  point.x - size.x;
	return res;
}
