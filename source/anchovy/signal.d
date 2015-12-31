/**
Copyright: Copyright (c) 2013-2015 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/

module anchovy.signal;

import std.algorithm : countUntil;
import std.functional : toDelegate;
import std.traits : isDelegate, ParameterTypeTuple, isFunctionPointer;

struct Signal(Args...)
{
	alias SlotType = void delegate(Args);

	SlotType[] slots;

	void emit(Args args) @trusted
	{
		foreach(slot; slots)
			slot(args);
	}

	void connect(Slot)(Slot slot) @trusted if(is(ParameterTypeTuple!Slot == Args))
	{
		static if(isDelegate!Slot)
		{
			slots ~= slot;
		}
		else static if(isFunctionPointer!Slot)
		{
			slots ~= toDelegate(slot);
		}
	}

	void disconnect(Slot)(Slot slot) @trusted
	{
		static if(isDelegate!Slot)
		{
			auto haystackPos = countUntil(slots, slot);

			if(haystackPos >= 0)
			{
				slots = slots[0..haystackPos] ~ slots[haystackPos+1 .. $];
			}
		}
		else static if(isFunctionPointer!Slot)
		{
			// struct from functional toDelegate
			static struct DelegateFields {
	            union {
	                SlotType del;
	                struct {
	                    void* contextPtr;
	                    void* funcPtr;
	                }
	            }
	        }

	        auto haystackPos = countUntil!((SlotType _slot, ){return (cast(DelegateFields)_slot).contextPtr == slot;})(slots);

			if(haystackPos >= 0)
			{
				slots = slots[0..haystackPos] ~ slots[haystackPos+1 .. $];
			}
		}

	}

	void disconnectAll() @trusted
	{
		slots = [];
	}
}

// Test for signal with 0 arguments
unittest
{
	Signal!() test1; // Signal for slots not taking any parameters.

	auto num = 0;
	auto slot = (){num += 1;}; // Slot is plain delegate.
	test1.connect(slot);
	assert(num == 0); // Slot doesn't gets called upon connecting.

	test1.emit();
	assert(num == 1); // Each connected slot is called only once.

	test1.disconnect(slot);
	assert(num == 1); // Doesn't called upon disconnecting.

	test1.emit();
	assert(num == 1);
}

// Test for signal with 1 argument
unittest
{
	// Slot that takes one argument.
	// Slots can have any number of parameters.
	Signal!int test2;

	auto num = 0;
	auto slot = (int increment){num += increment;};
	test2.connect(slot);
	assert(num == 0);

	test2.emit(3);
	assert(num == 3);

	test2.disconnect(slot);
	assert(num == 3);

	test2.emit(4);
	assert(num == 3);
}

// Test for multiple slots
unittest
{
	Signal!int test3;

	auto num = 0;
	auto slot1 = (int inc){num += inc;};
	auto slot2 = (int mult){num *= mult;};

	test3.connect(slot1);
	test3.connect(slot2);
	assert(num == 0);

	test3.emit(2);
	assert(num == 4);

	test3.connect(slot1);
	test3.emit(3);
	assert(num == (4 + 3) * 3 + 3); // 24

	test3.disconnect(slot1);
	test3.emit(2);
	assert(num == 24 * 2 + 2); // 50

	test3.disconnectAll();
	test3.emit(4);
	assert(num == 50);
}

// Test for static slots
unittest
{
	Signal!(int*, int) test4;

	auto num = 0;
	// Testing static functions.
	static void staticSlot(int* num, int inc){*num += inc;}

	test4.connect(&staticSlot);
	assert(num == 0);

	test4.emit(&num, 2);
	assert(num == 2);

	test4.disconnect(&staticSlot);
	test4.emit(&num, 2);
	assert(num == 2);
}
