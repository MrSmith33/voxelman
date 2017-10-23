/**
Copyright: Copyright (c) 2017 Andrey Penechko.
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

//alias MeshVertex = VertexPosColor!(float, 3, ubyte, 4);
alias MeshVertex = MeshVertex8;

struct MeshVertex8
{
	align(4):
	uint packed_position;
	ubyte[3] color;

	vec3 position() @property {
		return vec3(
			(packed_position >>  0) & 1023,
			(packed_position >> 10) & 1023,
			(packed_position >> 20) & 1023) / 31;
	}

	this(T)(Vector!(T, 3) pos, ubvec3 color) { set(cast(int)(pos.x * 31), cast(int)(pos.y * 31), cast(int)(pos.z * 31), color.arrayof); }
	this(T)(Vector!(T, 3) pos, ubyte[3] color) {set(cast(int)(pos.x * 31), cast(int)(pos.y * 31), cast(int)(pos.z * 31), color); }
	this(int x, int y, int z, ubyte[3] color) {set(x * 31, y * 31, z * 31, color); }

	void set(int x, int y, int z, ubyte[3] color) {
		packed_position = ((x & 1023) << 0) | ((y & 1023) << 10) | ((z & 1023) << 20) | 0b01_00000_00000_00000_00000_00000_00000;
		this.color = color;
	}

	static void setAttributes() {
		enum Size = typeof(this).sizeof;
		// (int index, int numComponents, AttrT, bool normalize, int totalSize, int offset)
		glEnableVertexAttribArray(0);
		checkgl!glVertexAttribPointer(0, 4, GL_UNSIGNED_INT_2_10_10_10_REV, false, Size, cast(void*)packed_position.offsetof);
		setupAttribute!(1, 3, ubyte, true, true, Size, color.offsetof);
	}

	void toString()(scope void delegate(const(char)[]) sink) {
		import std.format : formattedWrite;
		sink.formattedWrite("v(%s, %s)", position, color);
	}
}
static assert(MeshVertex8.sizeof == 8);

string chunk_vert_shader8 = `
#version 330
layout(location = 0) in vec3 packed_position;
layout(location = 1) in vec3 packed_uv_color;
uniform mat4 mvp;
smooth out vec3 frag_color;
void main() {
	gl_Position = mvp * vec4(packed_position/31, 1);
	frag_color = packed_uv_color;
}
`;

string chunk_frag_shader8 = `
#version 330
smooth in vec3 frag_color;
uniform float transparency;
out vec4 out_color;
void main() { out_color = vec4(frag_color, transparency); }
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
