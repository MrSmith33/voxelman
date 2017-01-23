/**
Copyright: Copyright (c) 2017 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.world.mesh.blockmeshers.slope;

import voxelman.log;
import voxelman.container.buffer;
import voxelman.math;
import voxelman.geometry.cube;

import voxelman.world.block;
import voxelman.world.mesh.chunkmesh;

import voxelman.world.mesh.config;
import voxelman.world.mesh.sidemeshers.full;
import voxelman.world.mesh.sidemeshers.slope;
import voxelman.world.mesh.sidemeshers.utils;
import voxelman.world.mesh.tables.slope;

void makeColoredSlopeBlockMesh(BlockMeshingData data)
{
	static if (RANDOM_BLOCK_TINT_ENABLED)
		auto color = calcColor(data.blockIndex, data.color);
	else
		auto color = data.color;

	if (data.sides != 0)
	{
		SideParams sideParams = SideParams(data.chunkPos, color, 0, data.buffer);
		auto sideMasks = slopeShapeFromMeta(data.metadata).sideMasks;

		foreach(ubyte i, sideMask; sideMasks)
		{
			auto cubeSide = cast(CubeSide)i;
			switch(sideMask) {
				case ShapeSideMask.empty: break;
				case ShapeSideMask.full:
					if (data.sides & (1 << cubeSide)) {
						ubyte[4] occlusions = data.occlusionHandler(data.blockIndex, cubeSide);
						meshFullSideOccluded(cubeSide, occlusions, sideParams);
					}
					break;
				case ShapeSideMask.slope0: goto case;
				case ShapeSideMask.slope1: goto case;
				case ShapeSideMask.slope2: goto case;
				case ShapeSideMask.slope3:
					if (data.sides & (1 << cubeSide)) {
						sideParams.rotation = cast(ubyte)(sideMask - ShapeSideMask.slope0);
						ubyte[4] occlusions = data.occlusionHandler(data.blockIndex, cubeSide);
						meshSlopeSideOccluded(cubeSide, occlusions, sideParams);
					}
					break;
				default: break;
			}
		}
	}

	// mesh internal geometry
	CubeSide[2] occlusionSides = slopeOcclusionSides[data.metadata];
	ubyte[4] occlusions0 = data.occlusionHandler(data.blockIndex, occlusionSides[0]);
	ubyte[4] occlusions1 = data.occlusionHandler(data.blockIndex, occlusionSides[1]);
	ubyte[4] occIndicies = slopeInternalOcclusionIndicies[data.metadata];
	ubyte[4] occlusionInternal = [
		occlusions0[occIndicies[0]],
		occlusions1[occIndicies[2]],
		occlusions1[occIndicies[3]],
		occlusions0[occIndicies[1]]];

	immutable float mult = (shadowMultipliers[occlusionSides[0]] + shadowMultipliers[occlusionSides[1]])/2;
	float[3] colorInternal = [mult * color[0], mult * color[1], mult * color[2]];

	meshOccludedQuad(*data.buffer, occlusionInternal, colorInternal, data.chunkPos,
		slopeInternalIndicies[data.metadata], cubeVerticies.ptr);
}
