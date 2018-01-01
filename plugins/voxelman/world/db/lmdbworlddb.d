/**
Copyright: Copyright (c) 2016-2018 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.world.db.lmdbworlddb;

import voxelman.log;
import lmdb;

import std.string : fromStringz, toStringz;
struct LmdbWorldDb
{
	private MDB_env* env;
	private MDB_txn* txn;
	private uint txnFlags;
	private MDB_dbi dbi;

	// filename needs to have /0 after end
	void open(string filename, size_t mapSize = 1 * 1024 * 1024 * 1024) {
		assert(env is null);
		assert(txn is null);
		checked!mdb_env_create(&env);

		checked!mdb_env_set_mapsize(env, mapSize);

		checked!mdb_env_open(env, filename.toStringz,
			MDB_NOSUBDIR|
			MDB_NOMETASYNC|
			MDB_NOSYNC|
			MDB_WRITEMAP|
			MDB_NOLOCK|
			MDB_NOMEMINIT,
			//rwx_rwx_rwx
			0b110_110_110);
	}

	static string libVersion() @nogc {
		return cast(string)mdb_version(null, null, null).fromStringz;
	}

	void close() @nogc {
		mdb_env_close(env);
		env = null;
		txn = null;
	}

	void beginTxn(uint flags = 0) @nogc {
		checked!mdb_txn_begin(env, null, flags, &txn);
		checked!mdb_dbi_open(txn, null/*main DB*/, 0/*flags*/, &dbi);
		checked!mdb_set_compare(txn, dbi, &mdb_cmp_long);
	}

	void abortTxn() @nogc {
		mdb_txn_abort(txn);
	}

	void commitTxn() @nogc {
		checked!mdb_txn_commit(txn);
	}

	void put(ubyte[] key, ubyte[] value) @nogc {
		checked!mdb_put(txn, dbi, &key, &value, 0);
	}

	ubyte[] get(ubyte[] key) @nogc {
		ubyte[] value;
		checked!mdb_get(txn, dbi, &key, &value);
		return value;
	}

	void del(ubyte[] key) @nogc {
		checked!mdb_del(txn, dbi, &key, null);
	}

	void dropDB() @nogc {
		checked!mdb_drop(txn, dbi, 0);
		checked!mdb_drop(txn, dbi, 1);
	}
}
