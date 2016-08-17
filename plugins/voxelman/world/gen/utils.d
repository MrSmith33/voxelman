/**
Copyright: Copyright (c) 2013-2016 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.world.gen.utils;

import std.experimental.logger;
import voxelman.math : ivec3, SimplexNoise;

import voxelman.block.utils;
import voxelman.core.config;
import voxelman.utils.worker;
import voxelman.world.storage.chunk;
import voxelman.world.storage.coordinates;

enum AIR = 1;
enum GRASS = 2;
enum DIRT = 3;
enum STONE = 4;
enum SAND = 5;
enum WATER = 6;

alias GenDelegate = void function(ChunkWorldPos cwp, shared(Worker)* workerInfo,
	BlockInfoTable blockInfos, ubyte[] compressBuffer);


//version = DBG_COMPR;
void genChunk(Generator)(ChunkWorldPos cwp, shared(Worker)* workerInfo,
	BlockInfoTable blockInfos, ubyte[] compressBuffer)
{
	Generator generator = Generator(cwp.ivector3 * CHUNK_SIZE);
	generator.genPerChunkData();

	bool uniform = true;
	bool[3] presentSolidities;

	BlockId uniformBlockId = AIR;
	BlockId[CHUNK_SIZE_CUBE] blocks;

	bool skipGen = false;
	static if (__traits(compiles, generator.heightMap))
	{
		if (generator.chunkOffset.y > generator.heightMap.maxHeight &&
			generator.chunkOffset.y > 0)
		{
			// optimization
			presentSolidities[Solidity.transparent] = true;
			skipGen = true;
		}
	}

	if (!skipGen)
	{
		blocks[0] = generator.generateBlock(0, 0, 0);
		uniformBlockId = blocks[0];
		Solidity solidity0 = blockInfos[blocks[0]].solidity;
		presentSolidities[solidity0] = true;

		int bx, by, bz;
		foreach(i; 1..CHUNK_SIZE_CUBE)
		{
			bx = i & CHUNK_SIZE_BITS;
			by = (i / CHUNK_SIZE_SQR) & CHUNK_SIZE_BITS;
			bz = (i / CHUNK_SIZE) & CHUNK_SIZE_BITS;

			// Actual block gen
			blocks[i] = generator.generateBlock(bx, by, bz);
			Solidity solidity = blockInfos[blocks[i]].solidity;
			presentSolidities[solidity] = true;

			if(uniform && blocks[i] != uniformBlockId)
			{
				uniform = false;
			}
		}
	}

	enum layerId = 0;
	enum timestamp = 0;
	enum numLayers = 1;

	// bit is set if there are blocks with corresponding solidity is in the chunk
	ubyte solidityBits;
	ubyte solidityFlag = 1;
	foreach(sol; presentSolidities)
	{
		if (sol) solidityBits |= solidityFlag;
		solidityFlag <<= 1;
	}

	workerInfo.resultQueue.startMessage();
	auto header = ChunkHeaderItem(cwp, numLayers);
	workerInfo.resultQueue.pushMessagePart(header);
	if(uniform)
	{
		ushort metadata = calcChunkSideMetadata(uniformBlockId, blockInfos);
		metadata |= cast(ushort)(solidityBits<<CHUNK_SIDE_METADATA_BITS);

		auto layer = ChunkLayerItem(StorageType.uniform, layerId, BLOCKID_UNIFORM_FILL_BITS, timestamp, uniformBlockId, metadata);
		workerInfo.resultQueue.pushMessagePart(layer);
	}
	else
	{
		//infof("%s L %s B (%(%02x%))", cwp, blocks.length, cast(ubyte[])blocks);
		ushort metadata = calcChunkSideMetadata(blocks[], blockInfos);
		metadata |= cast(ushort)(solidityBits<<CHUNK_SIDE_METADATA_BITS);

		ubyte[] compactBlocks = compressLayerData(cast(ubyte[])blocks, compressBuffer);
		//infof("%s L %s C (%(%02x%))", cwp, compactBlocks.length, cast(ubyte[])compactBlocks);

		StorageType storageType;
		LayerDataLenType dataLength;
		ubyte* data;

		if (compactBlocks.length <= LayerDataLenType.max)
		{
			version(DBG_COMPR)infof("Gen1 %s %s %s\n(%(%02x%))", cwp, compactBlocks.ptr, compactBlocks.length, cast(ubyte[])compactBlocks);
			compactBlocks = compactBlocks.dup;
			version(DBG_COMPR)infof("Gen2 %s %s %s\n(%(%02x%))", cwp, compactBlocks.ptr, compactBlocks.length, cast(ubyte[])compactBlocks);
			dataLength = cast(LayerDataLenType)compactBlocks.length;
			data = cast(ubyte*)compactBlocks.ptr;
			storageType = StorageType.compressedArray;
		}
		else
		{
			infof("Gen non-compressed %s", cwp);
			dataLength = cast(LayerDataLenType)blocks.length;
			assert(dataLength == CHUNK_SIZE_CUBE);
			data = cast(ubyte*)blocks.dup.ptr;
			storageType = StorageType.fullArray;
		}

		// Add root to data.
		// Data can be collected by GC if no-one is referencing it.
		// It is needed to pass array trough shared queue.
		// Root is removed inside ChunkProvider
		import core.memory : GC;
		GC.addRoot(data); // TODO remove when moved to non-GC allocator
		auto layer = ChunkLayerItem(storageType, layerId, dataLength, timestamp, data, metadata);
		workerInfo.resultQueue.pushMessagePart(layer);
	}
	workerInfo.resultQueue.endMessage();
}

double noise2d(int x, int z)
{
	enum NUM_OCTAVES = 8;
	enum DIVIDER = 50; // bigger - smoother
	enum HEIGHT_MODIFIER = 4; // bigger - higher

	double noise = 0.0;
	foreach(i; 1..NUM_OCTAVES+1)
	{
		// [-1; 1]
		noise += SimplexNoise.noise(cast(double)x/(DIVIDER*i), cast(double)z/(DIVIDER*i))*i*HEIGHT_MODIFIER;
	}

	return noise;
}

struct HeightmapChunkData
{
	int[CHUNK_SIZE_SQR] heightMap = void;
	int minHeight = int.max;
	int maxHeight = int.min;

	void generate(ivec3 chunkOffset)
	{
		foreach(i, ref elem; heightMap)
		{
			int cx = i & CHUNK_SIZE_BITS;
			int cz = (i / CHUNK_SIZE) & CHUNK_SIZE_BITS;
			elem = cast(int)noise2d(chunkOffset.x + cx, chunkOffset.z + cz);
			if (elem > maxHeight)
				maxHeight = elem;
			if (elem < minHeight)
				minHeight = elem;
		}
	}
}
