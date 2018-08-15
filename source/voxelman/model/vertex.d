/**
Copyright: Copyright (c) 2016-2018 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/

module voxelman.model.vertex;

import std.meta;
import voxelman.graphics.gl;
import voxelman.math;

align(4) struct VertexPosColor(PosType, uint pos_size, ColType, uint col_size)
{
	static if (pos_size == 2)
	this(Pos, Col)(Pos x, Pos y, Col color)
	{
		this.position.arrayof = [x, y];
		this.color = Vector!(ColType, col_size)(color);
	}

	static if (pos_size == 3)
	this(Pos, Col)(Pos x, Pos y, Pos z, Col color)
	{
		this.position.arrayof = [x, y, z];
		this.color = Vector!(ColType, col_size)(color);
	}

	static if (pos_size == 3)
	this(Pos, Col)(Pos x, Pos y, Pos z, ColType[col_size] color)
	{
		this.position.arrayof = [x, y, z];
		this.color.arrayof = color;
	}

	static if (col_size == 4 && is(ColType == ubyte))
	this(Vector!(PosType, pos_size) p, ColType[3] color)
	{
		this.position = p;
		this.color.arrayof = [color[0], color[1], color[2], 255];
	}

	static if (col_size == 4 && is(ColType == ubyte))
	this(Vector!(PosType, pos_size) p, Vector!(ColType, 3) color)
	{
		this.position = p;
		this.color.arrayof = [color.r, color.g, color.b, 255];
	}

	this(Vector!(PosType, pos_size) p, Vector!(ColType, col_size) color)
	{
		this.position = p;
		this.color = color;
	}

	void addOffset(vec3 offset)
	{
		position += Vector!(PosType, pos_size)(offset);
	}

	align(4):
	Vector!(PosType, pos_size) position;
	Vector!(ColType, col_size) color;

	void toString()(scope void delegate(const(char)[]) sink) const
	{
		import std.format : formattedWrite;
		sink.formattedWrite("V!(%s,%s)(%s, %s)", stringof(PosType), stringof(ColType), position, color);
	}

	static void setAttributes() {
		enum Size = typeof(this).sizeof;
		setupAttribute!(0, pos_size, PosType, false, true, Size, position.offsetof);
		setupAttribute!(1, col_size, ColType, true, true, Size, color.offsetof);
	}
}

align(4) struct VertexPosUvColor(PosType, uint pos_size, UvType, uint uv_size, ColType, uint col_size)
{
	align(4):
	Vector!(PosType, pos_size) position;
	Vector!(UvType, uv_size) uv;
	Vector!(ColType, col_size) color;

	void addOffset(vec3 offset)
	{
		position += Vector!(PosType, pos_size)(offset);
	}

	void toString()(scope void delegate(const(char)[]) sink) const
	{
		import std.format : formattedWrite;
		sink.formattedWrite("V!(%s,%s,%s)(%s, %s, %s)",
			stringof(PosType), stringof(UvType), stringof(ColType),
			position, uv, color);
	}

	static void setAttributes() {
		enum Size = typeof(this).sizeof;
		setupAttribute!(0, pos_size, PosType, false, true, Size, position.offsetof);
		setupAttribute!(1, uv_size, UvType, true, true, Size, uv.offsetof);
		setupAttribute!(2, col_size, ColType, true, true, Size, color.offsetof);
	}
}

void setupAttribute(int index, int numComponents, AttrT, bool normalize, bool isFloatAttrib, int totalVertSize, int offset)()
{
	glEnableVertexAttribArray(index);
	static if (isFloatAttrib)
	{
		enum bool doPosNomalization = normalize && normalizeAttributeType!AttrT;
		checkgl!glVertexAttribPointer(index, numComponents, glTypeOf!AttrT, doPosNomalization, totalVertSize, cast(void*)offset);
	}
	else
	{
		static if (normalizeAttributeType!AttrT) // only if integer
			checkgl!glVertexAttribIPointer(index, numComponents, glTypeOf!AttrT, totalVertSize, cast(void*)offset);
		else
			checkgl!glVertexAttribPointer(index, numComponents, glTypeOf!AttrT, false, totalVertSize, cast(void*)offset);
	}
}

enum glTypeOf(T) = glTypes[glTypeIndex!T];
enum normalizeAttributeType(T) = normalizeTypeTable[glTypeIndex!T];

alias glTypeIndex(T) = staticIndexOf!(T,
	byte,  // GL_BYTE
	ubyte, // GL_UNSIGNED_BYTE
	short, // GL_SHORT
	ushort,// GL_UNSIGNED_SHORT
	int,   // GL_INT
	uint,  // GL_UNSIGNED_INT
	half,  // GL_HALF_FLOAT
	float, // GL_FLOAT
	double,// GL_DOUBLE
	);

static immutable uint[] glTypes = [
	GL_BYTE,
	GL_UNSIGNED_BYTE,
	GL_SHORT,
	GL_UNSIGNED_SHORT,
	GL_INT,
	GL_UNSIGNED_INT,
	GL_HALF_FLOAT,
	GL_FLOAT,
	GL_DOUBLE,
];

static immutable bool[] normalizeTypeTable = [
	true,  // GL_BYTE
	true,  // GL_UNSIGNED_BYTE
	true,  // GL_SHORT
	true,  // GL_UNSIGNED_SHORT
	true,  // GL_INT
	true,  // GL_UNSIGNED_INT
	false, // GL_HALF_FLOAT
	false, // GL_FLOAT
	false, // GL_DOUBLE
];
