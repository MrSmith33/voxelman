/**
Copyright: Copyright (c) 2015-2017 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.text.textformatter;

import std.array;
import std.format;
import std.range;

char[4*1024] buf;
Appender!(char[]) app;

static this()
{
	app = appender(buf[]);
}

static struct TextPtrs {
	char* start;
	char* end;
}

const(char)[] makeFormattedText(Args ...)(string fmt, Args args) {
	app.clear();
	formattedWrite(app, fmt, args);
	return app.data;
}

TextPtrs makeFormattedTextPtrs(Args ...)(string fmt, Args args) {
	app.clear();
	formattedWrite(app, fmt, args);
	app.put("\0");
	return TextPtrs(app.data.ptr, app.data.ptr + app.data.length - 1);
}

void igTextf(Args ...)(string fmt, Args args)
{
	import derelict.imgui.imgui : igTextUnformatted;
	TextPtrs pair = makeFormattedTextPtrs(fmt, args);
	igTextUnformatted(pair.start, pair.end);
}

struct DigitSeparator(T, uint groupSize, char groupSeparator)
{
	T value;
	void toString(scope void delegate(const(char)[]) sink,
				  FormatSpec!char fmt) const
	{
		uint base =
			fmt.spec == 'x' || fmt.spec == 'X' ? 16 :
			fmt.spec == 'o' ? 8 :
			fmt.spec == 'b' ? 2 :
			fmt.spec == 's' || fmt.spec == 'd' || fmt.spec == 'u' ? 10 :
			0;
		assert(base > 0);
		formatIntegral(sink, value, fmt, base, groupSize, groupSeparator, ulong.max);
	}
}

// Modified version from std.format.
private void formatIntegral(Writer, T, Char)(Writer w, const(T) val, const ref FormatSpec!Char fmt, uint base, uint groupSize, char groupSeparator, ulong mask)
{
	T arg = val;

	bool negative = (base == 10 && arg < 0);
	if (negative)
	{
		arg = -arg;
	}

	// All unsigned integral types should fit in ulong.
	static if (is(ucent) && is(typeof(arg) == ucent))
		formatUnsigned(w, (cast(ucent) arg) & mask, fmt, base, groupSize, groupSeparator, negative);
	else
		formatUnsigned(w, (cast(ulong) arg) & mask, fmt, base, groupSize, groupSeparator, negative);
}

// Modified version from std.format.
private void formatUnsigned(Writer, T, Char)(Writer w, T arg, const ref FormatSpec!Char fmt, uint base, uint groupSize, char groupSeparator, bool negative)
{
	/* Write string:
	 *    leftpad prefix1 prefix2 zerofill digits rightpad
	 */

	/* Convert arg to digits[].
	 * Note that 0 becomes an empty digits[]
	 */
	char[128] buffer = void; // 64 bits in base 2 at most and 1 separator for each
	char[] digits;
	{
		size_t i = buffer.length;
		size_t curGroupDigits = 0;
		while (arg)
		{
			--i;
			char c = cast(char) (arg % base);
			arg /= base;

			if (curGroupDigits == groupSize) {
				buffer[i] = groupSeparator;
				--i;
				curGroupDigits = 0;
			}

			if (c < 10)
				buffer[i] = cast(char)(c + '0');
			else
				buffer[i] = cast(char)(c + (fmt.spec == 'x' ? 'a' - 10 : 'A' - 10));

			++curGroupDigits;
		}
		digits = buffer[i .. $]; // got the digits without the sign
	}


	int precision = (fmt.precision == fmt.UNSPECIFIED) ? 1 : fmt.precision;

	char padChar = 0;
	if (!fmt.flDash)
	{
		padChar = (fmt.flZero && fmt.precision == fmt.UNSPECIFIED) ? '0' : ' ';
	}

	// Compute prefix1 and prefix2
	char prefix1 = 0;
	char prefix2 = 0;
	if (base == 10)
	{
		if (negative)
			prefix1 = '-';
		else if (fmt.flPlus)
			prefix1 = '+';
		else if (fmt.flSpace)
			prefix1 = ' ';
	}
	else if (base == 16 && fmt.flHash && digits.length)
	{
		prefix1 = '0';
		prefix2 = fmt.spec == 'x' ? 'x' : 'X';
	}
	// adjust precision to print a '0' for octal if alternate format is on
	else if (base == 8 && fmt.flHash &&
			 (precision <= 1 || precision <= digits.length)) // too low precision
		prefix1 = '0';

	size_t zerofill = precision > digits.length ? precision - digits.length : 0;
	size_t leftpad = 0;
	size_t rightpad = 0;

	ptrdiff_t spacesToPrint = fmt.width - ((prefix1 != 0) + (prefix2 != 0) + zerofill + digits.length);
	if (spacesToPrint > 0) // need to do some padding
	{
		if (padChar == '0')
			zerofill += spacesToPrint;
		else if (padChar)
			leftpad = spacesToPrint;
		else
			rightpad = spacesToPrint;
	}

	/**** Print ****/

	foreach (i ; 0 .. leftpad)
		put(w, ' ');

	if (prefix1) put(w, prefix1);
	if (prefix2) put(w, prefix2);

	foreach (i ; 0 .. zerofill)
		put(w, '0');

	put(w, digits);

	foreach (i ; 0 .. rightpad)
		put(w, ' ');
}
