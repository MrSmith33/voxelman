/**
Copyright: Copyright (c) 2016 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.world.worlddb;

import voxelman.world.db.lmdbworlddb;
import voxelman.world.db.sqliteworlddb;

//version = Sqlite;
version = Lmdb;

enum Table : ulong
{
	world,
	dimention,
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
		import std.array : uninitializedArray;
		buffer = uninitializedArray!(ubyte[])(4096*64);
		version(Lmdb) mdb_load_libs();
		db.open(filename);
	}
	void close() {
		db.close();
	}

	ubyte[] tempBuffer() @property { return buffer; }

	//-----------------------------------------------
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
	version(Lmdb) void put(ulong key, ulong table, ubyte[] value) {
		ubyte[16] dbKey;
		(*cast(ulong[2]*)dbKey.ptr)[0] = key;
		(*cast(ulong[2]*)dbKey.ptr)[1] = table;
		db.put(dbKey, value);
	}
	version(Lmdb) ubyte[] get(ulong key, ulong table) {
		ubyte[16] dbKey;
		(*cast(ulong[2]*)dbKey.ptr)[0] = key;
		(*cast(ulong[2]*)dbKey.ptr)[1] = table;
		return db.get(dbKey);
	}
	version(Lmdb) void del(ulong key, ulong table) {
		ubyte[16] dbKey;
		(*cast(ulong[2]*)dbKey.ptr)[0] = key;
		(*cast(ulong[2]*)dbKey.ptr)[1] = table;
		return db.del(dbKey);
	}
}

ulong formKey(K)(K _key)
	if (is(K == string) || is(K == ulong))
{
	static if (is(K == string))
		return hashBytes(cast(ubyte[])_key);
	else static if (is(K == ulong))
		return _key;
}

ulong hashBytes(ubyte[] bytes)
{
    ulong hash = 5381;

    foreach(c; bytes)
        hash = ((hash << 5) + hash) + c; /* hash * 33 + c */

    return hash;
}
