/**
Copyright: Copyright (c) 2016 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.model.mesh;

align(1) struct VertexPosColor
{
	align(1):
	float x, y, z;
	ubyte r, g, b;
	ubyte _pad;
}

struct Mesh(V)
{
	V[] vertices;
	Faces faces;
}

struct Face3
{
	int[3] vertices;
}

struct Face
{
	int[] vertices;
}

struct Faces
{
	int[] faceData;
	size_t numFaces;

	bool isTriangulated() {
		return (faceData.length % (numFaces*4)) == 0;
	}

	Range opIndex() {
		return Range(faceData);
	}

	private static struct Range
	{
		private int[] faceData;
		int[] front() {
			return faceData[1 .. (faceData[0]+1)];
		}
		void popFront() {
			faceData = faceData[(faceData[0]+1)..$];
		}
		bool empty() { return faceData.length == 0; }
	}
}
