/**
Copyright: Copyright (c) 2016 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.world.worlddb;

import std.experimental.allocator.mallocator;
import voxelman.world.db.lmdbworlddb;
import voxelman.world.db.sqliteworlddb;

version(Windows) {
	version = Lmdb;
} else {
	version = Sqlite;
}

private enum Table : ulong
{
	world,
	region,
	chunk,
}

final class WorldDb
{
	version(Lmdb) LmdbWorldDb db;
	version(Sqlite) SqliteWorldDb db;
	private ubyte[] buffer;

	//-----------------------------------------------
	void open(string filename) {
		version(Lmdb) mdb_load_libs();
		db.open(filename);
	}
	void close() {
		db.close();
		if (buffer !is null) Mallocator.instance.deallocate(buffer);
	}

	ubyte[] tempBuffer() @property {
		if (buffer is null) buffer = cast(ubyte[])Mallocator.instance.allocate(4096*64);

		return buffer;
	}

	//-----------------------------------------------
	version(Lmdb) {
		void put(ubyte[16] key, ubyte[] value) {
			db.put(key, value);
		}
		ubyte[] get(ubyte[16] key) {
			return db.get(key);
		}
		void del(ubyte[16] key) {
			return db.del(key);
		}
	}

	version(Sqlite) {
		void put(ubyte[16] key, ubyte[] value) {
			ulong[2] keys = *cast(ulong[2]*)&key;
			db.savePerWorldData(keys[0], keys[1], value);
		}
		ubyte[] get(ubyte[16] key) {
			ulong[2] keys = *cast(ulong[2]*)&key;
			return db.loadPerWorldData(keys[0], keys[1]);
		}
		void del(ubyte[16] key) {
			ulong[2] keys = *cast(ulong[2]*)&key;
			assert(false, "not implemented");
		}
	}

	//-----------------------------------------------
	void beginTxn() {
		db.beginTxn();
	}
	void abortTxn() {
		db.abortTxn();
	}
	void commitTxn() {
		db.commitTxn();
	}
}

ubyte[16] formChunkKey(ulong chunkPos) {
	ubyte[16] res;
	(*cast(ulong[2]*)res.ptr)[0] = chunkPos;
	(*cast(ulong[2]*)res.ptr)[1] = Table.chunk;
	return res;
}

ubyte[16] formWorldKey(uint key) {
	ubyte[16] res;
	(*cast(ulong[2]*)res.ptr)[0] = key;
	(*cast(ulong[2]*)res.ptr)[1] = Table.world;
	return res;
}
