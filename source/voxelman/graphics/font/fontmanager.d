/**
Copyright: Copyright (c) 2013-2017 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/

module voxelman.graphics.font.fontmanager;

import voxelman.math;
import voxelman.graphics.font.font;
import voxelman.graphics.textureatlas;

class FontManager
{
	public:

	FontRef defaultFont;
	string fontPath;

	this(string fontPath, TextureAtlas texAtlas)
	{
		this.fontPath = fontPath;
		this.texAtlas = texAtlas;
		//defaultFont = createFont("font_12_1.png", 12);
		//defaultFont = createFont("font_13.png", 13);
		//defaultFont = createFont("font_14.png", 13);
		defaultFont = createFont(fontPath, "font_12_2.png", 12);
	}

	FontRef createFont(string path, string filename, in uint height)
	{
		//import std.array : array;
		import std.file : readText;
		import std.path;// : chainPath, withExtension, asAbsolutePath;
		string filenameAbs = buildPath(path, filename).absolutePath;
		string descriptionFilename = filenameAbs.setExtension("txt");
		string chars = readText(descriptionFilename);
		FontRef newFont = loadFont(filenameAbs, height, chars, texAtlas);
		newFont.sanitize();

		fonts[filename] = newFont;
		return newFont;
	}

	TextureAtlas texAtlas;
	FontRef[string] fonts;
}

FontRef loadFont(in string filename, in uint height, in string chars, TextureAtlas texAtlas)
{
	import voxelman.graphics.font.bitmapfontloader;
	FontRef result = new Font(filename);

	import std.path;
	string ext = std.path.extension(filename);

	switch(ext)
	{
		case ".png": loadBitmapFont(result, texAtlas, chars); break;
		default: break;
	}

	return result;
}
