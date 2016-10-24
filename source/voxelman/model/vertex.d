/**
Copyright: Copyright (c) 2016 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/

module voxelman.model.vertex;

import std.meta;
import derelict.opengl3.gl3;
import voxelman.math;

align(4) struct VertexPosColor(PosType, uint pos_size, ColType, uint col_size)
{
	static if (pos_size == 2)
	this(Pos, Col)(Pos x, Pos y, Col color)
	{
		this.position = Vector!(PosType, pos_size)(x, y);
		this.color = Vector!(ColType, col_size)(color);
	}

	static if (pos_size == 3)
	this(Pos, Col)(Pos x, Pos y, Pos z, Col color)
	{
		this.position = Vector!(PosType, pos_size)(x, y, z);
		this.color = Vector!(ColType, col_size)(color);
	}

	this(Vector!(PosType, pos_size) p, Vector!(ColType, col_size) color)
	{
		this.position = p;
		this.color = color;
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

		// position
		glEnableVertexAttribArray(0);
		enum uint posGlType = glTypeOf!PosType;
		enum posOffset = position.offsetof;
		enum bool doPosNomalization = GL_FALSE;
		glVertexAttribPointer(0, pos_size, posGlType, doPosNomalization, Size, null);

		// color
		glEnableVertexAttribArray(1);
		enum uint colGlType = glTypeOf!ColType;
		enum colOffset = color.offsetof;
		enum bool doColNomalization = normalizeColorType!ColType;
		glVertexAttribPointer(1, col_size, colGlType, doColNomalization, Size, cast(void*)colOffset);
	}
}

template glTypeOf(T) {
	enum glTypeOf = glTypes[glTypeIndex!T];
}

template normalizeColorType(T) {
	enum normalizeColorType = normalizeColorTable[glTypeIndex!T];
}

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

static immutable bool[] normalizeColorTable = [
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
