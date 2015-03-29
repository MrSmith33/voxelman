/**
Copyright: Copyright (c) 2014-2015 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.storage.storageworker;

import std.experimental.logger;
import std.conv : to;

import cbor;

import voxelman.block;
import voxelman.storage.chunk;
import voxelman.chunkgen;
import voxelman.storage.regionstorage;
import voxelman.utils.rlecompression;

private ubyte[4096*16] compressBuffer;
private ubyte[4096*16] buffer;


void storageWorkerThread(Tid mainTid, string regionDir)
{
	try
	{
		RegionStorage regionStorage = RegionStorage(regionDir);
		shared(bool)* isRunning;
		bool isRunningLocal = true;
		receive( (shared(bool)* _isRunning){isRunning = _isRunning;} );

		void writeChunk(ivec3 chunkPos, BlockData data)
		{
			//infof("writing chunk %s ", chunkPos);
			if (regionStorage.isChunkOnDisk(chunkPos)) return;

			BlockData compressedData = data;
			compressedData.blocks = rleEncode(data.blocks, compressBuffer);

			try
			{
				size_t encodedSize = encodeCborArray(buffer[], compressedData);
				//infof("size %s compressed %s", data.blocks.length, compressedData.blocks.length);
				regionStorage.writeChunk(chunkPos, buffer[0..encodedSize]);
			}
			catch(Exception e)
			{
				errorf("storage error %s", e.to!string);
			}
		}

		BlockData readChunk(ivec3 chunkPos)
		{
			assert(regionStorage.isChunkOnDisk(chunkPos));
			//infof("reading chunk %s ", chunkPos);
			auto data = regionStorage.readChunk(chunkPos, buffer[]);
			BlockData compressedData = decodeCborSingle!BlockData(data);
			BlockData uncompressedData = compressedData;
			uncompressedData.blocks = rleDecode(compressedData.blocks, compressBuffer).dup;

			//infof("size %s compressed %s", uncompressedData.blocks.length, compressedData.blocks.length);
			return uncompressedData;
		}

		while (isRunningLocal)
		{
			receive(
				// read
				(ivec3 chunkPos, Tid genWorker) {
					if (!atomicLoad(*isRunning)) return;
					if (regionStorage.isChunkOnDisk(chunkPos))
					{
						try
						{
							BlockData bd = readChunk(chunkPos);
							ChunkGenResult* genResult = new ChunkGenResult(bd, chunkPos);
							auto result = cast(immutable(ChunkGenResult)*)genResult;
							mainTid.send(result);
						}
						catch(Exception e)
						{
							infof("storage error %s", e.to!string);
						}
					}
					else
					{
						genWorker.send(chunkPos);
					}
				},
				// write
				(ivec3 chunkPos, shared BlockData blockData, bool deleteData) {
					writeChunk(chunkPos, cast(BlockData)blockData);

					if (deleteData)
						delete blockData.blocks;
				},
				(Variant v) {
					isRunningLocal = false;
					regionStorage.clear();
				}
			);
		}
	}
	catch(Throwable t)
	{
		infof("%s from storage worker", t.to!string);
		throw t;
	}
}
