/**
Copyright: Copyright (c) 2014 Andrey Penechko.
License: a$(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/

module voxelman.camera;

import dlib.math.vector;
import dlib.math.matrix;
import dlib.math.affine;

class Camera
{
public:
	this()
	{
		updatePerspective();
	}
		
	this(float fov ,
		 float aspect,
		 float near,
		 float far)
	{
		this.fov	= fov;
		this.aspect	= aspect;
		this.near	= near;
		this.far	= far;
		updatePerspective();
	}
	
	Matrix4f updatePerspective()
	{
		perspective = perspectiveMatrix(fov, aspect, near, far);
		return perspective;
	}

	float sensivity = 1.0f;
	Matrix4f perspective;
	vec3 position = vec3(0, 0, 0);
	vec3 target = vec3(0, 0, 1);
	vec3 up	= vec3(0, 1, 0);

	float fov = 60;
	float aspect = 1;
	float near = 0.01;
	float far = 2000;
}