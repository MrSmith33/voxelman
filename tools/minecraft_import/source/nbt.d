/**
Copyright: Copyright (c) 2016 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module nbt;

private import std.string : format;
private import std.traits : Unqual, isArray, isAssociativeArray, isBoolean, isDynamicArray,
	isExpressionTuple, isFloatingPoint, isIntegral, isSomeChar, isStaticArray, isUnsigned;
public import std.typecons : Flag, Yes, No;
private import std.range : ElementEncodingType, hasLength, save, tee;
private import std.conv : to;
private import std.utf : byChar;
private import std.range : isInputRange, isOutputRange, ElementType;
private import std.typecons : isTuple;

enum testFile = `D:\voxelman\tools\minecraft_import\test.data`;
enum VisitRes {r_break, r_continue}
unittest
{
	import std.file;
	auto fileData = cast(ubyte[])read(testFile);
	printNbtStream(fileData[]);

	double[3] pos;

	VisitRes visitor(ref ubyte[] input, NbtTag tag)
	{
		import std.stdio;
		if (tag.name == "Pos")
		{
			pos[0] = decodeNbtTag(input, NbtTagType.tag_double, "").floating;
			pos[1] = decodeNbtTag(input, NbtTagType.tag_double, "").floating;
			pos[2] = decodeNbtTag(input, NbtTagType.tag_double, "").floating;
			writefln("Found Pos %s", pos);
			return VisitRes.r_break;
		}
		else
		{
			writefln("visit %s %s int %s", tag.type, tag.name, tag.integer);
			return visitNbtValue(input, tag, &visitor);
		}
		//return VisitRes.r_continue;
	}

	visitNbtStream(fileData, &visitor);
}


enum NbtTagType : ubyte {
	tag_end,
	tag_byte,
	tag_short,
	tag_int,
	tag_long,
	tag_float,
	tag_double,
	tag_byte_array,
	tag_string,
	tag_list,
	tag_compound, // map
	tag_int_array,
}

struct NbtTag
{
	NbtTagType type;
	string name;
	union
	{
		long integer;
		double floating;
		struct {
			// used for storing arrays, map and string size
			uint length;
			NbtTagType itemType; // shows list items' type
		}
	}

	this(NbtTagType type) { this.type = type; }
	this(NbtTagType type, string name) { this.type = type; this.name = name; }

	this(NbtTagType type, string name, double floating) {
		this.type = type;
		this.name = name;
		this.floating = floating;
	}

	this(NbtTagType type, string name, long integer) {
		this.type = type;
		this.name = name;
		this.integer = integer;
	}

	this(NbtTagType type, string name, uint length) {
		this.type = type;
		this.name = name;
		this.length = length;
	}

	this(NbtTagType type, string name, NbtTagType itemType, uint length) {
		this.type = type;
		this.name = name;
		this.itemType = itemType;
		this.length = length;
	}
}

NbtTag decodeNbtNamedTag(R)(auto ref R input)
	if(isInputRange!R && is(ElementType!R == ubyte))
{
	import std.array;

	if (input.empty) onInsufficientInput();

	NbtTagType type = cast(NbtTagType)input.front;
	input.popFront;

	if (type > NbtTagType.max) onUnsupportedTag(type);

	if (type == NbtTagType.tag_end)
		return NbtTag(NbtTagType.tag_end);

	ushort nameLength = readInteger!ushort(input);
	string name = cast(string)readBytes(input, nameLength);

	return decodeNbtTag(input, type, name);
}

NbtTag decodeNbtTag(R)(auto ref R input, NbtTagType type, string name)
	if(isInputRange!R && is(ElementType!R == ubyte))
{
	final switch(type) with(NbtTagType)
	{
		case tag_end:
			return NbtTag(tag_end);
		case tag_byte:
			return NbtTag(type, name, cast(long)readInteger!byte(input));
		case tag_short:
			return NbtTag(type, name, cast(long)readInteger!short(input));
		case tag_int:
			return NbtTag(type, name, cast(long)readInteger!int(input));
		case tag_long:
			return NbtTag(type, name, cast(long)readInteger!long(input));
		case tag_float:
			__FloatRep fr = {u : readInteger!uint(input)};
			return NbtTag(type, name, fr.f);
		case tag_double:
			__DoubleRep dr = {u : readInteger!ulong(input)};
			return NbtTag(type, name, dr.d);
		case tag_byte_array:
			return NbtTag(type, name, cast(uint)readInteger!uint(input));
		case tag_string:
			return NbtTag(type, name, cast(uint)readInteger!ushort(input));
		case tag_list:
			return NbtTag(type, name, cast(NbtTagType)readInteger!ubyte(input), cast(uint)readInteger!uint(input));
		case tag_compound:
			return NbtTag(type, name);
		case tag_int_array:
			return NbtTag(type, name, cast(uint)readInteger!uint(input));
	}
	assert(false);
}

private union __FloatRep { float f; uint u;}
private union __DoubleRep { double d; ulong u; }

VisitRes visitNbtStream(R, V)(auto ref R input, V visitor)
	if(isInputRange!R && is(ElementType!R == ubyte))
{
	while(input.length > 0)
	{
		NbtTag tag = decodeNbtNamedTag(input);
		if (tag.type == NbtTagType.tag_end)
			return VisitRes.r_continue;
		if (visitor(input, tag) == VisitRes.r_break)
			return VisitRes.r_break;
	}
	return VisitRes.r_continue;
}

VisitRes visitNbtValue(R, V)(auto ref R input, NbtTag tag, V visitor)
	if(isInputRange!R && is(ElementType!R == ubyte))
{
	final switch(tag.type) with(NbtTagType)
	{
		case tag_end: return VisitRes.r_continue;

		case tag_byte: return VisitRes.r_continue;
		case tag_short: return VisitRes.r_continue;
		case tag_int: return VisitRes.r_continue;
		case tag_long: return VisitRes.r_continue;

		case tag_float: return VisitRes.r_continue;
		case tag_double: return VisitRes.r_continue;

		case tag_byte_array: readBytes(input, tag.length); return VisitRes.r_continue;
		case tag_string: readBytes(input, tag.length); return VisitRes.r_continue;
		case tag_list: return visitNbtList(input, visitor, tag.itemType, tag.length);
		case tag_compound: return visitNbtStream(input, visitor);
		case tag_int_array: readBytes(input, tag.length*4); return VisitRes.r_continue;
	}
}

VisitRes visitNbtList(string singleIndent="  ", R, V)(
		auto ref R input,
		V visitor,
		NbtTagType type,
		uint length
	)
	if(isInputRange!R && is(ElementType!R == ubyte))
{
	foreach(i; 0..length) {
		NbtTag tag = decodeNbtTag(input, type, "");
		if (visitor(input, tag) == VisitRes.r_break)
			return VisitRes.r_break;
		//printNbtValue!singleIndent(input, sink, tag, ulong.max, indent);
	}
	return VisitRes.r_continue;
}


/// Outputs textual representation of Nbt stream into sink or stdout if not provided.
void printNbtStream(string singleIndent="  ", R)(auto ref R input)
{
	import std.stdio : stdout;
	auto writer = stdout.lockingTextWriter;
	printNbtStream!singleIndent(input, writer);
}

/// ditto
void printNbtStream(string singleIndent="  ", Sink, R)(
		auto ref R input,
		auto ref Sink sink,
		ulong numItems = ulong.max,
		string indent = ""
	)
	if(isInputRange!R && is(ElementType!R == ubyte) && isOutputRange!(Sink, char))
{
	while(input.length > 0 && numItems > 0)
	{
		NbtTag tag = decodeNbtNamedTag(input);
		if (tag.type == NbtTagType.tag_end)
			return;
		printNbtValue!singleIndent(input, sink, tag, ulong.max, indent);
		--numItems;
	}
}

void printNbtList(string singleIndent="  ", Sink, R)(
		auto ref R input,
		auto ref Sink sink,
		NbtTagType type,
		uint length,
		string indent = ""
	)
	if(isInputRange!R && is(ElementType!R == ubyte) && isOutputRange!(Sink, char))
{
	foreach(i; 0..length) {
		NbtTag tag = decodeNbtTag(input, type, "");
		printNbtValue!singleIndent(input, sink, tag, ulong.max, indent);
	}
}

void printNbtIntArray(string singleIndent="  ", Sink, R)(
		auto ref R input,
		auto ref Sink sink,
		uint length,
		string indent = ""
	)
	if(isInputRange!R && is(ElementType!R == ubyte) && isOutputRange!(Sink, char))
{
	import std.format : formattedWrite;
	if (length)
	{
		uint integer = readInteger!uint(input);
		formattedWrite(sink, "%s(%s", indent, integer);
	}
	else
		formattedWrite(sink, "%s(", indent);


	auto bytes = readBytes(input, (length-1)*4);
	//foreach(i; 1..length) {
	//	uint integer = readInteger!uint(input);
	//	formattedWrite(sink, ", %s", integer);
	//}
	formattedWrite(sink, ")\n");
}

void printNbtValue(string singleIndent="  ", Sink, R)(
		auto ref R input,
		auto ref Sink sink,
		NbtTag tag,
		ulong numItems = ulong.max,
		string indent = ""
	)
	if(isInputRange!R && is(ElementType!R == ubyte) && isOutputRange!(Sink, char))
{
	import std.format : formattedWrite;
	final switch(tag.type) with(NbtTagType)
	{
		case tag_end: return;

		case tag_byte: formattedWrite(sink, "%sbyte(%s): %s\n", indent, tag.name, tag.integer); break;
		case tag_short: formattedWrite(sink, "%sshort(%s): %s\n", indent, tag.name, tag.integer); break;
		case tag_int: formattedWrite(sink, "%sint(%s): %s\n", indent, tag.name, tag.integer); break;
		case tag_long: formattedWrite(sink, "%slong(%s): %s\n", indent, tag.name, tag.integer); break;

		case tag_float: formattedWrite(sink, "%stag_float(%s): %s\n", indent, tag.name, tag.floating); break;
		case tag_double: formattedWrite(sink, "%stag_double(%s): %s\n", indent, tag.name, tag.floating); break;

		case tag_byte_array:
			formattedWrite(sink, "%sbyte array(%s): %s\n",
				indent, tag.name, tag.length,  );
			auto bytes = readBytes(input, tag.length);
			//formattedWrite(sink, "%s%s(%(%02x%))\n", indent, singleIndent, bytes);
			break;
		case tag_string:
			formattedWrite(sink, "%sstring(%s): %s\n%s%s\"%s\"\n",
				indent, tag.name, tag.length, indent, singleIndent, cast(string)readBytes(input, tag.length));
			break;
		case tag_list:
			formattedWrite(sink, "%slist(%s): %s\n", indent, tag.name, tag.length);
			printNbtList!singleIndent(input, sink, tag.itemType, tag.length, indent~singleIndent);
			break;
		case tag_compound:
			formattedWrite(sink, "%scompound(%s)\n", indent, tag.name);
			printNbtStream!singleIndent(input, sink, ulong.max, indent~singleIndent);
			break;
		case tag_int_array:
			formattedWrite(sink, "%sint array(%s): %s\n", indent, tag.name, tag.length);
			printNbtIntArray!singleIndent(input, sink, tag.length, indent~singleIndent);
			break;
	}
}

private T readInteger(T, R)(auto ref R input)
	if(isInputRange!R && is(ElementType!R == ubyte))
{
	enum ubyte size = T.sizeof;
	import std.algorithm : copy;
	import std.bitmanip : bigEndianToNative;
	import std.range : dropExactly, take;

	static assert(T.sizeof == size);
	static assert(size > 0);
	if (input.length < size) onInsufficientInput();

	ubyte[size] data;

	copy(take(input, size), data[]);
	input = input.dropExactly(size);
	T result = bigEndianToNative!(T, size)(data);

	return result;
}

// Reads byte array from input range. On 32-bit can read up to uint.max bytes.
// If ubyte[] is passed as input, a slice will be returned.
// Make sure to dup array when input buffer is reused.
ubyte[] readBytes(R)(auto ref R input, ulong length)
	if(isInputRange!R && is(ElementType!R == ubyte))
{
	import std.array;
	import std.range : take;
	if (input.length < length) onInsufficientInput();

	static if (size_t.sizeof < ulong.sizeof)
		if (length > size_t.max)
			throw new NbtException(format("Array size is too big %s", length));

	size_t dataLength = cast(size_t)length;
	ubyte[] result;
	static if (is(R == ubyte[]))
	{
		result = input[0..dataLength];
		input = input[dataLength..$];
	}
	else
	{
		result = take(input, dataLength).array; // TODO allocation
	}

	return result;
}


class NbtException : Exception
{
	@trusted pure @nogc this(string message, string file = __FILE__, size_t line = __LINE__)
	{
		super(message, file, line);
	}
}

private:

auto customEmplace(T, A...)(void[] buffer, A args) @nogc
{
	buffer[] = typeid(T).init;
	return (cast(T)buffer.ptr).__ctor(args);
}

NbtException getException(A...)(string file, size_t line, string fmt, A args) @nogc
{
	static ubyte[__traits(classInstanceSize, NbtException)] exceptionBuffer;
	static char[512] charBuffer;
	import core.stdc.stdio : snprintf;
	int written = snprintf(charBuffer.ptr, charBuffer.length, fmt.ptr, args);
	return customEmplace!NbtException(exceptionBuffer, cast(string)charBuffer[0..written], file, line);
}

void onCastErrorToFrom(To)(NbtTagType from, string file = __FILE__, size_t line = __LINE__) @nogc
{
	throw getException(file, line, "Attempt to cast %s to %s", from, typeid(To));
}

void onInsufficientInput(string file = __FILE__, size_t line = __LINE__) @nogc
{
	throw getException(file, line, "Input range is too short");
}

void onUnsupportedTag(ubyte tag, string file = __FILE__, size_t line = __LINE__) @nogc
{
	throw getException(file, line, "Unsupported tag found: %02x", tag);
}
