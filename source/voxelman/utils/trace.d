/**
Copyright: Copyright (c) 2014-2015 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/

module voxelman.utils.trace;

import std.math : floor;
import dlib.math.vector;

/// Returns true if block was hit
bool traceRay(
	bool delegate(ivec3) isBlockSolid,
	vec3 startingPosition, // starting position
	vec3 rayDirection, // direction
	float maxDistance,
	out vec3 hitPosition, // resulting position hit
	out ivec3 hitNormal, // normal of hit surface
	const float EPSILON = 1e-6)
{
	rayDirection.normalize;

	// Current position along the ray. Incremented by step each loop iteration.
	float curProgress = 0.0;
	int nx, ny, nz;
	float ex, ey, ez, step, minStep;

	vec3 curPos;
	ivec3 curPosInt;
	// delta between int and precise position.
	vec3 posFloatDelta;

	//Step block-by-block along ray
	while(curProgress <= maxDistance)
	{
		curPos = startingPosition + curProgress * rayDirection;

		curPosInt = curPos;

		posFloatDelta = curPos - vec3(curPosInt);

		if(isBlockSolid(curPosInt))
		{
			//Clamp to face on hit
			hitPosition.x = posFloatDelta.x < EPSILON ? curPosInt.x : (posFloatDelta.x > 1.0-EPSILON ? curPosInt.x+1.0-EPSILON : curPos.x);
			hitPosition.y = posFloatDelta.y < EPSILON ? curPosInt.y : (posFloatDelta.y > 1.0-EPSILON ? curPosInt.y+1.0-EPSILON : curPos.y);
			hitPosition.z = posFloatDelta.z < EPSILON ? curPosInt.z : (posFloatDelta.z > 1.0-EPSILON ? curPosInt.z+1.0-EPSILON : curPos.z);

			return true;
		}

		//Check edge cases
		minStep = (EPSILON * (1.0 + curProgress));

		if(curProgress > minStep)
		{
			ex = nx < 0 ? posFloatDelta.x <= minStep : posFloatDelta.x >= 1.0 - minStep;
			ey = ny < 0 ? posFloatDelta.y <= minStep : posFloatDelta.y >= 1.0 - minStep;
			ez = nz < 0 ? posFloatDelta.z <= minStep : posFloatDelta.z >= 1.0 - minStep;

			if(ex && ey && ez)
			{
				bool anySolid = isBlockSolid(ivec3(curPosInt.x+nx, curPosInt.y+ny, curPosInt.z)) ||
								isBlockSolid(ivec3(curPosInt.x, curPosInt.y+ny, curPosInt.z+nz)) ||
								isBlockSolid(ivec3(curPosInt.x+nx, curPosInt.y, curPosInt.z+nz));

				if(anySolid)
				{
					hitPosition.x = nx < 0 ? curPosInt.x-EPSILON : curPosInt.x + 1.0-EPSILON;
					hitPosition.y = ny < 0 ? curPosInt.y-EPSILON : curPosInt.y + 1.0-EPSILON;
					hitPosition.z = nz < 0 ? curPosInt.z-EPSILON : curPosInt.z + 1.0-EPSILON;

					return true;
				}
			}

			if(ex && (ey || ez))
			{
				if(isBlockSolid(ivec3(curPosInt.x+nx, curPosInt.y, curPosInt.z)))
				{
					hitPosition.x = nx < 0 ? curPosInt.x-EPSILON : curPosInt.x + 1.0-EPSILON;
					hitPosition.y = posFloatDelta.y < EPSILON ? +curPosInt.y : curPos.y;
					hitPosition.z = posFloatDelta.z < EPSILON ? +curPosInt.z : curPos.z;

					return true;
				}
			}

			if(ey && (ex || ez))
			{
				if(isBlockSolid(ivec3(curPosInt.x, curPosInt.y+ny, curPosInt.z)))
				{
					hitPosition.x = posFloatDelta.x < EPSILON ? +curPosInt.x : curPos.x;
					hitPosition.y = ny < 0 ? curPosInt.y-EPSILON : curPosInt.y + 1.0-EPSILON;
					hitPosition.z = posFloatDelta.z < EPSILON ? +curPosInt.z : curPos.z;

					return true;
				}
			}

			if(ez && (ex || ey))
			{
				if(isBlockSolid(ivec3(curPosInt.x, curPosInt.y, curPosInt.z+nz)))
				{
					hitPosition.x = posFloatDelta.x < EPSILON ? curPosInt.x : curPos.x;
					hitPosition.y = posFloatDelta.y < EPSILON ? curPosInt.y : curPos.y;
					hitPosition.z = nz < 0 ? curPosInt.z-EPSILON : curPosInt.z + 1.0-EPSILON;

					return true;
				}
			}
		}

		//Walk to next face of cube along ray
		nx = ny = nz = 0;
		step = 2.0;

		if(rayDirection.x < -EPSILON)
		{
			float s = -posFloatDelta.x/rayDirection.x;
			nx = 1;
			step = s;
		}

		if(rayDirection.x > EPSILON)
		{
			float s = (1.0-posFloatDelta.x)/rayDirection.x;
			nx = -1;
			step = s;
		}

		if(rayDirection.y < -EPSILON)
		{
			float s = -posFloatDelta.y/rayDirection.y;

			if(s < step-minStep)
			{
				nx = 0;
				ny = 1;
				step = s;
			}
			else if(s < step+minStep)
			{
				ny = 1;
			}
		}

		if(rayDirection.y > EPSILON)
		{
			float s = (1.0-posFloatDelta.y)/rayDirection.y;

			if(s < step-minStep)
			{
				nx = 0;
				ny = -1;
				step = s;
			}
			else if(s < step+minStep)
			{
				ny = -1;
			}
		}

		if(rayDirection.z < -EPSILON)
		{
			float s = -posFloatDelta.z/rayDirection.z;

			if(s < step-minStep)
			{
				nx = ny = 0;
				nz = 1;
				step = s;
			}
			else if(s < step+minStep)
			{
				nz = 1;
			}
		}

		if(rayDirection.z > EPSILON)
		{
			float s = (1.0-posFloatDelta.z)/rayDirection.z;

			if(s < step-minStep)
			{
				nx = ny = 0;
				nz = -1;
				step = s;
			}
			else if(s < step+minStep)
			{
				nz = -1;
			}
		}

		if(step > maxDistance - curProgress)
		{
			step = maxDistance - curProgress - minStep;
		}

		if(step < minStep)
		{
			step = minStep;
		}

		hitNormal.x = nx;
		hitNormal.y = ny;
		hitNormal.z = nz;

		curProgress += step;
	}

	hitPosition = curPos;

	hitNormal = ivec3(0);

	return false;
}
