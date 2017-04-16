/**
Copyright: Copyright (c) 2017 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module railroad.rail.packets;

import railroad.rail.utils;

struct PlaceRailPacket
{
	RailPos pos;
	ubyte data;
}

struct EditRailLinePacket
{
	RailPos from;
	size_t length;
	RailOrientation orientation;
	DiagonalRailSide diagonalRailSide;
	RailEditOp editOp;
}
