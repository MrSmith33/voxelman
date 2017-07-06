/**
Copyright: Copyright (c) 2017 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/

module voxelman.gui;

public import datadriven : Component, Replication;
public import voxelman.gui.components;
public import voxelman.gui.events;
public import voxelman.gui.guicontext;
public import voxelman.gui.eventpropagators;
public import voxelman.gui.widgets;

import datadriven : EntityId;

alias WidgetId = EntityId;
