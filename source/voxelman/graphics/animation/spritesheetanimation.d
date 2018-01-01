/**
Copyright: Copyright (c) 2017-2018 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.graphics.animation.spritesheetanimation;

import voxelman.math;
import voxelman.graphics;

struct AnimationFrame
{
	Sprite sprite;
	float timelineStart;
	float timelineEnd;
}

struct SpriteSheetAnimation
{
	AnimationFrame[] frames;
	float totalDuration;
}

alias SpriteSheetAnimationRef = SpriteSheetAnimation*;


import std.json;
SpriteSheetAnimationRef loadSpriteSheetAnimation(string filename, TextureAtlas texAtlas)
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
			Sprite(irect(
				cast(int)frameJson["frame"]["x"].integer,
				cast(int)frameJson["frame"]["y"].integer,
				cast(int)frameJson["frame"]["w"].integer,
				cast(int)frameJson["frame"]["h"].integer)));
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
		ivec2 position = texAtlas.insert(sourceBitmap, frame.sprite.atlasRect);
		frame.sprite.atlasRect.position = position;
	}
}

enum AnimationStatus
{
	playing,
	paused
}

struct AnimationInstance
{
	SpriteSheetAnimationRef sheet;
	AnimationStatus status;
	double timer = 0;
	size_t currentFrame = 0;
	vec2 scale = vec2(1, 1);
	vec2 origin = vec2(0, 0);
	void delegate() onLoop;

	void update(double dt)
	{
		if (status != AnimationStatus.playing) return;

		timer = timer + dt;

		double loops = floor(timer / sheet.totalDuration);
		if (loops != 0)
		{
			timer = timer - sheet.totalDuration * loops;
			if (onLoop) onLoop();
		}

		currentFrame = seekFrameIndex(timer);
	}

	Sprite currentFrameSprite()
	{
		return sheet.frames[currentFrame].sprite;
	}

	void pause()
	{
		status = AnimationStatus.paused;
	}

	void resume()
	{
		status = AnimationStatus.playing;
	}

	void gotoFrame(int frame)
	{
		currentFrame = clamp(frame, 0, sheet.frames.length-1);
		timer = sheet.frames[currentFrame].timelineStart;
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
