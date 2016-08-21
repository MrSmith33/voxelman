/**
Copyright: Copyright (c) 2013-2016 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/

module voxelman.core.chunkmesh;

import voxelman.math;
import voxelman.model.vertex;
import derelict.opengl3.gl3;
import voxelman.core.config : DimentionId;
import voxelman.utils.renderutils;

struct Attribute
{
	uint location;
	uint elementNum;///number of
	uint elementType;///GL_FLOAT etc
	uint elementSize;///in bytes
	uint offset;///offset from the begining of buffer
	bool normalized;
}

struct ChunkMesh
{
	vec3 position;
	DimentionId dimention;
	MeshVertex[] data;

	bool isDataDirty = true;
	static int numBuffersAllocated;

	private GLuint vao;
	private GLuint vbo;
	private bool hasBuffers = false;

	private void genBuffers()
	{
		glGenBuffers(1, &vbo);
		glGenVertexArrays(1, &vao);
		++numBuffersAllocated;
		hasBuffers = true;
	}

	void deleteBuffers()
	{
		if (!hasBuffers) return;
		glDeleteBuffers(1, &vbo);
		glDeleteVertexArrays(1, &vao);
		--numBuffersAllocated;
		hasBuffers = false;
	}

	void uploadBuffer()
	{
		glBindBuffer(GL_ARRAY_BUFFER, vbo);
		glBufferData(GL_ARRAY_BUFFER, data.length*MeshVertex.sizeof, data.ptr, GL_STATIC_DRAW);
		MeshVertex.setAttributes();
		glBindBuffer(GL_ARRAY_BUFFER, 0);
	}

	void bind()
	{
		if (!hasBuffers)
			genBuffers();
		glBindVertexArray(vao);
	}

	static void unbind()
	{
		glBindVertexArray(0);
	}

	void render(bool trianlges)
	{
		assert(hasBuffers);

		if (isDataDirty)
		{
			uploadBuffer();
			isDataDirty = false;
		}
		if (trianlges)
			glDrawArrays(GL_TRIANGLES, 0, cast(uint)numVertexes());//data.length/12);
		else
			glDrawArrays(GL_LINES, 0, cast(uint)numVertexes());//data.length/12);
	}

	bool empty() { return data.length == 0; }

	ulong numVertexes() {return data.length;}
	ulong numTris() {return data.length/3;}
	ulong dataBytes() { return data.length * MeshVertex.sizeof; }
}

alias MeshVertex = VertexPosColor!(float, ubyte);

