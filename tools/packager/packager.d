/**
Copyright: Copyright (c) 2015-2018 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module packager;

import std.file;
import std.string;
import std.digest.crc;
import std.stdio;
import std.zip;
import std.path;
import std.process;
import std.datetime;

enum ROOT_PATH = "../..";
enum TEST_DIR_NAME = "test";
string testDir;

version(Windows)
	enum bool is_Windows = true;
else
	enum bool is_Windows = false;

void makePackage(ReleasePackage* pack)
{
	string archStr = archToString[pack.arch];
	pack.addFiles("builds/default", "*.exe");
	pack.addFiles("res", "*.ply");
	pack.addFiles("config", "*.sdl");
	pack.addFile("config/servers.txt");
	pack.addFiles("lib/"~archStr, "*.dll");
	pack.addFile("saves/test"~archStr~".db");
	pack.addFile("README.md");
	pack.addFile("CHANGELOG.md");
	pack.addFile("LICENSE.md");
	pack.addFile("pluginpacks/default.txt");
	pack.addFile("launcher.exe");

	pack.addFile("tools/minecraft_import/minecraft_import.exe");
	pack.addFile("tools/minecraft_import/readme.md");
}

enum Compiler
{
	dmd,
	ldc,
	gdc
}
string[] compilerExeNames = ["dmd", "ldc2", "gdc"];

string semver = "0.8.0";
Compiler compiler = Compiler.ldc;
string buildType = "release-debug";

void main(string[] args)
{
	testDir = buildNormalizedPath(absolutePath(buildPath(ROOT_PATH, TEST_DIR_NAME)));
	if (exists(testDir) && isDir(testDir))
	{
		writefln("Deleting test dir %s", testDir);
		rmdirRecurse(testDir);
	}

	StopWatch sw;
	sw.start();
	doWork();
	sw.stop();
	writefln("Finished in %.1fs", sw.peek().to!("seconds", real));
}

void doWork()
{
	completeBuild(Arch.x32, semver, compiler, buildType);
	writeln;
	completeBuild(Arch.x64, semver, compiler, buildType);
}

void completeBuild(Arch arch, string semver, Compiler compiler, string buildType)
{
	buildApp(arch, semver, compiler, buildType, "tools/minecraft_import");

	string launcher_arch;
	if (compiler == Compiler.dmd && is_Windows)
		launcher_arch = arch == Arch.x32 ? "x86_mscoff" : "x86_64";
	else
		launcher_arch = arch == Arch.x32 ? "x86" : "x86_64";

	string voxelman_arch = arch == Arch.x32 ? "32" : "64";

	string dubCom() {
		return format(`dub run --root="tools/launcher" -q --nodeps --compiler=ldc2 --arch=%s --build=debug -- --arch=%s --compiler=%s --build=%s`,
			launcher_arch, voxelman_arch, compiler, buildType);
	}

	string com = dubCom();
	writefln("Executing '%s'", com); stdout.flush();

	auto dub = executeShell(com, null, Config.none, size_t.max, ROOT_PATH);

	dub.output.write;
	if (dub.status != 0) {
		writeln("Failed to run dub or launcher");
		return;
	}

	writefln("Packing %sbit", voxelman_arch); stdout.flush();
	pack(semver, arch, Platform.windows);
}

void buildApp(Arch arch, string semver, Compiler compiler, string buildType, string root = "./")
{
	string app_arch;
	if (compiler == Compiler.dmd && is_Windows)
		app_arch = arch == Arch.x32 ? "x86_mscoff" : "x86_64";
	else
		app_arch = arch == Arch.x32 ? "x86" : "x86_64";

	string dubCom() {
		return format(`dub build --root="%s" -q --nodeps --compiler=%s --arch=%s --build=%s`,
			root, compilerExeNames[compiler], app_arch, buildType);
	}

	string com = dubCom();
	writefln("Executing '%s'", com); stdout.flush();

	auto dub = executeShell(com, null, Config.none, size_t.max, ROOT_PATH);

	dub.output.write;
	if (dub.status != 0) {
		writeln("Failed to run dub");
	}
}

struct ReleasePackage
{
	string semver;
	Arch arch;
	Platform platform;
	ZipArchive zip;
	string fileRoot;
	string archRoot;
}

void pack(string semver, Arch arch, Platform pl)
{
	ReleasePackage pack = ReleasePackage(
		semver,
		arch,
		pl,
		new ZipArchive,
		ROOT_PATH);
	string archName = archName(&pack, "voxelman");
	pack.archRoot = archName;

	makePackage(&pack);
	string archiveName = buildNormalizedPath(ROOT_PATH, archName) ~ ".zip";
	writePackage(&pack, archiveName);

	extractArchive(archiveName, testDir);
}

enum Arch { x64, x32 }
enum Platform { windows, linux, macos }
string[Platform] platformToString;
string[Arch] archToString;
static this()
{
	platformToString = [Platform.windows : "win", Platform.linux : "linux", Platform.macos : "mac"];
	archToString = [Arch.x64 : "64", Arch.x32 : "32"];
}

void writePackage(ReleasePackage* pack, string path)
{
	writefln("Writing archive into %s", path);
	std.file.write(path, pack.zip.build());
}

string archName(R)(ReleasePackage* pack, R baseName)
{
	string arch = archToString[pack.arch];
	string platform = platformToString[pack.platform];
	return format("%s-v%s-%s%s", baseName, pack.semver, platform, arch);
}

alias normPath = buildNormalizedPath;
alias absPath = absolutePath;
void addFiles(ReleasePackage* pack, string path, string pattern)
{
	import std.file : dirEntries, SpanMode;

	string absRoot = pack.fileRoot.absPath.normPath;
	foreach (entry; dirEntries(buildPath(pack.fileRoot, path), pattern, SpanMode.depth))
	if (entry.isFile) {
		string absPath = entry.name.absPath.normPath;
		addFile(pack, absPath, relativePath(absPath, absRoot));
	}
}

void addFile(ReleasePackage* pack, string archive_name)
{
	addFile(pack.zip, buildPath(pack.fileRoot, archive_name).absPath.normPath, buildPath(pack.archRoot, archive_name));
}

void addFile(ReleasePackage* pack, string fs_name, string archive_name)
{
	addFile(pack.zip, fs_name.absPath.normPath, buildPath(pack.archRoot, archive_name));
}

void addFile(ZipArchive archive, string fs_name, string archive_name)
{
	string norm = archive_name.normPath;
	if (!exists(fs_name)) {
		writefln("Cannot find %s at %s", fs_name, norm);
		return;
	}
	writefln("Add %s as %s", fs_name, norm);
	void[] data = std.file.read(fs_name);
	ArchiveMember am = new ArchiveMember();
	am.name = norm;
	am.compressionMethod = CompressionMethod.deflate;
	am.expandedData(cast(ubyte[])data);
	archive.addMember(am);
}

void extractArchive(string archive, string pathTo)
{
	writefln("Extracting %s into %s", archive, pathTo);
	extractArchive(new ZipArchive(std.file.read(archive)), pathTo);
}

void extractArchive(ZipArchive archive, string pathTo)
{
	foreach (ArchiveMember am; archive.directory)
	{
		string targetPath = buildPath(pathTo, am.name);
		mkdirRecurse(dirName(targetPath));
		archive.expand(am);
		std.file.write(targetPath, am.expandedData);
	}
}
