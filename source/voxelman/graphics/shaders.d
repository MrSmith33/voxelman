/**
Copyright: Copyright (c) 2017 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/

module voxelman.graphics.shaders;

import derelict.opengl3.gl3;
import voxelman.graphics.irenderer;
import voxelman.graphics.shaderprogram;
import voxelman.graphics.glerrors;
import voxelman.math;


string solid_frag_shader = `
#version 330
smooth in vec4 frag_color;
out vec4 out_color;

void main() {
	out_color = frag_color;
}
`;

string color_frag_shader_transparent = `
#version 330
smooth in vec4 frag_color;
out vec4 out_color;
uniform float transparency;

void main() {
	out_color = vec4(frag_color.xyz, transparency);
}
`;

string vert_shader_2d = `
#version 330
layout(location = 0) in vec2 position;
layout(location = 1) in vec4 color;

smooth out vec4 frag_color;
uniform mat4 projection;

void main() {
	gl_Position = projection * vec4(position.xy, 0, 1);
	frag_color = color;
}
`;

string solid_vert_shader = `
#version 330
layout(location = 0) in vec4 position;
layout(location = 1) in vec4 color;
uniform mat4 projection;
uniform mat4 view;
uniform mat4 model;
smooth out vec4 frag_color;
void main() {
	gl_Position = projection * view * model * position;
	frag_color = color;
}
`;

string tex_col_pos_vert_shader_2d = `
#version 330
uniform mat4 projection_uniform;
layout(location = 0) in vec4 position;
layout(location = 1) in vec2 uv;
layout(location = 2) in vec4 color;
out vec2 frag_uv;
smooth out vec4 frag_color;

void main() {
	frag_uv = uv;
	frag_color = color;
	gl_Position = projection_uniform * position;
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

immutable Matrix4f matrix4fIdentity = Matrix4f.identity;

mixin template ModelSetter()
{
	void setModel(Matrix4f model) {
		checkgl!glUniformMatrix4fv(model_location, 1, GL_FALSE, model.arrayof.ptr);
	}

	void setModel() {
		checkgl!glUniformMatrix4fv(model_location, 1, GL_FALSE, Matrix4f.identity.arrayof.ptr);
	}
}

mixin template ViewSetter()
{
	void setView(Matrix4f view) {
		checkgl!glUniformMatrix4fv(view_location, 1, GL_FALSE, view.arrayof.ptr);
	}

	void setView() {
		checkgl!glUniformMatrix4fv(view_location, 1, GL_FALSE, Matrix4f.identity.arrayof.ptr);
	}
}

mixin template ProjectionSetter()
{
	void setProjection(Matrix4f projection) {
		checkgl!glUniformMatrix4fv(projection_location, 1, GL_FALSE, projection.arrayof.ptr);
	}

	void setProjection() {
		checkgl!glUniformMatrix4fv(projection_location, 1, GL_FALSE, Matrix4f.identity.arrayof.ptr);
	}
}

mixin template TransparencySetter() {
	void setTransparency(float transparency) {
		checkgl!glUniform1f(transparency_location, transparency);
	}
}

mixin template TextureSetter() {
	void setTexture(int textureUnit) {
		checkgl!glUniform1i(uv_location, textureUnit);
	}
}

mixin template MvpSetter()
{
	void setMVP(Matrix4f model, Matrix4f view, Matrix4f projection) {
		checkgl!glUniformMatrix4fv(model_location, 1, GL_FALSE, model.arrayof.ptr);
		checkgl!glUniformMatrix4fv(view_location, 1, GL_FALSE, view.arrayof.ptr);
		checkgl!glUniformMatrix4fv(projection_location, 1, GL_FALSE, projection.arrayof.ptr);
	}
}

mixin template VpSetter()
{
	void setVP(Matrix4f view, Matrix4f projection) {
		checkgl!glUniformMatrix4fv(view_location, 1, GL_FALSE, view.arrayof.ptr);
		checkgl!glUniformMatrix4fv(projection_location, 1, GL_FALSE, projection.arrayof.ptr);
	}
}

struct SolidShader3d
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

	void compile(IRenderer renderer) {
		shader = renderer.createShaderProgram(solid_vert_shader, solid_frag_shader);

		model_location = checkgl!glGetUniformLocation(handle, "model");
		view_location = checkgl!glGetUniformLocation(handle, "view");
		projection_location = checkgl!glGetUniformLocation(handle, "projection");
	}
}

struct TransparentShader3d
{
	ShaderProgram shader;
	alias shader this;

	mixin MvpSetter;
	mixin VpSetter;
	mixin ModelSetter;
	mixin ViewSetter;
	mixin ProjectionSetter;
	mixin TransparencySetter;

	GLint model_location = -1;
	GLint view_location = -1;
	GLint projection_location = -1;
	GLint transparency_location = -1;

	void compile(IRenderer renderer) {
		shader = renderer.createShaderProgram(solid_vert_shader, color_frag_shader_transparent);

		model_location = checkgl!glGetUniformLocation(handle, "model");
		view_location = checkgl!glGetUniformLocation(handle, "view");
		projection_location = checkgl!glGetUniformLocation(handle, "projection");
		transparency_location = checkgl!glGetUniformLocation(handle, "transparency");
	}
}

struct SolidShader2d
{
	ShaderProgram shader;
	alias shader this;

	mixin ProjectionSetter;

	GLint projection_location = -1;

	void compile(IRenderer renderer) {
		shader = renderer.createShaderProgram(vert_shader_2d, solid_frag_shader);

		projection_location = checkgl!glGetUniformLocation(handle, "projection");
	}
}

struct ColUvShader2d
{
	ShaderProgram shader;
	alias shader this;

	mixin ProjectionSetter;
	mixin TextureSetter;

	GLint projection_location = -1;
	GLint uv_location = -1;

	void compile(IRenderer renderer) {
		shader = renderer.createShaderProgram(tex_col_pos_vert_shader_2d, tex_col_frag_shader);

		projection_location = checkgl!glGetUniformLocation(handle, "projection_uniform");
		uv_location = checkgl!glGetUniformLocation(handle, "tex_uniform");
	}
}
