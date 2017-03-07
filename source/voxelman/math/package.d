/**
Copyright: Copyright (c) 2016-2017 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.math;

public import gfm.integers.half;
public import dlib.math.affine : translationMatrix;
public import dlib.math.vector;
public import dlib.math.matrix;
public import std.math : std_abs = abs, isNaN, floor, ceil, sqrt;
public import voxelman.math.utils;
public import voxelman.math.simplex;
public import voxelman.math.box;
public import std.algorithm : clamp, min, max, swap;

alias bvec3 = Vector!(byte, 3);
alias ubvec3 = Vector!(ubyte, 3);
alias ubvec4 = Vector!(ubyte, 4);
alias hvec3 = Vector!(half, 3);
alias svec2 = Vector!(short, 2);
alias svec3 = Vector!(short, 3);
alias svec4 = Vector!(short, 4);
