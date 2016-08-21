/**
Copyright: Copyright (c) 2016 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.world.gen.generator;

import voxelman.math : svec3;
import voxelman.core.config;
import voxelman.world.gen.utils;

interface IGenerator
{
	ChunkGeneratorResult generateChunk(svec3 chunkOffset,
		ref BlockId[CHUNK_SIZE_CUBE] blocks) const;
}
