/**
Copyright: Copyright (c) 2014-2015 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/

module voxelman.utils.trace;

import std.math : floor;
import dlib.math.vector;

import voxelman.blockman;
import voxelman.config;
import voxelman.storage.worldaccess;

/// Returns true if block was hit
bool traceRay(
	WorldAccess* worldAccess, // world access interface
	BlockMan* blockMan,
	vec3 startingPosition, // starting position
	vec3 rayDirection, // direction
	float maxDistance,
	out ivec3 blockPos, // world space position of block hit
	out BlockType blockType,
	out vec3 hitPosition, // resulting position hit
	out vec3 hitNormal, // normal of hit surface
	const float EPSILON = 1e-8)
{
	rayDirection.normalize;

	// Current position along the ray. Incremented by step each loop iteration.
	float curProgress = 0.0;
	int nx, ny, nz;
	float ex, ey, ez, step, minStep;

	BlockType block;

	vec3 curPos;
	ivec3 curPosInt;
	// delta between int and precise coordinate.
	vec3 posFloatDelta;

	//Step block-by-block along ray
	while(curProgress <= maxDistance)
	{
		curPos = startingPosition + curProgress * rayDirection;

		curPosInt = curPos;

		posFloatDelta = curPos - vec3(curPosInt);

		block = worldAccess.getBlock(curPosInt);

		if(blockMan.blocks[block].isVisible)
		{
			//Clamp to face on hit
			hitPosition.x = posFloatDelta.x < EPSILON ? +curPosInt.x : (posFloatDelta.x > 1.0-EPSILON ? curPosInt.x+1.0-EPSILON : curPos.x);
			hitPosition.y = posFloatDelta.y < EPSILON ? +curPosInt.y : (posFloatDelta.y > 1.0-EPSILON ? curPosInt.y+1.0-EPSILON : curPos.y);
			hitPosition.z = posFloatDelta.z < EPSILON ? +curPosInt.z : (posFloatDelta.z > 1.0-EPSILON ? curPosInt.z+1.0-EPSILON : curPos.z);

			hitNormal.x = nx;
			hitNormal.y = ny;
			hitNormal.z = nz;

			return true;
		}

		//Check edge cases
		minStep = +(EPSILON * (1.0 + curProgress));

		if(curProgress > minStep)
		{
			ex = nx < 0 ? posFloatDelta.x <= minStep : posFloatDelta.x >= 1.0 - minStep;
			ey = ny < 0 ? posFloatDelta.y <= minStep : posFloatDelta.y >= 1.0 - minStep;
			ez = nz < 0 ? posFloatDelta.z <= minStep : posFloatDelta.z >= 1.0 - minStep;

			if(ex && ey && ez)
			{
				block = worldAccess.getBlock(ivec3(curPosInt.x+nx, curPosInt.y+ny, curPosInt.z)) ||
					worldAccess.getBlock(ivec3(curPosInt.x, curPosInt.y+ny, curPosInt.z+nz)) ||
					worldAccess.getBlock(ivec3(curPosInt.x+nx, curPosInt.y, curPosInt.z+nz));

				if(blockMan.blocks[block].isVisible)
				{
					hitPosition.x = nx < 0 ? curPosInt.x-EPSILON : curPosInt.x + 1.0-EPSILON;
					hitPosition.y = ny < 0 ? curPosInt.y-EPSILON : curPosInt.y + 1.0-EPSILON;
					hitPosition.z = nz < 0 ? curPosInt.z-EPSILON : curPosInt.z + 1.0-EPSILON;

					hitNormal.x = nx;
					hitNormal.y = ny;
					hitNormal.z = nz;

					return true;
				}
			}

			if(ex && (ey || ez))
			{
				block = worldAccess.getBlock(ivec3(curPosInt.x+nx, curPosInt.y, curPosInt.z));

				if(blockMan.blocks[block].isVisible)
				{
					hitPosition.x = nx < 0 ? curPosInt.x-EPSILON : curPosInt.x + 1.0-EPSILON;
					hitPosition.y = posFloatDelta.y < EPSILON ? +curPosInt.y : curPos.y;
					hitPosition.z = posFloatDelta.z < EPSILON ? +curPosInt.z : curPos.z;

					hitNormal.x = nx;
					hitNormal.y = ny;
					hitNormal.z = nz;

					return true;
				}
			}

			if(ey && (ex || ez))
			{
				block = worldAccess.getBlock(ivec3(curPosInt.x, curPosInt.y+ny, curPosInt.z));

				if(blockMan.blocks[block].isVisible)
				{
					hitPosition.x = posFloatDelta.x < EPSILON ? +curPosInt.x : curPos.x;
					hitPosition.y = ny < 0 ? curPosInt.y-EPSILON : curPosInt.y + 1.0-EPSILON;
					hitPosition.z = posFloatDelta.z < EPSILON ? +curPosInt.z : curPos.z;

					hitNormal.x = nx;
					hitNormal.y = ny;
					hitNormal.z = nz;

					return true;
				}
			}

			if(ez && (ex || ey))
			{
				block = worldAccess.getBlock(ivec3(curPosInt.x, curPosInt.y, curPosInt.z+nz));

				if(blockMan.blocks[block].isVisible)
				{
					hitPosition.x = posFloatDelta.x < EPSILON ? curPosInt.x : curPos.x;
					hitPosition.y = posFloatDelta.y < EPSILON ? curPosInt.y : curPos.y;
					hitPosition.z = nz < 0 ? curPosInt.z-EPSILON : curPosInt.z + 1.0-EPSILON;

					hitNormal.x = nx;
					hitNormal.y = ny;
					hitNormal.z = nz;

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

		curProgress += step;
	}

	hitPosition = curPos;

	hitNormal = ivec3(0);

	return false;
}
