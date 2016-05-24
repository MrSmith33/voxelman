/**
Copyright: Copyright (c) 2015-2016 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/

module voxelman.client.appstatistics;

struct AppStatistics
{
	// counters. They are resetted every frame.
	ulong chunksVisible;
	ulong chunksRendered;
	ulong chunksRenderedSemitransparent;
	ulong vertsRendered;
	ulong trisRendered;

	ulong totalLoadedChunks;
	ulong lastFrameLoadedChunks;
	double fps;

	void resetCounters()
	{
		chunksVisible = 0;
		chunksRendered = 0;
		chunksRenderedSemitransparent = 0;
		vertsRendered = 0;
		trisRendered = 0;
		lastFrameLoadedChunks = totalLoadedChunks;
	}
}
