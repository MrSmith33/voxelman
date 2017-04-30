/**
Copyright: Copyright (c) 2016-2017 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.math;

public import std.algorithm : clamp, min, max, swap;
public import std.math : std_abs = abs, isNaN, floor, ceil, sqrt;

public import gfm.integers.half;

public import dlib.math.affine : translationMatrix, orthoMatrix, perspectiveMatrix;
public import dlib.math.interpolation : lerp;
public import dlib.math.matrix;
public import dlib.math.quaternion;
public import dlib.math.utils;
public import dlib.math.vector;

public import voxelman.geometry.rect;
public import voxelman.math.box;
public import voxelman.math.simplex;
public import voxelman.math.utils;

enum double SQRT_2 = sqrt(2.0);

alias bvec3 = Vector!(byte, 3);
alias hvec3 = Vector!(half, 3);
alias svec2 = Vector!(short, 2);
alias svec3 = Vector!(short, 3);
alias svec4 = Vector!(short, 4);
alias ubvec3 = Vector!(ubyte, 3);
alias ubvec4 = Vector!(ubyte, 4);
