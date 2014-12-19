/**
Copyright: Copyright (c) 2014 Andrey Penechko.
License: a$(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.region;

import std.string : format;
import std.bitmanip : BitArray, nativeToBigEndian, bigEndianToNative;
import std.file : exists;
import std.stdio : writefln, writeln, File, SEEK_END;
import std.path : isValidPath, dirSeparator;

enum REGION_SIZE = 16;
enum REGION_SIZE_SQR = REGION_SIZE * REGION_SIZE;
enum REGION_SIZE_CUBE = REGION_SIZE * REGION_SIZE * REGION_SIZE;
enum SECTOR_SIZE = 4096;

enum HEADER_SIZE = REGION_SIZE_CUBE * uint.sizeof;
enum NUM_HEADER_SECTORS = HEADER_SIZE / SECTOR_SIZE;
enum CHUNK_HEADER_SIZE = uint.sizeof;

// Chunk sectors number is stored as ubyte, so max 255 sectors can be used.
enum MAX_CHUNK_SECTORS = ubyte.max;


private immutable ubyte[SECTOR_SIZE] emptySector;

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
	/// Coords are region local. I.e. 0..REGION_SIZE
	public bool isChunkOnDisk(int x, int y, int z)
	{
		assert(isValidCoord(x, y, z));
		auto index = chunkIndex(x, y, z);
		return (offsets[index] & 0xFF) != 0;
	}

	/// Reads chunk from a file.
	/// Chunks coords are region local in range 0..REGION_SIZE.
	/// outBuffer should be big enough to store chunk of any size.
	/// Returns: a slice of outBuffer with actual data or null if chunk was not
	/// stored on disk previously.
	/// Coords are region local. I.e. 0..REGION_SIZE
	public ubyte[] readChunk(int x, int y, int z, ubyte[] outBuffer)
	{
		assert(isValidCoord(x, y, z));
		if (!isChunkOnDisk(x, y, z)) return null;

		auto index = chunkIndex(x, y, z);
		auto sectorNumber = offsets[index] >> 8;
		auto numSectors = offsets[index] & 0xFF;

		// Chunk sector is after EOF.
		if (sectorNumber + numSectors > sectors.length)
		{
			writefln("Invalid sector {%s, %s, %s}", x, y, z);
			return null;
		}

		file.seek(sectorNumber * SECTOR_SIZE);
		ubyte[4] uintBuffer;
		file.rawRead(uintBuffer[]);
		uint dataLength = bigEndianToNative!uint(uintBuffer);

		if (dataLength > numSectors * SECTOR_SIZE)
		{
			writefln("Invalid data length {%s, %s, %s}, %s > %s * %s",
				x, y, z, dataLength, numSectors, SECTOR_SIZE);
			return null;
		}

		return file.rawRead(outBuffer[0..dataLength]);
	}

	/// Writes chunk at x, y, z with data chunkData to disk.
	/// Coords are region local. I.e. 0..REGION_SIZE
	public void writeChunk(int x, int y, int z, in ubyte[] chunkData)
	{
		assert(isValidCoord(x, y, z));

		auto index = chunkIndex(x, y, z);
		auto sectorNumber = offsets[index] >> 8;
		auto numSectors = offsets[index] & 0xFF;

		import std.math : ceil;		
		auto sectorsNeeded = cast(size_t)ceil(
			cast(float)(chunkData.length + CHUNK_HEADER_SIZE) / SECTOR_SIZE);

		if (sectorsNeeded > MAX_CHUNK_SECTORS)
		{
			writefln("data length %s is too big", chunkData.length);
			return;
		}

		if (sectorNumber != 0 && numSectors == sectorsNeeded)
		{
			// Rewrite data in place.
			writeChunkData(sectorNumber, chunkData);
			return;
		}

		// Mark used sectors as free.
		foreach(i; sectorNumber..sectorNumber + numSectors)
			sectors[i] = true;

		uint numFreeSectors = 0;
		size_t firstFreeSector = 0;
		// Find a sequence of free sectors of big enough size.
		foreach(sectorIndex; sectors.bitsSet)
		{
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

		// Use free sectors found in a file.
		writeChunkData(firstFreeSector, chunkData);

		setChunkOffset(x, y, z, firstFreeSector, cast(ubyte)sectorsNeeded);
		foreach(i; firstFreeSector..firstFreeSector + sectorsNeeded)
			sectors[i] = false;

		// Fix last sector size if we was appending.
		fixPadding();
	}

	private bool isValidCoord(int x, int y, int z)
	{
		return !(x < 0 || x >= REGION_SIZE ||
				y < 0 || y >= REGION_SIZE ||
				z < 0 || z >= REGION_SIZE);
	}

	private size_t chunkIndex(int x, int y, int z)
	{
		return x + y * REGION_SIZE + z * REGION_SIZE_SQR;
	}

	private void openFile(string regionFilename)
	{
		assert(isValidPath(regionFilename));

		if (!exists(regionFilename))
		{
			//writeln("write header");
			file.open(regionFilename, "wb+");
		
			// Lets write chunk offset table.
			foreach(_; 0..(REGION_SIZE_CUBE*uint.sizeof) / SECTOR_SIZE)
				file.rawWrite(emptySector);

			sectors.length = NUM_HEADER_SECTORS;
			//writefln("%b", sectors);
			return;
		}

		//writeln("read header");
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

		//writefln("%b", sectors);
	}

	private void writeChunkData(uint sectorNumber, in ubyte[] data)
	{
		file.seek(sectorNumber * SECTOR_SIZE);
		file.rawWrite(nativeToBigEndian(cast(uint)data.length));
		file.rawWrite(data);
	}

	private void setChunkOffset(int x, int y, int z, uint position, ubyte size)
	{
		auto index = chunkIndex(x, y, z);
		uint offset = (position << 8) | size;
		offsets[index] = offset;
		file.seek(index * 4);
		file.rawWrite(nativeToBigEndian(offset));
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