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

alias MeshVertex = VertexPosColor!(float, 3, ubyte, 4);

struct MeshVertexSmall
{
	ushort position;
	ushort coluv;

	static void setAttributes() {
		enum Size = typeof(this).sizeof;
		// (int index, int numComponents, AttrT, bool normalize, int totalSize, int offset)
		setupAttribute!(0, 1, ushort, false, Size, position.offsetof);
		setupAttribute!(1, 1, ushort, false, Size, coluv.offsetof);
	}
}


string solid_vert_shader = `
#version 330
uniform sampler2D palette_uniform;
layout(location = 0) in uint packed_position;
layout(location = 1) in uint packed_uv_color;

uniform mat4 projection;
uniform mat4 view;
uniform mat4 model;

smooth out vec4 frag_color;
smooth out vec2 frag_uv;

void main() {
	vec3 position = vec3(
		packed_position % 33,
		(packed_position / (33 * 33)) % 33,
		(packed_position / 33) % 33);

	ivec2 pal_size = textureSize(palette_uniform, 0);
	vec2 palette_pos = vec2(packed_uv_color / pal_size.x, packed_uv_color % pal_size.x) / pal_size;

	gl_Position = projection * view * model * position;
	frag_color = texture(palette_uniform, palette_pos);

}
`;

string tex_col_frag_shader = `
#version 330
uniform sampler2D tex_uniform;

in vec2 frag_uv;
smooth in vec4 frag_color;

out vec4 out_color;

void main() {
	vec4 color = frag_color * texture(tex_uniform, frag_uv.st / textureSize(tex_uniform, 0));
	if (color.a == 0)
		discard;
	out_color = color;
}
`;

struct ChunkSolidShader
{
	ShaderProgram shader;
	alias shader this;

	mixin MvpSetter;
	mixin VpSetter;
	mixin ModelSetter;
	mixin ViewSetter;
	mixin ProjectionSetter;

	GLint model_location = -1;
	GLint view_location = -1;
	GLint projection_location = -1;
	GLint uv_location = -1;
	GLint palette_location = -1;

	void compile(IRenderer renderer) {
		shader = renderer.createShaderProgram(solid_vert_shader, solid_frag_shader);

		model_location = checkgl!glGetUniformLocation(handle, "model");
		view_location = checkgl!glGetUniformLocation(handle, "view");
		projection_location = checkgl!glGetUniformLocation(handle, "projection");
		uv_location = checkgl!glGetUniformLocation(handle, "tex_uniform");
		palette_location = checkgl!glGetUniformLocation(handle, "palette_uniform");
	}
}
