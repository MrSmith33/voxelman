/**
Copyright: Copyright (c) 2014-2017 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/

module voxelman.gui.textedit.linebuffer;

import voxelman.math;
import std.stdio;
import std.format : formattedWrite;
import voxelman.gui.textedit.cursor;

enum int NUM_BYTES_HIGH_BIT = 1<<31;
enum int NUM_BYTES_MASK = NUM_BYTES_HIGH_BIT - 1;

struct LineInfo
{
	this(int startOffset, int numBytes, int numBytesEol)
	{
		assert(numBytesEol > 0 && numBytesEol < 3);
		this.startOffset = startOffset;
		this.numBytesStorage = ((numBytesEol-1) << 31) | numBytes;
	}

	int startOffset;
	int numBytesStorage;  // excluding newline

	int endOffset() { return startOffset + numBytes; }
	int nextStartOffset() { return startOffset + numBytesTotal; }
	int numBytesEol() { return (numBytesStorage >> 31) + 1; }
	int numBytes() { return numBytesStorage & NUM_BYTES_MASK; } // excluding newline
	void numBytes(int bytes) { numBytesStorage = numBytesStorage & NUM_BYTES_HIGH_BIT | bytes; } // excluding newline
	int numBytesTotal() { return numBytes + numBytesEol; }

	void toString(scope void delegate(const(char)[]) sink)
	{
		sink.formattedWrite("LineInfo(off %s:%s; size %s:%s:%s)",
			startOffset, endOffset, numBytes, numBytesEol, numBytesTotal);
	}
}

// should be only used for small files (< int.max lines)
import voxelman.text.lexer;
struct LineInfoBuffer
{
	import voxelman.container.gapbuffer;
	GapBuffer!LineInfo lines;
	int maxLineSize = 0;
	int numLines = 0;
	int lastLine() { return numLines > 0 ? numLines - 1 : 0; }
	int textEnd = 0;

	void clear() {
		lines.clear();
		lines.put(LineInfo(0, 0, 1));
		maxLineSize = 0;
		numLines = 1;
		textEnd = 0;
		lastValidLine = 0;
	}

	size_t lastValidLine;

	ref LineInfo lineInfo(int lineIndex)
	{
		if (numLines == 0) lines.put(LineInfo(0, 0, 1));
		updateOffsetsToLine(lineIndex);
		return lines[lineIndex];
	}
	alias opIndex = lineInfo;

	int lineStartOffset(int lineIndex)
	{
		if (numLines == 0) return 0;
		updateOffsetsToLine(lineIndex);
		return lines[lineIndex].startOffset;
	}

	// Does not include newline bytes
	int numLineBytes(int lineIndex)
	{
		if (numLines == 0) return 0;
		updateOffsetsToLine(lineIndex);
		return lines[lineIndex].numBytes;
	}

	int numLineTotalBytes(int lineIndex)
	{
		if (numLines == 0) return 0;
		updateOffsetsToLine(lineIndex);
		return lines[lineIndex].numBytesTotal;
	}

	int lineEndOffset(int lineIndex)
	{
		if (numLines == 0) return 0;
		updateOffsetsToLine(lineIndex);
		return lines[lineIndex].endOffset;
	}

	int calc(R)(R text)
	{
		import std.regex : ctRegex, splitter;
		import std.algorithm : map;
		import std.range;
		import std.string;
		import std.utf : byDchar;

		lines.clear();

		auto stream = CharStream!R(text);
		size_t startOffset;
		size_t lineSize;

		while(!stream.empty)
		{
			auto bytePos = stream.currentOffset;
			if (stream.matchAnyOf('\n', '\v', '\f') || (stream.match('\r') && stream.matchOpt('\n')))
			{
				auto lineBytes = bytePos - startOffset;
				auto eolBytes = stream.currentOffset - bytePos;
				lines.put(LineInfo(cast(int)startOffset, cast(int)lineBytes, cast(int)eolBytes));
				maxLineSize = max(maxLineSize, cast(int)lineSize);
				startOffset = stream.currentOffset;
			}
			else
			{
				stream.next;
				++lineSize;
			}
		}

		// last line
		auto lineBytes = stream.currentOffset - startOffset;
		lines.put(LineInfo(cast(int)startOffset, cast(int)lineBytes, 1));

		textEnd = cast(int)stream.currentOffset;
		numLines = cast(int)lines.length;
		lastValidLine = lastLine;

		return numLines;
	}

	// returns number of inserted lines
	int onPaste(R)(const Cursor at, R text)
	{
		auto stream = CharStream!R(text);
		size_t startOffset;
		size_t lineSize;
		size_t lineIndex = at.line;

		LineInfo firstLine = lineInfo(at.line);

		auto oldBytesLeft = at.byteOffset - firstLine.startOffset;
		auto oldBytesRight = firstLine.numBytes - oldBytesLeft;
		auto oldEolBytes = at.line == lastLine ? 1 : firstLine.numBytesEol;

		while(!stream.empty)
		{
			auto bytePos = stream.currentOffset;
			if (stream.matchAnyOf('\n', '\v', '\f') || (stream.match('\r') && stream.matchOpt('\n')))
			{
				auto lineBytes = bytePos - startOffset;
				auto eolBytes = stream.currentOffset - bytePos;
				if (lineIndex == at.line)
				{
					// first line
					auto totalNewBytes = oldBytesLeft + lineBytes;
					lines[at.line] = LineInfo(firstLine.startOffset, cast(int)totalNewBytes, cast(int)eolBytes);
				}
				else
					lines.putAt(lineIndex, LineInfo(cast(int)(at.byteOffset + startOffset), cast(int)lineBytes, cast(int)eolBytes));
				maxLineSize = max(maxLineSize, cast(int)lineSize);
				startOffset = stream.currentOffset;
				++lineIndex;
			}
			else
			{
				stream.next;
				++lineSize;
			}
		}

		auto lineBytes = stream.currentOffset - startOffset;

		// last line
		if (lineIndex == at.line)
		{
			// and first line. no trailing newline
			auto totalNewBytes = oldBytesLeft + lineBytes + oldBytesRight;
			lines[at.line] = LineInfo(firstLine.startOffset, cast(int)totalNewBytes, cast(int)oldEolBytes);
		}
		else
		{
			// not a first line in text
			auto totalNewBytes = lineBytes + oldBytesRight;
			lines.putAt(lineIndex, LineInfo(cast(int)(at.byteOffset + startOffset), cast(int)totalNewBytes, cast(int)oldEolBytes));
		}
		textEnd += cast(int)stream.currentOffset;
		numLines = cast(int)lines.length;
		lastValidLine = lineIndex;

		return cast(int)(lineIndex - at.line);
	}

	void onRemove(Cursor from, Cursor to)
	{
		auto numBytesRemoved = to.byteOffset - from.byteOffset;
		if (numBytesRemoved == 0) return;

		textEnd -= numBytesRemoved;

		// we collapse all info into the first line
		// extra lines are removed. First line stays in place.

		LineInfo first = lineInfo(from.line);
		LineInfo last = lineInfo(to.line); // can be the same as first
		//-writefln("first %s", first);
		//-writefln("last %s", last);

		// from.byteOffset >= first.startOffset; firstBytesLeft >= 0;
		auto firstBytesLeft = from.byteOffset - first.startOffset;
		//-writefln("firstBytesLeft %s", firstBytesLeft);
		// to.byteOffset >= last.startOffset; lastBytesRemoved >= 0;
		auto lastBytesRemoved = to.byteOffset - last.startOffset;
		//-writefln("lastBytesRemoved %s", lastBytesRemoved);
		auto lastBytesRight = last.numBytes - lastBytesRemoved;
		//-writefln("lastBytesRight %s", lastBytesRight);
		auto totalFirstBytes = firstBytesLeft + lastBytesRight;
		//-writefln("totalFirstBytes %s", totalFirstBytes);

		// update data in first line
		lines[from.line] = LineInfo(first.startOffset, cast(int)totalFirstBytes, last.numBytesEol);
		//-writefln("lines[from.line] = %s", lines[from.line]);

		// remove extra lines
		size_t numLinesToRemove = to.line - from.line;
		if (numLinesToRemove > 0)
		{
			lines.remove(from.line + 1, numLinesToRemove);
			numLines -= numLinesToRemove;
		}

		lastValidLine = from.line;
	}

	void updateOffsetsToLine(int toLine)
	{
		assert(toLine <= lastLine);
		if (toLine <= lastValidLine) return;
		//writefln("updateOffsetsToLine %s", toLine);

		auto startOffset = lines[lastValidLine].startOffset;
		auto prevBytes = lines[lastValidLine].numBytesTotal;
		foreach(ref line; lines[lastValidLine+1..toLine+1])
		{
			startOffset += prevBytes;
			line.startOffset = startOffset;
			prevBytes = line.numBytesTotal;
		}
		lastValidLine = toLine;
	}

	void print()
	{
		foreach(line; lines[])
		{
			writefln("%s %s+%s=%s", line.startOffset, line.numBytes, line.numBytesEol, line.numBytesTotal);
			assert(line.numBytes + line.numBytesEol == line.numBytesTotal);
		}
	}
}

unittest
{
	LineInfoBuffer buf; buf.calc("abcd");
	buf.onRemove(Cursor(0, 0), Cursor(4, 0));
	assert(buf[0] == LineInfo(0, 0, 1));
}

unittest
{
	LineInfoBuffer buf; buf.calc("abcd");
	buf.onRemove(Cursor(1, 0), Cursor(3, 0));
	assert(buf[0] == LineInfo(0, 2, 1));
}

unittest
{
	LineInfoBuffer buf; buf.calc("ab\ncd");
	assert(buf.numLines == 2);
	assert(buf.lastLine == 1);
	assert(buf.textEnd == 5);

	buf.onRemove(Cursor(1, 0), Cursor(4, 1));

	assert(buf[0] == LineInfo(0, 2, 1));
	assert(buf.numLines == 1);
	assert(buf.lastLine == 0);
	assert(buf.textEnd == 2);
}
