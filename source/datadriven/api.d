module datadriven.api;

import core.time;
import std.conv : to;
import std.typetuple;
import std.random;
import std.traits;

alias EntityId = ulong;

// tests if CS is a Components storage of components C
template isComponentStorage(CS, C)
{
	enum bool isComponentStorage = is(typeof(
    (inout int = 0)
    {
        CS cs = CS.init;
        C c = C.init;
        EntityId eid = EntityId.init;

        cs.add(eid, c); // Can add component
        cs.remove(eid); // Can remove component
        cs.removeAll(); // Can remove all
        C* cptr = cs.get(eid); // Can get component pointer

        foreach(pair; cs.byKeyValue)
        {
        	eid = pair.key;
        	c = pair.value = c;
        }
    }));
}

unittest
{
	struct A {}
	struct B
	{
		void add(EntityId, int);
		void remove(EntityId);
		int* get(EntityId);
		void removeAll();
		auto byKeyValue() @property {
			return (int[EntityId]).init.byKeyValue;
		}
	}
    static assert(!isComponentStorage!(A, int));
    static assert( isComponentStorage!(B, int));
}

auto componentQuery(ComponentStorages...)(ComponentStorages storages)
{
	return ComponentQuery!(ComponentStorages)(storages);
}

// Can be looped by Row.
// struct Row {EntityId eid; Comp1* comp1; ... CompN* compN;}
// Returned rows are for entities that have all the components.
struct ComponentQuery(ComponentStorages...)
{
	//pragma(msg, genComponentStorages!(ComponentStorages)());
	mixin(genComponentStorages!(ComponentStorages));

	static struct Row
	{
		mixin(genRowDefinition!ComponentStorages);
	}

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
        	lengths[i].length = mixin(genComponentStorageName!(cs) ~ ".length");
        }

		import std.algorithm : sort;
        sort(lengths[]);

        // Iteration variables
        int result = 0;
    	Row row;

        mixin(genComponentIterationCode!(ComponentStorages));

        return result;
    }
}


///////////////////////////////////////////////////////////////////////////////
// QUERY CODE GEN

string genComponentIterationCode(ComponentStorages...)()
{
	string result;

	result ~= "switch(lengths[0].index) {\n";

	// gen code for each case when table has fewest items
	foreach(i, cs1; ComponentStorages)
	{
		string istr = i.to!string;
		result ~=  "case "~istr~":\n";
		//result ~=  "writeln("~istr~");\n";

		result ~=  "\t\tforeach(pair; " ~ genComponentStorageName!(ComponentStorages[i]) ~ ".byKeyValue) {\n";
		// gen component selection for shortest table
	    result ~=  "\t\t\trow.eid = pair.key;\n";
	    result ~=  "\t\t\trow." ~ genComponentName!(ComponentStorages[i]) ~" = &(pair.value());\n\n";

		// gen component selection for other tables
	    foreach(j, cs2; ComponentStorages)
	    if (i != j)
		{
			// gen component selection for other tables via random access lookup
			string jstr = j.to!string;
		    result ~= "\t\t\tauto component"~ jstr ~" = " ~ genComponentStorageName!(ComponentStorages[j]) ~ ".get(pair.key);\n";
	        result ~= "\t\t\tif (component"~ jstr ~" is null) continue;\n";
	        result ~= "\t\t\trow." ~ genComponentName!(ComponentStorages[j]) ~ " = component"~ jstr ~";\n\n";
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

string genComponentStorages(ComponentStorages...)()
{
	string result;

	foreach(i, cs; ComponentStorages)
	{
		result ~= "private ComponentStorages[" ~ i.to!string ~ "] " ~
			genComponentStorageName!cs ~ ";\n";
	}

	return result;
}

string genComponentStorageName(ComponentStorage)()
{
	return "_" ~ genComponentName!ComponentStorage ~ "Storage";
}

alias componentType(ComponentStorage) = TemplateArgsOf!ComponentStorage[0];

string genComponentName(ComponentStorage)()
{
	alias C = TemplateArgsOf!ComponentStorage[0];
	string ident = Unqual!C.stringof;
	import std.uni : toLower;
	return toLower(ident[0]).to!string ~ ident[1..$];
}

string genRowDefinition(ComponentStorages...)()
{
	string result;

	result ~= "EntityId eid;\n";

	foreach(i, ComponentStorage; ComponentStorages)
	{
		result ~= "TemplateArgsOf!(ComponentStorages["~ i.to!string ~"])[0] * "~ genComponentName!ComponentStorage ~";\n";
	}

	return result;
}
