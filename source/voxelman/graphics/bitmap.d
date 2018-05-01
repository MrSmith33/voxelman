/**
Copyright: Copyright (c) 2017-2018 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/

module voxelman.graphics.bitmap;

import voxelman.algorithm.arraycopy2d;
import voxelman.math;
import voxelman.graphics.color;
import dlib.image.image : ImageRGBA8, SuperImage;
import dlib.image.color;

class Bitmap : ImageRGBA8
{
	public:

	this(uint w, uint h)
	{
		super(w, h);
	}

	this(SuperImage image)
	{
		super(0,0);
		this._width = image.width;
		this._height = image.height;

		if (pixelFormat == image.pixelFormat)
		{
			this._bitDepth = image.bitDepth;
			this._channels = image.channels;
			this._pixelSize = image.pixelSize;
			this._data = image.data;
		}
		else
		{
			allocateData();
			foreach(x; 0..image.width)
			foreach(y; 0..image.height)
				this[x, y] = Color4ub(image[x, y].convert(8));
		}
	}

	ivec2 size()
	{
		return ivec2(width, height);
	}

	override Color4f opIndexAssign(Color4f c, int x, int y)
	{
		return super.opIndexAssign(c, x, y);
	}

	void opIndexAssign(Color4ub color, int x, int y)
	{
		auto offset = (this._width * y + x) * 4;
		_data[offset+0] = color.r;
		_data[offset+1] = color.g;
		_data[offset+2] = color.b;
		_data[offset+3] = color.a;
	}

	void resize(ivec2 newSize)
	{
		if (newSize == size) return;

		auto newData = new ubyte[newSize.x * newSize.y * _pixelSize];

		auto sourceSize = ivec2(_width * _pixelSize, _height);
		auto sourceSubRect = irect(ivec2(0,0), sourceSize);

		auto destSize = ivec2(newSize.x * _pixelSize, newSize.y);
		auto destSubRectPos = ivec2(0,0);

		setSubArray2d(_data, sourceSize, sourceSubRect,
			newData, destSize, destSubRectPos);

		_data = newData;
		_width = newSize.x;
		_height = newSize.y;
	}

	void fillSubRect(irect destRect, Color4ub color)
	{
		foreach(y; destRect.y..destRect.endY)
		foreach(x; destRect.x..destRect.endX)
		this[x, y] = color;
	}

	void putSubRect(in Bitmap source, irect sourceSubRect, ivec2 destPos)
	{
		auto sourceSize = ivec2(source._width * source._pixelSize, source._height);
		auto destSize = ivec2(_width * _pixelSize, _height);

		sourceSubRect.width *= source._pixelSize;
		sourceSubRect.x *= source._pixelSize;
		destPos.x *= _pixelSize;

		setSubArray2d(source._data, sourceSize, sourceSubRect,
			_data, destSize, destPos);
	}

	void putRect(in Bitmap source, ivec2 destPos)
	{
		auto sourceSize = ivec2(source._width * source._pixelSize, source._height);
		auto sourceSubRect = irect(ivec2(0,0), sourceSize);

		auto destSize = ivec2(_width * _pixelSize, _height);

		setSubArray2d(source._data, sourceSize, sourceSubRect,
			_data, destSize, destPos);
	}
}
