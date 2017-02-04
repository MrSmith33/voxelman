/**
Copyright: Copyright (c) 2013-2017 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/

module anchovy.iwindow;

import voxelman.math;
import anchovy.signal;
import anchovy.isharedcontext;

abstract class IWindow
{
	void init(ivec2 size, in string caption, bool center = false);
	ISharedContext createSharedContext();
	void reshape(ivec2 viewportSize);
	void moveToCenter();
	void processEvents(); // will emit signals
	double elapsedTime() @property; // in seconds
	void swapBuffers();
	void releaseWindow();

	void mousePosition(ivec2 newPosition) @property;
	ivec2 mousePosition() @property;

	ivec2 size() @property;
	ivec2 framebufferSize() @property;
	void size(ivec2 newSize) @property;

	bool isKeyPressed(uint key);

	string clipboardString() @property;
	void clipboardString(string newClipboardString) @property;

	void isCursorLocked(bool value);
	bool isCursorLocked();

	Signal!uint keyPressed;
	Signal!uint keyReleased;
	Signal!dchar charEntered;
	Signal!uint mousePressed;
	Signal!uint mouseReleased;
	Signal!ivec2 mouseMoved;
	Signal!bool focusChanged;
	Signal!ivec2 windowResized;
	Signal!ivec2 windowMoved;
	Signal!bool windowIconified;
	Signal!dvec2 wheelScrolled;
	Signal!() closePressed;
	Signal!() refresh;
}
