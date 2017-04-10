/**
Copyright: Copyright (c) 2017 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/

module voxelman.serialization.hashtable;

import std.range : save;
import voxelman.serialization;
import voxelman.container.buffer;
import voxelman.container.hash.map;
import voxelman.container.hash.set;

void serializeMap(HashMapT, Sink)(ref HashMapT hashmap, Sink sink)
{
	if (hashmap.empty) return;

	encodeCborMapHeader(sink, hashmap.length);
	foreach(key, value; hashmap) {
		encodeCbor!(Yes.Flatten)(sink, key);
		encodeCbor!(Yes.Flatten)(sink, value);
	}
}

void serializeMapPartial(HashMapT, Key, Sink)(ref HashMapT hashmap, Sink sink, HashSet!Key externalEntities)
{
	if (hashmap.empty) return;

	encodeCborMapHeader(sink);

	if (externalEntities.length < hashmap.length) {
		foreach(eid; externalEntities) {
			if (auto value = eid in hashmap) {
				encodeCbor!(Yes.Flatten)(sink, eid);
				encodeCbor!(Yes.Flatten)(sink, *value);
			}
		}
	} else {
		foreach(eid, value; hashmap) {
			if (externalEntities[eid]) {
				encodeCbor!(Yes.Flatten)(sink, eid);
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
			auto eid = decodeCborSingle!(HashMapT.KeyT)(input);
			auto component = decodeCborSingleDup!(HashMapT.ValueT, Yes.Flatten)(input);
			hashmap[eid] = component;
			--lengthToRead;
		}
	} else if (token.type == CborTokenType.mapIndefiniteHeader) {
		while (true) {
			token = decodeCborToken(input.save);
			if (token.type == CborTokenType.breakCode) {
				break;
			} else {
				auto eid = decodeCborSingle!(HashMapT.KeyT)(input);
				auto component = decodeCborSingleDup!(HashMapT.ValueT, Yes.Flatten)(input);
				hashmap[eid] = component;
			}
		}
	}
}


void serializeSet(HashSetT, Sink)(ref HashSetT hashset, Sink sink)
{
	if (hashset.empty) return;

	encodeCborArrayHeader(sink, hashset.length);
	foreach(eid; hashset) {
		encodeCbor(sink, eid);
	}
}

void serializeSetPartial(Key, Sink)(ref HashSet!Key hashset, Sink sink, HashSet!Key externalEntities)
{
	if (hashset.empty) return;
	encodeCborMapHeader(sink);

	if (externalEntities.length < hashset.length) {
		foreach(eid; externalEntities)
			if (hashset[eid]) encodeCbor(sink, eid);
	} else {
		foreach(eid; hashset)
			if (externalEntities[eid]) encodeCbor(sink, eid);
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
			hashset.put(decodeCborSingle!Key(input));
			--lengthToRead;
		}
	} else if (token.type == CborTokenType.arrayIndefiniteHeader) {
		while (true) {
			token = decodeCborToken(input.save);
			if (token.type == CborTokenType.breakCode)
				break;
			else
				hashset.put(decodeCborSingle!Key(input));
		}
	}
}
