# Change Log

## [Unreleased]

## [0.6.0] - 2016-01-08
### Added
- Add LICENSE.md.
- Add CHANGELOG.md.
- Add launcher.
- Add packager tool.
- Add command plugin. Close #44.
- Add simple chat plugin. Close #37.
- Add console window to client's gui.
- Add launcher access to application's console.
- Add remotecontrol plugin. Close #45.
- Add selective plugin loading.
- Add running of app without compile in launcher.
- Add cmd mode for release compilation to launcher.
- Add voxelman/datadriven.
- Add simple entity-component system.
- Add entity test plugin.
- Add example plugin.
- Add .travis.yml
- Add travis badge.
- Implement lib loading for posix systems.
- Add main packets in voxelman.net plugin, so they are registered in right order.
- Add start buttons to code view of launcher.
- Implement simple avatar plugin. Close #23.
- Add release build to launcher.
- Add `putf`, `putfln`, `putln` methods to - LineBuffer.
- Add test plugins to default pack.
- Add ring loading of chunks on server. Close #41.
- Add nickname option.
- Create builds folder for all pluginpack builds. Use default temporarily.
- Add .gitignore to default build folder.
- Add nodeps, force, x64, start flags to start buttons. Add restart button to job.
- Add separate process logs in launcher.
- Add mixin for auto-creating id and semver methods from plugininfo.d.
- Set default sizes for chat, console and debug windows.

### Changed
- Move launcher to tools/ folder
- Connect imgui callbacks to window events.
- Set entity placement on 'E' key. Now entity plugin can be loaded with edit plugin at once.
- Rename modules from Xplugin to just plugin.
- Update dependencies.
- Register plugins in shared static this() instead of static this().
- Make dll load from lib folder directly, instead of copying them to bin folder.
- Update anchovy to allow custom dll loading.
- Move most voxelman code into plugins.
- Make use of PluginRegistry main functions.
- Use pack name in pack option.
- Make fullscreen launcher gui.
- Separate networking into plugin.
- Move imgui stuff from launcher to voxelman.
- Move gui to imgui. Close #43.
- Embed and refresh anchovy code.
- Move imgui code to voxelman.
- Move to using anchovy.glfwwindow in launcher.gui.
- Move shaders into source code.
- Merge job types into one in launcher.

### Removed
- Remove unused resources.
- Remove old chunkman.
- Remove client storage from baseserver.

### Fixed
- Add missing importPaths to dub.json.
- Fix freelist memory leak.
- Fix config typo.
- Fix fpscamera.
- Fix server stop.
- Fix wrong rendering when resizing window. Viewport wasn't updated.

[Unreleased]: https://github.com/MrSmith33/voxelman/compare/v0.6.0...HEAD
[0.3.0]: https://github.com/MrSmith33/voxelman/compare/v0.5.0...v0.6.0