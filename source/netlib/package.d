/**
Copyright: Copyright (c) 2015-2016 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module netlib;

import std.typecons : Typedef;

alias SessionId = Typedef!size_t;

public import netlib.baseclient;
public import netlib.baseserver;
public import netlib.baseconnection;
public import netlib.packetmanagement;
