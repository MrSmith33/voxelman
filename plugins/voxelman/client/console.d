/**
Copyright: Copyright (c) 2015-2018 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.client.console;

import voxelman.log;
import voxelman.gui;
import voxelman.gui.textedit.lineedit;
import voxelman.gui.textedit.messagelog;
import voxelman.gui.textedit.texteditorview;
import voxelman.gui.textedit.textmodel;
import voxelman.graphics;
import voxelman.math;

struct Console
{
	MessageLog messages;
	MessageLogTextModel messagesModel;
	TextViewSettings editorSettings;

	void delegate(string command) messageHandler;
	bool isConsoleShown;

	WidgetProxy viewport;
	WidgetProxy input;

	void create(GuiContext guictx, void delegate(string command) messageHandler)
	{
		guictx.style.pushColor(Colors.white);

		this.messageHandler = messageHandler;

		auto con = guictx.createWidget(WidgetType("console"))
			.hexpand
			.minSize(0, 200)
			.visible_if(() => isConsoleShown)
			.addBackground(Color4ub(128, 128, 128, 128))
			.setVLayout(0, padding4(0));

		guictx.roots ~= con;

		editorSettings.font = guictx.style.font;
		editorSettings.color = cast(Color4ub)Colors.white;

		messages = MessageLog(null);
		messages.setClipboard = guictx.state.setClipboard;
		messagesModel = new MessageLogTextModel(&messages);

		viewport = TextEditorViewportLogic.create(con, messagesModel, &editorSettings).hvexpand;
		hline(con);
		input = LineEdit.create(con, &onInput).hexpand;

		viewport.get!TextEditorViewportData.autoscroll = true;

		guictx.style.popColor;
	}

	void onInput(string command)
	{
		if (messageHandler) messageHandler(command);
		LineEdit.clear(input);
	}

	void onConsoleToggleKey(string)
	{
		isConsoleShown = !isConsoleShown;
		input.setFocus(isConsoleShown);
	}
}
