/**
Copyright: Copyright (c) 2013-2017 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/

/// Rewrite of Jukka Jylanki's RectangleBinPacker
module voxelman.geometry.rectbinpacker;

import voxelman.math;

struct Node
{
	irect rect;
	Node* left, right;
}

class RectBinPacker
{
	this(in uint width, in uint height, in uint x = 0, in uint y = 0)
	{
		binWidth = width;
		binHeight = height;
		root.left = root.right = null;
		root.rect.x = x;
		root.rect.y = y;
		root.rect.width = width;
		root.rect.height = height;
	}

	/**
	 * Running time is linear to the number of rectangles already packed. Recursively calls itself.
	 * @Returns: null If the insertion didn't succeed.
	 */
	Node* insert(ivec2 size)
	{
		return insert(&root, size.x, size.y);
	}

	/++
	 + @Returns: A value [0, 1] denoting the ratio of total surface area that is in use.
	 + 0.0f - the bin is totally empty, 1.0f - the bin is full.
	 +/
	float occupancy()
	{
		ulong totalSurfaceArea = binWidth * binHeight;
		ulong area = usedSurfaceArea(&root);

		return cast(float)area/totalSurfaceArea;
	}

private:

	uint binWidth;
	uint binHeight;

	Node root;

	Node* insert(Node* node, in uint width, in uint height)
	{
		if (node.left !is null || node.right !is null)
		{
			if (node.left !is null)
			{
				Node* newNode = insert(node.left, width, height);
				if (newNode)
					return newNode;
			}
			if (node.right !is null)
			{
				Node* newNode = insert(node.right, width, height);
				if (newNode !is null)
					return newNode;
			}
			return null; // Didn't fit into either subtree!
		}

		if (width > node.rect.width || height > node.rect.height)
			return null; // no space.

		int w = node.rect.width - width;
		int h = node.rect.height - height;

		node.left = new Node();
		node.right = new Node();

		if (w <= h) // Split the remaining space in horizontal direction.
		{
			node.left.rect.x = node.rect.x + width;
			node.left.rect.y = node.rect.y;
			node.left.rect.width = w;
			node.left.rect.height = height;

			node.right.rect.x = node.rect.x;
			node.right.rect.y = node.rect.y + height;
			node.right.rect.width = node.rect.width;
			node.right.rect.height = h;
		}
		else // Split the remaining space in vertical direction.
		{
			node.left.rect.x = node.rect.x;
			node.left.rect.y = node.rect.y + height;
			node.left.rect.width = width;
			node.left.rect.height = h;

			node.right.rect.x = node.rect.x + width;
			node.right.rect.y = node.rect.y;
			node.right.rect.width = w;
			node.right.rect.height = node.rect.height;
		}

		node.rect.width = width;
		node.rect.height = height;
		return node;
	}

	ulong usedSurfaceArea(Node* node) const
	{
		if (node.left || node.right)
		{
			ulong result = node.rect.width * node.rect.height;

			if (node.left !is null)
			{
				result += usedSurfaceArea(node.left);
			}
			if (node.right !is null)
			{
				result += usedSurfaceArea(node.right);
			}

			return result;
		}

		// This is a leaf node, it doesn't constitute to the total surface area.
		return 0;
	}
}
