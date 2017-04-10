# Change Log

## [Unreleased]
- Implement click-and-drag rail placement.

## [0.8.0] - 2017-02-03
### Added
- Implement rail graph sync with actual rail entities.
- Implement new generic hashmap/hashset/multihashset.
- Add packet sniffing debug code (easier network debugging).
- Add `dim_spawn` and `dim_spawn set` commands.
- Add single block mesher helper.
- Add ability to append meshes to Batch.
- Add rotatable slope block.
- Add block side shapes/masks.
- Add block metadata layer.
- Do bottom meshing of rails/side meshing of slope rail.
- Add block shape occlusion calculation.
- Add block corner ambient occlusion calculation.
- Implement build type selection in launcher.
- Implement ambient occlusion.
- Implement optimized mesh generation.
- Add shared hashset.
- Add entity observer manager, which is used to send components only for entities that are observed by - client.
- Add partial (de)serialization of component storages.
- Add generator manager.
- Add directional teleportation command. `tp u|d|l|r|f|b <num_blocks>`
- Add player physics.
- Add dimension observer manager. Server world sends info about dimension border to clients. Use dimension borders - to shift and clamp observation box of clients.
- Add dimension manager.
- Add getOrCreate to HashMap.
- Add MultiHashSet container.
- Add getOrCreate to entity manager and storages.
- Add serializeToDb and serializeToNet component flags.
- Add storage type for loaders and savers.
- Use entity storage for ClientDb. Clients can have any set of components and flags now. They are persistently - stored. Client spawns on the same position he leaved server.
- Add # comment to plugin pack parsing.
- Add # comment to plugin pack.
- Add client db on server.
- Add new datadriven package.
- Add Batch2d.
- Save block entity id map.
- Add 'spawn set' command. Sets spawn position and rotation for current dimension to player's one.
- Use spawn position from dimention info when spawning player.
- Add teleport command.
- Minecraft save import tool.
- Implement launcher server connection feature.
- Implement integrated server. Used with --app=combined switch.
- Implement command line options override. Can override any config option (--option=value).
- Add save manipulation to launcher.
- Add ability to connect to a server from server list.
- Add ability to start game from world selection screen. Can be started in combined and dedicated server mode.

### Changed
- Store length and capacity of hashmap chunk layers inside data itself (Invalidates older saves that have block entities).
- Separate [de]serialization of hashmap/hashset into voxelman.serialization.hashtable module.
- Now chunk manager returns special timestamp for non-existent snapshots on user add. It is then - ignored on user remove.
- Start server internally in minecraft import tool.
- Move all engine initialization code into enginestarter.d.
- Create PluginManager outside of client and server plugins.
- Redo netlib package.
- Remove unused source parameter of packet handlers on client.
- Rename ClientId into SessionId.
- Correctly handle clients with the same name.
- Hide cursor on mouse lock.
- Use string map for DB keys.
- Allow committing compressed layers.
- Convert chunk storage to Mallocator.
- Free chunk meshes immediately after upload. Saves huge amount of memory.
- Reuse buffers for meshing (Significantly lowers memory consumption).
- Optimize getting snapshots for meshing.
- Use Mallocator for chunk meshes instead of GC.
- Uncompress snapshots when needed, not on receive.
- Do not uncompress chunks on client until requested. Less memory consumption.

### Fixed
- Fix nextPOT (static if had size in bits not in bytes).
- Fix holes in terrain. Chunks was sent before SpawnPacket was sent, so they were rejected.
- Fix assert when non-added chunk is loaded. Ignore it instead.
- Fix bug when commitLayerSnapshot uses StorageType.fullArray instead of writeBuffer.layer.type when committing new snapshot. This caused compressed layer to have type of full layer.
- Correctly handle clients with the same name.
- Fix gui order for task and result queues.
- Fix client disconnection code.
- Fix client repeated connection to the same server.

## [0.7.0] - 2016-08-22
### Added
- Add camera_speed and camera_boost client options.
- Add server telemetry. Debug plugin can send variables.
- Add chunk heightmap caching while generating world. Gives massive perf boost.
- Add generator abstraction. Generator is fully responsible for chunk gen. More optimization opportunities. Flat generator now generates only uniform chunks. Generation function now uses utilities for metadata generation.
- Add generic Box type
- Add multiple rails per tile.
- Add .obj and .ply model loading.
- Add multichunk block entity.
- Add block entity removing.
- Add block entity type registry.
- Add flat terrain gen.
- Add railroad test plugin.
- Add block entities.
- Add universal data management for chunk layers.
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
- Add multiple dimensions.
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
- Dont save unmodified chunks.
- Use optimized simplex noise.
- Split Box into WorldBox and Box.
- Rename Volume to Box.
- Use typed mesh vertices instead of ubyte array.
- Encapsulate block info retreival into BlockInfoTable.
- Change BlockID size to two bytes.
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
- Fix dimension change code to prevent use of stale client positions after dimension change.
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

[Unreleased]: https://github.com/MrSmith33/voxelman/compare/v0.8.0...HEAD
[0.8.0]: https://github.com/MrSmith33/voxelman/compare/v0.7.0...v0.8.0
[0.7.0]: https://github.com/MrSmith33/voxelman/compare/v0.6.1...v0.7.0
[0.6.1]: https://github.com/MrSmith33/voxelman/compare/v0.6.0...v0.6.1
[0.6.0]: https://github.com/MrSmith33/voxelman/compare/v0.5.0...v0.6.0