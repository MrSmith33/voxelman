/**
Copyright: Copyright (c) 2014 Andrey Penechko.
License: a$(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/

module voxelman.camera;

import dlib.math.vector;
import dlib.math.matrix;
import dlib.math.affine;
import dlib.geometry.plane;

enum IntersectionResult
{
	inside,
	outside,
	intersect
}

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
		frustum = extractPlanes(perspective);
		return perspective;
	}

	IntersectionResult frustumAABBIntersect(vec3 minPos, vec3 maxPos)
	{
		Plane[6] planes = frustum;
		vec3 vmin, vmax;

		foreach(i; 0..6)
		{
			// X axis
			if(planes[i].normal.x > 0) {
				vmin.x = minPos.x;
				vmax.x = maxPos.x;
			} else {
				vmin.x = maxPos.x;
				vmax.x = minPos.x;
			}
			// Y axis
			if(planes[i].normal.y > 0) {
				vmin.y = minPos.y;
				vmax.y = maxPos.y;
			} else {
				vmin.y = maxPos.y;
				vmax.y = minPos.y;
			}
			// Z axis
			if(planes[i].normal.z > 0) {
				vmin.z = minPos.z;
				vmax.z = maxPos.z;
			} else {
				vmin.z = maxPos.z;
				vmax.z = minPos.z;
			}

			if(dot(planes[i].normal, vmin) + planes[i].d > 0) 
				return IntersectionResult.outside; 
			if(dot(planes[i].normal, vmax) + planes[i].d >= 0) 
				return IntersectionResult.intersect; 
		}

		return IntersectionResult.inside;
	}

	Plane[6] extractPlanes(const ref Matrix4f comboMatrix)
	{
		Plane[6] p_planes;
		// Left clipping plane
		p_planes[0].a = comboMatrix.a41 + comboMatrix.a11;
		p_planes[0].b = comboMatrix.a42 + comboMatrix.a12;
		p_planes[0].c = comboMatrix.a43 + comboMatrix.a13;
		p_planes[0].d = comboMatrix.a44 + comboMatrix.a14;
		// Right clipping plane
		p_planes[1].a = comboMatrix.a41 - comboMatrix.a11;
		p_planes[1].b = comboMatrix.a42 - comboMatrix.a12;
		p_planes[1].c = comboMatrix.a43 - comboMatrix.a13;
		p_planes[1].d = comboMatrix.a44 - comboMatrix.a14;
		// Top clipping plane
		p_planes[2].a = comboMatrix.a41 - comboMatrix.a21;
		p_planes[2].b = comboMatrix.a42 - comboMatrix.a22;
		p_planes[2].c = comboMatrix.a43 - comboMatrix.a23;
		p_planes[2].d = comboMatrix.a44 - comboMatrix.a24;
		// Bottom clipping plane
		p_planes[3].a = comboMatrix.a41 + comboMatrix.a21;
		p_planes[3].b = comboMatrix.a42 + comboMatrix.a22;
		p_planes[3].c = comboMatrix.a43 + comboMatrix.a23;
		p_planes[3].d = comboMatrix.a44 + comboMatrix.a24;
		// Near clipping plane
		p_planes[4].a = comboMatrix.a41 + comboMatrix.a31;
		p_planes[4].b = comboMatrix.a42 + comboMatrix.a32;
		p_planes[4].c = comboMatrix.a43 + comboMatrix.a33;
		p_planes[4].d = comboMatrix.a44 + comboMatrix.a34;
		// Far clipping plane
		p_planes[5].a = comboMatrix.a41 - comboMatrix.a31;
		p_planes[5].b = comboMatrix.a42 - comboMatrix.a32;
		p_planes[5].c = comboMatrix.a43 - comboMatrix.a33;
		p_planes[5].d = comboMatrix.a44 - comboMatrix.a34;

		return p_planes;
	}

	float sensivity = 1.0f;
	Matrix4f perspective;
	vec3 position = vec3(0, 0, 0);
	vec3 target = vec3(0, 0, 1);
	vec3 up	= vec3(0, 1, 0);

	Plane[6] frustum;

	float fov = 60;
	float aspect = 1;
	float near = 0.01;
	float far = 2000;
}