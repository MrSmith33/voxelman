// Written in the D programming language
/++
This module provides a small wrapper around SQLite for the D programming language.
It wraps the C API in an idiomatic manner and handles built-in D types and
`Nullable!T` automatically.

Authors:
	Nicolas Sicard (biozic) and other contributors at $(LINK https://github.com/biozic/d2sqlite3)

Copyright:
	Copyright 2011-15 Nicolas Sicard.

License:
	$(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0).

Macros:
	D = <tt>$0</tt>
	DK = <strong><tt>$0</tt></strong>
+/
module sqlite.d2sqlite3;

import std.algorithm;
import std.array;
import std.conv;
import std.exception;
import std.range;
import std.string;
import std.traits;
import std.typecons;
import std.typetuple;
import std.variant;
import std.c.string : memcpy;
import core.memory : GC;


public import etc.c.sqlite3;
//public import sqlite3; replaced by etc.c.sqlite3 and some line from sqlite3.
extern (C) nothrow
{
	int sqlite3_bind_text64(sqlite3_stmt*, int, const char*, sqlite3_uint64,
							 void function (void*), ubyte encoding);
	int sqlite3_bind_blob64(sqlite3_stmt*, int, const void*, sqlite3_uint64,
							void function (void*));
	int sqlite3_libversion_number();
	int sqlite3_threadsafe();
	int sqlite3_changes(sqlite3*);
	int sqlite3_total_changes(sqlite3*);
	int sqlite3_errcode(sqlite3 *db);
	int sqlite3_bind_parameter_count(sqlite3_stmt*);
	int sqlite3_column_count(sqlite3_stmt *pStmt);
	void sqlite3_result_text64(sqlite3_context*, const char*,sqlite3_uint64,
                               void function(void*), ubyte encoding);
    void sqlite3_result_blob64(sqlite3_context*,const void*,sqlite3_uint64,void function(void*));
}



/// SQLite type codes
enum SqliteType
{
	INTEGER = SQLITE_INTEGER, ///
	FLOAT = SQLITE_FLOAT, ///
	TEXT = SQLITE3_TEXT, ///
	BLOB = SQLITE_BLOB, ///
	NULL = SQLITE_NULL ///
}

/++
Gets the library's version string (e.g. "3.8.7").
+/
string versionString()
{
	return to!string(sqlite3_libversion());
}

/++
Gets the library's version number (e.g. 3008007).
+/
int versionNumber() nothrow
{
	return sqlite3_libversion_number();
}

unittest
{
	import std.string : startsWith;
	assert(versionString.startsWith("3."));
	assert(versionNumber >= 3008007);
}

/++
Tells whether SQLite was compiled with the thread-safe options.

See_also: ($LINK http://www.sqlite.org/c3ref/threadsafe.html).
+/
bool threadSafe() nothrow
{
	return cast(bool) sqlite3_threadsafe();
}
unittest
{
	auto ts = threadSafe;
}

/++
Manually initializes (or shuts down) SQLite.

SQLite initializes itself automatically on the first request execution, so this
usually wouldn't be called. Use for instance before a call to config().
+/
void initialize()
{
	auto result = sqlite3_initialize();
	enforce(result == SQLITE_OK, new SqliteException("Initialization: error %s".format(result)));
}
/// Ditto
void shutdown()
{
	auto result = sqlite3_shutdown();
	enforce(result == SQLITE_OK, new SqliteException("Shutdown: error %s".format(result)));
}

/++
Sets a configuration option. Use before initialization, e.g. before the first
call to initialize and before execution of the first statement.

See_Also: $(LINK http://www.sqlite.org/c3ref/config.html).
+/
void config(Args...)(int code, Args args)
{
	auto result = sqlite3_config(code, args);
	enforce(result == SQLITE_OK,
			new SqliteException("Configuration: error %s".format(result)));
}
version (D_Ddoc)
{
	///
	unittest
	{
		config(SQLITE_CONFIG_MULTITHREAD);

		// Setup a logger callback function
		config(SQLITE_CONFIG_LOG,
			function(void* p, int code, const(char*) msg)
			{
				import std.stdio;
				writefln("%05d | %s", code, msg.to!string);
			},
			null);
		initialize();
	}
}
else
{
	unittest
	{
		shutdown();
		config(SQLITE_CONFIG_MULTITHREAD);
		config(SQLITE_CONFIG_LOG, function(void* p, int code, const(char*) msg) {}, null);
		initialize();
	}
}


/++
A caracteristic of user-defined functions or aggregates.
+/
enum Deterministic
{
	/++
	The returned value is the same if the function is called with the same parameters.
	+/
	yes = 0x800,

	/++
	The returned value can vary even if the function is called with the same parameters.
	+/
	no = 0
}


/++
An SQLite database connection.

This struct is a reference-counted wrapper around a $(D sqlite3*) pointer.
+/
struct Database
{
private:
	struct _Payload
	{
		sqlite3* handle;
		void* progressHandler;

		this(sqlite3* handle) @safe pure nothrow
		{
			this.handle = handle;
		}

		~this()
		{
			if (handle)
			{
				auto result = sqlite3_close(handle);
				enforce(result == SQLITE_OK, new SqliteException(errmsg(handle), result));
			}
			handle = null;
			ptrFree(progressHandler);
		}

		@disable this(this);
		void opAssign(_Payload) { assert(false); }
	}

	alias Payload = RefCounted!(_Payload, RefCountedAutoInitialize.no);
	Payload p;

	void check(int result) {
		enforce(result == SQLITE_OK, new SqliteException(errmsg(p.handle), result));
	}

public:
	/++
	Opens a database connection.

	Params:
		path = The path to the database file. In recent versions of SQLite, the path can be
		an URI with options.

		flags = Options flags.

	See_Also: $(LINK http://www.sqlite.org/c3ref/open.html) to know how to use the flags
	parameter or to use path as a file URI if the current configuration allows it.
	+/
	this(string path, int flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE)
	{
		sqlite3* hdl;
		auto result = sqlite3_open_v2(path.toStringz, &hdl, flags, null);
		enforce(result == SQLITE_OK, new SqliteException(p.handle
				? errmsg(p.handle) : "Error opening the database", result));
		p = Payload(hdl);
	}

	/++
	Gets the SQLite internal _handle of the database connection.
	+/
	sqlite3* handle() @property @safe pure nothrow
	{
		return p.handle;
	}

	/++
	Gets the path associated with an attached database.

	Params:
		database = The name of an attached database.

	Returns: The absolute path of the attached database.
		If there is no attached database, or if database is a temporary or
		in-memory database, then null is returned.
	+/
	string attachedFilePath(string database = "main")
	{
		return sqlite3_db_filename(p.handle, database.toStringz).to!string;
	}

	/++
	Gets the read-only status of an attached database.

	Params:
		database = The name of an attached database.
	+/
	bool isReadOnly(string database = "main")
	{
		int ret = sqlite3_db_readonly(p.handle, database.toStringz);
		enforce(ret >= 0, new SqliteException("Database not found: %s".format(database)));
		return ret == 1;
	}

	/++
	Gets metadata for a specific table column of an attached database.

	Params:
		table = The name of the table.

		column = The name of the column.

		database = The name of a database attached. If null, then all attached databases
		are searched for the table using the same algorithm used by the database engine
		to resolve unqualified table references.
	+/
	ColumnMetadata tableColumnMetadata(string table, string column, string database = "main")
	{
		ColumnMetadata data;
		char* pzDataType, pzCollSeq;
		int notNull, primaryKey, autoIncrement;
		check(sqlite3_table_column_metadata(p.handle, database.toStringz, table.toStringz,
			column.toStringz, &pzDataType, &pzCollSeq, &notNull, &primaryKey, &autoIncrement));
		data.declaredTypeName = pzDataType.to!string;
		data.collationSequenceName = pzCollSeq.to!string;
		data.isNotNull = cast(bool) notNull;
		data.isPrimaryKey = cast(bool) primaryKey;
		data.isAutoIncrement = cast(bool) autoIncrement;
		return data;
	}
	unittest
	{
		auto db = Database(":memory:");
		db.run("CREATE TABLE test (id INTEGER PRIMARY KEY AUTOINCREMENT,
				val FLOAT NOT NULL)");
		assert(db.tableColumnMetadata("test", "id") ==
			   ColumnMetadata("INTEGER", "BINARY", false, true, true));
		assert(db.tableColumnMetadata("test", "val") ==
			   ColumnMetadata("FLOAT", "BINARY", true, false, false));
	}

	/++
	Explicitly closes the database.

	After this function has been called successfully, using the database or one of its
	prepared statement is an error.
	+/
	void close()
	{
		check(sqlite3_close(handle));
		p.handle = null;
	}

	/++
	Executes a single SQL statement and returns the results directly. It's the equivalent
	of $(D prepare(sql).execute()).

	The results become undefined when the Database goes out of scope and is destroyed.
	+/
	ResultRange execute(string sql)
	{
		return prepare(sql).execute();
	}
	///
	unittest
	{
		auto db = Database(":memory:");
		db.execute("VACUUM");
	}

	/++
	Runs an SQL script that can contain multiple statements.

	Params:
		sql = The code of the script.

		dg = A delegate to call for each statement to handle the results. The passed
		ResultRange will be empty if a statement doesn't return rows. If the delegate
		return false, the execution is aborted.
	+/
	void run(string sql, scope bool delegate(ResultRange) dg = null)
	{
		foreach (statement; sql.byStatement)
		{
			auto stmt = prepare(statement);
			auto results = stmt.execute();
			if (dg && !dg(results))
				return;
		}
	}
	///
	unittest
	{
		auto db = Database(":memory:");
		db.run(`CREATE TABLE test1 (val INTEGER);
				CREATE TABLE test2 (val FLOAT);
				DROP TABLE test1;
				DROP TABLE test2;`);
	}

	/++
	Prepares (compiles) a single SQL statement and returngs it, so that it can be bound to
	values before execution.

	The statement becomes invalid if the Database goes out of scope and is destroyed.
	+/
	Statement prepare(string sql)
	{
		return Statement(this, sql);
	}

	/// Convenience functions equivalent to an SQL statement.
	void begin() { execute("BEGIN"); }
	/// Ditto
	void commit() { execute("COMMIT"); }
	/// Ditto
	void rollback() { execute("ROLLBACK"); }

	/++
	Returns the rowid of the last INSERT statement.
	+/
	long lastInsertRowid()
	{
		return sqlite3_last_insert_rowid(p.handle);
	}

	/++
	Gets the number of database rows that were changed, inserted or deleted by the most
	recently executed SQL statement.
	+/
	int changes() @property nothrow
	{
		assert(p.handle);
		return sqlite3_changes(p.handle);
	}

	/++
	Gets the number of database rows that were changed, inserted or deleted since the
	database was opened.
	+/
	int totalChanges() @property nothrow
	{
		assert(p.handle);
		return sqlite3_total_changes(p.handle);
	}

	/++
	Gets the SQLite error code of the last operation.
	+/
	int errorCode() @property nothrow
	{
		return p.handle ? sqlite3_errcode(p.handle) : 0;
	}

	version (SQLITE_OMIT_LOAD_EXTENSION) {}
	else
	{
		/++
		Enables or disables loading extensions.
		+/
		void enableLoadExtensions(bool enable = true)
		{
			enforce(sqlite3_enable_load_extension(p.handle, enable) == SQLITE_OK,
				new SqliteException("Could not enable loading extensions."));
		}

		/++
		Loads an extension.

		Params:
			path = The path of the extension file.

			entryPoint = The name of the entry point function. If null is passed, SQLite
			uses the name of the extension file as the entry point.
		+/
		void loadExtension(string path, string entryPoint = null)
		{
			auto ret = sqlite3_load_extension(p.handle, path.toStringz, entryPoint.toStringz, null);
			enforce(ret == SQLITE_OK, new SqliteException(
					"Could not load extension: %s:%s".format(entryPoint, path)));
		}
	}

	/++
	Creates and registers a new function in the database.

	If a function with the same name and the same arguments already exists, it is replaced
	by the new one.

	The memory associated with the function will be released when the database connection
	is closed.

	Params:
		name = The name that the function will have in the database; this name defaults to
		the identifier of $(D_PARAM fun).

		fun = a $(D delegate) or $(D function) that implements the function. $(D_PARAM fun)
		must satisfy these criteria:
			$(UL
				$(LI It must not be a variadic.)
				$(LI Its arguments must all have a type that is compatible with SQLite types:
				it must be a boolean or numeric type, a string, an array, null,
				or a Nullable!T where T is any of the previous types.)
				$(LI Its return value must also be of a compatible type.)
			)

		det = Tells SQLite whether the result of the function is deterministic, i.e. if the
		result is the same when called with the same parameters. Recent versions of SQLite
		perform optimizations based on this. Set to $(D Deterministic.no) otherwise.

	See_Also: $(LINK http://www.sqlite.org/c3ref/create_function.html).
	+/
	void createFunction(string name, T)(T fun, Deterministic det = Deterministic.yes)
	{
		static assert(isCallable!fun, "expecting a callable");
		static assert(variadicFunctionStyle!(fun) == Variadic.no,
			"variadic functions are not supported");

		alias ReturnType!fun RT;
		static assert(!is(RT == void), "function must not return void");

		alias PT = staticMap!(Unqual, ParameterTypeTuple!fun);

		extern(C) static
		void x_func(sqlite3_context* context, int argc, sqlite3_value** argv)
		{
			PT args;

			foreach (i, type; PT)
				args[i] = getValue!type(argv[i]);

			auto ptr = sqlite3_user_data(context);

			try
				setResult(context, delegateUnwrap!T(ptr)(args));
			catch (Exception e)
			{
				auto txt = "error in function %s(): %s".format(name, e.msg);
				sqlite3_result_error(context, txt.toStringz, -1);
			}
		}

		assert(p.handle);
		check(sqlite3_create_function_v2(p.handle, name.toStringz, PT.length, SQLITE_UTF8 | det,
			delegateWrap(fun), &x_func, null, null, &ptrFree));
	}
	///
	unittest
	{
		string fmt = "Hello, %s!";
		string my_msg(string name)
		{
			return fmt.format(name);
		}
		auto db = Database(":memory:");
		db.createFunction!"msg"(&my_msg);
		auto msg = db.execute("SELECT msg('John')").oneValue!string;
		assert(msg == "Hello, John!");
	}

	/++
	Creates and registers a new aggregate function in the database.

	Params:
		T = The $(D struct) type implementing the aggregate. T must be default-construtible
		(a POD type) and implement at least these two methods: $(D accumulate) and $(D result).
		Each parameter and the returned type of $(D accumulate) and $(D result) must be
		a boolean or numeric type, a string, an array, null, or a Nullable!T
		where T is any of the previous types.

		name = The name that the aggregate function will have in the database.

		det = Tells SQLite whether the result of the function is deterministic, i.e. if the
		result is the same when called with the same parameters. Recent versions of SQLite
		perform optimizations based on this. Set to $(D Deterministic.no) otherwise.

	See_Also: $(LINK http://www.sqlite.org/c3ref/create_function.html).
	+/
	void createAggregate(T, string name)(Deterministic det = Deterministic.yes)
	{
		static assert(isAggregateType!T,
			name ~ " should be an aggregate type");
		static assert(__traits(isPOD, T),
			name ~ " should be a POD type");
		static assert(is(typeof(T.accumulate) == function),
			name ~ " shoud have a method named accumulate");
		static assert(is(typeof(T.result) == function),
			name ~ " shoud have a method named result");
		static assert(variadicFunctionStyle!(T.accumulate) == Variadic.no,
			"variadic functions are not supported");
		static assert(variadicFunctionStyle!(T.result) == Variadic.no,
			"variadic functions are not supported");

		alias staticMap!(Unqual, ParameterTypeTuple!(T.accumulate)) PT;
		alias ReturnType!(T.result) RT;

		extern(C) static
		void x_step(sqlite3_context* context, int argc, sqlite3_value** argv)
		{
			auto aggregate = cast(T*) sqlite3_aggregate_context(context, T.sizeof);
			if (!aggregate)
			{
				sqlite3_result_error_nomem(context);
				return;
			}

			PT args;
			foreach (i, type; PT)
				args[i] = getValue!type(argv[i]);

			try
				aggregate.accumulate(args);
			catch (Exception e)
			{
				auto txt = "error in aggregate function %s(): %s".format(name, e.msg);
				sqlite3_result_error(context, txt.toStringz, -1);
			}
		}

		extern(C) static
		void x_final(sqlite3_context* context)
		{
			auto aggregate = cast(T*) sqlite3_aggregate_context(context, T.sizeof);
			if (!aggregate)
			{
				sqlite3_result_error_nomem(context);
				return;
			}

			try
				setResult(context, aggregate.result());
			catch (Exception e)
			{
				auto txt = "error in aggregate function %s(): %s".format(name, e.msg);
				sqlite3_result_error(context, txt.toStringz, -1);
			}
		}

		assert(p.handle);
		check(sqlite3_create_function_v2(p.handle, name.toStringz, PT.length, SQLITE_UTF8 | det,
			null, null, &x_step, &x_final, null));
	}
	///
	unittest // Aggregate creation
	{
		import std.array : appender, join;

		static struct Joiner
		{
			Appender!(string[]) app;
			string separator;

			void accumulate(string word, string sep)
			{
				separator = sep;
				app.put(word);
			}

			string result()
			{
				return join(app.data, separator);
			}
		}

		auto db = Database(":memory:");
		db.execute("CREATE TABLE test (word TEXT)");
		db.createAggregate!(Joiner, "strjoin");

		auto statement = db.prepare("INSERT INTO test VALUES (?)");
		auto list = ["My", "cat", "is", "black"];
		foreach (word; list)
		{
			statement.bind(1, word);
			statement.execute();
			statement.reset();
		}

		auto text = db.execute("SELECT strjoin(word, '-') FROM test").oneValue!string;
		assert(text == "My-cat-is-black");
	}

	/++
	Creates and registers a collation function in the database.

	Params:
		fun = An alias to the D implementation of the function. The function $(D_PARAM fun)
		must satisfy these criteria:
			$(UL
				$(LI If s1 is less than s2, $(D ret < 0).)
				$(LI If s1 is equal to s2, $(D ret == 0).)
				$(LI If s1 is greater than s2, $(D ret > 0).)
				$(LI If s1 is equal to s2, then s2 is equal to s1.)
				$(LI If s1 is equal to s2 and s2 is equal to s3, then s1 is equal to s3.)
				$(LI If s1 is less than s2, then s2 is greater than s1.)
				$(LI If s1 is less than s2 and s2 is less than s3, then s1 is less than s3.)
			)

		name = The name that the function will have in the database; this name defaults to
		the identifier of $(D_PARAM fun).

	See_Also: $(LINK http://www.sqlite.org/lang_aggfunc.html)
	+/
	void createCollation(string name, T)(T fun)
	{
		static assert(isCallable!fun, "expecting a callable");
		static assert(variadicFunctionStyle!(fun) == Variadic.no,
			"variadic functions are not supported");

		alias ParameterTypeTuple!fun PT;
		static assert(isSomeString!(PT[0]),
			"the first argument of function " ~ name ~ " should be a string");
		static assert(isSomeString!(PT[1]),
			"the second argument of function " ~ name ~ " should be a string");
		static assert(isImplicitlyConvertible!(ReturnType!fun, int),
			"function " ~ name ~ " should return a value convertible to an int");

		extern (C) static
		int x_compare(void* ptr, int n1, const(void*) str1, int n2, const(void*) str2)
		{
			auto dg = delegateUnwrap!T(ptr);
			char[] s1, s2;
			s1.length = n1;
			s2.length = n2;
			memcpy(s1.ptr, str1, n1);
			memcpy(s2.ptr, str2, n2);
			return dg(cast(immutable) s1, cast(immutable) s2);
		}

		assert(p.handle);
		check(sqlite3_create_collation_v2(p.handle, name.toStringz, SQLITE_UTF8,
			delegateWrap(fun), &x_compare, &ptrFree));
	}
	///
	unittest // Collation creation
	{
		static int my_collation(string s1, string s2)
		{
			import std.uni;
			return icmp(s1, s2);
		}

		auto db = Database(":memory:");
		db.createCollation!"my_coll"(&my_collation);
		db.execute("CREATE TABLE test (word TEXT)");

		auto statement = db.prepare("INSERT INTO test (word) VALUES (?)");
		foreach (word; ["straße", "strasses"])
		{
			statement.bind(1, word);
			statement.execute();
			statement.reset();
		}

		auto word = db.execute("SELECT word FROM test ORDER BY word COLLATE my_coll")
					  .oneValue!string;
		assert(word == "straße");
	}

	/++
	Registers a delegate as the database's update hook. Any previously set hook is released.

	See_Also: $(LINK http://www.sqlite.org/c3ref/commit_hook.html).
	+/
	void setUpdateHook(scope void delegate(int type, string dbName, string tableName, long rowid) hook)
	{
		extern(C) static
		void callback(void* ptr, int type, char* dbName, char* tableName, long rowid)
		{
			return delegateUnwrap!(void delegate(int, string, string, long))(ptr)(
				type, dbName.to!string, tableName.to!string, rowid);
		}

		auto ptr = delegateWrap(hook);
		auto prev = sqlite3_update_hook(p.handle, &callback, ptr);
		ptrFree(prev);
	}
	///
	unittest
	{
		int i;
		auto db = Database(":memory:");
		db.setUpdateHook((int type, string dbName, string tableName, long rowid) {
			assert(type == SQLITE_INSERT);
			assert(dbName == "main");
			assert(tableName == "test");
			assert(rowid == 1);
			i = 42;
		});
		db.execute("CREATE TABLE test (val INTEGER)");
		db.execute("INSERT INTO test VALUES (100)");
		assert(i == 42);
	}

	/++
	Registers a delegate as the database's commit or rollback hook.
	Any previously set hook is released.

	Params:
		hook = For the commit hook, a delegate that should return 0 if the operation must be
		aborted or another value if it can continue.

	See_Also: $(LINK http://www.sqlite.org/c3ref/commit_hook.html).
	+/
	void setCommitHook(int delegate() hook)
	{
		extern(C) static int callback(void* ptr)
		{
			return delegateUnwrap!(int delegate())(ptr)();
		}

		auto ptr = delegateWrap(hook);
		auto prev = sqlite3_commit_hook(p.handle, &callback, ptr);
		ptrFree(prev);
	}
	/// Ditto
	void setRollbackHook(void delegate() hook)
	{
		extern(C) static void callback(void* ptr)
		{
			delegateUnwrap!(void delegate())(ptr)();
		}

		auto ptr = delegateWrap(hook);
		auto prev = sqlite3_rollback_hook(p.handle, &callback, ptr);
		ptrFree(prev);
	}
	///
	unittest
	{
		int i;
		auto db = Database(":memory:");
		db.setCommitHook({ i = 42; return SQLITE_OK; });
		db.setRollbackHook({ i = 666; });
		db.begin();
		db.execute("CREATE TABLE test (val INTEGER)");
		db.rollback();
		assert(i == 666);
		db.begin();
		db.execute("CREATE TABLE test (val INTEGER)");
		db.commit();
		assert(i == 42);
	}

	/++
	Sets the progress handler.
	Any previously set handler is released.

	Params:
		pace = The approximate number of virtual machine instructions that are
		evaluated between successive invocations of the handler.

		handler = A delegate that should return 0 if the operation must be
		aborted or another value if it can continue.

	See_Also: $(LINK http://www.sqlite.org/c3ref/commit_hook.html).
	+/
	void setProgressHandler(int pace, int delegate() handler)
	{
		extern(C) static int callback(void* ptr)
		{
			return delegateUnwrap!(int delegate())(ptr)();
		}

		ptrFree(p.progressHandler);
		auto ptr = delegateWrap(handler);
		sqlite3_progress_handler(p.handle, pace, &callback, ptr);
		p.progressHandler = ptr;
	}
}
///
unittest // Documentation example
{
	// Note: exception handling is left aside for clarity.

	import std.typecons : Nullable;

	// Open a database in memory.
	auto db = Database(":memory:");

	// Create a table
	db.execute(
		"CREATE TABLE person (
			id INTEGER PRIMARY KEY,
			name TEXT NOT NULL,
			score FLOAT
		 )"
	);

	// Populate the table

	// Prepare an INSERT statement
	auto statement = db.prepare(
		"INSERT INTO person (name, score)
		 VALUES (:name, :score)"
	);

	// Bind values one by one (by parameter name or index)
	statement.bind(":name", "John");
	statement.bind(2, 77.5);
	statement.execute();

	statement.reset(); // Need to reset the statement after execution.

	// Bind muliple values at once
	statement.bindAll("John", null);
	statement.execute();

	// Count the changes
	assert(db.totalChanges == 2);

	// Count the Johns in the table.
	auto count = db.execute("SELECT count(*) FROM person WHERE name == 'John'")
				   .oneValue!long;
	assert(count == 2);

	// Read the data from the table lazily
	auto results = db.execute("SELECT * FROM person");
	foreach (row; results)
	{
		// Retrieve "id", which is the column at index 0, and contains an int,
		// e.g. using the peek function (best performance).
		auto id = row.peek!long(0);

		// Retrieve "name", e.g. using opIndex(string), which returns a ColumnData.
		auto name = row["name"].as!string;

		// Retrieve "score", which is at index 3, e.g. using the peek function,
		// using a Nullable type
		auto score = row.peek!(Nullable!double)(3);
		if (!score.isNull) {
			// ...
		}
	}

	// Read all the table in memory at once
	auto data = RowCache(db.execute("SELECT * FROM person"));
	foreach (row; data)
	{
		auto id = row[0].as!long;
		auto last = row["name"].as!string;
		auto score = row[2].as!(Nullable!double);
		// etc.
	}
}

unittest // Database construction
{
	Database db1;
	auto db2 = db1;
	db1 = Database(":memory:");
	db2 = Database("");
	auto db3 = Database(null);
	db1 = db2;
	assert(db2.p.refCountedStore.refCount == 2);
	assert(db1.p.refCountedStore.refCount == 2);
}

unittest
{
	auto db = Database(":memory:");
	assert(db.attachedFilePath("main") is null);
	assert(!db.isReadOnly);
	db.close();
}


unittest // Execute an SQL statement
{
	auto db = Database(":memory:");
	db.run("");
	db.run("-- This is a comment!");
	db.run(";");
	db.run("ANALYZE; VACUUM;");
}

version (DigitalMars) unittest // Unexpected multiple statements
{
	auto db = Database(":memory:");
	db.execute("BEGIN; CREATE TABLE test (val INTEGER); ROLLBACK;");
	//assertThrown(db.execute("DROP TABLE test"));

	db.execute("CREATE TABLE test (val INTEGER); DROP TABLE test;");
	assertNotThrown(db.execute("DROP TABLE test;"));

	db.execute("SELECT 1; CREATE TABLE test (val INTEGER); DROP TABLE test;");
	//assertThrown(db.execute("DROP TABLE test"));
}

unittest // Multiple statements with callback
{
	auto db = Database(":memory:");
	RowCache[] rows;
	db.run("SELECT 1, 2, 3; SELECT 'A', 'B', 'C';", (ResultRange r) {
		rows ~= RowCache(r);
		return true;
	});
	assert(equal!"a.as!int == b"(rows[0][0], [1, 2, 3]));
	assert(equal!"a.as!string == b"(rows[1][0], ["A", "B", "C"]));
}

unittest // Different arguments and result types with createFunction
{
	import std.math;

	auto db = Database(":memory:");

	T display(T)(T value)
	{
		return value;
	}

	db.createFunction!"display_integer"(&display!int);
	db.createFunction!"display_float"(&display!double);
	db.createFunction!"display_text"(&display!string);
	db.createFunction!"display_blob"(&display!(ubyte[]));

	assert(db.execute("SELECT display_integer(42)").oneValue!int == 42);
	assert(db.execute("SELECT display_float(3.14)").oneValue!double == 3.14);
	assert(db.execute("SELECT display_text('ABC')").oneValue!string == "ABC");
	assert(db.execute("SELECT display_blob(x'ABCD')").oneValue!(ubyte[]) == cast(ubyte[]) x"ABCD");

	assert(db.execute("SELECT display_integer(NULL)").oneValue!int == 0);
	assert(db.execute("SELECT display_float(NULL)").oneValue!double.isNaN);
	assert(db.execute("SELECT display_text(NULL)").oneValue!string is null);
	assert(db.execute("SELECT display_blob(NULL)").oneValue!(ubyte[]) is null);
}

unittest // Different Nullable argument types with createFunction
{
	import std.math;

	auto db = Database(":memory:");

	auto display(T : Nullable!U, U...)(T value)
	{
		if (value.isNull)
			return T();
		return value;
	}

	db.createFunction!"display_integer"(&display!(Nullable!int));
	db.createFunction!"display_float"(&display!(Nullable!double));
	db.createFunction!"display_text"(&display!(Nullable!string));
	db.createFunction!"display_blob"(&display!(Nullable!(ubyte[])));

	assert(db.execute("SELECT display_integer(42)").oneValue!(Nullable!int) == 42);
	assert(db.execute("SELECT display_float(3.14)").oneValue!(Nullable!double) == 3.14);
	assert(db.execute("SELECT display_text('ABC')").oneValue!(Nullable!string) == "ABC");
	assert(db.execute("SELECT display_blob(x'ABCD')").oneValue!(Nullable!(ubyte[])) == cast(ubyte[]) x"ABCD");

	assert(db.execute("SELECT display_integer(NULL)").oneValue!(Nullable!int).isNull);
	assert(db.execute("SELECT display_float(NULL)").oneValue!(Nullable!double).isNull);
	assert(db.execute("SELECT display_text(NULL)").oneValue!(Nullable!string).isNull);
	assert(db.execute("SELECT display_blob(NULL)").oneValue!(Nullable!(ubyte[])).isNull);
}


/++
An SQLite statement execution.

This struct is a reference-counted wrapper around a $(D sqlite3_stmt*) pointer. Instances
of this struct are typically returned by $(D Database.prepare()).
+/
struct Statement
{
private:
	struct _Payload
	{
		Database db;
		sqlite3_stmt* handle; // null if error or empty statement

		~this()
		{
			auto result = sqlite3_finalize(handle);
			enforce(result == SQLITE_OK, new SqliteException(errmsg(handle), result));
			handle = null;
		}

		@disable this(this);
		void opAssign(_Payload) { assert(false); }
	}
	alias Payload = RefCounted!(_Payload, RefCountedAutoInitialize.no);
	Payload p;

	this(Database db, string sql)
	{
		sqlite3_stmt* handle;
		const(char*) ptail;
		auto result = sqlite3_prepare_v2(db.handle(), sql.toStringz, sql.length.to!int,
			&handle, null);
		enforce(result == SQLITE_OK, new SqliteException(errmsg(db.handle()), result, sql));
		p = Payload(db, handle);
	}

	void checkResult(int result)
	{
		enforce(result == SQLITE_OK, new SqliteException(errmsg(p.handle), result));
	}

public:
	/++
	Gets the SQLite internal _handle of the statement.
	+/
	sqlite3_stmt* handle() @property
	{
		return p.handle;
	}

	/++
	Tells whether the statement is empty (no SQL statement).
	+/
	bool empty() @property
	{
		return p.handle is null;
	}
	///
	unittest
	{
		auto db = Database(":memory:");
		auto statement = db.prepare(" ; ");
		assert(statement.empty);
	}

	/++
	Binds values to parameters of this statement.

	Params:
		index = The index of the parameter (starting from 1).

		value = The bound _value. The type of value must be compatible with the SQLite
		types: it must be a boolean or numeric type, a string, an array, null,
		or a Nullable!T where T is any of the previous types.
	+/
	void bind(T)(int index, T value)
		if (is(T == typeof(null)) || is(T == void*))
	{
		assert(p.handle, "Operation on an empty statement");
		checkResult(sqlite3_bind_null(p.handle, index));
	}

	/// ditto
	void bind(T)(int index, T value)
		if (isIntegral!T || isSomeChar!T)
	{
		assert(p.handle, "Operation on an empty statement");
		checkResult(sqlite3_bind_int64(p.handle, index, value.to!long));
	}

	/// ditto
	void bind(T)(int index, T value)
		if (isBoolean!T)
	{
		assert(p.handle, "Operation on an empty statement");
		checkResult(sqlite3_bind_int(p.handle, index, value.to!T));
	}

	/// ditto
	void bind(T)(int index, T value)
		if (isFloatingPoint!T)
	{
		assert(p.handle, "Operation on an empty statement");
		checkResult(sqlite3_bind_double(p.handle, index, value.to!double));
	}

	/// ditto
	void bind(T)(int index, T value)
		if (isSomeString!T)
	{
		assert(p.handle, "Operation on an empty statement");
		string str = value.to!string;
		auto ptr = anchorMem(cast(void*) str.ptr);
		checkResult(sqlite3_bind_text64(p.handle, index, cast(const(char)*) ptr, str.length, &releaseMem, SQLITE_UTF8));
	}

	/// ditto
	void bind(T)(int index, T value)
		if (isStaticArray!T)
	{
		assert(p.handle, "Operation on an empty statement");
		checkResult(sqlite3_bind_blob64(p.handle, index, cast(void*) value.ptr, value.sizeof, SQLITE_TRANSIENT));
	}

	/// ditto
	void bind(T)(int index, T value)
		if (isDynamicArray!T && !isSomeString!T)
	{
		assert(p.handle, "Operation on an empty statement");
		auto arr = cast(void[]) value;
		checkResult(sqlite3_bind_blob64(p.handle, index, anchorMem(arr.ptr), arr.length, &releaseMem));
	}

	/// ditto
	void bind(T)(int index, T value)
		if (is(T == Nullable!U, U...))
	{
		if (value.isNull)
		{
			assert(p.handle, "Operation on an empty statement");
			checkResult(sqlite3_bind_null(p.handle, index));
		}
		else
			bind(index, value.get);
	}

	/++
	Binds values to parameters of this statement.

	Params:
		name = The name of the parameter, including the ':', '@' or '$' that introduced it.

		value = The bound _value. The type of value must be compatible with the SQLite
		types: it must be a boolean or numeric type, a string, an array, null,
		or a Nullable!T where T is any of the previous types.

	Warning:
		While convenient, this overload of $(D bind) is less performant, because it has to
		retrieve the column index with a call to the SQLite function $(D
		sqlite3_bind_parameter_index).
	+/
	void bind(T)(string name, T value)
	{
		auto index = sqlite3_bind_parameter_index(p.handle, name.toStringz);
		enforce(index > 0, new SqliteException(format("no parameter named '%s'", name)));
		bind(index, value);
	}

	/++
	Binds all the arguments at once in order.
	+/
	void bindAll(Args...)(Args args)
	{
		foreach (index, _; Args)
			bind(index + 1, args[index]);
	}

	/++
	Clears the bindings.

	This does not reset the statement. Use $(D Statement.reset()) for this.
	+/
	void clearBindings()
	{
		assert(p.handle, "Operation on an empty statement");
		checkResult(sqlite3_clear_bindings(p.handle));
	}

	/++
	Executes the statement and return a (possibly empty) range of results.
	+/
	ResultRange execute()
	{
		return ResultRange(this);
	}

	/++
	Resets a this statement before a new execution.

	Calling this method invalidates any $(D ResultRange) struct returned by a previous call
	to $(D Database.execute()) or $(D Statement.execute()).

	This does not clear the bindings. Use $(D Statement.clear()) for this.
	+/
	void reset()
	{
		assert(p.handle, "Operation on an empty statement");
		checkResult(sqlite3_reset(p.handle));
	}

	/++
	Convenience function equivalent of:
	---
	bindAll(args);
	execute();
	reset();
	---
	+/
	void inject(Args...)(Args args)
	{
		bindAll(args);
		execute();
		reset();
	}

	/// Gets the count of bind parameters.
	int parameterCount() nothrow
	{
		if (p.handle)
			return sqlite3_bind_parameter_count(p.handle);
		else
			return 0;
	}

	/++
	Gets the name of the bind parameter at the given index.

	Returns: The name of the parameter or null is not found or out of range.
	+/
	string parameterName(int index)
	{
		assert(p.handle, "Operation on an empty statement");
		return sqlite3_bind_parameter_name(p.handle, index).to!string;
	}

	/++
	Gets the index of a bind parameter.

	Returns: The index of the parameter (the first parameter has the index 1)
	or 0 is not found or out of range.
	+/
	int parameterIndex(string name)
	{
		assert(p.handle, "Operation on an empty statement");
		return sqlite3_bind_parameter_index(p.handle, name.toStringz);
	}
}

unittest
{
  Statement statement;
  {
	auto db = Database(":memory:");
	statement = db.prepare(" SELECT 42 ");
  }
  assert(statement.execute.oneValue!int == 42);
}

unittest // Simple parameters binding
{
	auto db = Database(":memory:");
	db.execute("CREATE TABLE test (val INTEGER)");

	auto statement = db.prepare("INSERT INTO test (val) VALUES (?)");
	statement.bind(1, 42);
	statement.execute();
	statement.reset();
	statement.bind(1, 42);
	statement.execute();

	assert(db.lastInsertRowid == 2);
	assert(db.changes == 1);
	assert(db.totalChanges == 2);

	auto results = db.execute("SELECT * FROM test");
	foreach (row; results)
		assert(row.peek!int(0) == 42);
}

unittest // Multiple parameters binding
{
	auto db = Database(":memory:");
	db.execute("CREATE TABLE test (i INTEGER, f FLOAT, t TEXT)");
	auto statement = db.prepare("INSERT INTO test (i, f, t) VALUES (:i, @f, $t)");
	assert(statement.parameterCount == 3);
	statement.bind("$t", "TEXT");
	statement.bind(":i", 42);
	statement.bind("@f", 3.14);
	statement.execute();
	statement.reset();
	statement.bind(1, 42);
	statement.bind(2, 3.14);
	statement.bind(3, "TEXT");
	statement.execute();

	auto results = db.execute("SELECT * FROM test");
	foreach (row; results)
	{
		assert(row.length == 3);
		assert(row.peek!int("i") == 42);
		assert(row.peek!double("f") == 3.14);
		assert(row.peek!string("t") == "TEXT");
	}
}

unittest // Multiple parameters binding: tuples
{
	auto db = Database(":memory:");
	db.execute("CREATE TABLE test (i INTEGER, f FLOAT, t TEXT)");
	auto statement = db.prepare("INSERT INTO test (i, f, t) VALUES (?, ?, ?)");
	statement.bindAll(42, 3.14, "TEXT");
	statement.execute();

	auto results = db.execute("SELECT * FROM test");
	foreach (row; results)
	{
		assert(row.length == 3);
		assert(row.peek!int(0) == 42);
		assert(row.peek!double(1) == 3.14);
		assert(row.peek!string(2) == "TEXT");
	}
}

unittest // Static array binding
{
	ubyte[3] data = [1,2,3];

	auto db = Database(":memory:");
	db.execute("CREATE TABLE test (a BLOB)");
	auto statement = db.prepare("INSERT INTO test (a) VALUES (?)");
	statement.bind(1, data);
	statement.execute();

	auto results = db.execute("SELECT * FROM test");
	foreach (row; results)
	{
		assert(row.length == 1);
		auto rdata = row.peek!(ubyte[])(0);
		assert(rdata.length == 3);
		assert(rdata[0] == 1);
		assert(rdata[1] == 2);
		assert(rdata[2] == 3);
	}
}

unittest // Nullable binding
{
	auto db = Database(":memory:");
	db.execute("CREATE TABLE test (a, b, c, d, e);");

	auto statement = db.prepare("INSERT INTO test (a,b,c,d,e) VALUES (?,?,?,?,?)");
	statement.bind(1, Nullable!int(123));
	statement.bind(2, Nullable!int());
	statement.bind(3, Nullable!(uint, 0)(42));
	statement.bind(4, Nullable!(uint, 0)());
	statement.bind(5, Nullable!bool(false));
	statement.execute();

	auto results = db.execute("SELECT * FROM test");
	foreach (row; results)
	{
		assert(row.length == 5);
		assert(row.peek!int(0) == 123);
		assert(row.columnType(1) == SqliteType.NULL);
		assert(row.peek!int(2) == 42);
		assert(row.columnType(3) == SqliteType.NULL);
		assert(!row.peek!bool(4));
	}
}

unittest // Nullable peek
{
	auto db = Database(":memory:");
	auto results = db.execute("SELECT 1, NULL, 8.5, NULL");
	foreach (row; results)
	{
		assert(row.length == 4);
		assert(row.peek!(Nullable!double)(2).get == 8.5);
		assert(row.peek!(Nullable!double)(3).isNull);
		assert(row.peek!(Nullable!(int, 0))(0).get == 1);
		assert(row.peek!(Nullable!(int, 0))(1).isNull);
	}
}

unittest // GC anchoring test
{
	auto db = Database(":memory:");
	auto stmt = db.prepare("SELECT ?");

	auto str = ("I am test string").dup;
	stmt.bind(1, str);
	str = null;

	for(int i=0; i<3; i++) {
		GC.collect();
		GC.minimize();
	}

	ResultRange results = stmt.execute();
	foreach(row; results) {
		assert(row.length == 1);
		assert(row.peek!string(0) == "I am test string");
	}
}


/++
An input range interface to access the results of the execution of a statement.

The elements of the range are $(D Row) structs. A $(D Row) is just a view of the current
row when iterating the results of a $(D ResultRange). It becomes invalid as soon as $(D
ResultRange.popFront()) is called (it contains undefined data afterwards). Use $(D
RowCache) to store the content of rows past the execution of the statement.

Instances of this struct are typically returned by $(D Database.execute()) or $(D
Statement.execute()).
+/
struct ResultRange
{
private:
	struct _Payload
	{
		Statement statement;
		int state;

		@disable this(this);
		void opAssign(_Payload) { assert(false); }
	}
	alias Payload = RefCounted!(_Payload, RefCountedAutoInitialize.no);
	Payload p;

	this(Statement statement)
	{
		p = Payload(statement);
		if (!p.statement.empty)
			p.state = sqlite3_step(p.statement.handle);
		else
			p.state = SQLITE_DONE;

		enforce(p.state == SQLITE_ROW || p.state == SQLITE_DONE,
				new SqliteException(errmsg(p.statement.handle), p.state));
	}

public:
	/++
	Range primitives.
	+/
	bool empty() @property
	{
		assert(p.state);
		return p.state == SQLITE_DONE;
	}

	/// ditto
	Row front() @property
	{
		assert(p.state);
		enforce(!empty, new SqliteException("No rows available"));
		return Row(p.statement.handle);
	}

	/// ditto
	void popFront()
	{
		assert(p.state);
		enforce(!empty, new SqliteException("No rows available"));
		p.state = sqlite3_step(p.statement.handle);
		enforce(p.state == SQLITE_DONE || p.state == SQLITE_ROW,
				new SqliteException(errmsg(p.statement.handle), p.state));
	}

	/++
	Gets only the first value of the first row returned by the execution of the statement.
	+/
	auto oneValue(T)()
	{
		return front.peek!T(0);
	}
	///
	unittest // One value
	{
		auto db = Database(":memory:");
		db.execute("CREATE TABLE test (val INTEGER)");
		auto count = db.execute("SELECT count(*) FROM test").oneValue!long;
		assert(count == 0);
	}
}

unittest // Refcount tests
{
	auto db = Database(":memory:");
	{
		db.execute("CREATE TABLE test (val INTEGER)");
		auto tmp = db.prepare("INSERT INTO test (val) VALUES (?)");
		tmp.bind(1, 42);
		tmp.execute();
	}

	auto results = { return db.execute("SELECT * FROM test"); }();
	assert(!results.empty);
	assert(results.oneValue!int == 42);
	results.popFront();
	assert(results.empty);
}


/++
A SQLite row, implemented as a random-access range of ColumnData.
+/
struct Row
{
	private
	{
		sqlite3_stmt* statement;
		int frontIndex;
		int backIndex;
	}

	this(sqlite3_stmt* statement) nothrow
	{
		assert(statement);
		this.statement = statement;
		backIndex = sqlite3_column_count(statement) - 1;
	}

	/// Range interface.
	bool empty() @property @safe pure nothrow
	{
		return length == 0;
	}

	/// ditto
	ColumnData front() @property
	{
		return opIndex(0);
	}

	/// ditto
	void popFront() @safe pure nothrow
	{
		frontIndex++;
	}

	/// ditto
	Row save() @property @safe pure nothrow
	{
		Row ret;
		ret.statement = statement;
		ret.frontIndex = frontIndex;
		ret.backIndex = backIndex;
		return ret;
	}

	/// ditto
	ColumnData back() @property
	{
		return opIndex(backIndex - frontIndex);
	}

	/// ditto
	void popBack() @safe pure nothrow
	{
		backIndex--;
	}

	/// ditto
	int length() @property @safe pure nothrow
	{
		return backIndex - frontIndex + 1;
	}

	/// ditto
	ColumnData opIndex(int index)
	{
		auto i = internalIndex(index);
		enforce(i >= 0 && i <= backIndex,
				new SqliteException(format("invalid column index: %d", i)));

		auto type = sqlite3_column_type(statement, i);

		final switch (type)
		{
			case SqliteType.INTEGER:
				auto data = peek!(Nullable!long)(index);
				if (data.isNull)
					return ColumnData.init;
				return ColumnData(Variant(data.get));

			case SqliteType.FLOAT:
				auto data = peek!(Nullable!double)(index);
				if (data.isNull)
					return ColumnData.init;
				return ColumnData(Variant(data.get));

			case SqliteType.TEXT:
				auto data = peek!(Nullable!string)(index);
				if (data.isNull)
					return ColumnData.init;
				return ColumnData(Variant(data.get));

			case SqliteType.BLOB:
				auto data = peek!(Nullable!(ubyte[]))(index);
				if (data.isNull)
					return ColumnData.init;
				return ColumnData(Variant(data.get));

			case SqliteType.NULL:
				return ColumnData.init;
		}
	}

	/++
	Returns the data of a column as a $(D ColumnData).

	Params:
		columnName = The name of the column, as specified in the prepared statement with an AS
		clause.
	+/
	ColumnData opIndex(string columnName)
	{
		return opIndex(indexForName(columnName));
	}

	/++
	Returns the data of a column.

	Contrary to $(D opIndex), the $(D peek) functions return the data directly,
	automatically cast to T, without the overhead of using a wrapped $(D Variant)
	($(D ColumnData)).

	Params:
		T = The type of the returned data. T must be a boolean, a built-in numeric type, a
		string, an array or a Variant.

		index = The index of the column in the prepared statement or
		the name of the column, as specified in the prepared statement
		with an AS clause.

	Returns:
		A value of type T. The returned value is T.init if the data type is NULL.
		In all other cases, the data is fetched from SQLite (which returns a value
		depending on its own conversion rules;
		see $(LINK http://www.sqlite.org/c3ref/column_blob.html) and
		$(LINK http://www.sqlite.org/lang_expr.html#castexpr)), and it is converted
		to T using $(D std.conv.to!T).

		$(TABLE
		$(TR $(TH Condition on T)
			 $(TH Requested database type))
		$(TR $(TD isIntegral!T || isBoolean!T)
			 $(TD INTEGER, via $(D sqlite3_column_int64)))
		$(TR $(TD isFloatingPoint!T)
			 $(TD FLOAT, via $(D sqlite3_column_double)))
		$(TR $(TD isSomeString!T)
			 $(TD TEXT, via $(D sqlite3_column_text)))
		$(TR $(TD isArray!T)
			 $(TD BLOB, via $(D sqlite3_column_blob)))
		$(TR $(TD is(T == Nullable!U))
			 $(TD NULL or T))
		$(TR $(TD Other types)
			 $(TD Compilation error))
		)

	Warnings:
		The result is undefined if then index is out of range.

		If the second overload is used, the names of all the columns are
		tested each time this function is called: use
		numeric indexing for better performance.
	+/
	T peek(T)(int index)
		if (isBoolean!T || isIntegral!T)
	{
		return sqlite3_column_int64(statement, internalIndex(index)).to!T();
	}

	/// ditto
	T peek(T)(int index)
		if (isFloatingPoint!T)
	{
		auto i = internalIndex(index);
		if (sqlite3_column_type(statement, i) == SqliteType.NULL)
			return T.init;
		return sqlite3_column_double(statement, i).to!T();
	}

	/// ditto
	T peek(T)(int index)
		if (isSomeString!T)
	{
		return sqlite3_column_text(statement, internalIndex(index)).to!T;
	}

	/// ditto
	T peek(T)(int index)
		if (isArray!T && !isSomeString!T)
	{
		auto i = internalIndex(index);
		auto ptr = sqlite3_column_blob(statement, i);
		auto length = sqlite3_column_bytes(statement, i);
		ubyte[] blob;
		blob.length = length;
		memcpy(blob.ptr, ptr, length);
		return blob.to!T;
	}

	/// ditto
	T peek(T : Nullable!U, U...)(int index)
	{
		if (sqlite3_column_type(statement, internalIndex(index)) == SqliteType.NULL)
			return T();
		return T(peek!(U[0])(index));
	}

	/// ditto
	T peek(T)(string columnName)
	{
		return peek!T(indexForName(columnName));
	}

	/++
	Determines the type of a particular result column in SELECT statement.

	See_Also: $(D http://www.sqlite.org/c3ref/column_database_name.html).
	+/
	SqliteType columnType(int index)
	{
		return cast(SqliteType) sqlite3_column_type(statement, internalIndex(index));
	}
	/// Ditto
	SqliteType columnType(string columnName)
	{
		return columnType(indexForName(columnName));
	}

	version (SQLITE_ENABLE_COLUMN_METADATA)
	{
		/++
		Determines the name of the database, table, or column that is the origin of a
		particular result column in SELECT statement.

		See_Also: $(D http://www.sqlite.org/c3ref/column_database_name.html).
		+/
		string columnDatabaseName(int index)
		{
			return sqlite3_column_database_name(statement, internalIndex(index)).to!string;
		}
		/// Ditto
		string columnDatabaseName(string columnName)
		{
			return columnDatabaseName(indexForName(columnName));
		}
		/// Ditto
		string columnTableName(int index)
		{
			return sqlite3_column_database_name(statement, internalIndex(index)).to!string;
		}
		/// Ditto
		string columnTableName(string columnName)
		{
			return columnTableName(indexForName(columnName));
		}
		/// Ditto
		string columnOriginName(int index)
		{
			return sqlite3_column_origin_name(statement, internalIndex(index)).to!string;
		}
		/// Ditto
		string columnOriginName(string columnName)
		{
			return columnOriginName(indexForName(columnName));
		}
	}

	/++
	Determines the declared type name of a particular result column in SELECT statement.

	See_Also: $(D http://www.sqlite.org/c3ref/column_database_name.html).
	+/
	string columnDeclaredTypeName(int index)
	{
		return sqlite3_column_decltype(statement, internalIndex(index)).to!string;
	}
	/// Ditto
	string columnDeclaredTypeName(string columnName)
	{
		return columnDeclaredTypeName(indexForName(columnName));
	}

private:
	int internalIndex(int index)
	{
		return index + frontIndex;
	}

	int indexForName(string name)
	{
		foreach (i; frontIndex .. backIndex + 1)
			if (sqlite3_column_name(statement, i).to!string == name)
				return i;

		throw new SqliteException("invalid column name: '%s'".format(name));
	}
}

version (unittest)
{
	static assert(isRandomAccessRange!Row);
	static assert(is(ElementType!Row == ColumnData));
}

unittest // Peek
{
	auto db = Database(":memory:");
	db.execute("CREATE TABLE test (value)");
	auto statement = db.prepare("INSERT INTO test VALUES(?)");
	statement.inject(null);
	statement.inject(42);
	statement.inject(3.14);
	statement.inject("ABC");
	auto blob = cast(ubyte[]) x"DEADBEEF";
	statement.inject(blob);

	import std.math : isNaN;
	auto results = db.execute("SELECT * FROM test");
	auto row = results.front;
	assert(row.peek!long(0) == 0);
	assert(row.peek!double(0).isNaN);
	assert(row.peek!string(0) is null);
	assert(row.peek!(ubyte[])(0) is null);
	results.popFront();
	row = results.front;
	assert(row.peek!long(0) == 42);
	assert(row.peek!double(0) == 42);
	assert(row.peek!string(0) == "42");
	assert(row.peek!(ubyte[])(0) == cast(ubyte[]) "42");
	results.popFront();
	row = results.front;
	assert(row.peek!long(0) == 3);
	assert(row.peek!double(0) == 3.14);
	assert(row.peek!string(0) == "3.14");
	assert(row.peek!(ubyte[])(0) == cast(ubyte[]) "3.14");
	results.popFront();
	row = results.front;
	assert(row.peek!long(0) == 0);
	assert(row.peek!double(0) == 0.0);
	assert(row.peek!string(0) == "ABC");
	assert(row.peek!(ubyte[])(0) == cast(ubyte[]) "ABC");
	results.popFront();
	row = results.front;
	assert(row.peek!long(0) == 0);
	assert(row.peek!double(0) == 0.0);
	assert(row.peek!string(0) == x"DEADBEEF");
	assert(row.peek!(ubyte[])(0) == cast(ubyte[]) x"DEADBEEF");
}

unittest // Row random-access range interface
{
	auto db = Database(":memory:");

	{
		db.execute("CREATE TABLE test (a INTEGER, b INTEGER, c INTEGER, d INTEGER)");
		auto statement = db.prepare("INSERT INTO test VALUES(?, ?, ?, ?)");
		statement.bind(1, 1);
		statement.bind(2, 2);
		statement.bind(3, 3);
		statement.bind(4, 4);
		statement.execute();
		statement.reset();
		statement.bind(1, 5);
		statement.bind(2, 6);
		statement.bind(3, 7);
		statement.bind(4, 8);
		statement.execute();
	}

	{
		auto results = db.execute("SELECT * FROM test");
		auto values = [1, 2, 3, 4, 5, 6, 7, 8];
		foreach (row; results)
		{
			while (!row.empty)
			{
				assert(row.front.as!int == values.front);
				row.popFront();
				values.popFront();
			}
		}
	}

	{
		auto results = db.execute("SELECT * FROM test");
		auto values = [4, 3, 2, 1, 8, 7, 6, 5];
		foreach (row; results)
		{
			while (!row.empty)
			{
				assert(row.back.as!int == values.front);
				row.popBack();
				values.popFront();
			}
		}
	}

	auto results = { return db.execute("SELECT * FROM test"); }();
	auto values = [1, 2, 3, 4, 5, 6, 7, 8];
	foreach (row; results)
	{
		while (!row.empty)
		{
			assert(row.front.as!int == values.front);
			row.popFront();
			values.popFront();
		}
	}
}


/++
The data retrived from a column, stored internally as a $(D Variant).
+/
struct ColumnData
{
	private Variant variant;

	/++
	Returns the data converted to T. If the data is NULL, defaultValue is
	returned.
	+/
	auto as(T)(T defaultValue = T.init)
		if (isBoolean!T || isNumeric!T || isSomeChar!T || isSomeString!T)
	{
		if (!variant.hasValue)
			return defaultValue;

		static if (isBoolean!T)
			return variant.get!T; // Work around bug in 2.065
		else
			return variant.coerce!T;
	}

	/// ditto
	auto as(T)(T defaultValue = T.init)
		if (isArray!T && !isSomeString!T)
	{
		if (!variant.hasValue)
			return defaultValue;

		return cast(T) variant.get!(ubyte[]);
	}

	/// ditto
	auto as(T : Nullable!U, U...)(T defaultValue = T.init)
	{
		if (!variant.hasValue)
			return defaultValue;

		return T(as!U());
	}

	void toString(scope void delegate(const(char)[]) sink)
	{
		if (variant.hasValue)
			sink(variant.toString);
		else
			sink("NULL");
	}
}


unittest // Getting integral values
{
	auto db = Database(":memory:");
	db.execute("CREATE TABLE test (val INTEGER)");

	auto statement = db.prepare("INSERT INTO test (val) VALUES (?)");
	statement.bind(1, cast(byte) 42);
	statement.execute();
	statement.reset();
	statement.bind(1, 42U);
	statement.execute();
	statement.reset();
	statement.bind(1, 42UL);
	statement.execute();
	statement.reset();
	statement.bind(1, '\x2A');
	statement.execute();

	auto results = db.execute("SELECT * FROM test");
	foreach (row; results)
		assert(row.peek!long(0) == 42);
}

unittest // Getting floating point values
{
	auto db = Database(":memory:");
	db.execute("CREATE TABLE test (val FLOAT)");

	auto statement = db.prepare("INSERT INTO test (val) VALUES (?)");
	statement.bind(1, 42.0F);
	statement.execute();
	statement.reset();
	statement.bind(1, 42.0);
	statement.execute();
	statement.reset();
	statement.bind(1, 42.0L);
	statement.execute();
	statement.reset();
	statement.bind(1, "42");
	statement.execute();

	auto results = db.execute("SELECT * FROM test");
	foreach (row; results)
		assert(row.peek!double(0) == 42.0);
}

unittest // Getting text values
{
	auto db = Database(":memory:");
	db.execute("CREATE TABLE test (val TEXT)");

	auto statement = db.prepare("INSERT INTO test (val) VALUES (?)");
	statement.bind(1, "I am a text.");
	statement.execute();

	auto results = db.execute("SELECT * FROM test");
	assert(results.front.peek!string(0) == "I am a text.");
}

unittest // Getting blob values
{
	auto db = Database(":memory:");
	db.execute("CREATE TABLE test (val BLOB)");

	auto statement = db.prepare("INSERT INTO test (val) VALUES (?)");
	ubyte[] array = [1, 2, 3];
	statement.bind(1, array);
	statement.execute();
	statement.reset;
	ubyte[3] sarray = [1, 2, 3];
	statement.bind(1, sarray);
	statement.execute();

	auto results = db.execute("SELECT * FROM test");
	foreach (row; results)
		assert(row.peek!(ubyte[])(0) ==  [1, 2, 3]);
}

unittest // Getting null values
{
	import std.math;

	auto db = Database(":memory:");
	db.execute("CREATE TABLE test (val TEXT)");

	auto statement = db.prepare("INSERT INTO test (val) VALUES (?)");
	statement.bind(1, null);
	statement.execute();

	auto results = db.execute("SELECT * FROM test");
	assert(results.front.peek!bool(0) == false);
	assert(results.front.peek!long(0) == 0);
	assert(results.front.peek!double(0).isNaN);
	assert(results.front.peek!string(0) is null);
	assert(results.front.peek!(ubyte[])(0) is null);
	assert(results.front[0].as!bool == false);
	assert(results.front[0].as!long == 0);
	assert(results.front[0].as!double.isNaN);
	assert(results.front[0].as!string is null);
	assert(results.front[0].as!(ubyte[]) is null);
}

/// Information about a column.
struct ColumnMetadata
{
	string declaredTypeName; ///
	string collationSequenceName; ///
	bool isNotNull; ///
	bool isPrimaryKey; ///
	bool isAutoIncrement; ///
}


/++
Caches all the results of a $(D Statement) in memory as $(D ColumnData).

Allows to iterate on the rows and their columns with an array-like interface. The rows can
be viewed as an array of $(D ColumnData) or as an associative array of $(D ColumnData)
indexed by the column names.
+/
struct RowCache
{
	struct CachedRow
	{
		ColumnData[] columns;
		alias columns this;

		int[string] columnIndexes;

		private this(Row row, int[string] columnIndexes)
		{
			this.columnIndexes = columnIndexes;

			auto colapp = appender!(ColumnData[]);
			foreach (i; 0 .. row.length)
				colapp.put(row[i]);
			columns = colapp.data;
		}

		ColumnData opIndex(int index)
		{
			return columns[index];
		}

		ColumnData opIndex(string name)
		{
			auto index = name in columnIndexes;
			enforce(index, new SqliteException("Unknown column name: %s".format(name)));
			return columns[*index];
		}
	}

	CachedRow[] rows;
	alias rows this;

	private int[string] columnIndexes;

	/++
	Creates and populates the cache from the results of the statement.
	+/
	this(ResultRange results)
	{
		if (!results.empty)
		{
			auto first = results.front;
			foreach (i; 0 .. first.length)
			{
				auto name = sqlite3_column_name(first.statement, i).to!string;
				columnIndexes[name] = i;
			}
		}

		auto rowapp = appender!(CachedRow[]);
		while (!results.empty)
		{
			rowapp.put(CachedRow(results.front, columnIndexes));
			results.popFront();
		}
		rows = rowapp.data;
	}
}
///
unittest
{
	auto db = Database(":memory:");
	db.execute("CREATE TABLE test (msg TEXT, num FLOAT)");

	auto statement = db.prepare("INSERT INTO test (msg, num) VALUES (?1, ?2)");
	statement.bind(1, "ABC");
	statement.bind(2, 123);
	statement.execute();
	statement.reset();
	statement.bind(1, "DEF");
	statement.bind(2, 456);
	statement.execute();

	auto results = db.execute("SELECT * FROM test");
	auto data = RowCache(results);
	assert(data.length == 2);
	assert(data[0].front.as!string == "ABC");
	assert(data[0][1].as!int == 123);
	assert(data[1]["msg"].as!string == "DEF");
	assert(data[1]["num"].as!int == 456);
}

unittest // RowCache copies
{
	auto db = Database(":memory:");
	db.execute("CREATE TABLE test (msg TEXT)");
	auto statement = db.prepare("INSERT INTO test (msg) VALUES (?)");
	statement.bind(1, "ABC");
	statement.execute();

	static getdata(Database db)
	{
		return RowCache(db.execute("SELECT * FROM test"));
	}

	auto data = getdata(db);
	assert(data.length == 1);
	assert(data[0][0].as!string == "ABC");
}


/++
Turns $(D_PARAM value) into a _literal that can be used in an SQLite expression.
+/
string literal(T)(T value)
{
	static if (is(T == typeof(null)))
		return "NULL";
	else static if (isBoolean!T)
		return value ? "1" : "0";
	else static if (isNumeric!T)
		return value.to!string();
	else static if (isSomeString!T)
		return format("'%s'", value.replace("'", "''"));
	else static if (isArray!T)
		return "'X%(%X%)'".format(cast(ubyte[]) value);
	else
		static assert(false, "cannot make a literal of a value of type " ~ T.stringof);
}
///
unittest
{
	assert(null.literal == "NULL");
	assert(false.literal == "0");
	assert(true.literal == "1");
	assert(4.literal == "4");
	assert(4.1.literal == "4.1");
	assert("foo".literal == "'foo'");
	assert("a'b'".literal == "'a''b'''");
	auto a = cast(ubyte[]) x"DEADBEEF";
	assert(a.literal == "'XDEADBEEF'");
}

/++
Exception thrown when SQLite functions return an error.
+/
class SqliteException : Exception
{
	/++
	The _code of the error that raised the exception, or 0 if this _code is not known.
	+/
	int code;

	/++
	The SQL code that raised the exception, if applicable.
	+/
	string sql;

	private this(string msg, string sql, int code,
				 string file = __FILE__, size_t line = __LINE__, Throwable next = null)
	{
		this.sql = sql;
		this.code = code;
		super(msg, file, line, next);
	}

	this(string msg, int code, string sql = null,
		 string file = __FILE__, size_t line = __LINE__, Throwable next = null)
	{
		this("error %d: %s".format(code, msg), sql, code, file, line, next);
	}

	this(string msg, string sql = null,
		 string file = __FILE__, size_t line = __LINE__, Throwable next = null)
	{
		this(msg, sql, 0, file, line, next);
	}
}


private:

string errmsg(sqlite3* db)
{
	return sqlite3_errmsg(db).to!string;
}

string errmsg(sqlite3_stmt* stmt)
{
	return errmsg(sqlite3_db_handle(stmt));
}

auto byStatement(string sql)
{
	static struct ByStatement
	{
		string sql;
		size_t end;

		this(string sql)
		{
			this.sql = sql;
			end = findEnd();
		}

		bool empty()
		{
			return !sql.length;
		}

		string front()
		{
			return sql[0 .. end];
		}

		void popFront()
		{
			sql = sql[end .. $];
			end = findEnd();
		}

	private:
		size_t findEnd()
		{
			size_t pos;
			bool complete;
			do
			{
				auto tail = sql[pos .. $];
				auto offset = tail.countUntil(';') + 1;
				pos += offset;
				if (offset == 0)
					pos = sql.length;
				auto part = sql[0 .. pos];
				complete = cast(bool) sqlite3_complete(part.toStringz);
			}
			while (!complete && pos < sql.length);
			return pos;
		}
	}

	return ByStatement(sql);
}
unittest
{
	auto sql = "CREATE TABLE test (dummy);
		CREATE TRIGGER trig INSERT ON test BEGIN SELECT 1; SELECT 'a;b'; END;
		SELECT 'c;d';;
		CREATE";
	assert(equal(sql.byStatement.map!(s => s.strip), [
		"CREATE TABLE test (dummy);",
		"CREATE TRIGGER trig INSERT ON test BEGIN SELECT 1; SELECT 'a;b'; END;",
		"SELECT 'c;d';",
		";",
		"CREATE"
	]));
}

struct DelegateWrapper(T)
{
	T dlg;
}

void* delegateWrap(T)(T dlg)
	if (isCallable!T)
{
	import std.functional;
	alias D = typeof(toDelegate(dlg));
	auto d = cast(DelegateWrapper!D*) GC.malloc(DelegateWrapper!D.sizeof);
	GC.setAttr(d, GC.BlkAttr.NO_MOVE);
	d.dlg = toDelegate(dlg);
	return cast(void*) d;
}

auto delegateUnwrap(T)(void* ptr)
	if (isCallable!T)
{
	return (cast(DelegateWrapper!T*) ptr).dlg;
}

extern(C) void ptrFree(void* ptr)
{
	if (ptr)
		GC.free(ptr);
}


// Anchors and returns a pointer to D memory, so that it will not
// be moved or collected. For use with releaseMem.
void* anchorMem(void* ptr)
{
	GC.addRoot(ptr);
	GC.setAttr(ptr, GC.BlkAttr.NO_MOVE);
	return ptr;
}

// Passed to sqlite3_xxx_blob64/sqlite3_xxx_text64 to unanchor memory.
extern(C) void releaseMem(void* ptr)
{
	GC.setAttr(ptr, GC.BlkAttr.NO_MOVE);
	GC.removeRoot(ptr);
}

// getValue and setResult function templates
// used by createFunction and createAggregate

auto getValue(T)(sqlite3_value* argv)
	if (isBoolean!T)
{
	return sqlite3_value_int64(argv) != 0;
}

auto getValue(T)(sqlite3_value* argv)
	if (isIntegral!T)
{
	return sqlite3_value_int64(argv).to!T;
}

auto getValue(T)(sqlite3_value* argv)
	if (isFloatingPoint!T)
{
	if (sqlite3_value_type(argv) == SqliteType.NULL)
		return double.nan;
	return sqlite3_value_double(argv).to!T;
}

auto getValue(T)(sqlite3_value* argv)
	if (isSomeString!T)
{
	return sqlite3_value_text(argv).to!T;
}

auto getValue(T)(sqlite3_value* argv)
	if (isArray!T && !isSomeString!T)
{
	auto n = sqlite3_value_bytes(argv);
	ubyte[] blob;
	blob.length = n;
	memcpy(blob.ptr, sqlite3_value_blob(argv), n);
	return blob.to!T;
}

auto getValue(T : Nullable!U, U...)(sqlite3_value* argv)
{
	if (sqlite3_value_type(argv) == SqliteType.NULL)
		return T();
	return T(getValue!(U[0])(argv));
}

void setResult(T)(sqlite3_context* context, T value)
	if (isIntegral!T || isBoolean!T)
{
	sqlite3_result_int64(context, value.to!long);
}

void setResult(T)(sqlite3_context* context, T value)
	if (isFloatingPoint!T)
{
	sqlite3_result_double(context, value.to!double);
}

void setResult(T)(sqlite3_context* context, T value)
	if (isSomeString!T)
{
	auto val = value.to!string;
	sqlite3_result_text64(context, cast(const(char)*) anchorMem(cast(void*) val.ptr), val.length, &releaseMem, SQLITE_UTF8);
}

void setResult(T)(sqlite3_context* context, T value)
	if (isDynamicArray!T && !isSomeString!T)
{
	auto val = cast(void[]) value;
	sqlite3_result_blob64(context, anchorMem(val.ptr), val.length, &releaseMem);
}

void setResult(T)(sqlite3_context* context, T value)
	if (isStaticArray!T)
{
	auto val = cast(void[]) value;
	sqlite3_result_blob64(context, val.ptr, val.sizeof, SQLITE_TRANSIENT);
}

void setResult(T : Nullable!U, U...)(sqlite3_context* context, T value)
{
	if (value.isNull)
		sqlite3_result_null(context);
	else
		setResult(context, value.get);
}
