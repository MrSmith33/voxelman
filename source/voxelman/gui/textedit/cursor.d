/**
Copyright: Copyright (c) 2017-2018 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.gui.textedit.cursor;

import voxelman.gui.textedit.linebuffer;

struct Cursor
{
	size_t byteOffset;
	int line;
}

enum MoveCommand
{
	move_right_char,
	move_right_word,
	move_left_char,
	move_left_word,
	move_up_line,
	move_up_page,
	move_down_line,
	move_down_page,
	move_to_bol,
	move_to_eol,
}


