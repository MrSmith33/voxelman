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
	for (int x = imageStart.x; x < imageStart.x + imageSize.x; ++x)
	{
		for (int y = imageStart.y; y < imageStart.y + imageSize.y; ++y)
			if (image[x, y].a != 0) return;

		--imageSize.x;
		++imageStart.x;
	}

	// right
	for (int x = imageStart.x + imageSize.x - 1; x >= imageStart.x; --x)
	{
		for (int y = imageStart.y; y < imageStart.y + imageSize.y; ++y)
			if (image[x, y].a != 0) return;

		--imageSize.x;
	}

	// top
	for (int y = imageStart.y; y < imageStart.y + imageSize.y; ++y)
	{
		for (int x = imageStart.x; x < imageStart.x + imageSize.x; ++x)
			if (image[x, y].a != 0) return;

		--imageSize.y;
		++imageStart.y;
	}

	// bottom
	for (int y = imageStart.y + imageSize.y - 1; y >= imageStart.y; --y)
	{
		for (int x = imageStart.x; x < imageStart.x + imageSize.x; ++x)
			if (image[x, y].a != 0) return;

		--imageSize.y;
	}
}
