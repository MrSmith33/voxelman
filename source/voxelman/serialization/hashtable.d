/**
Copyright: Copyright (c) 2017 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/

module voxelman.serialization.hashtable;

import voxelman.log;
import std.range : save;
import voxelman.serialization;
import voxelman.container.buffer;
import voxelman.container.hash.map;
import voxelman.container.hash.set;

void serializeMap(HashMapT, Sink)(ref HashMapT hashmap, auto ref Sink sink)
{
	if (hashmap.empty) return;

	encodeCborMapHeader(sink, hashmap.length);
	foreach(key, value; hashmap) {
		encodeCbor!(Yes.Flatten)(sink, key);
		encodeCbor!(Yes.Flatten)(sink, value);
	}
}

void serializeMapPartial(HashMapT, Key, Sink)(ref HashMapT hashmap, auto ref Sink sink, HashSet!Key externalKeys)
{
	if (hashmap.empty || externalKeys.empty) return;

	encodeCborMapHeader(sink);

	if (externalKeys.length < hashmap.length) {
		foreach(key; externalKeys) {
			if (auto value = key in hashmap) {
				encodeCbor!(Yes.Flatten)(sink, key);
				encodeCbor!(Yes.Flatten)(sink, *value);
			}
		}
	} else {
		foreach(key, value; hashmap) {
			if (externalKeys[key]) {
				encodeCbor!(Yes.Flatten)(sink, key);
				encodeCbor!(Yes.Flatten)(sink, value);
			}
		}
	}
	encodeCborBreak(sink);
}

void deserializeMap(HashMapT)(ref HashMapT hashmap, ubyte[] input)
{
	if (input.length == 0) return;
	CborToken token = decodeCborToken(input);
	if (token.type == CborTokenType.mapHeader) {
		size_t lengthToRead = cast(size_t)token.uinteger;
		hashmap.reserve(lengthToRead);
		while (lengthToRead > 0) {
			auto key = decodeCborSingle!(HashMapT.KeyT, Yes.Flatten)(input);
			auto value = decodeCborSingleDup!(HashMapT.ValueT, Yes.Flatten)(input);
			hashmap[key] = value;
			--lengthToRead;
		}
	} else if (token.type == CborTokenType.mapIndefiniteHeader) {
		while (true) {
			token = decodeCborToken(input.save);
			if (token.type == CborTokenType.breakCode) {
				break;
			} else {
				auto key = decodeCborSingle!(HashMapT.KeyT, Yes.Flatten)(input);
				auto value = decodeCborSingleDup!(HashMapT.ValueT, Yes.Flatten)(input);
				hashmap[key] = value;
			}
		}
	}
}


void serializeSet(HashSetT, Sink)(ref HashSetT hashset, auto ref Sink sink)
{
	if (hashset.empty) return;

	encodeCborArrayHeader(sink, hashset.length);
	foreach(key; hashset) {
		encodeCbor!(Yes.Flatten)(sink, key);
	}
}

void serializeSetPartial(Key, Sink)(ref HashSet!Key hashset, auto ref Sink sink, HashSet!Key externalKeys)
{
	if (hashset.empty || externalKeys.empty) return;
	encodeCborMapHeader(sink);

	if (externalKeys.length < hashset.length) {
		foreach(key; externalKeys)
			if (hashset[key]) encodeCbor!(Yes.Flatten)(sink, key);
	} else {
		foreach(key; hashset)
			if (externalKeys[key]) encodeCbor!(Yes.Flatten)(sink, key);
	}
	encodeCborBreak(sink);
}

void deserializeSet(Key)(ref HashSet!Key hashset, ubyte[] input)
{
	if (input.length == 0) return;
	CborToken token = decodeCborToken(input);
	if (token.type == CborTokenType.arrayHeader) {
		size_t lengthToRead = cast(size_t)token.uinteger;
		hashset.reserve(lengthToRead);
		while (lengthToRead > 0) {
			hashset.put(decodeCborSingle!(Key, Yes.Flatten)(input));
			--lengthToRead;
		}
	} else if (token.type == CborTokenType.arrayIndefiniteHeader) {
		while (true) {
			token = decodeCborToken(input.save);
			if (token.type == CborTokenType.breakCode)
				break;
			else
				hashset.put(decodeCborSingle!(Key, Yes.Flatten)(input));
		}
	}
}
