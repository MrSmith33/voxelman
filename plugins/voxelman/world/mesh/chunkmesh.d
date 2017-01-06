/**
Copyright: Copyright (c) 2013-2016 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/

module voxelman.world.mesh.chunkmesh;

import anchovy.vao;
import anchovy.vbo;
import voxelman.math;
import voxelman.model.vertex;
import voxelman.graphics;

struct ChunkMesh
{
	vec3 position;

	private Vao vao;
	private Vbo vbo;

	void del()
	{
		vbo.del;
		vao.del;
	}

	void uploadMeshData(MeshVertex[] data)
	{
		vao.gen;
		vao.bind;
			vbo.gen;
			vbo.bind;

			vbo.uploadData(data);
			MeshVertex.setAttributes();

			vbo.unbind;
		vao.unbind;
	}

	void render(bool trianlges) const
	{
		vao.bind;
		if (trianlges) vao.drawArrays(PrimitiveType.TRIANGLES, 0, cast(uint)numVertexes());
		else vao.drawArrays(PrimitiveType.LINES, 0, cast(uint)numVertexes());
		vao.unbind;
	}

	bool empty() const { return vbo.uploadedBytes == 0; }

	ulong numVertexes() const {
		return vbo.uploadedBytes/MeshVertex.sizeof;
	}

	ulong numTris() const {
		return numVertexes/3;
	}

	size_t uploadedBytes() const {
		return vbo.uploadedBytes;
	}
}

alias MeshVertex = VertexPosColor!(float, 3, ubyte, 4);

void freeChunkMeshData(ref MeshVertex[] data)
{
	import std.experimental.allocator;
	import std.experimental.allocator.mallocator;
	Mallocator.instance.dispose(data);
	data = null;
}
