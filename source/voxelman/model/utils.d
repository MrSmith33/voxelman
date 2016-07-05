/**
Copyright: Copyright (c) 2016 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.model.utils;

import voxelman.container.buffer : Buffer;
import voxelman.model.mesh : Face3, Faces;

T[] allocate(T)(size_t size) {
	import std.experimental.allocator.gc_allocator;
	alias allocator = GCAllocator.instance;
	return cast(T[])allocator.allocate(T.sizeof * size);
}

V[] unrollFaces(V)(V[] vertices, Face3[] faces)
{
	int[] indexes = cast(int[])faces;
	V[] result = allocate!(V)(indexes.length);

	foreach(i, index; indexes)
	{
		result[i] = vertices[index];
	}

	return result;
}

V[] unrollFaces(V)(V[] vertices, Faces faces)
{
	if (faces.isTriangulated)
	{
		V[] result = allocate!(V)(faces.numFaces * 3);

		size_t i;
		foreach(face; faces[])
		{
			result[i  ] = vertices[face[i  ]];
			result[i+1] = vertices[face[i+1]];
			result[i+2] = vertices[face[i+2]];
			i += 3;
		}

		return result;
	}
	else
	{
		return unrollFaces(vertices, triangulateFaces(faces));
	}
}

Face3[] triangulateFaces(Faces faces)
{
	Buffer!int triFaces;
	foreach(faceVertices; faces[])
	{
		triFaces.put(faceVertices[0], faceVertices[1], faceVertices[2]);
		for(size_t i = 3; i < faceVertices.length; ++i)
		{
			triFaces.put(faceVertices[0], faceVertices[i-1], faceVertices[i]);
		}
	}
	return cast(Face3[])triFaces.data;
}
