/**
Copyright: Copyright (c) 2015 Andrey Penechko.
License: a$(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/

module voxelman.utils.queue;

// Do not store GC pointer there, Nodes are reused without wiping data.
struct Queue(Item)
{
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

	bool empty() @property
	{
		return first is null;
	}

	Item front() @property
	{
		assert(!empty);
		return first.data;
	}

	void popFront()
	{
		assert(!empty);

		Node* node = first;
		first = first.next;

		node.next = firstFree;
		firstFree = node;
		
		if (first is null)
		{
			last = null;
		}
		--length;
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
	Queue!int q;
	q.put(1);
	q.put(2);
	q.put(3);
	q.put(4);
	assert(equal(q, [1,2,3,4]));
}