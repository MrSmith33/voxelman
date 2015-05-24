/**
Copyright: Copyright (c) 2014-2015 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/

module voxelman.utils.trace2;

import std.math : floor, sqrt;
import dlib.math.vector;
import voxelman.utils.debugdraw;
import voxelman.block : sideFromNormal;


/**
 * Call the callback with (x,y,z,value,face) of all blocks along the line
 * segment from point 'origin' in vector direction 'direction' of length
 * 'radius'. 'radius' may be infinite.
 *
 * 'face' is the normal vector of the face of that block that was entered.
 * It should not be used after the callback returns.
 *
 * If the callback returns a true value, the traversal will be stopped.
 */

bool traceRay2(bool drawDebug)(
	bool delegate(ivec3) isBlockSolid,
	vec3 startingPosition, // starting position
	vec3 rayDirection, // direction
	double maxDistance,
	out vec3 hitPosition, // resulting position hit
	out ivec3 hitNormal, // normal of hit surface
	ref Batch batch)
{
	// Avoids an infinite loop.
	assert(rayDirection != vec3(0,0,0), "Raycast in zero direction!");

	// From "A Fast Voxel Traversal Algorithm for Ray Tracing"
	// by John Amanatides and Andrew Woo, 1987
	// <http://www.cse.yorku.ca/~amana/research/grid.pdf>
	// <http://citeseer.ist.psu.edu/viewdoc/summary?doi=10.1.1.42.3443>
	// Extensions to the described algorithm:
	//   • Imposed a distance limit.
	//   • The face passed through to reach the current cube is provided to
	//     the callback.

	// The foundation of this algorithm is a parameterized representation of
	// the provided ray,
	//                    origin + t * direction,
	// except that t is not actually stored; rather, at any given point in the
	// traversal, we keep track of the *greater* t values which we would have
	// if we took a step sufficient to cross a cube boundary along that axis
	// (i.e. change the integer part of the coordinate) in the variables
	// tMaxX, tMaxY, and tMaxZ.

	// Cube containing origin point.
	int x = cast(int)floor(startingPosition.x);
	int y = cast(int)floor(startingPosition.y);
	int z = cast(int)floor(startingPosition.z);
	// Break out direction vector.
	double dx = rayDirection.x;
	double dy = rayDirection.y;
	double dz = rayDirection.z;
	// Direction to increment x,y,z when stepping.
	int stepX = signum(dx);
	int stepY = signum(dy);
	int stepZ = signum(dz);
	// See description above. The initial values depend on the fractional
	// part of the startingPosition.
	double tMaxX = intbound(startingPosition.x, dx);
	double tMaxY = intbound(startingPosition.y, dy);
	double tMaxZ = intbound(startingPosition.z, dz);
	// The change in t when taking a step (always positive).
	double tDeltaX = stepX/dx;
	double tDeltaY = stepY/dy;
	double tDeltaZ = stepZ/dz;

	// Rescale from units of 1 cube-edge to units of 'direction' so we can
	// compare with 't'.
	maxDistance /= sqrt(dx*dx+dy*dy+dz*dz);

	static if (drawDebug)
		vec3 prevPos = startingPosition;

	while (true)
	{
		// Invoke the callback
		if (isBlockSolid(ivec3(x, y, z)))
		{
			hitPosition = vec3(x, y, z);
			return true;
		}

		// tMaxX stores the t-value at which we cross a cube boundary along the
		// X axis, and similarly for Y and Z. Therefore, choosing the least tMax
		// chooses the closest cube boundary. Only the first case of the four
		// has been commented in detail.
		if (tMaxX < tMaxY)
		{
			if (tMaxX < tMaxZ)
			{
				if (tMaxX > maxDistance) break;
				// Update which cube we are now in.
				x += stepX;

				static if (drawDebug)
				{
					batch.putLine(prevPos, startingPosition + rayDirection*tMaxX, Colors.red);
					prevPos = startingPosition + rayDirection*tMaxX;
				}

				// Adjust tMaxX to the next X-oriented boundary crossing.
				tMaxX += tDeltaX;
				// Record the normal vector of the cube face we entered.
				hitNormal.x = -stepX;
				hitNormal.y = 0;
				hitNormal.z = 0;
			}
			else
			{
				if (tMaxZ > maxDistance) break;
				z += stepZ;

				static if (drawDebug)
				{
					batch.putLine(prevPos, startingPosition + rayDirection*tMaxZ, Colors.blue);
					prevPos = startingPosition + rayDirection*tMaxZ;
				}

				tMaxZ += tDeltaZ;
				hitNormal.x = 0;
				hitNormal.y = 0;
				hitNormal.z = -stepZ;
			}
		}
		else
		{
			if (tMaxY < tMaxZ)
			{
				if (tMaxY > maxDistance) break;
				y += stepY;

				static if (drawDebug)
				{
					batch.putLine(prevPos, startingPosition + rayDirection*tMaxY, Colors.green);
					prevPos = startingPosition + rayDirection*tMaxY;
				}

				tMaxY += tDeltaY;
				hitNormal.x = 0;
				hitNormal.y = -stepY;
				hitNormal.z = 0;
			}
			else
			{
				// Identical to the second case, repeated for simplicity in
				// the conditionals.
				if (tMaxZ > maxDistance) break;
				z += stepZ;

				static if (drawDebug)
				{
					batch.putLine(prevPos, startingPosition + rayDirection*tMaxZ, Colors.blue);
					prevPos = startingPosition + rayDirection*tMaxZ;
				}

				tMaxZ += tDeltaZ;
				hitNormal.x = 0;
				hitNormal.y = 0;
				hitNormal.z = -stepZ;
			}
		}

		static if (drawDebug)
		{
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

double intbound(double s, double ds)
{
	// Find the smallest positive t such that s+t*ds is an integer.
	if (ds < 0)
	{
		return intbound(-s, -ds);
	}
	else
	{
		s = s % 1;
		// problem is now s+t*ds = 1
		return (1-s)/ds;
	}
}

int signum(T)(T x)
{
	return x > 0 ? 1 : x < 0 ? -1 : 0;
}
