/**
Copyright: Copyright (c) 2017-2018 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/

module voxelman.edit.tools.itool;

import voxelman.graphics.plugin;

abstract class ITool
{
	string name;
	size_t id;
	void onUpdate() {}
	void onRender(GraphicsPlugin renderer) {}
	void onShowDebug() {}
	void onMainActionPress() {}
	void onMainActionRelease() {}
	void onSecondaryActionPress() {}
	void onSecondaryActionRelease() {}
	void onTertiaryActionPress() {}
	void onTertiaryActionRelease() {}
	void onRotateAction() {}
}
