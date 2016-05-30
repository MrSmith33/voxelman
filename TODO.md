- Isolate client position, view volume and dimention.
	+ draw avatar based on dimention.
	+ send dimention with avatar.
- Distinguish between client camera position, observer position and avatar position. Associate multiple clients with single view volume.

- Implement generic solution for saving/loading data for use in plugins.
	(double buffering?)
	- Fix world save on game stop.

- Implement graphics pipeline.

- Big-scale editing.
	- Send edit commands instead of per-block changes


-? remove _saving states on chunk manager
- for each layer register handlers for allocation, save, load
- fix problem with dimention change when old position confuses server and volume is not updated.

+ fix chunks not loading sometimes [Chunks were not added early enough, so first snapshots were loaded for not added chunks => holes]
+ remove old observer on client when (re)connecting
+ fix metadata usage in chunk mesh manager. [Bug in hasSingleSolidity]
+ fix crash on recieving data for already loaded chunks. [isLoaded was not checked. Now chunks are loaded through modification]
+ fix snapshot users not correctly added on commit. [snapshot was added to oldSnapshots with wrong timestamp (currentTime instead of snap.timestamp)]
+ change clientworld
+ remove chunkman
+ remove chunkstorage
+ chunkmanager usage of chunkProvider
+ rework chunkmeshman
+ mesh gen new queue
- remove observer on stop in client
+ set received data in chunk manager on client
+ remove chunk changes from chunk manager
+ remove mesh when mesh is not generated on remesh
+ remove limit on message size in shared queue
+ remove chunk
+ add remesh button
+ fix memory leak. Meshes was iterated by value and was loaded each frame again. Fix: change foreach(mesh) to foreach(ref mesh)
+ fix transparent drawing
+ implement total number of snapshot users
+ fix excess addCurrentSnapshotUser call on save in onSnapshotLoaded (chunks were not unloaded earlier?)