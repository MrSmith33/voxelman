/**
Copyright: Copyright (c) 2013-2016 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.core.chunkgen;

import std.experimental.logger;
import core.sync.semaphore;
import std.variant : Variant;
import core.atomic : atomicLoad;
import std.conv : to;
import core.exception : Throwable;

import dlib.math.vector : ivec3;

import anchovy.simplex;
import voxelman.block.utils;
import voxelman.core.config;
import voxelman.world.storage.chunk;
import voxelman.world.storage.chunkprovider;
import voxelman.world.storage.coordinates;
import voxelman.utils.compression;
import voxelman.utils.worker;
import core.thread;


alias Generator = Generator2d;
//alias Generator = Generator2d3d;
//alias Generator = TestGeneratorSmallCubes;
//alias Generator = TestGeneratorSmallCubes2;
//alias Generator = TestGeneratorSmallCubes3;


enum AIR = 1;
enum GRASS = 2;
enum DIRT = 3;
enum STONE = 4;
enum SAND = 5;
enum WATER = 6;

version = DBG_OUT;
//version = DBG_COMPR;
void chunkGenWorkerThread(shared(Worker)* workerInfo, immutable(BlockInfo)[] blockInfos)
{
	import std.array : uninitializedArray;

	ubyte[] compressBuffer = uninitializedArray!(ubyte[])(CHUNK_SIZE_CUBE*BlockId.sizeof);
	try
	{
		void genChunk()
		{
			ulong _cwp = workerInfo.taskQueue.popItem!ulong();
			ChunkWorldPos cwp = ChunkWorldPos(_cwp);
			int wx = cwp.x, wy = cwp.y, wz = cwp.z;

			Generator generator = Generator(cwp.ivector3 * CHUNK_SIZE);
			generator.genPerChunkData();

			bool uniform = true;
			bool[3] presentSolidities;

			BlockId uniformBlockId = AIR;
			BlockId[CHUNK_SIZE_CUBE] blocks;

			if (generator.chunkOffset.y > generator.perColumnChunkData.maxHeight &&
				generator.chunkOffset.y > 0)
			{
				// optimization
				presentSolidities[Solidity.transparent] = true;
			}
			else
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

				auto layer = ChunkLayerItem(StorageType.uniform, layerId, 0, timestamp, uniformBlockId, metadata);
				workerInfo.resultQueue.pushMessagePart(layer);
			}
			else
			{
				//infof("%s L %s B (%(%02x%))", cwp, blocks.length, cast(ubyte[])blocks);
				ushort metadata = calcChunkSideMetadata(blocks[], blockInfos);
				metadata |= cast(ushort)(solidityBits<<CHUNK_SIDE_METADATA_BITS);

				ubyte[] compactBlocks = compress(cast(ubyte[])blocks, compressBuffer);
				//infof("%s L %s C (%(%02x%))", cwp, compactBlocks.length, cast(ubyte[])compactBlocks);

				StorageType storageType;
				ushort dataLength;
				ubyte* data;

				if (compactBlocks.length <= ushort.max)
				{
					version(DBG_COMPR)infof("Gen1 %s %s %s\n(%(%02x%))", cwp, compactBlocks.ptr, compactBlocks.length, cast(ubyte[])compactBlocks);
					compactBlocks = compactBlocks.dup;
					version(DBG_COMPR)infof("Gen2 %s %s %s\n(%(%02x%))", cwp, compactBlocks.ptr, compactBlocks.length, cast(ubyte[])compactBlocks);
					dataLength = cast(ushort)compactBlocks.length;
					data = cast(ubyte*)compactBlocks.ptr;
					storageType = StorageType.compressedArray;
				}
				else
				{
					infof("Gen non-compressed %s", cwp);
					dataLength = cast(ushort)blocks.length;
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

		while (workerInfo.isRunning)
		{
			(cast(Semaphore)workerInfo.workAvaliable).wait();

			if (!workerInfo.taskQueue.empty)
			{
				genChunk();
			}
		}
	}
	catch(Throwable t)
	{
		infof("%s from gen worker", t.to!string);
		throw t;
	}
	version(DBG_OUT)infof("Gen worker stopped");
}

struct Generator2d3d
{
	ivec3 chunkOffset;

	private PerColumnChunkData perColumnChunkData;

	void genPerChunkData()
	{
		perColumnChunkData.generate(chunkOffset);
	}

	BlockId generateBlock(int x, int y, int z)
	{
		enum NOISE_SCALE_3D = 42;
		enum NOISE_TRESHOLD_3D = -0.6;
		int height = perColumnChunkData.heightMap[z * CHUNK_SIZE + x];
		int blockY = chunkOffset.y + y;
		if (blockY > height) {
			if (blockY > 0)
				return AIR;
			else
				return WATER;
		}

		float noise3d = Simplex.noise(cast(float)(chunkOffset.x+x)/NOISE_SCALE_3D,
			cast(float)(chunkOffset.y+y)/NOISE_SCALE_3D, cast(float)(chunkOffset.z+z)/NOISE_SCALE_3D);
		if (noise3d < NOISE_TRESHOLD_3D) return AIR;

		if (height + 5 < 0)
		{
			if (height - blockY < 10) return SAND;
			else return STONE;
		}
		else
		{
			if (blockY == height) return GRASS;
			else if (blockY > height - 10) return DIRT;
			else return STONE;
		}
	}
}

struct Generator2d
{
	ivec3 chunkOffset;
	PerColumnChunkData perColumnChunkData;

	void genPerChunkData()
	{
		perColumnChunkData.generate(chunkOffset);
	}

	BlockId generateBlock(int x, int y, int z)
	{
		int height = perColumnChunkData.heightMap[z * CHUNK_SIZE + x];
		int blockY = chunkOffset.y + y;
		if (blockY > height) {
			if (blockY > 0)
				return AIR;
			else
				return WATER;
		}

		if (height - 5 < 0)
		{
			if (height - blockY < 10) return SAND;
			else return STONE;
		}
		else
		{
			if (blockY == height) return GRASS;
			else if (blockY > height - 10) return DIRT;
			else return STONE;
		}
	}
}

struct TestGeneratorSmallCubes
{
	ivec3 chunkOffset;
	void genPerChunkData(){}

	BlockId generateBlock(int x, int y, int z)
	{
		if (x % 2 == 0 && y % 2 == 0 && z % 2 == 0) return GRASS;
		else return AIR;
	}
}

struct TestGeneratorSmallCubes2
{
	ivec3 chunkOffset;
	void genPerChunkData(){}

	BlockId generateBlock(int x, int y, int z)
	{
		if (x % 4 == 0 && y % 4 == 0 && z % 4 == 0) return GRASS;
		else return AIR;
	}
}

struct TestGeneratorSmallCubes3
{
	enum cubesSizes = 4;
	enum cubeOffsets = 16;
	ivec3 chunkOffset;
	void genPerChunkData(){}

	BlockId generateBlock(int x, int y, int z)
	{
		if (x % cubeOffsets < cubesSizes &&
			y % cubeOffsets < cubesSizes &&
			z % cubeOffsets < cubesSizes) return GRASS;
		else return AIR;
	}
}

float noise2d(int x, int z)
{
	enum NUM_OCTAVES = 8;
	enum DIVIDER = 50; // bigger - smoother
	enum HEIGHT_MODIFIER = 4; // bigger - higher

	float noise = 0.0;
	foreach(i; 1..NUM_OCTAVES+1)
	{
		// [-1; 1]
		noise += Simplex.noise(cast(float)x/(DIVIDER*i), cast(float)z/(DIVIDER*i))*i*HEIGHT_MODIFIER;
	}

	return noise;
}

struct PerColumnChunkData
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
