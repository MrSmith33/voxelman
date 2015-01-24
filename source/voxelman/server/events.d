/**
Copyright: Copyright (c) 2015 Andrey Penechko.
License: a$(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/

module voxelman.server.events;

public import std.typecons : scoped;

import netlib.connection : ClientId;
import voxelman.modules.eventdispatchermodule : GameEvent;

string autoInitCode(This)()
{
	string code = "this(";
	foreach (member; __traits(allMembers, This))
	{
		static if(__traits(compiles, typeof(mixin("This."~member)).init))
		{
			alias type = typeof(mixin("This."~member));
			code ~= type.stringof ~ " " ~ member ~ "="~type.stringof~".init, ";
		}
	}
	code ~= ") {";
	foreach (member; __traits(allMembers, This))
	{
		static if(__traits(compiles, typeof(mixin("This."~member)).init))
		{
			code ~= "this." ~ member ~ " = " ~ member ~ ";";
		}
	}
	code ~= "}";
	return code;
}

string autoInitCode2(This)(string members)
{
	import std.algorithm : splitter;
	string code = "this(";
	foreach (member; members.splitter)
	{
		alias type = typeof(mixin("This."~member));
		code ~= type.stringof ~ " " ~ member ~ "="~type.stringof~".init, ";
	}
	code ~= ") {";
	foreach (member; members.splitter)
	{
		code ~= "this." ~ member ~ " = " ~ member ~ ";";
	}
	code ~= "}";
	return code;
}

mixin template AutoInit()
{
	mixin(autoInitCode!(typeof(this)));
}

mixin template AutoInit2(string members)
{
	mixin(autoInitCode2!(typeof(this))(members));
}

class CommandEvent : GameEvent
{
	this(ClientId clientId, string command) {
		this.clientId = clientId;
		this.command = command;
	}
	ClientId clientId;
	string command;
}

class ClientConnectedEvent : GameEvent
{
	this(ClientId clientId) {
		this.clientId = clientId;
	}
	ClientId clientId;
}

class ClientDisconnectedEvent : GameEvent
{
	this(ClientId clientId) {
		this.clientId = clientId;
	}
	ClientId clientId;
}

class ClientLoggedInEvent : GameEvent
{
	this(ClientId clientId) {
		this.clientId = clientId;
	}
	ClientId clientId;
}