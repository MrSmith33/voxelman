/**
Copyright: Copyright (c) 2015-2017 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.text.messagewindow;

struct MessageWindow
{
	import voxelman.text.linebuffer : LineBuffer;
	LineBuffer lineBuffer;
	alias lineBuffer this;
	void delegate(string command) messageHandler;
}
