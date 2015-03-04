/**
Copyright: Copyright (c) 2014-2015 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.storageworker;

import std.experimental.logger;
import std.conv : to;

import cbor;

import voxelman.block;
import voxelman.chunk;
import voxelman.chunkgen;
import voxelman.regionstorage;
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

		void writeChunk(ivec3 chunkPos, ChunkData data)
		{
			//infof("writing chunk %s ", chunkPos);
			if (regionStorage.isChunkOnDisk(chunkPos)) return;

			ChunkData compressedData = data;
			compressedData.typeData = rleEncode(data.typeData, compressBuffer);

			try
			{
				size_t encodedSize = encodeCborArray(buffer[], compressedData);
				//infof("size %s compressed %s", data.typeData.length, compressedData.typeData.length);
				regionStorage.writeChunk(chunkPos, buffer[0..encodedSize]);
			}
			catch(Exception e)
			{
				errorf("storage error %s", e.to!string);
			}
		}

		ChunkData readChunk(ivec3 chunkPos)
		{
			assert(regionStorage.isChunkOnDisk(chunkPos));
			//infof("reading chunk %s ", chunkPos);
			auto data = regionStorage.readChunk(chunkPos, buffer[]);
			ChunkData compressedData = decodeCborSingle!ChunkData(data);
			ChunkData uncompressedData = compressedData;
			uncompressedData.typeData = rleDecode(compressedData.typeData, compressBuffer).dup;

			//infof("size %s compressed %s", uncompressedData.typeData.length, compressedData.typeData.length);
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
							ChunkData cd = readChunk(chunkPos);
							ChunkGenResult* genResult = new ChunkGenResult(cd, chunkPos);
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
				(ivec3 chunkPos, shared ChunkData chunkData, bool deleteData) {
					writeChunk(chunkPos, cast(ChunkData)chunkData);

					if (deleteData)
						delete chunkData.typeData;
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
