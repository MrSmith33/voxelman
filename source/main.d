/**
Copyright: Copyright (c) 2014 Andrey Penechko.
License: a$(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/

module main;

import std.stdio;

import anchovy.graphics.windows.glfwwindow;

import voxelman.app;

version(linux)
{
	pragma(lib, "dl");
}

import anchovy.gui;

void main(string[] args)
{
	auto app = new VoxelApplication(uvec2(800, 600), "Voxel engine test");
	app.run(args);
}