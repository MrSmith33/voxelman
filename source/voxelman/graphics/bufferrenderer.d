/**
Copyright: Copyright (c) 2017-2018 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.graphics.bufferrenderer;

import voxelman.graphics;
import voxelman.math;

final class BufferRenderer
{
	Vao vao;
	Vbo vbo;
	Matrix4f ortho_projection;

	SolidShader3d solidShader3d;
	TransparentShader3d transparentShader3d;
	SolidShader2d solidShader2d;
	ColUvShader2d colUvShader2d;

	this(IRenderer renderer)
	{
		vao.gen;
		vbo.gen;

		solidShader3d.compile(renderer);
		transparentShader3d.compile(renderer);
		solidShader2d.compile(renderer);
		colUvShader2d.compile(renderer);

		updateOrtoMatrix(renderer);
	}

	void updateOrtoMatrix(IRenderer renderer)
	{
		renderer.setViewport(ivec2(0, 0), renderer.framebufferSize);

		enum far = 100_000;
		enum near = -100_000;

		// (T l, T r, T b, T t, T n, T f)
		ortho_projection = orthoMatrix!float(0, renderer.framebufferSize.x, renderer.framebufferSize.y, 0, near, far);
	}

	void draw(Batch2d batch)
	{
		solidShader2d.bind;
		solidShader2d.setProjection(ortho_projection);

		uploadAndDrawBuffer(batch.triBuffer.data, PrimitiveType.TRIANGLES);
		uploadAndDrawBuffer(batch.lineBuffer.data, PrimitiveType.LINES);
		uploadAndDrawBuffer(batch.pointBuffer.data, PrimitiveType.POINTS);

		solidShader2d.unbind;
	}

	void draw(IRenderer renderer, TexturedBatch2d batch)
	{
		if (batch.buffer.data.length)
		{
			auto vertices = batch.buffer.data;
			uploadBuffer(vertices);

			colUvShader2d.bind;

			colUvShader2d.setProjection(ortho_projection);
			colUvShader2d.setTexture(0);

			size_t start = 0;
			foreach (command; batch.commands.data)
			{
				final switch(command.type)
				{
					case CommandType.batch:
						command.texture.bind;
						drawBuffer(PrimitiveType.TRIANGLES, start, command.numVertices);
						start += command.numVertices;
						break;
					case CommandType.clipRect:
						renderer.setClipRect(command.clipRect);
						break;
				}
			}

			colUvShader2d.unbind;

			Texture.unbind(TextureTarget.target2d);
		}
	}

	private void uploadAndDrawBuffer(VertexType)(VertexType[] buffer, PrimitiveType mode)
	{
		uploadBuffer(buffer);
		drawBuffer(mode, 0, buffer.length);
	}

	private void drawBuffer(PrimitiveType mode, size_t from, size_t count)
	{
		vao.bind;
		vao.drawArrays(mode, cast(int)from, cast(int)count);
		vao.unbind;
	}

	private void uploadBuffer(VertexType)(VertexType[] buffer)
	{
		vao.bind;
			vbo.bind;
				vbo.uploadData(buffer, GL_DYNAMIC_DRAW);
				VertexType.setAttributes();
			vbo.unbind;
		vao.unbind;
	}
}
