/**
Copyright: Copyright (c) 2014-2015 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/

module voxelman.utils.camera;

import std.math;

import dlib.math.vector;
import dlib.math.matrix;
import dlib.math.affine;
import dlib.math.utils;
import dlib.geometry.plane;
import dlib.geometry.frustum;

import voxelman.config;

enum IntersectionResult
{
	inside,
	outside,
	intersect
}

struct Camera
{
public:
	this(float fov,
		 float aspect,
		 float near,
		 float far)
	{
		this.fov	= fov;
		this.aspect	= aspect;
		this.near	= near;
		this.far	= far;
		updateProjection();
	}

	Matrix4f updateProjection()
	{
		perspective = perspectiveMatrix(fov, aspect, near, far);
		return perspective;
	}

	float sensivity = 1.0f;
	Matrix4f perspective;
	vec3 position = vec3(0, 0, 0);
	vec3 target = vec3(0, 0, -1);
	vec3 up	= vec3(0, 1, 0);
	vec3 right	= vec3(1, 0, 0);

	float fov = 60;
	float aspect = 1;
	float near = 0.01;
	float far = 2000;
}
