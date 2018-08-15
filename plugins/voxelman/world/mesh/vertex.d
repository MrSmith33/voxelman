/**
Copyright: Copyright (c) 2017-2018 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/

module voxelman.world.mesh.vertex;

import voxelman.model.vertex;
import voxelman.graphics.gl;
import voxelman.graphics.irenderer;
import voxelman.graphics.shaderprogram;
import voxelman.graphics.shaders;
import voxelman.math;
import voxelman.graphics.color;

//alias MeshVertex = VertexPosUvColor!(float, 3, ubyte, 4);
//alias MeshVertex = VertexPosColor!(float, 3, ubyte, 4);
//alias MeshVertex = MeshVertex8;
alias MeshVertex = MeshVertex16;

//alias ChunkShader = ChunkShader8;
alias ChunkShader = ChunkShader16;

struct MeshVertex16
{
	vec3 position;
	ubyte[2] uv;
	ubyte gray;

	this(T)(Vector!(T, 3) pos, ubyte[2] uv, ubyte gray) {
		set(pos.x, pos.y, pos.z, uv, gray);
	}
	this(float x, float y, float z, ubyte[2] uv, ubyte gray) {
		set(x, y, z, uv, gray);
	}

	void set(float x, float y, float z, ubyte[2] uv, ubyte gray) {
		position.x = x;
		position.y = y;
		position.z = z;
		this.uv = uv;
		this.gray = gray;
	}

	void addOffset(vec3 offset)
	{
		position += offset;
	}

	static void setAttributes() {
		enum Size = typeof(this).sizeof;
		// (int index, int numComponents, AttrT, bool normalize, int totalVertSize, int offset)
		setupAttribute!(0, 3, float, false, true, Size, position.offsetof);
		setupAttribute!(1, 3, ubyte, false, true, Size, uv.offsetof);
	}

	void toString()(scope void delegate(const(char)[]) sink) {
		import std.format : formattedWrite;
		sink.formattedWrite("v(%s, %s, %s)", position, uv, gray);
	}
}
static assert(MeshVertex16.sizeof == 16);

struct MeshVertex8
{
	uint packed_position;
	ubyte[2] uv;
	ubyte gray;

	vec3 position() @property {
		return vec3(
			(packed_position >>  0) & 1023,
			(packed_position >> 10) & 1023,
			(packed_position >> 20) & 1023) / 31;
	}

	this(T)(Vector!(T, 3) pos, ubyte[2] uv, ubyte gray) {
		set(cast(int)(pos.x * 31), cast(int)(pos.y * 31), cast(int)(pos.z * 31), uv, gray);
	}
	this(int x, int y, int z, ubyte[2] uv, ubyte gray) {
		set(x * 31, y * 31, z * 31, uv, gray);
	}

	private void set(int x, int y, int z, ubyte[2] uv, ubyte gray) {
		packed_position = ((x & 1023) << 0) | ((y & 1023) << 10) | ((z & 1023) << 20);
		this.uv = uv;
		this.gray = gray;
	}

	void addOffset(vec3 offset)
	{
		uint pos = ((cast(int)(offset.x * 31) & 1023) << 0) | ((cast(int)(offset.y * 31) & 1023) << 10) | ((cast(int)(offset.z * 31) & 1023) << 20);
		packed_position += pos;
	}

	static void setAttributes() {
		enum Size = typeof(this).sizeof;
		// (int index, int numComponents, AttrT, bool normalize, int totalVertSize, int offset)
		glEnableVertexAttribArray(0);
		checkgl!glVertexAttribPointer(0, 4, GL_UNSIGNED_INT_2_10_10_10_REV, false, Size, cast(void*)packed_position.offsetof);
		setupAttribute!(1, 3, ubyte, false, true, Size, uv.offsetof);
		//setupAttribute!(2, 1, ubyte, true, true, Size, gray.offsetof);
	}

	void toString()(scope void delegate(const(char)[]) sink) {
		import std.format : formattedWrite;
		sink.formattedWrite("v(%s, %s, %s)", position, uv, gray);
	}

	/*
	this(T)(Vector!(T, 3) pos, ubvec3 color) { set(cast(int)(pos.x * 31), cast(int)(pos.y * 31), cast(int)(pos.z * 31), color.arrayof); }
	this(T)(Vector!(T, 3) pos, ubyte[3] color) {set(cast(int)(pos.x * 31), cast(int)(pos.y * 31), cast(int)(pos.z * 31), color); }
	this(int x, int y, int z, ubyte[3] color) {set(x * 31, y * 31, z * 31, color); }

	void set(int x, int y, int z, ubyte[3] color) {
		packed_position = ((x & 1023) << 0) | ((y & 1023) << 10) | ((z & 1023) << 20) | 0b01_00000_00000_00000_00000_00000_00000;
		this.color = color;
	}

	static void setAttributes() {
		enum Size = typeof(this).sizeof;
		// (int index, int numComponents, AttrT, bool normalize, int totalVertSize, int offset)
		glEnableVertexAttribArray(0);
		checkgl!glVertexAttribPointer(0, 4, GL_UNSIGNED_INT_2_10_10_10_REV, false, Size, cast(void*)packed_position.offsetof);
		setupAttribute!(1, 3, ubyte, true, true, Size, color.offsetof);
	}
	*/
}
static assert(MeshVertex8.sizeof == 8);

string chunk_vert_shader8 = `
#version 330

layout(location = 0) in vec3 packed_position;
layout(location = 1) in vec3 uv_shade;

uniform sampler2D atlas_uniform;
uniform mat4 mvp;

smooth out float frag_shade;
out vec2 frag_uv;

void main() {
	gl_Position = mvp * vec4(packed_position/31, 1);
	frag_uv = uv_shade.xy*32 / textureSize(atlas_uniform, 0);
	frag_shade = uv_shade.z / 255;
}
`;

string chunk_frag_shader8 = `
#version 330

smooth in float frag_shade;
in vec2 frag_uv;

uniform sampler2D atlas_uniform;
uniform float transparency;

out vec4 out_color;

void main() {
	vec3 color = vec3(frag_shade * texture(atlas_uniform, frag_uv));
	out_color = vec4(color, transparency);
}
`;

struct ChunkShader8
{
	ShaderProgram shader;
	alias shader this;

	GLint transparency_location = -1;
	GLint mvp_location = -1;

	void setMvp(Matrix4f mvp) { checkgl!glUniformMatrix4fv(mvp_location, 1, GL_FALSE, mvp.arrayof.ptr); }
	void setTransparency(float transparency) { checkgl!glUniform1f(transparency_location, transparency); }

	void compile(IRenderer renderer) {
		shader = renderer.createShaderProgram(chunk_vert_shader8, chunk_frag_shader8);

		transparency_location = checkgl!glGetUniformLocation(handle, "transparency");
		mvp_location = checkgl!glGetUniformLocation(handle, "mvp");
	}
}

string chunk_vert_shader16 = `
#version 330

layout(location = 0) in vec3 packed_position;
layout(location = 1) in vec3 uv_shade;

uniform sampler2D atlas_uniform;
uniform mat4 mvp;

smooth out float frag_shade;
out vec2 frag_uv;

void main() {
	gl_Position = mvp * vec4(packed_position, 1);
	frag_uv = uv_shade.xy*32 / textureSize(atlas_uniform, 0);
	frag_shade = uv_shade.z / 255;
}
`;

struct ChunkShader16
{
	ShaderProgram shader;
	alias shader this;

	GLint transparency_location = -1;
	GLint mvp_location = -1;

	void setMvp(Matrix4f mvp) { checkgl!glUniformMatrix4fv(mvp_location, 1, GL_FALSE, mvp.arrayof.ptr); }
	void setTransparency(float transparency) { checkgl!glUniform1f(transparency_location, transparency); }

	void compile(IRenderer renderer) {
		shader = renderer.createShaderProgram(chunk_vert_shader16, chunk_frag_shader8);

		transparency_location = checkgl!glGetUniformLocation(handle, "transparency");
		mvp_location = checkgl!glGetUniformLocation(handle, "mvp");
	}
}
