/**
Copyright: Copyright (c) 2015 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/

module voxelman.utils.queue;

import std.range;

// Any reference type items are set to Item.init when reused.
// Traversing with foreach does not modify range. You can remove elements during foreach using NodeAccessor.
// To use Queue as consumable range use valueRange prroperty.
// To use as reference range use slice operator -> queue[]
struct Queue(Item)
{
	static struct NodeAccessor
	{
		ref Item value() @property
		{
			return node.data;
		}
		void remove()
		{
			queue.removeNode(prev, node);
		}

		private Node* prev;
		private Node* node;
		private Queue!(Item)* queue;
	}

	int opApply(int delegate(NodeAccessor) dg)
    {
        int result = 0;
        Node* prev;
		Node* pointer = first;

		while(pointer)
		{
			auto accessor = NodeAccessor(prev, pointer, &this);

			// advance pointers since accessor can remove current one
			prev = pointer;
			pointer = pointer.next;

			result = dg(accessor);
            if (result)
                break;
		}

        return result;
    }

	void put(Item item)
	{
		Node* node;
		if (firstFree !is null)
		{
			node = firstFree;
			firstFree = firstFree.next;
			node.next = null;
			node.data = item;
		}
		else
		{
			node = new Node(item, null);
		}
		// first will be also null
		if (last is null)
		{
			first = last = node;
		}
		else
		{
			last.next = node;
			last = node;
		}

		++length;
	}

	ValueRange valueRange() @property
    {
        return ValueRange(&this);
    }

    private static struct ValueRange
    {
    	private Queue!(Item)* queue;

		bool empty() @property
		{
			return queue.first is null;
		}

		Item front() @property
		{
			assert(!queue.empty);
			return queue.first.data;
		}

		void popFront()
		{
			queue.popFrontImpl();
		}
	}

	RefRange opSlice()
	{
		return RefRange(first);
	}

	private static struct RefRange
	{
		private Node* pointer;
		private Node* prev;

		bool empty() @property
		{
			return pointer is null;
		}

		Item front() @property
		{
			assert(!empty);
			return pointer.data;
		}

		void popFront()
		{
			assert(!empty);
			prev = pointer;
			pointer = pointer.next;
		}
	}

	bool empty() @property
	{
		return first is null;
	}

	bool remove(Item item)
	{
		Node* prev;
		Node* pointer = first;

		while(pointer)
		{
			if (pointer.data == item)
			{
				removeNode(prev, pointer);
				return true;
			}

			prev = pointer;
			pointer = pointer.next;
		}

		return false;
	}

	private void popFrontImpl()
	{
		assert(!empty);

		Node* node = first;
		first = first.next;

		freeNode(node);

		if (first is null)
		{
			last = null;
		}
		--length;
	}

	private void removeNode(Node* prev, Node* pointer)
	{
		if (pointer == first)
			popFrontImpl();
		else
		{
			Node* node = pointer;

			if (pointer == last)
			{
				last = prev;
			}

			prev.next = node.next;

			freeNode(node);
			--length;
		}
	}

	private void freeNode(Node* node)
	{
		import std.traits : hasIndirections;
		static if (hasIndirections!Item)
			node.data = Item.init;

		node.next = firstFree;
		firstFree = node;
	}

	Node* first;
	Node* last;
	Node* firstFree;
	size_t length;

	struct Node
	{
		Item data;
		Node* next;
	}
}

unittest
{
	import std.algorithm : equal;
	import std.stdio;
	Queue!int q;
	q.put(1);
	q.put(2);
	q.put(3);
	q.put(4);
	assert(q.length == 4);
	assert(equal(q[], [1,2,3,4]));

	// test remove
	q = typeof(q).init;
	q.put(1);
	q.put(2);
	q.put(3);
	q.put(4);

	assert(q.remove(5) == false);
	assert(q.remove(2));
	assert(q.length == 3);
	q.remove(3);
	assert(q.length == 2);
	q.remove(1);
	q.remove(4);
	assert(q.empty);

	// test remove from foreach
	q = typeof(q).init;
	q.put(1);
	q.put(2);
	q.put(3);
	q.put(4);

	uint i;
	foreach(nodeAccess; q)
	{
		if (i == 0)
			nodeAccess.remove();
		++i;
	}

	assert(equal(q[], [2,3,4]));

	i = 0;
	foreach(nodeAccess; q)
	{
		if (i == 2)
			nodeAccess.remove();
		++i;
	}

	assert(equal(q[], [2,3]));
}
