/**
Copyright: Copyright (c) 2016 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.math;

public import gfm.integers.half;
public import dlib.math.vector;
public import std.math : isNaN, floor;
public import voxelman.math.utils;
public import voxelman.math.simplex;
public import std.algorithm : clamp;

alias bvec3 = Vector!(byte, 3);
alias ubvec3 = Vector!(ubyte, 3);
alias hvec3 = Vector!(half, 3);
alias svec2 = Vector!(short, 2);
alias svec3 = Vector!(short, 3);
alias svec4 = Vector!(short, 4);
