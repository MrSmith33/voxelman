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
		private enum Table : ulong
		{
			world,
			dimension,
			region,
			chunk,
		}
		void putPerWorldValue(K)(K key, ubyte[] value) {
			put(formKey(key), Table.world, value);
		}
		ubyte[] getPerWorldValue(K)(K key) {
			return get(formKey(key), Table.world);
		}
		void putPerChunkValue(ulong key, ubyte[] value) {
			put(key, Table.chunk, value);
		}
		ubyte[] getPerChunkValue(ulong key) {
			return get(key, Table.chunk);
		}
		void putPerDimensionValue(uint key, ushort dimension, ubyte[] value) {
			put(key, Table.dimension, value);
		}
		ubyte[] getPerDimensionValue(uint key, ushort dimension) {
			return get(key, Table.dimension);
		}

		private void put(ulong key, ulong table, ubyte[] value) {
			ubyte[16] dbKey;
			(*cast(ulong[2]*)dbKey.ptr)[0] = key;
			(*cast(ulong[2]*)dbKey.ptr)[1] = table;
			db.put(dbKey, value);
		}
		private ubyte[] get(ulong key, ulong table) {
			ubyte[16] dbKey;
			(*cast(ulong[2]*)dbKey.ptr)[0] = key;
			(*cast(ulong[2]*)dbKey.ptr)[1] = table;
			return db.get(dbKey);
		}
		private void del(ulong key, ulong table) {
			ubyte[16] dbKey;
			(*cast(ulong[2]*)dbKey.ptr)[0] = key;
			(*cast(ulong[2]*)dbKey.ptr)[1] = table;
			return db.del(dbKey);
		}
	}

	version(Sqlite) {
		void putPerWorldValue(K)(K key, ubyte[] value) {
			db.savePerWorldData(key, value);
		}
		ubyte[] getPerWorldValue(K)(K key) {
			return db.loadPerWorldData(key);
		}
		void putPerChunkValue(ulong key, ubyte[] value) {
			db.savePerChunkData(key, value);
		}
		ubyte[] getPerChunkValue(ulong key) {
			return db.loadPerChunkData(key);
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

ulong formKey(K)(K _key) @nogc
	if (is(K == string) || is(K == ulong))
{
	static if (is(K == string))
		return hashBytes(cast(ubyte[])_key);
	else static if (is(K == ulong))
		return _key;
}

ulong hashBytes(ubyte[] bytes) @nogc
{
    ulong hash = 5381;

    foreach(c; bytes)
        hash = ((hash << 5) + hash) + c; /* hash * 33 + c */

    return hash;
}
