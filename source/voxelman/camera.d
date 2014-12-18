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

	void updateFrustum(Matrix4f mvp)
	{
		frustum = extractPlanes(mvp);
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

	Plane[6] extractPlanes(const ref Matrix4f m)
	{
		Plane[6] p_planes;
		// Left clipping plane
		p_planes[0] = Plane(m.a41 + m.a11, m.a42 + m.a12, m.a43 + m.a13, m.a44 + m.a14);
		p_planes[0].normalize();
		// Right clipping plane
		p_planes[1] = Plane(m.a41 - m.a11, m.a42 - m.a12, m.a43 - m.a13, m.a44 - m.a14);
		p_planes[1].normalize();
		// Top clipping plane
		p_planes[2] = Plane(m.a41 - m.a21, m.a42 - m.a22, m.a43 - m.a23, m.a44 - m.a24);
		p_planes[2].normalize();
		// Bottom clipping plane
		p_planes[3] = Plane(m.a41 + m.a21, m.a42 + m.a22, m.a43 + m.a23, m.a44 + m.a24);
		p_planes[3].normalize();
		// Near clipping plane
		p_planes[4] = Plane(m.a41 + m.a31, m.a42 + m.a32, m.a43 + m.a33, m.a44 + m.a34);
		p_planes[4].normalize();
		// Far clipping plane
		p_planes[5] = Plane(m.a41 - m.a31, m.a42 - m.a32, m.a43 - m.a33, m.a44 - m.a34);
		p_planes[5].normalize();

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