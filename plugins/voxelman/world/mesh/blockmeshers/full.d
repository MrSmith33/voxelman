/**
Copyright: Copyright (c) 2017 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.world.mesh.blockmeshers.full;

import voxelman.container.buffer;
import voxelman.math;
import voxelman.geometry;

import voxelman.world.block;
import voxelman.world.mesh.chunkmesh;

import voxelman.world.mesh.config;
import voxelman.world.mesh.sidemeshers.full;
import voxelman.world.mesh.sidemeshers.slope;
import voxelman.world.mesh.sidemeshers.utils;

void makeColoredFullBlockMesh(BlockMeshingData data)
{
	if (data.sides != 0)
	{
		static if (RANDOM_BLOCK_TINT_ENABLED)
			auto color = calcColor(data.blockIndex, data.color);
		else
			auto color = data.color;

		SideParams sideParams = SideParams(data.chunkPos, color, data.uv, 0, data.buffer);

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
