/**
Copyright: Copyright (c) 2016-2017 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/

module voxelman.serialization;

public import cbor;
public import voxelman.serialization.dataloader;
public import voxelman.serialization.datasaver;
public import voxelman.serialization.stringmap;

enum IoStorageType {
	database,
	network
}

struct IoKey {
	string str;
	uint id = uint.max;
}