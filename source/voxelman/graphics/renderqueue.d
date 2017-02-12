/**
Copyright: Copyright (c) 2016-2017 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko, Stephan Dilly (imgui_d_test).
*/
module voxelman.graphics.renderqueue;

import voxelman.container.buffer;
import voxelman.graphics;
import voxelman.math;

enum DrawMode
{
	fill,
	line
}

// vec3
struct RenderQueue3d
{
	//void putCube(vec3 pos, vec3 size, Color4ub color, bool fill)

}

// ivec2
struct RenderQueue2d
{
	Buffer!ColoredVertex triBuffer;
	Buffer!ColoredVertex lineBuffer;
	Buffer!ColoredVertex pointBuffer;

	// rect
	void rect(DrawMode mode, ivec2 pos, ivec2 size, Color4ub color)
	{
		//if (mode == DrawMode.fill)
		//	putFilledRect(triBuffer, pos, size, color);
		//else
		//	putLineRect(lineBuffer, pos, size, color);
	}
	// rect rounded
	// triangle
	// arc
	// point
	// circle
	// polygon
	// point
	// points
	// line
}
/*
void putFilledRect(V)(Buffer!V sink, ivec2 pos, ivec2 size, Color4ub color)
{
	sink.put(V(), V(), V(), V(), V(), V());
}
void putLineRect(V)(Buffer!V sink, ivec2 pos, ivec2 size, Color4ub color)
{
	(rect.x, rect.y + rect.height), (rect.x, rect.y),
				(rect.x + rect.width, rect.y), (rect.x + rect.width, rect.y + rect.height)
	sink.put(V(), V(), V(), V(), V(), V(), V(), V());
}
override void drawRect(Rect rect)
{
	bindShaderProgram(primShader);
	primShader.setUniform2!float("gHalfTarget", window.size.x/2, window.size.y/2);
	primShader.setUniform4!float("gColor", curColor.r, curColor.g, curColor.b, curColor.a);
	rectVao.bind;
	rectVbo.data = cast(short[])[rect.x, rect.y + rect.height, rect.x, rect.y,
				rect.x + rect.width, rect.y, rect.x + rect.width, rect.y + rect.height];
	glDrawArrays(GL_LINE_LOOP, 0, 4);
	rectVao.unbind;
}

override void fillRect(Rect rect)
{
	bindShaderProgram(primShader);
	primShader.setUniform2!float("gHalfTarget", window.size.x/2, window.size.y/2);
	primShader.setUniform4!float("gColor", curColor.r, curColor.g, curColor.b, curColor.a);
	rectVao.bind;
	rectVbo.data = cast(short[])[rect.x, rect.y + rect.height, rect.x, rect.y,
				rect.x + rect.width, rect.y, rect.x, rect.y + rect.height,
				rect.x + rect.width, rect.y, rect.x + rect.width, rect.y + rect.height];
	glDrawArrays(GL_TRIANGLES, 0, 6);
	rectVao.unbind;
}
*/
