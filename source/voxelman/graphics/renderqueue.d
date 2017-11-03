/**
Copyright: Copyright (c) 2017 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.graphics.renderqueue;

import voxelman.graphics;
import voxelman.math;

final class RenderQueue
{
	ResourceManager resourceManager;
	Texture atlasTexture;
	IRenderer renderer;

	BufferRenderer bufferRenderer;
	Batch2d batch;
	TexturedBatch2d texBatch;
	TextStyle[] defaultTextStyles;

	this(ResourceManager resMan, IRenderer renderer)
	{
		resourceManager = resMan;
		this.renderer = renderer;
		this.atlasTexture = new Texture(TextureTarget.target2d, TextureFormat.rgba);
		bufferRenderer = new BufferRenderer(renderer);
		defaultTextStyles = [TextStyle(Colors.black)];
	}

	void reuploadTexture()
	{
		atlasTexture.loadFromImage(resourceManager.texAtlas.bitmap);
	}

	enum minDepth2d = -100_000;
	enum maxDepth2d = 100_000;

	void beginFrame()
	{
		irect clipRect = irect(ivec2(0,0), renderer.framebufferSize);
		texBatch.reset(clipRect);
		batch.reset();
	}

	void endFrame()
	{}

	void drawFrame()
	{
		renderer.alphaBlending = true;
		renderer.rectClipping = true;
		renderer.depthTest = true;
		bufferRenderer.updateOrtoMatrix(renderer);
		bufferRenderer.draw(renderer, texBatch);
		bufferRenderer.draw(batch);
		renderer.rectClipping = false;
	}

	void draw(AnimationInstance animation, vec2 target, float depth, Color4ub color = Colors.white)
	{
		auto frameRect = animation.currentFrameRect;
		vec2 targetRectPos = target - vec2(animation.origin * animation.scale);
		texBatch.putRect(
			frect(targetRectPos, vec2(frameRect.size) * animation.scale),
			frect(frameRect),
			depth,
			color,
			atlasTexture);
	}

	void draw(Sprite sprite, vec2 target, float depth, Color4ub color = Colors.white)
	{
		texBatch.putRect(
			frect(target, vec2(sprite.atlasRect.size)),
			frect(sprite.atlasRect),
			depth,
			color,
			atlasTexture);
	}

	void draw(SpriteInstance sprite, vec2 target, float depth, Color4ub color = Colors.white)
	{
		vec2 targetRectPos = target - vec2(sprite.origin * sprite.scale);
		texBatch.putRect(
			frect(targetRectPos, vec2(sprite.sprite.atlasRect.size) * sprite.scale),
			frect(sprite.sprite.atlasRect),
			depth,
			color,
			atlasTexture);
	}

	void drawTexRect(frect target, frect source, float depth, Color4ub color = Colors.white)
	{
		texBatch.putRect(target, source, depth, color, atlasTexture);
	}

	void drawRectFill(vec2 pos, vec2 size, float depth, Color4ub color)
	{
		texBatch.putRect(frect(pos, size), frect(resourceManager.whitePixelPos, vec2(1,1)), depth, color, atlasTexture);
	}

	void drawRectLine(vec2 pos, vec2 size, float depth, Color4ub color)
	{
		texBatch.putRect(frect(pos.x, pos.y, size.x, 1), frect(resourceManager.whitePixelPos, vec2(1,1)), depth, color, atlasTexture);
		texBatch.putRect(frect(pos.x, pos.y+1, 1, size.y-2), frect(resourceManager.whitePixelPos, vec2(1,1)), depth, color, atlasTexture);
		texBatch.putRect(frect(pos.x, pos.y+size.y-1, size.x, 1), frect(resourceManager.whitePixelPos, vec2(1,1)), depth, color, atlasTexture);
		texBatch.putRect(frect(pos.x+size.x-1, pos.y+1, 1, size.y-2), frect(resourceManager.whitePixelPos, vec2(1,1)), depth, color, atlasTexture);
	}

	void pushClipRect(irect rect) {
		texBatch.pushClipRect(rect);
	}
	void popClipRect() {
		texBatch.popClipRect();
	}

	FontRef defaultFont()
	{
		return resourceManager.fontManager.defaultFont;
	}

	TextMesherParams defaultText()
	{
		TextMesherParams params;
		params.sink = TextRectSink(&texBatch, atlasTexture);
		params.depth = 0;
		params.font = defaultFont;
		params.styles = defaultTextStyles;
		return params;
	}

	TextMesherParams startTextAt(vec2 origin)
	{
		auto params = defaultText();
		params.origin = origin;
		return params;
	}

	void print(vec2 pos, Color4ub color, int scale, const(char[]) str)
	{
		auto params = startTextAt(pos);
		params.color = color;
		params.scale = scale;
		params.meshText(str);
	}

	void print(vec2 pos, Color4ub color, int scale, int depth, const(char[]) str)
	{
		auto params = startTextAt(pos);
		params.color = color;
		params.scale = scale;
		params.depth = depth;
		params.meshText(str);
	}

	void print(Args...)(vec2 pos, Color4ub color, int scale, const(char[]) fmt, Args args)
	{
		auto params = startTextAt(pos);
		params.color = color;
		params.scale = scale;
		params.meshText(fmt, args);
	}

	void print(Args...)(vec2 pos, Color4ub color, const(char[]) fmt, Args args)
	{
		this.print(pos, color, 1, fmt, args);
	}

	void print(Args...)(vec2 pos, const(char[]) fmt, Args args)
	{
		this.print(pos, Colors.black, 1, fmt, args);
	}
}
