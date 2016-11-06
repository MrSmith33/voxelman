/**
Copyright: Copyright (c) 2013-2016 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/

module voxelman.world.mesh.chunkmesh;

import voxelman.math;
import voxelman.model.vertex;
import derelict.opengl3.gl3;
import voxelman.core.config : DimensionId;
import voxelman.graphics;

struct Attribute
{
	uint location;
	uint elementNum;///number of
	uint elementType;///GL_FLOAT etc
	uint elementSize;///in bytes
	uint offset;///offset from the begining of buffer
	bool normalized;
}

//enum Store_mesh = true;
enum Store_mesh = false;

struct ChunkMesh
{
	vec3 position;
	DimensionId dimension;
	static if(Store_mesh) MeshVertex[] data;
	size_t uploadedLength;

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
		static if(Store_mesh) freeChunkMesh(data);
	}

	void uploadBuffer(MeshVertex[] data)
	{
		assert(!hasBuffers);
		genBuffers();
		bind();

		static if(Store_mesh) this.data = data;
		uploadedLength = data.length;

		glBindBuffer(GL_ARRAY_BUFFER, vbo);
		MeshVertex.setAttributes();
		glBufferData(GL_ARRAY_BUFFER, data.length*MeshVertex.sizeof, data.ptr, GL_STATIC_DRAW);
		glBindBuffer(GL_ARRAY_BUFFER, 0);

		unbind();
		static if(!Store_mesh) freeChunkMesh(data);
	}

	void bind()
	{
		glBindVertexArray(vao);
	}

	static void unbind()
	{
		glBindVertexArray(0);
	}

	void render(bool trianlges)
	{
		assert(hasBuffers);

		if (trianlges)
			glDrawArrays(GL_TRIANGLES, 0, cast(uint)numVertexes());
		else
			glDrawArrays(GL_LINES, 0, cast(uint)numVertexes());
	}

	bool empty() { return uploadedLength == 0; }

	ulong numVertexes() {return uploadedLength;}
	ulong numTris() {return uploadedLength/3;}
	ulong dataBytes() { return uploadedLength * MeshVertex.sizeof; }
}

alias MeshVertex = VertexPosColor!(float, 3, ubyte, 4);

void freeChunkMesh(ref MeshVertex[] data)
{
	import std.experimental.allocator;
	import std.experimental.allocator.mallocator;
	Mallocator.instance.dispose(data);
	data = null;
}
