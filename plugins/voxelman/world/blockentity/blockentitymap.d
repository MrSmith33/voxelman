/**
Copyright: Copyright (c) 2016-2017 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.world.blockentity.blockentitymap;

import voxelman.container.hashmap;
import std.experimental.allocator.mallocator;

alias BlockEntityMap = HashMap!(ushort, ulong, ushort.max, Mallocator);
