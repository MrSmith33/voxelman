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
	ubyte[4] occlusionsTop = data.occlusionHandler(data.blockIndex, occlusionSides[0]);
	ubyte[4] occlusionsFront = data.occlusionHandler(data.blockIndex, occlusionSides[1]);
	ubyte[2] topOcIndicies = slopeIntTopOcclusionIndicies[data.metadata];
	ubyte[4] occlusionInternal = [
		occlusionsTop[topOcIndicies[0]], occlusionsFront[1],
		occlusionsFront[2], occlusionsTop[topOcIndicies[1]]];

	immutable float mult = (shadowMultipliers[occlusionSides[0]] + shadowMultipliers[occlusionSides[1]])/2;
	float[3] colorInternal = [mult * color[0], mult * color[1], mult * color[2]];

	meshOccludedQuad(*data.buffer, occlusionInternal, colorInternal, data.chunkPos,
		slopeIntIndicies[data.metadata], cubeVerticies.ptr);
}

immutable ubyte[2][12] slopeIntTopOcclusionIndicies = [
	[0,3],[3,2],[2,1],[1,0],
	[0,3],[3,2],[2,1],[1,0], //TODO
	[0,3],[3,2],[2,1],[1,0], //TODO
];

// internal geometry
immutable ubyte[4][12] slopeIntIndicies = [
	[4,2,3,5],
	[5,0,2,7],
	[7,1,0,6],
	[6,3,1,4],

	[4,2,3,5], //TODO
	[4,2,3,5], //TODO
	[4,2,3,5], //TODO
	[4,2,3,5], //TODO

	[4,2,3,5], //TODO
	[4,2,3,5], //TODO
	[4,2,3,5], //TODO
	[4,2,3,5], //TODO
];

immutable CubeSide[2][12] slopeOcclusionSides = [
	[CubeSide.ypos, CubeSide.zpos],
	[CubeSide.ypos, CubeSide.xneg],
	[CubeSide.ypos, CubeSide.zneg],
	[CubeSide.ypos, CubeSide.xpos],

	[CubeSide.ypos, CubeSide.zpos], //TODO
	[CubeSide.ypos, CubeSide.xneg], //TODO
	[CubeSide.ypos, CubeSide.zneg], //TODO
	[CubeSide.ypos, CubeSide.xpos], //TODO

	[CubeSide.ypos, CubeSide.zpos], //TODO
	[CubeSide.ypos, CubeSide.xneg], //TODO
	[CubeSide.ypos, CubeSide.zneg], //TODO
	[CubeSide.ypos, CubeSide.xpos], //TODO
];
