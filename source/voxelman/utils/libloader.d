/**
Copyright: Copyright (c) 2015 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/

module voxelman.utils.libloader;

public import voxelman.globalconfig;

version(Posix)
	enum DLL_SUFFIX = ".a";
else version(Windows)
	enum DLL_SUFFIX = ".dll";
else static assert(false, "lib loading is not implemented for this platform");

version(X86)
	enum LIB_FOLDER = "lib/32";
else version(X86_64)
	enum LIB_FOLDER = "lib/64";
else static assert(false, "lib loading is not implemented for this platform");

string getLibName(string pathToRoot, string libName)
{
	import std.path : chainPath, asAbsolutePath, asNormalizedPath;
	import std.array : array;
	return chainPath(pathToRoot, LIB_FOLDER, libName ~ DLL_SUFFIX)
		.asAbsolutePath
		.asNormalizedPath
		.array;
}
