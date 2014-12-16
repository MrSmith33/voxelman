/**
Copyright: Copyright (c) 2014 Andrey Penechko.
License: a$(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/

module voxelman.fpscontroller;

import std.stdio;
import dlib.math.matrix;
import dlib.math.affine;
import dlib.math.vector;
import dlib.math.quaternion;
import dlib.math.utils;

import voxelman.camera;

struct FpsController
{
	void move(Vector3f vec)
	{
		if (isUpdated == false) update();
		camera.position += vec;
		isUpdated = false;
	}
	
	void moveAxis(vec3 vec)
	{
		if (isUpdated == false) update();

		// Strafe
		vec3 horRight = vec3(1,0,0);
		horRight = rotationQuatHor.rotate(horRight);
		horRight.normalize();
		camera.position += horRight * vec.x * vec3(1,1,-1);

		// Move up/down
		camera.position.y += vec.y;

		// Move forward
		vec3 horTarget = vec3(0,0,1);
		horTarget = rotationQuatHor.rotate(horTarget);
		horTarget.normalize();
		camera.position += horTarget * vec.z * vec3(1,1,-1);
		
		isUpdated = false;
	}
	
	void rotateHor(float angle)
	{
		angleHor += angle * camera.sensivity;
		angleHor %= 360;
		isUpdated = false;
	}
	
	void rotateVert(float angle)
	{
		angleVert += angle * camera.sensivity;
		angleVert = clamp!float(angleVert, angleVertMin, angleVertMax);
		isUpdated = false;
	}

	void update()
	{
		rotationQuatHor = rotation!float(Vector3f(0,1,0), degtorad!float(angleHor));
		rotationQuatVert = rotation!float(Vector3f(1,0,0), degtorad!float(angleVert));
		
		rotationQuat = rotationQuatVert * rotationQuatHor;
		rotationQuat.normalize();

		Matrix4f rotation = rotationQuat.toMatrix4x4;//fromEuler!float(vec3(degtorad!float(-angleVert), degtorad!float(-angleHor), 0));
		Matrix4f proj = translationMatrix(-camera.position);
		calcVectors();

		cameraToClipMatrix = rotation * proj;
		camera.updateFrustum(cameraToClipMatrix);
		isUpdated = true;
	}

	float* cameraMatrix()
	{
		if(!isUpdated) update();
		return &(cameraToClipMatrix.arrayof[0]);
	}
	
	void printVectors()
	{
		writefln("camera\nposition\t%s\ttarget\t%s\tup\t%s\tright\t%s",
			camera.position, camera.target, camera.up, right);
	}
		
	private void calcVectors()
	{
		camera.target	= vec3(0,0,1);
		camera.up		= vec3(0,1,0);
		right			= vec3(-1,0,0);
		
		camera.target = rotationQuat.rotate(camera.target);
		camera.target.normalize();

		camera.target.y = 0;
		
		rotationQuat.rotate(camera.up);
		camera.up.normalize();
		
		right = cross(camera.up, camera.target);
	}
	
	Camera camera;

	float angleHor = 0;				//yaw
	float angleVert = 0;				//pitch
	
	enum angleVertMin = -90.0f;	//minimum pitch
	enum angleVertMax =  90.0f;	//maximal pitch
	
	Matrix4f cameraToClipMatrix;
	Quaternionf rotationQuat;
	Quaternionf rotationQuatHor;
	Quaternionf rotationQuatVert;
	vec3 right	= vec3(1,0,0);	//for strafe
	
	bool isUpdated = false;
}