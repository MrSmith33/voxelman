/**
Copyright: Copyright (c) 2015-2017 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/

module voxelman.utils.trace;

import std.math : floor, abs;
import voxelman.math;
import voxelman.graphics : Batch;
import voxelman.world.block : sideFromNormal;

enum bool drawDebug = false;

// Implementation of algorithm found at
// http://playtechs.blogspot.co.uk/2007/03/raytracing-on-grid.html

/// Returns true if block was hit
bool traceRay(
	bool delegate(ivec3) isBlockSolid,
	vec3 startingPosition, // starting position
	vec3 rayDirection, // direction
	double maxDistance,
	out ivec3 hitPosition, // resulting position hit
	out ivec3 hitNormal, // normal of hit surface
	ref Batch batch)
{
	assert(rayDirection != vec3(0,0,0), "Raycast in zero direction!");

	rayDirection *= maxDistance;

	double x0 = startingPosition.x;
	double y0 = startingPosition.y;
	double z0 = startingPosition.z;
	double x1 = startingPosition.x + rayDirection.x;
	double y1 = startingPosition.y + rayDirection.y;
	double z1 = startingPosition.z + rayDirection.z;

	int x = cast(int)floor(x0);
	int y = cast(int)floor(y0);
	int z = cast(int)floor(z0);

	double dt_dx = abs(1.0 / rayDirection.x);
	double dt_dy = abs(1.0 / rayDirection.y);
	double dt_dz = abs(1.0 / rayDirection.z);

	int n = 1;

	int inc_x;
	int inc_y;
	int inc_z;

	double t_next_x;
	double t_next_y;
	double t_next_z;

	if (rayDirection.x > 0)
	{
		inc_x = 1;
		n += cast(int)floor(x1) - x;
		t_next_x = (floor(x0) + 1 - x0) * dt_dx;
	}
	else if (rayDirection.x < 0)
	{
		inc_x = -1;
		n += x - cast(int)floor(x1);
		t_next_x = (x0 - floor(x0)) * dt_dx;
	}
	else
	{
		inc_x = 0;
		t_next_x = dt_dx; // infinity
	}

	if (rayDirection.z > 0)
	{
		inc_z = 1;
		n += cast(int)floor(z1) - z;
		t_next_z = (floor(z0) + 1 - z0) * dt_dz;
	}
	else if (rayDirection.z < 0)
	{
		inc_z = -1;
		n += z - cast(int)floor(z1);
		t_next_z = (z0 - floor(z0)) * dt_dz;
	}
	else
	{
		inc_z = 0;
		t_next_z = dt_dz; // infinity
	}

	if (rayDirection.y > 0)
	{
		inc_y = 1;
		n += cast(int)floor(y1) - y;
		t_next_y = (floor(y0) + 1 - y0) * dt_dy;
	}
	else if (rayDirection.y < 0)
	{
		inc_y = -1;
		n += y - cast(int)floor(y1);
		t_next_y = (y0 - floor(y0)) * dt_dy;
	}
	else
	{
		inc_y = 0;
		t_next_y = dt_dy; // infinity
	}

	double t = 0;
	static if (drawDebug)
		vec3 prevPos = startingPosition;

	for (; n > 0; --n)
	{
		if (isBlockSolid(ivec3(x, y, z)))
		{
			hitPosition = ivec3(x, y, z);
			return true;
		}

		if (t_next_x < t_next_y)
		{
			if (t_next_x < t_next_z)
			{
				x += inc_x;
				t = t_next_x;
				t_next_x += dt_dx;
				hitNormal = ivec3(-inc_x, 0, 0);
			}
			else
			{
				z += inc_z;
				t = t_next_z;
				t_next_z += dt_dz;
				hitNormal = ivec3(0, 0, -inc_z);
			}
		}
		else
		{
			if (t_next_y < t_next_z)
			{
				y += inc_y;
				t = t_next_y;
				t_next_y += dt_dy;
				hitNormal = ivec3(0, -inc_y, 0);
			}
			else
			{
				z += inc_z;
				t = t_next_z;
				t_next_z += dt_dz;
				hitNormal = ivec3(0, 0, -inc_z);
			}
		}

		static if (drawDebug)
		{
			batch.putLine(prevPos, startingPosition + rayDirection*t,
				colorsArray[sideFromNormal(hitNormal)+2]);
			prevPos = startingPosition + rayDirection*t;

			batch.putCubeFace(
				vec3(x, y, z),
				vec3(1, 1, 1),
				sideFromNormal(hitNormal),
				Colors.black,
				false);
		}
	}

	return false;
}
