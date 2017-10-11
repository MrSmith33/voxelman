/**
Copyright: Copyright (c) 2017 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.text.lexer;

//import std.array;
import std.range;
import std.uni;
import std.utf : byDchar, decodeFront;
import std.stdio;

struct Stack(T)
{
	import std.array;
	T[] data;
	@property bool empty(){ return data.empty; }
	@property size_t length(){ return data.length; }
	void push(T val){ data ~= val; }
	T pop()
	{
		assert(!empty);
		auto val = data[$ - 1];
		data = data[0 .. $ - 1];
		if (!__ctfe)
			cast(void)data.assumeSafeAppend();
		return val;
	}
}

enum TokenType
{
	SOI, // start of input
	Invalid,
	Hexadecimal,
	Binary,
	Decimal,
	String,
	LabelDefinition,
	ReservedWord,
	BinaryOpCode,
	UnaryOpCode,
	Register,
	Identifier,
	OpenBracket,
	CloseBracket,
	Plus,
	Minus,
	Multiply,
	Divide,
	Comma,
	EOI // end of input
}

struct Token
{
	TokenType type;
	StreamPos start;
	StreamPos end;
}

struct StreamPos
{
	int pos = -1;
}

struct CharStream(R)
	if (isForwardRange!R && is(ElementType!R : dchar))
{
	R originalInput;

	struct StreamState
	{
		dchar current = '\2'; // start of text
		bool empty;
		StreamPos currentPos;
		R input;
		size_t currentOffset;
	}

	StreamState _state;
	alias _state this;

	Stack!StreamState _checkpointStack;

	this(R inp)
	{
		originalInput = input = inp;
		next();
	}

	/// Returns false if input is empty
	/// Updates current and returns true otherwise
	bool next()
	{
		if (input.empty)
		{
			//writefln("next empty front %s ", current);
			if (!this.empty) // advance past last char
			{
				++currentPos.pos;
				currentOffset = originalInput.length - this.input.length;
				current = '\3'; // end of text
			}

			this.empty = true;
			return false;
		}

		currentOffset = originalInput.length - this.input.length;
		current = decodeFront!(Yes.useReplacementDchar)(input);
		++currentPos.pos;
		//input.popFront();
		//writefln("next, state %s", _state);
		return true;
	}

	/// Skips zero or more whitespace chars consuming input
	void skipSpace()
	{
		while (isWhite(current) && next()) {}
	}

	/// Matches all chars from str consuming input and returns true
	/// If fails consumes no input and returns false
	bool match(R)(R str)
		if (isInputRange!R && is(ElementType!R : dchar))
	{
		pushCheckpoint;
		foreach (dchar item; str.byDchar)
		{
			if (this.empty)
			{
				popCheckpoint;
				return false;
			}

			if (toLower(item) != toLower(current))
			{
				popCheckpoint;
				return false;
			}

			next();
		}

		discardCheckpoint;
		return true;
	}

	bool match(dchar chr)
	{
		//if (input.empty) return false;

		if (current == chr)
		{
			next();
			return true;
		}

		return false;
	}

	bool matchCase(R)(R str)
		if (isInputRange!R && is(ElementType!R : dchar))
	{
		pushCheckpoint;
		foreach (dchar item; str.byDchar)
		{
			if (this.empty)
			{
				popCheckpoint;
				return false;
			}

			if (item != current)
			{
				popCheckpoint;
				return false;
			}

			next();
		}

		discardCheckpoint;
		return true;
	}

	/// Matches single char
	bool match(alias pred)()
	{
		//if (this.empty) return false;

		if (pred(current))
		{
			next();
			return true;
		}

		return false;
	}

	bool matchAnyOf(dchar[] options...)
	{
		//if (this.empty) return false;

		foreach (option; options)
		{
			if (option == current)
			{
				next();
				return true;
			}
		}

		return false;
	}

	bool matchOpt(dchar optional)
	{
		match(optional);
		return true;
	}

	/// save current stream position
	void pushCheckpoint() {
		_checkpointStack.push(_state);
	}

	/// restore saved position
	void discardCheckpoint() {
		_checkpointStack.pop;
	}

	/// restore saved position
	void popCheckpoint() {
		_state = _checkpointStack.pop;
	}
}

/*
	TokenMatcher(ctRegex!(r"^(0x[0-9ABCDEF]+)\b","i"), TokenType.Hexadecimal),
	TokenMatcher(ctRegex!(r"^(0b[0-1]+)\b","i"), TokenType.Binary),
	TokenMatcher(ctRegex!(r"^([0-9]+)\b"), TokenType.Decimal),
	TokenMatcher(ctRegex!( "^(\".*\")"), TokenType.String),
	TokenMatcher(ctRegex!(r"^((:[0-9A-Za-z_]+)|([0-9A-Za-z_]+:))"), TokenType.LabelDefinition),
	TokenMatcher(ctRegex!(r"^(POP|PUSH|PEEK|PICK|DAT|DATA|DW|WORD)\b","i"), TokenType.ReservedWord),
	TokenMatcher(ctRegex!(r"^(SET|ADD|SUB|MUL|MLI|DIV|DVI|MOD|MDI|AND|BOR|XOR|SHR|ASR|SHL|IFB|IFC|IFE|IFN|IFG|IFA|IFL|IFU|ADX|SBX|STI|STD)\b","i"), TokenType.BinaryOpCode),
	TokenMatcher(ctRegex!(r"^(JSR|INT|IAG|IAS|RFI|IAQ|HWN|HWQ|HWI)\b", "i"), TokenType.UnaryOpCode),
	TokenMatcher(ctRegex!(r"^([ABCXYZIJ]|SP|PC|EX)\b","i"), TokenType.Register),
	TokenMatcher(ctRegex!(r"^([0-9A-Za-z_]+)"), TokenType.Identifier),
	TokenMatcher(ctRegex!(r"^\["), TokenType.OpenBracket),
	TokenMatcher(ctRegex!(r"^\+"), TokenType.Plus),
	TokenMatcher(ctRegex!(r"^-"), TokenType.Minus),
	TokenMatcher(ctRegex!(r"^\*"), TokenType.Multiply),
	TokenMatcher(ctRegex!(r"^/"), TokenType.Divide),
	TokenMatcher(ctRegex!(r"^\]"), TokenType.CloseBracket),
	TokenMatcher(ctRegex!("^,"), TokenType.Comma),
*/

bool isDigit(dchar chr) pure nothrow
{
	return '0' <= chr && chr <= '9';
}

bool isHexDigit(dchar chr) pure nothrow
{
	return
		'0' <= chr && chr <= '9' ||
		'a' <= chr && chr <= 'f' ||
		'A' <= chr && chr <= 'F';
}

struct TokenMatcher
{
	bool delegate() matcher;
	TokenType type;
}

alias StringLexer = Lexer!string;
struct Lexer(R)
{
	CharStream!R input;
	TokenMatcher[] matchers;
	Token current;
	bool empty;

	int opApply(scope int delegate(in Token) del)
	{
		do
		{
			if (auto ret = del(current))
				return ret;
			next();
		}
		while (!empty);
		return 0;
	}

	bool matchHexNumber()
	{
		if (!input.match("0x")) return false;
		if (!input.match!isHexDigit) return false;
		while (input.match!isHexDigit) {}
		return true;
	}

	bool matchComment()
	{
		if (!input.match("/")) return false;
		if (!input.match!isHexDigit) return false;
		while (input.match!isHexDigit) {}
		return true;
	}

	private void next()
	{
		if (checkInputState) return;

		foreach (matcher; matchers)
		{
			input.pushCheckpoint;
			StreamPos startPos = input.currentPos;

			bool matchSuccess = matcher.matcher();

			if (matchSuccess)
			{
				current = Token(matcher.type, startPos, input.currentPos);
				//writefln("success on %s, state %s", matcher.type, input._state);
				input.discardCheckpoint;
				return;
			}

			input.popCheckpoint;
			//writefln("fail %s", matcher.type);
		}

		current = Token(TokenType.Invalid, input.currentPos);
	}

	// returns true if no matching should be done
	private bool checkInputState()
	{
		if (input.empty)
		{
			if (current.type == TokenType.EOI) // on second try mark as empty and return
			{
				empty = true;
			}
			else // when input just became empty emit EOI token, but do not mark us as empty
			{
				current = Token(TokenType.EOI, input.currentPos);
			}

			return true; // exit matching
		}

		return false; // continue matching
	}
}
