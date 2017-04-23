/**
Copyright: Copyright (c) 2017 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.graphics.vbo;

import derelict.opengl3.gl3;
import voxelman.graphics.glerrors;


struct Vbo
{
	import core.atomic;
	shared static size_t numAllocated;

	private GLuint handle_;
	private size_t uploadedBytes_;

	GLuint handle() const {
		return handle_;
	}

	// data size in bytes
	size_t uploadedBytes() const {
		return uploadedBytes_;
	}

	bool isGenerated() const {
		return handle_ != 0;
	}

	bool empty() const {
		return uploadedBytes_ == 0;
	}

	void gen() {
		if (isGenerated) return;
		checkgl!glGenBuffers(1, &handle_);
		atomicOp!"+="(numAllocated, 1);
	}

	void del() {
		if (handle_ == 0) return;
		atomicOp!"-="(numAllocated, 1);
		checkgl!glDeleteBuffers(1, &handle_);
		uploadedBytes_ = 0;
	}

	void bind() const {
		assert(isGenerated);
		checkgl!glBindBuffer(GL_ARRAY_BUFFER, handle_);
	}

	static void unbind() {
		checkgl!glBindBuffer(GL_ARRAY_BUFFER, 0);
	}

	// requires binding
	void uploadData(Vert)(const Vert[] data, int usage = GL_STATIC_DRAW) {
		uploadedBytes_ = data.length*Vert.sizeof;
		checkgl!glBufferData(GL_ARRAY_BUFFER, uploadedBytes_, data.ptr, usage);
	}
}
