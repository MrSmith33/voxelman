/**
Copyright: Copyright (c) 2015 Andrey Penechko.
License: a$(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/

module voxelman.client.appstatistics;

struct AppStatistics
{
	// counters. They are resetted every frame.
	ulong chunksVisible;
	ulong chunksRendered;
	ulong vertsRendered;
	ulong trisRendered;

	ulong totalLoadedChunks;
	ulong lastFrameLoadedChunks;
	double fps;

	void resetCounters()
	{
		chunksVisible = 0;
		chunksRendered = 0;
		vertsRendered = 0;
		trisRendered = 0;
	}

	string[] getFormattedOutput()
	{
		import std.string : format;

		string[] result;
		result ~= format("FPS: %s", fps);
		result ~= format("Chunks visible/rendered %s/%s %.0f%%",
			chunksVisible, chunksRendered,
			chunksVisible ? cast(float)chunksRendered/chunksVisible*100 : 0);
		result ~= format("Chunks per frame loaded: %s",
			totalLoadedChunks - lastFrameLoadedChunks);
		result ~= format("Chunks total loaded: %s",
			totalLoadedChunks);
		result ~= format("Vertexes %s", vertsRendered);
		result ~= format("Triangles %s", trisRendered);

		return result;
	}
}