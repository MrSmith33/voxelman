/**
Copyright: Copyright (c) 2017-2018 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.container.hash.keybucket;

struct MetaKeyBucket(Key)
{
	enum BucketType : ubyte {
		empty,
		used,
		deleted
	}

	BucketType type;
	Key key;

	bool empty() const { return type == BucketType.empty; }
	bool used() const { return type == BucketType.used; }
	bool deleted() const { return type == BucketType.deleted; }
	bool corrupted() const { return type > cast(BucketType)2; }

	bool canInsert(Key key) const {
		return type == BucketType.empty || this.key == key;
	}

	void markAsDeleted() {
		type = BucketType.deleted;
	}
	void assignKey(Key key) {
		this.key = key;
		type = BucketType.used;
	}

	static void clearBuckets(typeof(this)[] keyBuckets)
	{
		auto buf = cast(ubyte[])keyBuckets;
		buf[] = 0; // set KeyBucket.type to empty
	}
}

/// Uses 2 special key values to mark empty and deleted buckets
struct KeyBucket(Key, Key emptyKey, Key deletedKey)
{
	Key key = emptyKey;

	bool empty() const { return key == emptyKey; }
	bool used() const { return key != emptyKey && key != deletedKey; }
	bool deleted() const { return key == deletedKey; }
	bool corrupted() const { return false; }

	bool canInsert(Key key) const {
		return this.key == emptyKey || this.key == key;
	}

	void markAsDeleted() {
		key = deletedKey;
	}
	void assignKey(Key key) {
		this.key = key;
	}

	static void clearBuckets(typeof(this)[] keyBuckets)
	{
		keyBuckets[] = typeof(this).init;
	}
}
