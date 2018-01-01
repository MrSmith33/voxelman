/**
Copyright: Copyright (c) 2013-2018 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/

module voxelman.graphics.textureatlas;

import voxelman.geometry.rectbinpacker;
import voxelman.graphics.bitmap;
import voxelman.graphics.color;
import voxelman.math;


class InsertException : Exception
{
	this(string msg, string file = __FILE__, size_t line = __LINE__)
	{
		super(msg, file, line);
	}
}

/// Can be used to tightly store small images in big atlas, such as font glyps, or lightmaps etc.
class TextureAtlas
{
	public Bitmap bitmap;
	public bool autoGrow = true;

private:
	uint _maxAtlasSize = 8192; // 2^13
	RectBinPacker binPacker;

public:

	this(in uint size)
	{
		binPacker = new RectBinPacker(size, size);
		bitmap = new Bitmap(size, size);
	}

	this(in uint width, in uint height)
	{
		binPacker = new RectBinPacker(width, height);
		bitmap = new Bitmap(width, height);
	}

	/// Returns: position of inserted node, or throws if not enough space
	ivec2 insert(ivec2 size, Color4ub color)
	{
		ivec2 pos = insert(size);
		bitmap.fillSubRect(irect(pos, size), color);
		return pos;
	}

	/// ditto
	ivec2 insert(ivec2 size)
	{
		Node* node = binPacker.insert(size);

		if (node is null) // There is no place to put new item.
		{
			if (autoGrow) // Atlas can grow.
			{
				delete binPacker;
				if (bitmap.width >= bitmap.height) // Growing vertically.
				{
					binPacker = new RectBinPacker(bitmap.width, bitmap.height, 0, bitmap.height);
					if (bitmap.height >= _maxAtlasSize)
						throw new InsertException("Texture atlas is full. Max atlas size reached");
					bitmap.resize(ivec2(bitmap.width, bitmap.height*2));
				}
				else // Growing horizontally.
				{
					binPacker = new RectBinPacker(bitmap.width, bitmap.height, bitmap.width, 0);
					bitmap.resize(ivec2(bitmap.width*2, bitmap.height));
				}

				node = binPacker.insert(size);
			}
			else
			{
				throw new InsertException("Texture atlas is full");
			}
		}

		return ivec2(node.rect.x, node.rect.y);
	}

	/// ditto
	ivec2 insert(in Bitmap source, in irect sourceSubRect)
	{
		ivec2 pos = insert(sourceSubRect.size);
		bitmap.putSubRect(source, sourceSubRect, pos);
		return pos;
	}
}
