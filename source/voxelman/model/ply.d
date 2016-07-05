/**
Copyright: Copyright (c) 2016 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.model.ply;

import std.algorithm : startsWith;
import std.conv : to, parse;
import std.string : lineSplitter, stripLeft;

import voxelman.container.buffer : Buffer;
import voxelman.model.utils : Faces, unrollFaces;
import voxelman.model.mesh : Mesh, VertexPosColor;

enum HEADER_STR = "end_header";
enum VERTEX_STR = "element vertex ";
enum FACE_STR = "element face ";

VertexPosColor[] readPlyFile(string fileName)
{
	import std.file : read;
	string data = cast(string)read(fileName);
	Mesh mesh = parsePly(data);
	return unrollFaces(mesh.vertices, mesh.faces);
}

Mesh parsePly(string fileData)
{
	auto lines = fileData.lineSplitter;

	size_t numVertices;
	size_t numFaces;

	// parse header
	while(!lines.empty)
	{
		auto line = lines.front;

		if (line.startsWith(HEADER_STR))
		{
			lines.popFront;
			break;
		}
		else if (line.startsWith(VERTEX_STR))
		{
			numVertices = to!size_t(line[VERTEX_STR.length..$]);
		}
		else if (line.startsWith(FACE_STR))
		{
			numFaces = to!size_t(line[FACE_STR.length..$]);
		}

		lines.popFront;
	}

	Buffer!VertexPosColor vertices;

	// parse vertices
	foreach (i; 0..numVertices)
	{
		auto line = lines.front;

		VertexPosColor v;
		v.x = parse!float(line); line = stripLeft(line);
		v.y = parse!float(line); line = stripLeft(line);
		v.z = parse!float(line); line = stripLeft(line);
		v.r = parse!ubyte(line); line = stripLeft(line);
		v.g = parse!ubyte(line); line = stripLeft(line);
		v.b = parse!ubyte(line);

		vertices.put(v);

		lines.popFront;
	}

	Buffer!int faceData;
	faceData.reserve(numFaces * 4);

	// parse faces
	foreach (i; 0..numFaces)
	{
		auto line = lines.front;

		int numFaceVertices = parse!int(line);
		faceData.put(numFaceVertices);

		foreach (j; 0..numFaceVertices)
		{
			line = stripLeft(line);
			faceData.put(parse!int(line));
		}

		lines.popFront;
	}

	return Mesh(
		vertices.data,
		Faces(faceData.data, numFaces));
}
