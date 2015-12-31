/**
Copyright: Copyright (c) 2013-2015 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/

module anchovy.iwindow;

import dlib.math.vector;
import anchovy.signal;

abstract class IWindow
{
	void init(uvec2 size, in string caption);
	void reshape(uvec2 viewportSize);
	void processEvents(); // will emit signals
	double elapsedTime() @property; // in seconds
	void swapBuffers();
	void releaseWindow();

	void mousePosition(ivec2 newPosition) @property;
	ivec2 mousePosition() @property;

	uvec2 size() @property;
	uvec2 framebufferSize() @property;
	void size(uvec2 newSize) @property;

	bool isKeyPressed(uint key);

	string clipboardString() @property;
	void clipboardString(string newClipboardString) @property;

	Signal!uint keyPressed;
	Signal!uint keyReleased;
	Signal!dchar charEntered;
	Signal!uint mousePressed;
	Signal!uint mouseReleased;
	Signal!ivec2 mouseMoved;
	Signal!bool focusChanged;
	Signal!uvec2 windowResized;
	Signal!ivec2 windowMoved;
	Signal!bool windowIconified;
	Signal!dvec2 wheelScrolled;
	Signal!() closePressed;
}
