/**
Copyright: Copyright (c) 2014-2017 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/

module voxelman.gui.textedit.textbuffer;

import std.algorithm : equal, min;
import std.array : Appender, appender, empty, back, front, popFront;
import std.format : formattedWrite;
import std.exception : assumeUnique, assertThrown;
import std.string : format;
import std.range : isForwardRange, isBidirectionalRange, hasSlicing, dropExactly;
import std.typecons : Tuple;
import std.traits : isSomeString;
import std.uni : byGrapheme;
import std.utf : byDchar, count, stride, strideBack, decode, decodeFront, Yes;

import core.exception : AssertError;

bool equalDchars(S1, S2)(S1 str1, S2 str2)
{
	return equal(str1.byDchar, str2.byDchar);
}

void* shortPtr(void* ptr)
{
	return cast(void*)(cast(uint)ptr >> 4 & 0xFF);
	//return ptr;
}

// Refers to a text slice in a buffer.
private struct Piece
{
	// Offset in code points (bytes for utf-8) from the begining of the buffer.
	size_t bufferOffset;

	// length in bytes
	size_t length;

	PieceRef prev;
	PieceRef next;

	void toString(scope void delegate(const(char)[]) sink)
	{
		//sink.formattedWrite("P(O %s L %s P %s N %s)",
		//	bufferOffset, length, shortPtr(prev), shortPtr(next));
		sink.formattedWrite("P %s N %s", shortPtr(prev), shortPtr(next));
	}
}
alias PieceRef = Piece*;

struct PieceRestoreRange
{
	PieceRef first;
	PieceRef last;

	// length of the whole sequence in bytes
	size_t sequenceLength;

	// true if need to restore link between first and last
	// otherwise need to restore link first.prev.next -> first
	// and last.next.prev -> last
	bool boundary;

	PieceRestoreRange apply(ref size_t currentSequenceLength)
	{
		if (boundary)
		{
			auto undoItem = PieceRestoreRange(first.next, last.prev, currentSequenceLength, false);
			first.next = last;
			last.prev = first;
			currentSequenceLength = sequenceLength;
			return undoItem;
		}
		else
		{
			PieceRestoreRange undoItem;
			PieceRef left = first.prev;
			PieceRef right = last.next;

			if (left.next == right)
			{
				// we are inserting range first..last between
				// left and right, so new sequence is
				// left - first..last - right
				// generate Op to connect left and right
				undoItem = PieceRestoreRange(left, right, currentSequenceLength, true);
			}
			else
			{
				// we are replacing some sequence with first..last sequence
				// left - curFirst..curLast - right becomes
				// left - first..last - right
				// generate op to insert curFirst..curLast between left and right
				undoItem = PieceRestoreRange(left.next, right.prev, currentSequenceLength, false);
			}
			first.prev.next = first;
			last.next.prev = last;
			currentSequenceLength = sequenceLength;
			return undoItem;
		}
	}

	void toString()(scope void delegate(const(char)[]) sink)
	{
		sink.formattedWrite("F[%s]%s L[%s]%s B%s G%s",
			shortPtr(first), *first, shortPtr(last), *last, cast(int)boundary, cast(int)group);
	}
}

private struct PieceWithPos
{
	PieceRef piece;
	/// Offset into buffer in bytes
	size_t pos;

	// Can be used to continue searching for next position.
	PieceWithPos pieceAt(size_t index)
	{
		PieceRef piece = piece;
		size_t textPosition = pos;

		while (index >= textPosition + piece.length)
		{
			textPosition += piece.length;
			piece = piece.next;
		}

		return PieceWithPos(piece, textPosition);
	}
}

private enum Previous {no, yes};

private PieceStorage pieceStorage()
{
	PieceStorage storage;
	storage.sentinel = new Piece; // bug 17740
	storage.sentinel.next = storage.sentinel;
	storage.sentinel.prev = storage.sentinel;
	return storage;
}

private struct PieceStorage
{
	//PieceRef sentinel = new Piece; // bug 17740
	PieceRef sentinel;

	// length in bytes
	size_t length;

	void toString(scope void delegate(const(char)[]) sink)
	{
		auto piece = sentinel.next;
		sink.formattedWrite("PieceStorage(S[%s]%s <-> ", shortPtr(sentinel), *sentinel);
		while(piece != sentinel)
		{
			sink.formattedWrite("P[%s]%s <-> ", shortPtr(piece), *piece);
			piece = piece.next;
		}
		sink.formattedWrite("S[%s]%s)", shortPtr(sentinel), *sentinel);
	}

	// test fresh storage.
	unittest
	{
		PieceStorage storage = pieceStorage();

		assert((*storage.sentinel).length == 0);
		assert(storage.length == 0);
	}

	// Find piece at position index.
	PieceWithPos pieceAt(size_t index)
	{
		assert(index < length);
		return PieceWithPos(sentinel.next, 0).pieceAt(index);
	}

	unittest
	{
		PieceStorage storage = pieceStorage();
		//storage.writeln;

		auto piece1 = new Piece(10, 2);
		storage.insertBack(piece1);
		//writefln("piece1 %s", shortPtr(piece1));
		//storage.writeln;

		auto piece2 = new Piece(5, 2);
		storage.insertBack(piece2);
		//writefln("piece1 %s", shortPtr(piece2));
		//storage.writeln;

		auto piece3 = new Piece(1, 2);
		storage.insertBack(piece3);
		//writefln("piece1 %s", shortPtr(piece3));
		//storage.writeln;

		assert(storage.pieceAt(0) == PieceWithPos(piece1, 0));
		assert(storage.pieceAt(1) == PieceWithPos(piece1, 0));
		assert(storage.pieceAt(2) == PieceWithPos(piece2, 2));
		assert(storage.pieceAt(3) == PieceWithPos(piece2, 2));
		assert(storage.pieceAt(4) == PieceWithPos(piece3, 4));
		assert(storage.pieceAt(5) == PieceWithPos(piece3, 4));
		assert(storage.pieceAt(2).pieceAt(4) == PieceWithPos(piece3, 4));
		assertThrown!AssertError(storage.pieceAt(6));
	}

	PieceRestoreRange insertFront(PieceRef piece)
	{
		assert(piece);
		return insertAt(piece, 0);
	}

	unittest
	{
		PieceStorage storage = pieceStorage();

		auto piece1 = new Piece(0, 2);
		storage.insertFront(piece1);

		assert(storage.sentinel.next == piece1);
		assert(storage.sentinel.prev == piece1);
		assert(storage.sentinel == storage.sentinel.next.next);
		assert(storage.sentinel == storage.sentinel.prev.prev);
		assert(storage.length == 2);

		auto piece2 = new Piece(4, 2);
		storage.insertFront(piece2);
		// sentinel <-> piece2 <-> piece1 <-> sentinel

		assert(storage.sentinel.next == piece2);
		assert(storage.sentinel.next.next == piece1);
		assert(storage.sentinel.next.next.next == storage.sentinel);
		assert(storage.sentinel.prev == piece1);
		assert(storage.sentinel.prev.prev == piece2);
		assert(storage.sentinel.prev.prev.prev == storage.sentinel);
		assert(storage.length == 4);

		assert(piece1.next == storage.sentinel);
		assert(piece1.prev == piece2);
		assert(piece2.next == piece1);
		assert(piece2.prev == storage.sentinel);
	}

	PieceRestoreRange insertBack(PieceRef piece)
	{
		assert(piece);
		return insertAt(piece, length);
	}

	unittest
	{
		PieceStorage storage = pieceStorage();

		auto piece1 = new Piece(0, 2);
		storage.insertBack(piece1);

		assert(storage.sentinel.next == piece1);
		assert(storage.sentinel.next.next == storage.sentinel);
		assert(storage.length == 2);
		// sentinel <-> piece1 <-> sentinel

		auto piece2 = new Piece(4, 2);
		storage.insertBack(piece2);
		// sentinel <-> piece1 <-> piece2 <-> sentinel

		assert(storage.sentinel.next == piece1);
		assert(storage.sentinel.next.next == piece2);
		assert(storage.length == 4);

		assert(piece1.next == piece2);
		assert(piece2.prev == piece1);
		assert(piece2.next == storage.sentinel);
		assert(piece1.prev == storage.sentinel);
	}

	PieceRestoreRange insertAt(PieceRef newPiece, size_t insertPos)
	{
		assert(newPiece);
		assert(newPiece.length > 0);

		if (insertPos >= length) // At the end of text
		{
			auto last = sentinel.prev;

			PieceRestoreRange restoreRange = PieceRestoreRange(last, sentinel, length, true);

			length += newPiece.length;

			last.next = newPiece;
			newPiece.prev = last;

			newPiece.next = sentinel;
			sentinel.prev = newPiece;

			return restoreRange;
		}

		auto pair = pieceAt(insertPos);

		if (insertPos == pair.pos) // At the begining of piece
		{
			PieceRef before = pair.piece.prev;
			PieceRef after = pair.piece;

			PieceRestoreRange restoreRange = PieceRestoreRange(pair.piece.prev, pair.piece, length, true);

			before.next = newPiece;
			newPiece.prev = before;

			newPiece.next = after;
			after.prev = newPiece;

			length += newPiece.length;

			return restoreRange;
		}
		else // In the middle of piece
		{
			auto restoreRange = PieceRestoreRange(pair.piece, pair.piece, length);

			length += newPiece.length;

			PieceRef before = pair.piece.prev;
			PieceRef after = pair.piece.next;

			auto leftPieceLength = insertPos - pair.pos;
			auto rightPiecePos = pair.piece.bufferOffset + leftPieceLength;

			PieceRef leftPiece = createPiece(pair.piece.bufferOffset, leftPieceLength, before, newPiece);
			PieceRef rightPiece = createPiece(rightPiecePos, pair.piece.length - leftPieceLength, newPiece, after);

			before.next = leftPiece;

			newPiece.prev = leftPiece;
			newPiece.next = rightPiece;

			after.prev = rightPiece;

			return restoreRange;
		}
	}
}

private PieceRef createPiece(size_t position = 0, size_t length = 0, PieceRef prev = null, PieceRef next = null)
{
	return new Piece(position, length, prev, next);
}

import std.stdio;
struct PieceTable
{
	PieceStorage pieces;
	// Stores original text followed by inserted text.
	Appender!(char[]) buffer;

	/// Returns appended text length in bytes
	size_t appendBuffer(S)(S text)
	{
		auto initialLength = buffer.data.length;
		buffer ~= text;
		size_t textLength = buffer.data.length - initialLength;
		return textLength;
	}

	this(S)(S initialText)
	{
		pieces = pieceStorage();
		if (initialText.empty) return; // sequence cannot contain empty pieces
		size_t textLength = appendBuffer(initialText);
		pieces.insertBack(createPiece(0, textLength));
	}

	unittest
	{
		PieceTable table = PieceTable("test");
		assert(table.length == 4);
		table = PieceTable("абвгде");
		assert(table.length == 12);
	}

	Range!char opSlice()
	{
		if (!pieces.length)
			return Range!char();

		PieceRef first = pieces.sentinel.next;
		PieceRef last = pieces.sentinel.prev;
		size_t lastOffset = last.length;
		return Range!char(first, 0, last, lastOffset,
			pieces.length, cast(string)buffer.data);
	}

	Range!char opSlice(size_t x, size_t y)
	{
		assert(x <= y, format("%s <= %s", x, y));
		assert(y <= length, format("%s <= %s", y, length));
		if (x == y) return Range!char();

		PieceWithPos first = pieces.pieceAt(x);
		PieceWithPos last;

		if (y == length)
			last = PieceWithPos(pieces.sentinel.prev, pieces.sentinel.prev.length);
		else
			last = first.pieceAt(y);

		return Range!char(
			first.piece, x-first.pos,
			last.piece, y-last.pos,
			y - x,
			cast(string)buffer.data);
	}

	size_t length() @property { return pieces.length; }
	alias opDollar = length;

	unittest
	{
		PieceTable table = PieceTable("абвгде");

		assert("абвгде".length == 12);
		//writefln("%s", "абвгде".length);
		assert(table.length == 12);
		//writefln("%s", table.length);
		assert(table[0..2].length == 2);

		//writefln("%s", table[0..$]);
		//writefln("%s", table[]);
		assert(table[0..$].equalDchars(table[]));
		//writefln("1: %s где", table[6..$]);
		assert(table[6..$].equalDchars("где"));
		assert(table[0..6].equalDchars("абв"));
		//assertThrown!AssertError(table[6..2]);
		assert(table[0..12].equalDchars(table[]));

		auto range = table[0..$];
		assert(range.equalDchars(range.save[0..$]));
		assert((table[4..8])[0..2].length == 2);
		assert((table[4..8])[0..2].equalDchars("в"));
	}

	/// Remove sequence of text starting at index of length length
	/*
	 *    |---------| - Piece
	 *
	 * 1. |XXXXX----| - Remove from begining to the middle
	 *
	 * 2. |XXXXXXXXX| - Remove whole piece
	 *
	 * 3. |XXXXXXXXX|XXX... - Remove whole piece and past piece
	 *
	 * 4. |--XXXXX--| - Remove in the middle of piece
	 *
	 * 5. |--XXXXXXX| - Remove from middle to the end of piece
	 *
	 * 6. |--XXXXXXX|XXX... - Remove from middle and past piece
	 */
	PieceRestoreRange remove(size_t removePos, size_t removeLength)
	{
		assert(removePos < pieces.length && removeLength > 0);

		if (removePos + removeLength > length)
		{
			removeLength = length - removePos;
		}

		size_t removeEnd = removePos + removeLength - 1;

		// First piece in the sequence.
		PieceWithPos first = pieces.pieceAt(removePos);
		PieceWithPos last = first.pieceAt(removeEnd);
		size_t lastEnd = last.pos + last.piece.length - 1;

		PieceRef newPieces = first.piece.prev;

		// handle cases 4, 5 and 6.
		if (removePos > first.pos)
		{
			PieceRef subPiece = createPiece(first.piece.bufferOffset, removePos - first.pos, newPieces);
			newPieces.next = subPiece;
			newPieces = subPiece;
		}

		// Handle cases 1 and 4
		if (removeEnd < lastEnd)
		{
			auto offset = removeEnd - last.pos + 1;
			PieceRef subPiece = createPiece(last.piece.bufferOffset + offset, lastEnd - removeEnd, newPieces);
			newPieces.next = subPiece;
			newPieces = subPiece;
		}

		PieceRef after = last.piece.next;
		newPieces.next = after;
		after.prev = newPieces;

		auto undoItem = PieceRestoreRange(first.piece, last.piece, pieces.length);

		pieces.length -= removeLength;

		return undoItem;
	}

	unittest
	{
		PieceTable table = PieceTable("абвгде");

		assert(table.length == 12);
		auto piece1 = table.pieces.sentinel.next;

		table.remove(0, 2); // case 1
		assert(table.length == 10);
		assert(equalDchars(table[], "бвгде"));

		table.remove(0, 12); // case 2
		assert(table.length == 0);
		assert(equalDchars(table[], ""));

		table = PieceTable("абвгде");

		table.remove(4, 2); // case 4
		assert(table.pieces.sentinel.next.length == 4);
		assert(table.pieces.sentinel.next.next.length == 6);
		assert(table.pieces.sentinel.prev.length == 6);
		assert(table.pieces.sentinel.prev.prev.length == 4);
		assert(table.length == 10);
		assert(equalDchars(table[], "абгде"));

		table.remove(0, 10); // case 3 + case 2
		assert(table.length == 0);
		assert(equalDchars(table[], ""));

		table = PieceTable("абвгде");

		table.remove(4, 8); // case 5
		assert(table.length == 4);
		assert(equalDchars(table[], "аб"));

		table = PieceTable("абвгде");

		table.remove(4, 2);
		table.remove(2, 10); // case 6 + case 2
		assert(table.length == 2);
		assert(equalDchars(table[], "а"));

		table = PieceTable("аб");
		table.insert("вг");
		table.insert("де");
		table.remove(4, 4);
		assert(table[].equalDchars("абде"));
	}

	PieceRestoreRange insert(S)(S text)
		if (isSomeString!S || (isInputRange!S && isSomeChar!(ElementType!S)))
	{
		return insert(length, text);
	}

	PieceRestoreRange insert(S)(size_t insertPos, S text)
		if (isSomeString!S || (isInputRange!S && isSomeChar!(ElementType!S)))
	{
		size_t bufferPos = buffer.data.length;
		size_t textLength = appendBuffer(text);

		PieceRef middlePiece = createPiece(bufferPos, textLength);

		return pieces.insertAt(middlePiece, insertPos);
	}

	unittest
	{
		PieceTable table = PieceTable("абвгде");

		table.insert(0, "абв");
		assert(table.length == 18);
		assert(equalDchars(table[], "абвабвгде"));

		table.insert(18, "абв");
		assert(table.length == 24);
		assert(equalDchars(table[], "абвабвгдеабв"));

		table = PieceTable("абвгде");
		table.insert(6, "ggg");
		assert(table.length == 15);
		assert(equalDchars(table[], "абвgggгде"));
	}

	unittest
	{
		PieceTable table = PieceTable("\ntest");
		table.insert(0, "d");
		assert(equalDchars(table[], "d\ntest"));
	}

	unittest
	{
		PieceTable table = PieceTable("");

		table.insert(4, "абв");
		table.insert(4, "абв");
		assert(table.length == 12);
		assert(equalDchars(table[], "абабвв"));
	}
}

private struct Range(T)
{
	private PieceRef first;
	private size_t firstOffset;
	private PieceRef last;
	private size_t lastOffset;
	private size_t _length;
	private string buffer;
	size_t length() @property { return _length; }
	alias opDollar = length;
	bool empty() @property { return _length == 0; }
	T front() @property {
		static if (is(T == char))
			return buffer[first.bufferOffset + firstOffset];
		else // dchar
		{
			auto offset = first.bufferOffset + firstOffset;
			auto str = buffer[offset..$];
			if (str.length == 0)
			{
				writefln("str [%s..%s]", offset, buffer.length);
			}
			return decodeFront!(Yes.useReplacementDchar)(str);
		}
	}
	T back() @property {
		static if (is(T == char))
			return buffer[first.bufferOffset + firstOffset];
		else // dchar
		{
			uint backLength = strideBack(buffer, last.bufferOffset + lastOffset);
			auto pos = last.bufferOffset + lastOffset - backLength;
			return decode!(Yes.useReplacementDchar)(buffer, pos);
		}
	}

	void popFront() {
		static if (is(T == char))
			uint frontLength = 1;
		else // dchar
			uint frontLength = stride(buffer, first.bufferOffset + firstOffset);

		firstOffset += frontLength;
		_length -= frontLength;

		if (firstOffset == first.length)
		{
			first = first.next;
			firstOffset = 0;
		}
	}

	void popBack()
	{
		static if (is(T == char))
			uint backLength = 1;
		else // dchar
			uint backLength = strideBack(buffer, last.bufferOffset + lastOffset);

		lastOffset -= backLength;
		_length -= backLength;

		if (lastOffset == 0)
		{
			last = last.prev;
			lastOffset = last.length;
		}
	}

	Range opSlice(size_t x, size_t y)
	{
		assert(x <= y);
		assert(y <= _length);
		if (x == y) return Range();

		PieceWithPos first = PieceWithPos(this.first, 0).pieceAt(firstOffset + x);
		PieceWithPos last = first.pieceAt(y);

		return Range(
			first.piece, firstOffset + x - first.pos,
			last.piece, y-last.pos,
			y - x,
			buffer);
	}

	Range save() { return this; }

	static if (is(T == dchar))
	Range!char byChar() {
		return cast(Range!char)this;
	}

	import voxelman.container.chunkedrange;
	ChunkedRange!char toChunkedRange()
	{
		if (_length == 0) return ChunkedRange!char(null, 0, null, null, &ChunkedRange_popFront);
		size_t itemsLeft = _length;
		size_t chunkLength = min(itemsLeft, first.length-firstOffset);
		auto from = first.bufferOffset + firstOffset;
		auto to = from + chunkLength;
		itemsLeft -= chunkLength;
		auto front = buffer[from..to];
		return ChunkedRange!char(
			cast(char[])front, itemsLeft, cast(void*)first.next, cast(void*)buffer.ptr, &ChunkedRange_popFront);
	}

	private static void ChunkedRange_popFront(
		ref char[] front,
		ref size_t itemsLeft,
		ref void* nextPieceData,
		ref void* bufferData)
	{
		PieceRef nextPiece = cast(PieceRef)nextPieceData;
		char* buffer = cast(char*)bufferData;

		if (itemsLeft == 0)
		{
			front = null;
			return;
		}

		size_t chunkLength = min(itemsLeft, nextPiece.length);
		front = buffer[nextPiece.bufferOffset..nextPiece.bufferOffset+chunkLength];
		nextPiece = nextPiece.next;

		itemsLeft -= chunkLength;

		nextPieceData = cast(void*)nextPiece;
	}

	void copyInto(char[] sink)
	{
		assert(sink.length == _length);

		auto bytesLeft = _length;

		void copyChunk(size_t from, size_t to)
		{
			auto chunkLen = to - from;
			sink[0..chunkLen] = buffer[from..to];
			sink = sink[chunkLen..$];
			bytesLeft -= chunkLen;
		}

		// copy first
		auto firstFrom = first.bufferOffset + firstOffset;
		auto firstLen = min(first.length - firstOffset, bytesLeft);
		auto firstTo = firstFrom + firstLen;
		copyChunk(firstFrom, firstTo);

		// copy other pieces
		auto piece = first.next;
		while(piece != last.next)
		{
			auto from = piece.bufferOffset;
			auto to = from + min(piece.length, bytesLeft);
			copyChunk(from, to);
			piece = piece.next;
		}

		assert(sink.length == 0); // filled sink fully
	}
}

static assert(isForwardRange!(Range!dchar));
static assert(hasSlicing!(Range!dchar));
static assert(isBidirectionalRange!(Range!dchar));
static assert(isForwardRange!(Range!char));
static assert(hasSlicing!(Range!char));
static assert(isBidirectionalRange!(Range!char));

version(unittest) string callCopy(PieceTable table, size_t from, size_t to)
{
	char[] buf = new char[to-from];
	table[from..to].copyInto(buf);
	return cast(string)buf;
}

unittest
{
	PieceTable table = PieceTable("abcd");
	assert(table.callCopy(0, 4).equalDchars("abcd"));
	assert(table.callCopy(1, 4).equalDchars("bcd"));
	assert(table.callCopy(1, 3).equalDchars("bc"));
}
