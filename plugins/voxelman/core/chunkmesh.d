/**
Copyright: Copyright (c) 2013-2016 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/

module voxelman.core.chunkmesh;

import core.atomic : atomicLoad, atomicOp;
import std.concurrency : thisTid;

import dlib.math.vector;
import dlib.math.quaternion;
import derelict.opengl3.gl3;

struct Attribute
{
	uint location;
	uint elementNum;///number of
	uint elementType;///GL_FLOAT etc
	uint elementSize;///in bytes
	uint offset;///offset from the begining of buffer
	bool normalized;
}



class ChunkMesh
{
	vec3 position;
	ubyte[] data;
	bool isDataDirty = false;
	GLuint vao;
	GLuint vbo;

	private shared static size_t _meshInstanceCount;
	static size_t meshInstanceCount() @property
	{
		return atomicLoad(_meshInstanceCount);
	}

	this()
	{
		atomicOp!("+=")(_meshInstanceCount, 1);
		glGenBuffers( 1, &vbo );
		glGenVertexArrays(1, &vao);
	}

	~this()
	{
		atomicOp!("-=")(_meshInstanceCount, 1);
	}

	void free()
	{
		glDeleteBuffers(1, &vbo);
		glDeleteVertexArrays(1, &vao);
	}

	alias ElemType = ubyte;
	enum VERTEX_SIZE = ubyte.sizeof * 8;

	void loadBuffer()
	{
		glBindBuffer(GL_ARRAY_BUFFER, vbo );
		glBufferData(GL_ARRAY_BUFFER, data.length, data.ptr, GL_STATIC_DRAW);
		glEnableVertexAttribArray(0);
		glEnableVertexAttribArray(1);
		// positions
		glVertexAttribPointer(0, 3, GL_UNSIGNED_BYTE, GL_FALSE, VERTEX_SIZE, null);
		// color
		glVertexAttribPointer(1, 3, GL_UNSIGNED_BYTE, GL_TRUE, VERTEX_SIZE, cast(void*)(VERTEX_SIZE / 2));
		glBindBuffer(GL_ARRAY_BUFFER,0);
	}

	void load()
	{
		glBindVertexArray(vao);
		loadBuffer();
		glBindVertexArray(0);
	}

	void bind()
	{
		glBindVertexArray(vao);
	}

	void render()
	{
		if (isDataDirty)
		{
			loadBuffer();
			isDataDirty = false;
		}
		glDrawArrays(GL_TRIANGLES, 0, cast(uint)numVertexes());//data.length/12);
	}

	ulong numVertexes() {return data.length/VERTEX_SIZE;}
	ulong numTris() {return data.length/(VERTEX_SIZE*3);}

}
