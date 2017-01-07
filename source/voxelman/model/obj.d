/**
Copyright: Copyright (c) 2016-2017 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.model.obj;

import std.algorithm : splitter, startsWith;
import std.conv : to;
import std.string : lineSplitter, stripLeft;

import voxelman.math;

import voxelman.container.buffer : Buffer;
import voxelman.model.utils : unrollFaces;
import voxelman.model.mesh;

Vector!(T, 3)[] readObjFile(T)(string fileName)
{
	import std.file : read;
	string data = cast(string)read(fileName);
	return parseObj!T(data);
}

Vector!(T, 3)[] parseObj(T)(string fileData)
{
	auto lines = fileData.lineSplitter;

	Buffer!(Vector!(T, 3)) vertices;
	Buffer!Face3 faces;

	foreach (line; lines)
	{
		if (line.startsWith("v "))
		{
			Vector!(T, 3) v;
			string items = cast(string)line[2..$];

			size_t i;
			foreach(num; items.splitter)
			{
				v.arrayof[i] = to!T(num);
				++i;
			}
			vertices.put(v);
		}
		else if (line.startsWith("f "))
		{
			int[3] face;

			size_t i;
			foreach (pol; line[2..$].splitter)
			{
				int ind = to!int(pol.splitter("/").front) - 1;
				face[i] = ind;
				++i;
			}
			faces.put(Face3(face));
		}
	}

	return unrollFaces(vertices.data, faces.data);
}
