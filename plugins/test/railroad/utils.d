/**
Copyright: Copyright (c) 2016 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module test.railroad.utils;

enum RailSegment
{
	north,
	east,
	eastNorth,
	westNorth,
	westSouth,
	eastSouth,

	northUp,
	southUp,
	eastUp,
	westUp,

	northDown = southUp,
	southDown = northUp,
	eastDown = westUp,
	westDown = eastUp,
}
enum HOR_RAIL_MASK = 0b0100_0000;
struct RailType
{
	ubyte data;
	bool isHorizontal() {
		return !!(data & HOR_RAIL_MASK);
	}
}
