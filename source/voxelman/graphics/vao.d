/**
Copyright: Copyright (c) 2017-2018 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.graphics.vao;

import voxelman.graphics.gl;
import voxelman.graphics.vbo;

enum PrimitiveType : GLenum
{
	POINTS = GL_POINTS,
	LINE_STRIP = GL_LINE_STRIP,
	LINE_LOOP = GL_LINE_LOOP,
	LINES = GL_LINES,
	//LINE_STRIP_ADJACENCY = GL_LINE_STRIP_ADJACENCY,
	//LINES_ADJACENCY = GL_LINES_ADJACENCY,
	TRIANGLE_STRIP = GL_TRIANGLE_STRIP,
	TRIANGLE_FAN = GL_TRIANGLE_FAN,
	TRIANGLES = GL_TRIANGLES,
	//TRIANGLE_STRIP_ADJACENCY = GL_TRIANGLE_STRIP_ADJACENCY,
	//TRIANGLES_ADJACENCY = GL_TRIANGLES_ADJACENCY,
	//PATCHES = GL_PATCHES,
}


struct Vao
{
	//import core.atomic;
	//shared static size_t numAllocated;
	private GLuint handle_;

	GLuint handle() const {
		return handle_;
	}

	bool isGenerated() const {
		return handle_ != 0;
	}

	void gen() {
		if (isGenerated) return;
		//atomicOp!"+="(numAllocated, 1);
		checkgl!glGenVertexArrays(1, &handle_);
	}

	void del() {
		//if (handle_ != 0) atomicOp!"-="(numAllocated, 1);
		checkgl!glDeleteVertexArrays(1, &handle_);
	}

	void bind() const {
		assert(isGenerated);
		checkgl!glBindVertexArray(handle_);
	}

	static void unbind() {
		checkgl!glBindVertexArray(0);
	}

	// requires binding
	void drawArrays(PrimitiveType mode, int first, int count) const {
		checkgl!glDrawArrays(mode, first, count);
	}
}
