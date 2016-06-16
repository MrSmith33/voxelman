# Change Log

## [Unreleased]
### Added
- Add toolbar.
- Add active chunk system.
- Implement generic solution for saving/loading data for use in plugins.
- Add number formatter with digit separation.
- Add chunk and mesh memory counting.
- Complex write buffer with delayed allocation and uniform type support.
- Big-scale editing. Send edit commands instead of per-block changes.
- Add chunk manager unittests. Decouple chunk provider from chunk manager.
- Add remesh command.
- Add max_players option for server config.
- Add cancelLoad option for chunkmanager. Unloads 'loading' chunk immidiately. Makes chunkmanager usable by client.
- Add multiple dimentions.
- Add semi-transparent solidity state for blocks.
- Add transparent meshes to chunks.
- Add minSolidity calculation to chunk meta data.
- Add wireframe mode [Y].
- Add 3d grid rendering helper.
- Add metadata drawinf to client world.
- Add LMDB storage backend.
- Add lock-free work queue. Constant memory consumption. No allocations. Works faster.
- Add multiple layers of data for chunks.
- Add multiblock editing. Press and drag to select a box.
- Add fps control in debug gui.
- Add fog.
- Add debugger plugin.
- Add world save handler registration.
- Add save on server stop.
- Add generic id mapping synchronization.
- Add generic id mapping utility.
- Add block id map saving/loading/sync.
- Add autosave.
- Add save command.
- Add WorldSaveEvent.
- Add stop button to launcher gui.
- Add world info load.
- Add IoManager.
- Add basic io thread task support.
- Add lz4 compression.
- Add simple chunk validation.
- Add sqlite world storage.
- Add simple worldDb implementation.
- Add sqlite2d lib.
- Add block registering in block plugin.
- Add block plugin.
- Add client part of `clientDb`.
- Add isSpawned state to client info.
- Add current frame number to update events.

### Changed
- Rewrite client to use new chunk manager.
- Rewrite chunk mesh manager to new algo of chunk meshing. Meshing passes that use snapshot system of chunk manager.
- Implement new worker and worker group.
- Use shared queue for chunk gen and mesh gen.
- Improve sharedqueue. Allow any message sizes. Improve naming.
- Merge world access types.
- Finish layer support in chunk manager.
- Merge client and server configuration in a single executable. Config is choosen with --app flag.
- Make threads use proper sync primitives. Worker threads are not wasting CPU anymore.
- [Launcher] Add server list add/remove ability.
- [Launcher] Move app settings to job.
- [Launcher] Make separate buttons for Run, Build and Run-and-build.
- [Launcher] Change job items to take equal amount of height.
- Allow one client to observe single chunk multiple times.
- Make water transparent.
- Store chunk meshes in chunkmeshman instead of chunk.
- Optimize generation of chunks above ground.
- Implement chunk side transparency metadata calculation => massive boost of client.
- Put trace log messages only in file.
- Store data in compressed form in memory of server.
- Compress blocks on chunk gen.
- Use new data layout for saves.
- Make chat transparent.
- Move ClientWorld to voxelman/world/clientworld.d.
- Use journal_mode = WAL in sqlite.
- Rename clientdb plugin into login.
- Move block modules into block plugin package.
- Rename `BlockType` to `BlockId`.
- Move world handling to `world` plugin from `client`.
- Move login handling to `clientDb` from `client`.
- Move network handling to `net` from `client`.

### Removed
- Remove _saving states in chunk manager
- Remove chunk change management from chunk manager.
- Remove old chunk manager and chunk storage.
- Remove old chunk.
- Remove `continuePropagation` from events.
- Remove tharsis-prof dependency.
- Remove old `blockman` and merge utilities into `voxelman.block.utils` module.
- Remove voxelman/storage/world.d.

### Fixed
- Fix case in chunk manager when old snapshot was saved and current snapshot is added_loaded.
- Fix app not stopping when main thread crashes.
- Fix world save on game stop.
- Fix volume intersection.
- Fix mesh deletion when chunk does not produce mesh. Use special "delete mesh" tasks to queue mesh deletions. This allows to upload new chunk meshes together with deleting meshes of chunks that do not produce meshes anymore.
- Fix old snapshot added with wrong timestamp on commit.
- Fix error on missing config option.
- Fix commands in launcher when app is not running.
- Fix chunk free list not working.
- Fix app crash on Alt+PrintScreen.
- Fix generated chunks not saved, but regenerated every time.
- Fix buttons in imgui_glfw.d.
- Make random block tint persistent.
- Fix performance bug in chunk meshing. Now meshing is much faster. Was allocating on each block's meshing.
- Fix wrong disconnect code.
- Fix client chunkman stopping.

## [0.6.1] - 2016-01-09
### Added
- Add `spawn` command moving client to starting position.
- Add _clientDb_ plugin and move client handling there from server plugin.
- Add falling sand.
- Add `removeAll()` method to component storage interface.
- Add sand block.
- Command name aliasing. Put `|` to separate aliases.

### Changed
- Change cursor ray distance from 80 to 200.
- Move connection handling from server to net plugin.
- Updated copyrights.
- Server has `stop` alias of `sv_stop` now.
- Moved world management from server plugin into world plugin.
- Move server command handling into command plugin.
- Move message command into chat plugin.
- Add checks allowing update of connection when connection is not running.

### Fixed
- Fix wrong key supply for imgui not clearing key modifiers.
- Fps limit now works as intended (120 fps by default).

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

[Unreleased]: https://github.com/MrSmith33/voxelman/compare/v0.6.1...HEAD
[0.6.1]: https://github.com/MrSmith33/voxelman/compare/v0.6.0...v0.6.1
[0.6.0]: https://github.com/MrSmith33/voxelman/compare/v0.5.0...v0.6.0