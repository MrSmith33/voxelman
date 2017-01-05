/**
Copyright: Copyright (c) 2016 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.world.db.lmdbworlddb;

import voxelman.log;

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

template checked(alias func)
{
	import std.traits;
	debug auto checked(string file = __FILE__, int line = __LINE__)(auto ref Parameters!func args)
	{
		int rc = func(args);
		checkCode(rc, file, line);
		return rc;
	} else
		alias checked = func;
}

void checkCode(int code, string file = __FILE__, int line = __LINE__) @nogc
{
	if (code != MDB_SUCCESS && code != MDB_NOTFOUND)
	{
		//errorf("%s@%s: MDB error: %s", file, line, mdb_strerror(code).fromStringz);
		import core.stdc.stdio;
		printf("%s@%s: MDB error: %s", file.ptr, line, mdb_strerror(code));
		assert(false);
	}
}

extern(C):
nothrow:
@nogc:

static int mdb_cmp_long(const MDB_val *a, const MDB_val *b)
{
	immutable ulong a0 = (cast(ulong*)a.ptr)[0];
	immutable ulong a1 = (cast(ulong*)a.ptr)[1];
	immutable ulong b0 = (cast(ulong*)b.ptr)[0];
	immutable ulong b1 = (cast(ulong*)b.ptr)[1];

	if (a1 == b1)
	{
		if (a0 == b0)
			return 0;
		else
			return (a0 < b0) ? -1 : 1;
	}
	else
	{
		return (a1 < b1) ? -1 : 1;
	}
}

void mdb_load_libs();

alias mdb_mode_t = uint;
struct mdb_filehandle_ts {}
alias mdb_filehandle_t = mdb_filehandle_ts*;

struct MDB_env {}
struct MDB_txn {}
alias MDB_dbi = uint;
struct MDB_cursor {}

alias MDB_val = ubyte[];

enum {
  MDB_FIXEDMAP = 0x01,
  MDB_NOSUBDIR = 0x4000,
  MDB_NOSYNC = 0x10000,
  MDB_RDONLY = 0x20000,
  MDB_NOMETASYNC = 0x40000,
  MDB_WRITEMAP = 0x80000,
  MDB_MAPASYNC = 0x100000,
  MDB_NOTLS = 0x200000,
  MDB_NOLOCK = 0x400000,
  MDB_NORDAHEAD = 0x800000,
  MDB_NOMEMINIT = 0x1000000
}

enum {
  MDB_REVERSEKEY = 0x02,
  MDB_DUPSORT = 0x04,
  MDB_INTEGERKEY = 0x08,
  MDB_DUPFIXED = 0x10,
  MDB_INTEGERDUP = 0x20,
  MDB_REVERSEDUP = 0x40,
  MDB_CREATE = 0x40000
}

enum {
  MDB_NOOVERWRITE = 0x10,
  MDB_NODUPDATA = 0x20,
  MDB_RESERVE = 0x10000,
  MDB_APPEND = 0x20000,
  MDB_APPENDDUP = 0x40000,
  MDB_MULTIPLE = 0x80000
}

enum /*MDB_cursor_op*/ {
  MDB_FIRST,
  MDB_FIRST_DUP,
  MDB_GET_BOTH,
  MDB_GET_BOTH_RANGE,
  MDB_GET_CURRENT,
  MDB_GET_MULTIPLE,
  MDB_LAST,
  MDB_LAST_DUP,
  MDB_NEXT,
  MDB_NEXT_DUP,
  MDB_NEXT_MULTIPLE,
  MDB_NEXT_NODUP,
  MDB_PREV,
  MDB_PREV_DUP,
  MDB_PREV_NODUP,
  MDB_SET,
  MDB_SET_KEY,
  MDB_SET_RANGE,
}

enum {
  MDB_SUCCESS = 0,
  MDB_KEYEXIST = (-30799),
  MDB_NOTFOUND = (-30798),
  MDB_PAGE_NOTFOUND = (-30797),
  MDB_CORRUPTED = (-30796),
  MDB_PANIC = (-30795),
  MDB_VERSION_MISMATCH = (-30794),
  MDB_INVALID = (-30793),
  MDB_MAP_FULL = (-30792),
  MDB_DBS_FULL = (-30791),
  MDB_READERS_FULL = (-30790),
  MDB_TLS_FULL = (-30789),
  MDB_TXN_FULL = (-30788),
  MDB_CURSOR_FULL = (-30787),
  MDB_PAGE_FULL = (-30786),
  MDB_MAP_RESIZED = (-30785),
  MDB_INCOMPATIBLE = (-30784),
  MDB_BAD_RSLOT = (-30783),
  MDB_BAD_TXN = (-30782),
  MDB_BAD_VALSIZE = (-30781),
  MDB_BAD_DBI = (-30780),
  MDB_LAST_ERRCODE = MDB_BAD_DBI
}

struct MDB_stat {
  uint ms_psize;
  uint ms_depth;
  size_t ms_branch_pages;
  size_t ms_leaf_pages;
  size_t ms_overflow_pages;
  size_t ms_entries;
}

struct MDB_envinfo {
  void* me_mapaddr;
  size_t me_mapsize;
  size_t me_last_pgno;
  size_t me_last_txnid;
  uint me_maxreaders;
  uint me_numreaders;
}

const(char)* mdb_version (int* major, int* minor, int* patch);
const(char)* mdb_strerror (int err);

int mdb_env_create (MDB_env** env);
int mdb_env_open (MDB_env* env, const(char)* path, uint flags, mdb_mode_t mode);
int mdb_env_copy (MDB_env* env, const(char)* path);
int mdb_env_copyfd (MDB_env* env, mdb_filehandle_t fd);
int mdb_env_stat (MDB_env* env, MDB_stat* stat);
int mdb_env_info (MDB_env* env, MDB_envinfo* stat);
int mdb_env_sync (MDB_env* env, int force);
void mdb_env_close (MDB_env* env);
int mdb_env_set_flags (MDB_env* env, uint flags, int onoff);
int mdb_env_get_flags (MDB_env* env, uint* flags);
int mdb_env_get_path (MDB_env* env, const(char)** path);
int mdb_env_get_fd (MDB_env* env, mdb_filehandle_t* fd);
int mdb_env_set_mapsize (MDB_env* env, size_t size);
int mdb_env_set_maxreaders (MDB_env* env, uint readers);
int mdb_env_get_maxreaders (MDB_env* env, uint* readers);
int mdb_env_set_maxdbs (MDB_env* env, MDB_dbi dbs);
int mdb_env_get_maxkeysize (MDB_env* env);
int mdb_env_set_userctx (MDB_env* env, void* ctx);
void* mdb_env_get_userctx (MDB_env* env);
int mdb_env_set_assert (MDB_env* env, void function (MDB_env* env, const(char)* msg) func);

int mdb_txn_begin (MDB_env* env, MDB_txn* parent, uint flags, MDB_txn** txn);
MDB_env* mdb_txn_env (MDB_txn* txn);
size_t mdb_txn_id (MDB_txn* txn);
int mdb_txn_commit (MDB_txn* txn);
void mdb_txn_abort (MDB_txn* txn);
void mdb_txn_reset (MDB_txn* txn);
int mdb_txn_renew (MDB_txn* txn);

int mdb_dbi_open (MDB_txn* txn, const(char)* name, uint flags, MDB_dbi* dbi);
int mdb_stat (MDB_txn* txn, MDB_dbi dbi, MDB_stat* stat);
int mdb_dbi_flags (MDB_txn* txn, MDB_dbi dbi, uint* flags);
void mdb_dbi_close (MDB_env* env, MDB_dbi dbi);
int mdb_drop (MDB_txn* txn, MDB_dbi dbi, int del);
int mdb_set_compare (MDB_txn* txn, MDB_dbi dbi, int function (const MDB_val* a, const MDB_val* b) cmp);
int mdb_set_dupsort (MDB_txn* txn, MDB_dbi dbi, int function (MDB_val* a, MDB_val* b) cmp);
int mdb_set_relfunc (MDB_txn* txn, MDB_dbi dbi, void function (MDB_val* item, void* oldptr, void* newptr, void* relctx) rel);
int mdb_set_relctx (MDB_txn* txn, MDB_dbi dbi, void* ctx);
int mdb_get (MDB_txn* txn, MDB_dbi dbi, MDB_val* key, MDB_val* data);
int mdb_put (MDB_txn* txn, MDB_dbi dbi, MDB_val* key, MDB_val* data, uint flags);
int mdb_del (MDB_txn* txn, MDB_dbi dbi, MDB_val* key, MDB_val* data);
int mdb_cursor_open (MDB_txn* txn, MDB_dbi dbi, MDB_cursor** cursor);
void mdb_cursor_close (MDB_cursor* cursor);
int mdb_cursor_renew (MDB_txn* txn, MDB_cursor* cursor);
MDB_txn* mdb_cursor_txn (MDB_cursor* cursor);
MDB_dbi mdb_cursor_dbi (MDB_cursor* cursor);
int mdb_cursor_get (MDB_cursor* cursor, MDB_val* key, MDB_val* data, /*MDB_cursor_op*/uint op);
int mdb_cursor_put (MDB_cursor* cursor, MDB_val* key, MDB_val* data, uint flags);
int mdb_cursor_del (MDB_cursor* cursor, uint flags);
int mdb_cursor_count (MDB_cursor* cursor, size_t* countp);
int mdb_cmp (MDB_txn* txn, MDB_dbi dbi, MDB_val* a, MDB_val* b);
int mdb_dcmp (MDB_txn* txn, MDB_dbi dbi, MDB_val* a, MDB_val* b);
int mdb_reader_list (MDB_env* env, int function (const(char)* msg, void* ctx) func, void* ctx);
int mdb_reader_check (MDB_env* env, int* dead);
