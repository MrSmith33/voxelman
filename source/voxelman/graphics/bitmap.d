/**
Copyright: Copyright (c) 2017 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/

module voxelman.graphics.bitmap;

import voxelman.algorithm.arraycopy2d;
import voxelman.math;
import dlib.image.image : ImageRGBA8, SuperImage;

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
				this[x, y] = image[x, y];
		}
	}

	void resize(in uint newWidth, in uint newHeight)
	{
		auto newData = new ubyte[newWidth * newHeight * _pixelSize];

		auto sourceSize = ivec2(_width * _pixelSize, _height);
		auto sourceSubRect = irect(ivec2(0,0), sourceSize);

		auto destSize = ivec2(newWidth * _pixelSize, newHeight);
		auto destSubRectPos = ivec2(0,0);

		setSubArray2d(_data, sourceSize, sourceSubRect,
			newData, destSize, destSubRectPos);

		delete _data;
		_data = newData;
		_width = newWidth;
		_height = newHeight;
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
