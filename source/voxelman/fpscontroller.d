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

class FpsController
{
	this()
	{
		camera = new Camera;
		_angleHor = 0;
		_angleVert = 0;
		camera.sensivity = 1;
	}

	/++
	 + Moves position by Vector3f vec. vec must be product of dir vector and distance scalar
	 +/
	void move(Vector3f dir, float dist)
	{
		if (isUpdated == false) update();
		camera.position += dir * dist;
		isUpdated = false;
	}

	void move(Vector3f vec)
	{
		if (isUpdated == false) update();
		camera.position += vec;
		isUpdated = false;
	}
	
	void mveAxis(Vector3f vec)
	{
		if (isUpdated == false) update();
		camera.position += right * vec.x;
		camera.position.y += vec.y;
		camera.position -= camera.target * vec.z;
		isUpdated = false;
	}
	
	void rotateHor(float angle)
	{
		_angleHor += angle * camera.sensivity;		
		isUpdated = false;
	}
	
	void rotateVert(float angle)
	{
		_angleVert += angle * camera.sensivity;
		_angleVert = clamp!float(_angleVert, _angleVertMin, _angleVertMax);
		isUpdated = false;
	}
	

	void update()
	{		
		rotationQuat = rotation!float(Vector3f(1,0,0), degtorad!float(-_angleVert)) * rotation!float(Vector3f(0,1,0), degtorad!float(-_angleHor));
		rotationQuat.normalize();
		//writeln(rotationQuat);
		Matrix4f rotation = fromEuler!float(Vector3f(degtorad!float(_angleVert), degtorad!float(_angleHor), 0));
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
		writefln("camera.position\t%s\ncamera.target\t%s\ncamera.up\t%s\nright\t\t%s",camera.position, camera.target, camera.up, right);	
	}
		
	private void calcVectors()
	{
		camera.target	= vec3(0,0,1);
		camera.up		= vec3(0,1,0);
		right			= vec3(1,0,0);	
		
		camera.target = rotationQuat.rotate(camera.target);
		//writeln(camera.target);
		camera.target.normalize();
		camera.target.y = 0;
		rotationQuat.rotate(camera.up);
		camera.up.normalize();
		right = cross(camera.target, Vector3f(0,1,0));
	}
	
	Camera camera;

	float _angleHor;				//yaw
	float _angleVert;				//pitch
	
	float _angleVertMin = -90.0f;	//minimum pitch
	float _angleVertMax =  90.0f;	//maximal pitch
	
	Matrix4f cameraToClipMatrix;
	Quaternionf rotationQuat;
	Vector3f right	= vec3(1,0,0);	//for strafe
	
	bool isUpdated = false;
}