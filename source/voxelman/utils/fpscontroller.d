/**
Copyright: Copyright (c) 2014 Andrey Penechko.
License: a$(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/

module voxelman.utils.fpscontroller;

import std.stdio;

import dlib.math.matrix;
import dlib.math.affine;
import dlib.math.vector;
import dlib.math.quaternion;
import dlib.math.utils;

import voxelman.utils.camera;

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
		angleVert = clamp!float(angleVert, ANGLE_VERT_MIN, ANGLE_VERT_MAX);
		isUpdated = false;
	}

	void setRotation(float angleHor, float angleVert)
	{
		this.angleHor = angleHor;
		this.angleVert = angleVert;
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
		isUpdated = true;
	}

	float* cameraMatrix()
	{
		if(!isUpdated) update();
		return &(cameraToClipMatrix.arrayof[0]);
	}
	
	void printVectors()
	{
		writefln("camera\nposition\t%s\ttarget\t%s\tup\t%s\tcamera.right\t%s",
			camera.position, camera.target, camera.up, camera.right);
	}
		
	private void calcVectors()
	{
		camera.target	= vec3(0,0,-1);
		camera.up		= vec3(0,1,0);
		
		camera.target = rotationQuat.rotate(camera.target);
		camera.target.normalize();
		
		rotationQuat.rotate(camera.up);
		camera.up.normalize();
		
		camera.right = cross(camera.up, camera.target);
	}
	
	Camera camera;

	float angleHor = 0;				//yaw
	float angleVert = 0;				//pitch
	
	enum ANGLE_VERT_MIN = -90.0f;	//minimum pitch
	enum ANGLE_VERT_MAX =  90.0f;	//maximal pitch
	
	Matrix4f cameraToClipMatrix;
	Quaternionf rotationQuat;
	Quaternionf rotationQuatHor;
	Quaternionf rotationQuatVert;
	
	bool isUpdated = false;
}