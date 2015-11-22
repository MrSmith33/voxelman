/**
Copyright: Copyright (c) 2015 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/

module voxelman.utils.libloader;

import voxelman.core.config;

string getLibName(string libName)
{
	version(Win32)
		return LIB_PATH ~ "/32/" ~ libName ~ ".dll";
	else version(Win64)
		return LIB_PATH ~ "/64/" ~ libName ~ ".dll";
	else
		static assert(false, "lib loading is not implemented for this platform");
}
