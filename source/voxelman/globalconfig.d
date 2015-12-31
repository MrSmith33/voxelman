/**
Copyright: Copyright (c) 2014-2015 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module voxelman.globalconfig;

version(Windows)
	enum EXE_SUFFIX = ".exe";
else version(Posix)
	enum EXE_SUFFIX = "";
else
	static assert(false, "Implement exe suffix for this platform");

enum DESPIKER_PATH = "../../tools/despiker/64/despiker" ~ EXE_SUFFIX;
enum BUILD_TO_ROOT_PATH = "../../";
