/**
Copyright: Copyright (c) 2016-2017 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.container.sharedhashset;

import voxelman.container.intkeyhashset;
import core.sync.rwmutex;

shared final class SharedHashSet(Key, Key nullKey = Key.max)
{
	alias SetType = IntKeyHashSet!(Key, nullKey);
	private SetType hashSet;
	private ReadWriteMutex mutex;

	this() shared {
		mutex = cast(shared) new ReadWriteMutex;
	}

	/// Returns true if key was in set
	bool remove(Key key) shared {
		synchronized ((cast(ReadWriteMutex)mutex).writer) {
			return (cast(SetType)hashSet).remove(key);
		}
	}

	void put(Key key) shared {
		synchronized ((cast(ReadWriteMutex)mutex).writer) {
			(cast(SetType)hashSet).put(key);
		}
	}

	bool opIndex(Key key) inout shared {
		synchronized ((cast(ReadWriteMutex)mutex).reader) {
			return (cast(SetType)hashSet).opIndex(key);
		}
	}

	size_t length() inout shared {
		synchronized ((cast(ReadWriteMutex)mutex).reader) {
			return (cast(SetType)hashSet).length;
		}
	}
}
