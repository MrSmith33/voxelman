/**
Copyright: Copyright (c) 2013-2014 Andrey Penechko.
License: a$(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/

module voxelman.chunkmesh;

import std.stdio;
import core.atomic;
import std.concurrency : thisTid;

public import dlib.math.vector;
public import dlib.math.quaternion;
import derelict.opengl3.gl3;

class Attribute
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
	
	void load()
	{
		glBindVertexArray(vao);
		glBindBuffer(GL_ARRAY_BUFFER, vbo );
		glBufferData(GL_ARRAY_BUFFER, data.length, data.ptr, GL_STATIC_DRAW);
		glEnableVertexAttribArray(0);
		glEnableVertexAttribArray(1);
		glVertexAttribPointer(0, 3, GL_FLOAT, GL_FALSE, 6*float.sizeof, null);
		glVertexAttribPointer(1, 3, GL_FLOAT, GL_FALSE, 6*float.sizeof, cast(void*)(3*float.sizeof));
		glBindBuffer(GL_ARRAY_BUFFER,0);
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
			glBindBuffer(GL_ARRAY_BUFFER, vbo );
			glBufferData(GL_ARRAY_BUFFER, data.length, data.ptr, GL_STATIC_DRAW);
			glEnableVertexAttribArray(0);
			glEnableVertexAttribArray(1);
			glVertexAttribPointer(0, 3, GL_FLOAT, GL_FALSE, 6*float.sizeof, null);
			glVertexAttribPointer(1, 3, GL_FLOAT, GL_FALSE, 6*float.sizeof, cast(void*)(3*float.sizeof));
			glBindBuffer(GL_ARRAY_BUFFER,0);
			isDataDirty = false;
		}
		glDrawArrays(GL_TRIANGLES, 0, cast(uint)(data.length/24));//data.length/12);
	}

	ulong numVertexes() {return data.length/24;}
	ulong numTris() {return data.length/72;}
	
}