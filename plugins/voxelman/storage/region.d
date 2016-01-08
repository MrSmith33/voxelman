/**
Copyright: Copyright (c) 2014-2016 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.storage.region;

import std.experimental.logger;
import std.bitmanip : BitArray, nativeToBigEndian, bigEndianToNative;
import std.file : exists;
import std.path : isValidPath, dirSeparator;
import std.stdio : File, SEEK_END;
import std.string : format;
import dlib.math.vector : ivec3;

import voxelman.core.config : TimestampType;
import voxelman.storage.coordinates;

int ceiling_pos (float X) {return (X-cast(int)(X)) > 0 ? cast(int)(X+1) : cast(int)(X);}
int ceiling_neg (float X) {return (X-cast(int)(X)) < 0 ? cast(int)(X-1) : cast(int)(X);}
int ceiling (float X) {return ((X) > 0) ? ceiling_pos(X) : ceiling_neg(X);}

enum REGION_SIZE = 16;
enum REGION_SIZE_SQR = REGION_SIZE * REGION_SIZE;
enum REGION_SIZE_CUBE = REGION_SIZE * REGION_SIZE * REGION_SIZE;
enum SECTOR_SIZE = 512;

enum HEADER_SIZE = REGION_SIZE_CUBE * uint.sizeof + REGION_SIZE_CUBE * TimestampType.sizeof;
enum NUM_HEADER_SECTORS = ceiling(float(HEADER_SIZE) / SECTOR_SIZE);
enum CHUNK_HEADER_SIZE = uint.sizeof;

// Chunk sectors number is stored as ubyte, so max 255 sectors can be used.
enum MAX_CHUNK_SECTORS = ubyte.max;


private immutable ubyte[SECTOR_SIZE] emptySector;

struct ChunkStoreInfo
{
	bool isStored;
	ChunkRegionPos positionInRegion;
	ChunkWorldPos positionInWorld;
	RegionWorldPos parentRegionPosition;
	ChunkRegionIndex headerIndex;

	// following fields are only valid when isStored == true.
	size_t sectorNumber;
	size_t numSectors;
	TimestampType timestamp;
	size_t dataLength;
	size_t dataByteOffset() @property {return sectorNumber * SECTOR_SIZE;}

	string toString()
	{
		return format("position in region %s\nposition in world %s\n"~
			"parent region %s\nheader index %s\n"~
			"data length %s\nsector number %s\ndata offset %s",
			positionInRegion, positionInWorld, parentRegionPosition,
			headerIndex.index, dataLength, sectorNumber, dataByteOffset);
	}
}

/**
	A storage for REGION_SIZE^3 offsets on a disk.

	Format:
	Header consists of REGION_SIZE^3 records of 4 bytes.
	record = position << 8 | (size & 0xFF)
	where position is the number of first sector and size is the total number
	of sectors that are used by a chunk.
	Header is followed by sectors each of size SECTOR_SIZE. 4096

	Region files are named like x_y_z.region.
*/
struct Region
{
	private File file;
	private uint[REGION_SIZE_CUBE] offsets;
	private TimestampType[REGION_SIZE_CUBE] timestamps;
	// true if free, false if occupied.
	private BitArray sectors;

	@disable this();
	this(string regionFilename)
	{
		openFile(regionFilename);
	}

	/// Closes the underlyiing file handle.
	/// Renders Region unusable after this.
	public void close()
	{
		file.close();
	}

	/// Returns true if chunk is presented on disk.
	/// Positions are region local. I.e. 0..REGION_SIZE
	public bool isChunkOnDisk(ChunkRegionPos chunkPosition)
	{
		assert(isValidPosition(chunkPosition), format("Invalid position %s", chunkPosition));
		auto chunkIndex = ChunkRegionIndex(chunkPosition);
		return (offsets[chunkIndex] & 0xFF) != 0;
	}

	public TimestampType chunkTimestamp(ChunkRegionPos chunkPosition)
	{
		assert(isValidPosition(chunkPosition), format("Invalid position %s", chunkPosition));
		auto chunkIndex = ChunkRegionIndex(chunkPosition);
		return timestamps[chunkIndex];
	}

	public ChunkStoreInfo getChunkStoreInfo(ChunkRegionPos chunkPosition)
	{
		auto chunkIndex = ChunkRegionIndex(chunkPosition);
		auto sectorNumber = offsets[chunkIndex] >> 8;
		auto numSectors = offsets[chunkIndex] & 0xFF;
		auto timestamp = timestamps[chunkIndex];

		ChunkStoreInfo res = ChunkStoreInfo(true, chunkPosition, ChunkWorldPos(),
			RegionWorldPos(), chunkIndex, sectorNumber, numSectors, timestamp);
		if (!isChunkOnDisk(chunkPosition))
		{
			res.isStored = false;
			return res;
		}

		file.seek(sectorNumber * SECTOR_SIZE);
		ubyte[4] uintBuffer;
		file.rawRead(uintBuffer[]);
		res.dataLength = bigEndianToNative!uint(uintBuffer);

		return res;
	}

	/// Reads chunk from a file.
	/// Chunks positions are region local in range 0..REGION_SIZE.
	/// outBuffer should be big enough to store chunk of any size.
	/// Returns: a slice of outBuffer with actual data or null if chunk was not
	/// stored on disk previously.
	/// Positions are region local. I.e. 0..REGION_SIZE
	public ubyte[] readChunk(ChunkRegionPos chunkPosition, ubyte[] outBuffer, out TimestampType timestamp)
	{
		assert(isValidPosition(chunkPosition), format("Invalid position %s", chunkPosition));
		if (!isChunkOnDisk(chunkPosition)) return null;

		auto chunkIndex = ChunkRegionIndex(chunkPosition);
		auto sectorNumber = offsets[chunkIndex] >> 8;
		auto numSectors = offsets[chunkIndex] & 0xFF;

		// Chunk sector is after EOF.
		if (sectorNumber + numSectors > sectors.length)
		{
			errorf("Invalid sector chunk %s, sector %s, numSectors %s while total sectors %s",
				chunkPosition, sectorNumber, numSectors, sectors.length);
			errorf("Erasing chunk");
			eraseChunk(chunkIndex);
			return null;
		}

		file.seek(sectorNumber * SECTOR_SIZE);
		ubyte[4] uintBuffer;
		file.rawRead(uintBuffer[]);
		uint dataLength = bigEndianToNative!uint(uintBuffer);
		//infof("read data length %s BE %(%02x%)", dataLength, uintBuffer[]);

		if (dataLength > numSectors * SECTOR_SIZE)
		{
			errorf("Invalid data length %s, %s > %s * %s",
				chunkPosition, dataLength, numSectors, SECTOR_SIZE);
			errorf("Erasing chunk");
			eraseChunk(chunkIndex);
			return null;
		}

		timestamp = timestamps[chunkIndex];
		return file.rawRead(outBuffer[0..dataLength]);
	}

	/// Writes chunk at chunkPosition with data blockData to disk.
	/// Positions are region local. I.e. 0..REGION_SIZE
	public void writeChunk(ChunkRegionPos chunkPosition, in ubyte[] blockData, TimestampType timestamp)
	{
		assert(isValidPosition(chunkPosition), format("Invalid position %s", chunkPosition));

		auto chunkIndex = ChunkRegionIndex(chunkPosition);
		auto sectorNumber = offsets[chunkIndex] >> 8;
		auto numSectors = offsets[chunkIndex] & 0xFF;

		import std.math : ceil;
		auto sectorsNeeded = cast(size_t)ceil(
			cast(float)(blockData.length + CHUNK_HEADER_SIZE) / SECTOR_SIZE);

		if (sectorsNeeded > MAX_CHUNK_SECTORS)
		{
			errorf("data length %s is too big", blockData.length);
			return;
		}

		if (sectorNumber != 0 && numSectors == sectorsNeeded)
		{
			// Rewrite data in place.
			writeChunkData(sectorNumber, blockData);
			return;
		}
		//infof("searching for free sectors");

		// Mark used sectors as free.
		foreach(i; sectorNumber..sectorNumber + numSectors)
			sectors[i] = true;

		uint numFreeSectors = 0;
		size_t firstFreeSector = 0;
		// Find a sequence of free sectors of big enough size.
		foreach(sectorIndex; sectors.bitsSet)
		{
			//infof("chunkIndex %s", sectorIndex);

			if (numFreeSectors > 0)
			{
				if (sectorIndex - firstFreeSector > 1) ++numFreeSectors;
				else numFreeSectors = 0;
			}
			else
			{
				firstFreeSector = sectorIndex;
				numFreeSectors = 1;
			}

			if (numFreeSectors >= sectorsNeeded) break;
		}
		//infof("first %s num %s", firstFreeSector, numFreeSectors);

		if (numFreeSectors < sectorsNeeded)
		{
			// We need to append if no free space was found.
			if (firstFreeSector + numFreeSectors < sectors.length)
			{
				firstFreeSector = sectors.length;
				numFreeSectors = 0;
			}

			// But if we have free sectors at the end, lets use them.
			sectors.length = sectors.length + sectorsNeeded - numFreeSectors;
		}

		//infof("first %s num %s", firstFreeSector, numFreeSectors);
		// Use free sectors found in a file.
		writeChunkData(cast(uint)firstFreeSector, blockData);

		setChunkOffset(chunkIndex, cast(uint)firstFreeSector, cast(ubyte)sectorsNeeded);
		setChunkTimestamp(chunkIndex, timestamp);

		foreach(i; firstFreeSector..firstFreeSector + sectorsNeeded)
			sectors[i] = false;

		// Fix last sector size if we was appending.
		fixPadding();
	}

	private bool isValidPosition(ChunkRegionPos chunkPosition)
	{
		return !(chunkPosition.x < 0 || chunkPosition.x >= REGION_SIZE ||
				chunkPosition.y < 0 || chunkPosition.y >= REGION_SIZE ||
				chunkPosition.z < 0 || chunkPosition.z >= REGION_SIZE);
	}

	private void openFile(string regionFilename)
	{
		assert(isValidPath(regionFilename));

		if (!exists(regionFilename))
		{
			//trace("write header");
			file.open(regionFilename, "wb+");

			// Lets write chunk offset table.
			foreach(_; 0..(REGION_SIZE_CUBE*uint.sizeof) / SECTOR_SIZE)
				file.rawWrite(emptySector);

			sectors.length = NUM_HEADER_SECTORS;
			//tracef("sectors %b", sectors);
			return;
		}

		//trace("read header");
		file.open(regionFilename, "rb+");
		file.rawRead(offsets[]);

		// File size is not multiple of SECTOR_SIZE, bump it.
		fixPadding();

		version(LittleEndian)
		foreach(ref uint item; offsets)
			item = bigEndianToNative!uint(*cast(ubyte[4]*)&item);

		sectors.length = cast(size_t)(file.size / SECTOR_SIZE);
		// Mark all data sectors as free.
		foreach(i; NUM_HEADER_SECTORS..sectors.length)
			sectors[i] = true;

		foreach(i, offset; offsets)
		{
			auto sectorNumber = offset >> 8;
			auto numSectors = offset & 0xFF;
			// If chunk is stored on disk and is valid.
			if (offset != 0 && (sectorNumber + numSectors) <= sectors.length)
			{
				// Mark sectors as occupied.
				foreach(sector; sectorNumber..sectorNumber + numSectors)
					sectors[sector] = false;
			}
		}

		//tracef("sectors %b", sectors);
	}

	private void writeChunkData(uint sectorNumber, in ubyte[] data)
	{
		file.seek(sectorNumber * SECTOR_SIZE);
		//tracef("write data length %s BE %(%02x%), sector %s",
		//	data.length, nativeToBigEndian(cast(uint)data.length), sectorNumber);
		file.rawWrite(nativeToBigEndian(cast(uint)data.length));
		file.rawWrite(data);
	}

	private void setChunkOffset(ChunkRegionIndex chunkIndex, uint position, ubyte size)
	{
		uint offset = (position << 8) | size;
		offsets[chunkIndex] = offset;
		file.seek(chunkIndex * uint.sizeof);
		file.rawWrite(nativeToBigEndian(offset));
	}

	private void setChunkTimestamp(ChunkRegionIndex chunkIndex, TimestampType timestamp)
	{
		timestamps[chunkIndex] = timestamp;
		file.seek(REGION_SIZE_CUBE * uint.sizeof + chunkIndex * TimestampType.sizeof);
		file.rawWrite(nativeToBigEndian(timestamp));
	}

	private void eraseChunk(ChunkRegionIndex chunkIndex)
	{
		setChunkTimestamp(chunkIndex, 0);
		setChunkOffset(chunkIndex, 0, 0);
	}

	private void fixPadding()
	{
		auto lastSectorSize = file.size & (SECTOR_SIZE - 1);
		if (lastSectorSize != 0)
		{
			file.seek(0, SEEK_END);
			ubyte[1] emptyByte;
			foreach(_; 0..SECTOR_SIZE - lastSectorSize)
				file.rawWrite(emptyByte);
		}
	}
}
