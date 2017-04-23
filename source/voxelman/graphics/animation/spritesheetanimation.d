/**
Copyright: Copyright (c) 2017 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.graphics.animation.spritesheetanimation;

import voxelman.math;
import voxelman.graphics;

struct AnimationFrame
{
	int x, y, w, h;
	float timelineStart;
	float timelineEnd;
}

struct SpriteSheetAnimation
{
	AnimationFrame[] frames;
	float totalDuration;
}

import std.json;
SpriteSheetAnimation* loadAnimation(string filename, TextureAtlas texAtlas)
{
	// create filenames
	import std.path : setExtension;
	string imageFilename = setExtension(filename, "png");
	string metaFilename = setExtension(filename, "json");

	// load texture
	import dlib.image.io.png;
	auto image = new Bitmap(loadPNG(imageFilename));

	// parse frames
	import std.file;
	string metaFileData = cast(string)read(metaFilename);
	auto jsonValue = parseJSON(metaFileData);
	auto frames = parseFrames(jsonValue["frames"].array);
	float totalDuration = frames[$-1].timelineEnd;

	putFramesIntoAtlas(image, frames, texAtlas);

	return new SpriteSheetAnimation(frames, totalDuration);
}

AnimationFrame[] parseFrames(JSONValue[] framesArray)
{
	AnimationFrame[] frames;
	float timelineStart = 0;
	float timelineEnd = 0;
	foreach(frameJson; framesArray)
	{
		auto frame = AnimationFrame(
			cast(int)frameJson["frame"]["x"].integer,
			cast(int)frameJson["frame"]["y"].integer,
			cast(int)frameJson["frame"]["w"].integer,
			cast(int)frameJson["frame"]["h"].integer);
		auto durationMsecs = cast(int)frameJson["duration"].integer;
		frame.timelineStart = timelineStart;
		timelineEnd = timelineStart + durationMsecs / 1000.0;
		frame.timelineEnd = timelineEnd;
		timelineStart = timelineEnd;
		frames ~= frame;
	}

	return frames;
}

// After this frames refer to positions in atlas
void putFramesIntoAtlas(Bitmap sourceBitmap, AnimationFrame[] frames, TextureAtlas texAtlas)
{
	foreach(ref frame; frames)
	{
		ivec2 position = texAtlas.insert(sourceBitmap, irect(frame.x, frame.y, frame.w, frame.h));
		frame.x = position.x;
		frame.y = position.y;
	}
}

enum AnimationStatus
{
	playing,
	paused
}

struct AnimationInstance
{
	SpriteSheetAnimation* sheet;
	AnimationStatus status;
	float timer = 0;
	size_t currentFrame = 0;
	void delegate() onLoop;

	private void update(float dt)
	{
		if (status != AnimationStatus.playing) return;

		timer = timer + dt;

		float loops = floor(timer / sheet.totalDuration);
		if (loops != 0)
		{
			timer = timer - sheet.totalDuration * loops;
			if (onLoop) onLoop();
		}

		currentFrame = seekFrameIndex(timer);
	}

	void drawAt(ref TexturedBatch2d batch, Texture texture, ivec2 traget, Color4ub color, float dt)
	{
		update(dt);
		auto frameRect = currentFrameInfo;
		batch.putRect(frect(traget, frameRect.size), frect(frameRect), color, texture);
	}

	irect currentFrameInfo()
	{
		auto frame = sheet.frames[currentFrame];
		return irect(frame.x, frame.y, frame.w, frame.h);
	}

	void pause()
	{
		status = AnimationStatus.paused;
	}

	void resume()
	{
		status = AnimationStatus.playing;
	}

	size_t seekFrameIndex(float timer)
	{
		if (sheet.frames.length < 2) return 0;

		int right = cast(int)(sheet.frames.length-1);
		int left = 0;
		int middle = 0;

		while (left <= right)
		{
			middle = (left + right) / 2;
			if (timer > sheet.frames[middle].timelineEnd) left = middle + 1;
			else if (timer <= sheet.frames[middle].timelineStart) right = middle - 1;
			else return middle;
		}

		return middle;
	}
}
