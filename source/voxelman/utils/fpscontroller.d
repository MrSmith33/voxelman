/**
Copyright: Copyright (c) 2014-2015 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/

module voxelman.utils.fpscontroller;

import std.experimental.logger;

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
		vec3 right = rotationQuatHor.rotate(vec3(1,0,0));
		camera.position += right * vec.x;

		// Move up/down
		camera.position.y += vec.y;

		// Move forward
		vec3 target = rotationQuatHor.rotate(vec3(0,0,-1));
		camera.position += target * vec.z;

		isUpdated = false;
	}

	void rotate(vec2 angles)
	{
		heading += angles * camera.sensivity;
		clampHeading();
		isUpdated = false;
	}

	void setHeading(vec2 heading)
	{
		this.heading = heading;
		clampHeading();
		isUpdated = false;
	}

	void clampHeading()
	{
		heading.x %= 360;
		heading.y = clamp!float(heading.y, ANGLE_VERT_MIN, ANGLE_VERT_MAX);
	}

	void update()
	{
		rotationQuatHor = rotation!float(vec3(0,1,0), degtorad!float(heading.x));
		rotationQuatVert = rotation!float(vec3(1,0,0), degtorad!float(heading.y));

		rotationQuat = rotationQuatHor * rotationQuatVert;
		rotationQuat.normalize();
		calcVectors();

		Matrix4f rotation = rotationQuat.toMatrix4x4.inverse;//fromEuler!float(vec3(degtorad!float(-heading.y), degtorad!float(-angleHor), 0));
		Matrix4f proj = translationMatrix(-camera.position);

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
		infof("camera\npos\t%s\ttarget\t%s\tup\t%s\tright\t%s",
			camera.position, camera.target, camera.up, camera.right);
	}

	private void calcVectors()
	{
		camera.target = rotationQuat.rotate(vec3(0,0,-1));
		camera.up = rotationQuat.rotate(vec3(0,1,0));
		camera.right = rotationQuat.rotate(vec3(1,0,0));
	}

	Camera camera;

	vec2 heading = vec2(0, 0); // yaw, pitch

	enum ANGLE_VERT_MIN = -90.0f;	//minimum pitch
	enum ANGLE_VERT_MAX =  90.0f;	//maximal pitch

	Matrix4f cameraToClipMatrix;
	Quaternionf rotationQuat;
	Quaternionf rotationQuatHor;
	Quaternionf rotationQuatVert;

	bool isUpdated = false;
}
