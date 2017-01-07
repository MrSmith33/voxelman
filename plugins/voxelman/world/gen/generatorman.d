/**
Copyright: Copyright (c) 2016-2017 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.world.gen.generatorman;

import cbor;
import voxelman.world.gen.generator;
import voxelman.world.storage;

struct GeneratorFactory
{
	TypeInfo_Class[string] nameToType;
	TypeInfo_Class[uint] idToType;
	uint[TypeInfo_Class] typeToId;

	void registerGenerator(T : IGenerator)() {
		assert(T.name !in nameToType);
		nameToType[T.name] = T.classinfo;
	}

	IGenerator create(uint id) {
		if (auto type = id in idToType)
		{
			return cast(IGenerator)((*type).create());
		}
		return null;
	}

	uint getId(IGenerator generator) {
		return typeToId[generator.classinfo];
	}

	void load(ref PluginDataLoader loader) {
		foreach(pair; nameToType.byKeyValue)
		{
			IoKey ioKey = IoKey(pair.key);
			loader.stringMap.get(ioKey);
			idToType[ioKey.id] = pair.value;
			typeToId[pair.value] = ioKey.id;
		}
	}
}


struct GeneratorManager
{
	auto ioKey = IoKey("voxelman.world.gen.generatormanager");
	IGenerator[DimensionId] generators;
	GeneratorFactory factory;

	IGenerator opIndex(DimensionId dimensionId)
	{
		return generators.get(dimensionId, null);
	}

	void opIndexAssign(IGenerator generator, DimensionId dimensionId)
	{
		generators[dimensionId] = generator;
	}

	void load(ref PluginDataLoader loader) {
		factory.load(loader);

		ubyte[] data = loader.readEntryRaw(ioKey);
		if (data.length == 0) return;

		CborToken token = decodeCborToken(data);
		if (token.type == CborTokenType.mapHeader) {
			size_t lengthToRead = cast(size_t)token.uinteger;
			//generators.reserve(lengthToRead);
			while (lengthToRead > 0) {
				auto dimId = decodeCborSingle!DimensionId(data);
				auto generatorId = decodeCborSingle!uint(data);
				IGenerator generator = factory.create(generatorId);
				generator.load(data);
				generators[dimId] = generator;
				--lengthToRead;
			}
		}
	}

	void save(ref PluginDataSaver saver) {
		if (generators.length == 0) return;
		auto sink = saver.beginWrite();
		encodeCborMapHeader(sink, generators.length);
		foreach(dimId, generator; generators) {
			encodeCbor(sink, dimId);
			encodeCbor(sink, factory.getId(generator));
			generator.save(sink);
		}
		saver.endWrite(ioKey);
	}
}
