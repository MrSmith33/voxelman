/**
Copyright: Copyright (c) 2013-2016 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/

module anchovy.irenderer;

import dlib.math.vector;
import anchovy.texture;
import anchovy.shaderprogram;

interface IRenderer
{
	void enableAlphaBlending();
	void disableAlphaBlending();
	void setClearColor(ubyte r, ubyte g, ubyte b, ubyte a = 255);
	Texture createTexture(string filename);
	ShaderProgram createShaderProgram(string vertexSource, string fragmentSource);
	uvec2 framebufferSize() @property;
	void flush();
	void close();
}
