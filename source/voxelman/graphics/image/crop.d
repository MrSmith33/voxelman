/**
Copyright: Copyright (c) 2017 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.graphics.image.crop;

import dlib.image.image : SuperImage;
import voxelman.math;

void cropImage(SuperImage image, ref ivec2 imageStart, ref ivec2 imageSize)
{
	// left
	loop_left:
	for (int x = imageStart.x; x < imageStart.x + imageSize.x; ++x)
	{
		for (int y = imageStart.y; y < imageStart.y + imageSize.y; ++y)
			if (image[x, y].a != 0) break loop_left;

		--imageSize.x;
		++imageStart.x;
	}

	// right
	loop_right:
	for (int x = imageStart.x + imageSize.x - 1; x >= imageStart.x; --x)
	{
		for (int y = imageStart.y; y < imageStart.y + imageSize.y; ++y)
			if (image[x, y].a != 0) break loop_right;

		--imageSize.x;
	}

	// top
	loop_top:
	for (int y = imageStart.y; y < imageStart.y + imageSize.y; ++y)
	{
		for (int x = imageStart.x; x < imageStart.x + imageSize.x; ++x)
			if (image[x, y].a != 0) break loop_top;

		--imageSize.y;
		++imageStart.y;
	}

	// bottom
	loop_bottom:
	for (int y = imageStart.y + imageSize.y - 1; y >= imageStart.y; --y)
	{
		for (int x = imageStart.x; x < imageStart.x + imageSize.x; ++x)
			if (image[x, y].a != 0) break loop_bottom;

		--imageSize.y;
	}
}
