/**
Copyright: Copyright (c) 2016-2017 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module datadriven.query;

import std.conv : to;
import std.traits : TemplateArgsOf, Unqual;

import datadriven.api;

auto componentQuery(ComponentStorages...)(ComponentStorages storages)
{
	return ComponentQuery!(ComponentStorages)(storages);
}

struct ComponentQuery(ComponentStorages...)
{
	mixin(genComponentStorages!ComponentStorages);
	mixin(genRowDefinition!ComponentStorages);

	// Sorts component storages by length.
	// Then iterates by smallest storage to reduce number of lookups.
	int opApply(scope int delegate(Row) dg)
	{
		static struct StorageLength
		{
			size_t index;
			size_t length;
			int opCmp(StorageLength other) { return cast(int)(cast(long)length - cast(long)other.length); }
		}

		StorageLength[ComponentStorages.length] lengths;

		foreach(size_t i, cs; ComponentStorages)
		{
			lengths[i].index = i;
			lengths[i].length = mixin(genComponentStorageName!(cs, i) ~ ".length");
		}

		import std.algorithm : sort;
		sort(lengths[]);

		// Iteration variables
		int result = 0;
		Row row;

		mixin(genComponentIterationCode!ComponentStorages);

		return result;
	}
}


///////////////////////////////////////////////////////////////////////////////
// QUERY CODE GEN
///////////////////////////////////////////////////////////////////////////////

// // example
///////////////////////////////////////////////////////////////////////////////
// genComponentIterationCode!(EntitySet, EntitySet, HashmapComponentStorage!Velocity)
///////////////////////////////////////////////////////////////////////////////
// // yields
/*
  switch(lengths[0].index) {
    case 0:
        foreach(key; _entity_set_0) {
            row.id = key;
            bool component_1 = _entity_set_1.get(key);
            if (!component_1) continue;
            auto component_2 = _velocity_2_storage.get(key);
            if (component_2 is null) continue;
            row.velocity_2 = component_2;
            result = dg(row);
            if (result)
                break;
        }
        break;
    case 1:
        foreach(key; _entity_set_1) {
            row.id = key;
            bool component_0 = _entity_set_0.get(key);
            if (!component_0) continue;
            auto component_2 = _velocity_2_storage.get(key);
            if (component_2 is null) continue;
            row.velocity_2 = component_2;
            result = dg(row);
            if (result)
                break;
        }
        break;
    case 2:
        foreach(key, value; _velocity_2_storage) {
            row.id = key;
            row.velocity_2 = &value;
            bool component_0 = _entity_set_0.get(key);
            if (!component_0) continue;
            bool component_1 = _entity_set_1.get(key);
            if (!component_1) continue;
            result = dg(row);
            if (result)
                break;
        }
        break;
    default: assert(0);
  }
*/
// // as code inside ComponentQuery.opApply()



string genComponentIterationCode(ComponentStorages...)()
{
	string result;

	result ~= "switch(lengths[0].index) {\n";

	// gen code for each case when table has fewest items
	foreach(i, CS_1; ComponentStorages)
	{
		string istr = i.to!string;
		result ~=  "\tcase "~istr~":\n";
		//result ~=  "writeln("~istr~");\n";

		static if(isAnyComponentStorage!CS_1)
		{
			result ~=  "\t\tforeach(key, ref value; " ~ genComponentStorageName!(CS_1, i) ~ ") {\n";
			// gen component selection for shortest table
			result ~=  "\t\t\trow.id = key;\n";
			result ~=  "\t\t\trow." ~ genRowComponentName!(CS_1, i) ~" = &value;\n\n";
		}
		else
		{
			result ~=  "\t\tforeach(key; " ~ genComponentStorageName!(CS_1, i) ~ ") {\n";
			// gen component selection for shortest table
			result ~=  "\t\t\trow.id = key;\n\n";
		}

		// gen component selection for other tables
		foreach(j, CS_2; ComponentStorages)
		if (i != j)
		{
			// gen component selection for other tables via random access lookup
			static if(isAnyComponentStorage!CS_2)
			{
				string jstr = j.to!string;
				result ~= "\t\t\tauto component_"~ jstr ~" = " ~ genComponentStorageName!(CS_2, j) ~ ".get(key);\n";
				result ~= "\t\t\tif (component_"~ jstr ~" is null) continue;\n";
				result ~= "\t\t\trow." ~ genRowComponentName!(CS_2, j) ~ " = component_"~ jstr ~";\n\n";
			}
			else
			{
				string jstr = j.to!string;
				result ~= "\t\t\tbool component_"~ jstr ~" = " ~ genComponentStorageName!(CS_2, j) ~ ".get(key);\n";
				result ~= "\t\t\tif (!component_"~ jstr ~") continue;\n\n";
			}
		}

		// call foreach body passing current row
		result ~=  "\t\t\tresult = dg(row);\n";
		result ~=  "\t\t\tif (result)\n";
		result ~=  "\t\t\t\tbreak;\n";

		result ~=  "\t\t}\n"; // end foreach
		result ~=  "\t\tbreak;\n";
	}

	result ~= "\tdefault: assert(0);\n";
	result ~= "}\n"; // end switch

	return result;
}

// // example
///////////////////////////////////////////////////////////////////////////////
// genComponentStorages!(HashmapComponentStorage!Transform, EntitySet, HashmapComponentStorage!Velocity);
///////////////////////////////////////////////////////////////////////////////
// // yields
// private HashmapComponentStorage!Transform _transform_0_storage;
// private EntitySet _entity_set_1;
// private HashmapComponentStorage!Velocity _velocity_2_storage;
// // as fields inside ComponentQuery

string genComponentStorages(ComponentStorages...)()
{
	string result;

	foreach(i, cs; ComponentStorages)
	{
		result ~= "private ComponentStorages[" ~ i.to!string ~ "] " ~
			genComponentStorageName!(cs, i) ~ ";\n";
	}

	return result;
}

string genComponentStorageName(ComponentStorage, uint i)()
{
	static if(isAnyComponentStorage!ComponentStorage)
		return "_" ~ genStorageComponentName!ComponentStorage ~ "_" ~ i.to!string ~ "_storage";
	else
		return "_entity_set_" ~ i.to!string;
}

string genStorageComponentName(ComponentStorage)()
{
	alias C = TemplateArgsOf!ComponentStorage[0];
	return genComponentName!C;
}

string genComponentName(Component)()
{
	string ident = Unqual!Component.stringof;
	import std.uni : toLower;
	return toLower(ident[0]).to!string ~ ident[1..$];
}

// // example
///////////////////////////////////////////////////////////////////////////////
// genComponentStorages!(HashmapComponentStorage!Transform, EntitySet, HashmapComponentStorage!Velocity);
///////////////////////////////////////////////////////////////////////////////
// // yields
// static struct Row
// {
//     EntityId id;
//     Transform* transform_0;
//     Velocity* velocity_2;
// }
// // as type definition inside ComponentQuery
// // numbers start from zero. entity sets affect numbers.
// // Entity sets need no entries since they only affect which entities will be returned by query.

string genRowDefinition(ComponentStorages...)()
{
	string result;

	result =
		"static struct Row\n"~
		"{\n"~
		"\tEntityId id;\n";

	foreach(i, CS; ComponentStorages)
	{
		static if (isAnyComponentStorage!CS)
		{
			result ~= "\tTemplateArgsOf!(ComponentStorages["~ i.to!string ~"])[0]* "~
				genRowComponentName!(CS, i) ~ ";\n";
		}
	}
	result ~= "}\n";

	return result;
}

string genRowComponentName(ComponentStorage, uint i)()
{
	return genStorageComponentName!ComponentStorage ~ "_" ~ i.to!string;
}
