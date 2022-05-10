/**
Copyright: Copyright (c) 2014-2018 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/

module voxelman.graphics.fpscamera;

import voxelman.log;
import voxelman.math;

struct FpsCamera
{
	void move(Vector3f vec)
	{
		if (isUpdated == false) update();
		position += vec;
		isUpdated = false;
	}

	void moveAxis(vec3 vec)
	{
		if (isUpdated == false) update();

		// Strafe
		vec3 right = rotationQuatHor.rotate(vec3(1,0,0));
		position += right * vec.x;

		// Move up/down
		position.y += vec.y;

		// Move forward
		vec3 target = rotationQuatHor.rotate(vec3(0,0,-1));
		position += target * vec.z;

		isUpdated = false;
	}

	void rotate(vec2 angles)
	{
		heading += angles * sensivity;
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
		rotationQuatHor = rotationQuaternion!float(vec3(0,1,0), degtorad!float(heading.x));
		rotationQuatVert = rotationQuaternion!float(vec3(1,0,0), degtorad!float(heading.y));

		rotationQuat = rotationQuatHor * rotationQuatVert;
		rotationQuat.normalize();
		calcVectors();

		Matrix4f rotation = rotationQuat.toMatrix4x4.inverse;
		Matrix4f translation = translationMatrix(-position);

		cameraToClipMatrix = rotation * translation;
		isUpdated = true;
	}

	ref Matrix4f cameraMatrix() return
	{
		if(!isUpdated) update();
		return cameraToClipMatrix;
	}

	void printVectors()
	{
		infof("camera pos\t%s\ttarget\t%s\tup\t%s\tright\t%s",
			position, target, up, right);
	}

	private void calcVectors()
	{
		target = rotationQuat.rotate(vec3(0,0,-1));
		up = rotationQuat.rotate(vec3(0,1,0));
		right = rotationQuat.rotate(vec3(1,0,0));
	}

	Matrix4f perspective()
	{
		return perspectiveMatrix(fov, aspect, near, far);
	}

	float sensivity = 1.0f;
	float fov = 60; // field of view
	float aspect = 1; // window width/height
	float near = 0.01;
	float far = 4000;

	vec3 position = vec3(0, 0, 0);
	vec2 heading = vec2(0, 0); // hor, vert

	vec3 target = vec3(0, 0, -1);
	vec3 up	= vec3(0, 1, 0);
	vec3 right	= vec3(1, 0, 0);

	enum ANGLE_VERT_MIN = -90.0f;	//minimum pitch
	enum ANGLE_VERT_MAX =  90.0f;	//maximal pitch

	Matrix4f cameraToClipMatrix;

	Quaternionf rotationQuat;
	Quaternionf rotationQuatHor;
	Quaternionf rotationQuatVert;

	bool isUpdated = false;
}
