/**
Copyright: Copyright (c) 2017 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.world.mesh.blockmesher;

import voxelman.container.buffer;
import voxelman.math;
import voxelman.geometry.cube;

import voxelman.world.block;
import voxelman.world.mesh.chunkmesh;

import voxelman.world.mesh.sidemeshers.full;
import voxelman.world.mesh.sidemeshers.slope;
import voxelman.world.mesh.sidemeshers.utils;

void makeColoredFullBlockMesh(BlockMeshingData data)
{
	if (data.sides != 0)
	{
		SideParams sideParams = SideParams(data.chunkPos, calcColor(data.blockIndex, data.color), data.buffer);

		ubyte flag = 1;
		foreach(CubeSide side; CubeSide.min..cast(CubeSide)(CubeSide.max+1))
		{
			if (data.sides & flag)
			{
				ubyte[4] occlusions = data.occlusionHandler(data.blockIndex, side);
				meshFullSideOccluded(side, occlusions, sideParams);
			}
			flag <<= 1;
		}
	}
}

void makeColoredSlopeBlockMesh(BlockMeshingData data)
{
	auto color = calcColor(data.blockIndex, data.color);
	if (data.sides != 0)
	{
		SideParams sideParams = SideParams(data.chunkPos, color, data.buffer);

		if (data.sides & SideMask.zneg) {
			ubyte[4] occlusions = data.occlusionHandler(data.blockIndex, CubeSide.zneg);
			meshFullSideOccluded(CubeSide.zneg, occlusions, sideParams);
		}
		if (data.sides & SideMask.yneg) {
			ubyte[4] occlusions = data.occlusionHandler(data.blockIndex, CubeSide.yneg);
			meshFullSideOccluded(CubeSide.yneg, occlusions, sideParams);
		}

		if (data.sides & SideMask.xneg) {
			ubyte[4] occlusions = data.occlusionHandler(data.blockIndex, CubeSide.xneg);
			meshSlopeSideOccluded(CubeSide.xneg, occlusions, sideParams);
		}
		if (data.sides & SideMask.xpos) {
			ubyte[4] occlusions = data.occlusionHandler(data.blockIndex, CubeSide.xpos);
			meshSlopeSideOccluded(CubeSide.xpos, occlusions, sideParams);
		}
	}

	// mesh internal geometry
	ubyte[4] occlusionsTop = data.occlusionHandler(data.blockIndex, CubeSide.ypos);
	ubyte[4] occlusionsFront = data.occlusionHandler(data.blockIndex, CubeSide.zpos);
	ubyte[4] occlusionInternal = [
		occlusionsTop[0], occlusionsFront[1],
		occlusionsFront[2], occlusionsTop[3]];

	immutable float mult = (shadowMultipliers[CubeSide.ypos] + shadowMultipliers[CubeSide.zpos])/2;
	float[3] colorInternal = [mult * color[0], mult * color[1], mult * color[2]];

	meshOccludedQuad(*data.buffer, occlusionInternal, colorInternal, data.chunkPos,
		slopeIntIndexes, cubeVerticies.ptr);
}
