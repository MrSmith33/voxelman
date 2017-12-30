Voxelman [![Build Status](https://travis-ci.org/MrSmith33/voxelman.svg?branch=master)](https://travis-ci.org/MrSmith33/voxelman) [![Join the chat at https://gitter.im/MrSmith33/voxelman](https://badges.gitter.im/Join%20Chat.svg)](https://gitter.im/MrSmith33/voxelman?utm_source=badge&utm_medium=badge&utm_campaign=pr-badge&utm_content=badge)
========

Plugin-based engine written in D language.

Voxelman plugin pack includes plugins for a voxel-based game(s).

Launcher will allow for any plugin combination, while master-server will host all plugins and online server list.

## Screenshots and videos

[Twitter](https://twitter.com/MrSmith33)

[Imgur album](https://imgur.com/a/CLTCZ)

See [releases](https://github.com/MrSmith33/voxelman/releases) for binaries.

See [youtube channel](https://www.youtube.com/channel/UCFiCQez_ZT2ZoBBJadUv3cA) for videos.

## Installing game
- Download [latest build](https://github.com/MrSmith33/voxelman/releases).
- Unpack.
- Follow instructions below.

## Requirements
- OpenGL 3.1 support
- Multicore CPUs are utilized
- Memory consumption
<table>
<thead>
<tr> <th rowspan="2">Map name</th>
<th colspan="2">10 (21^3) chunks</th>
<th colspan="2">20 (41^3) chunks</th>
<th colspan="2">30 (61^3) chunks</th> </tr>
<tr> <th>RAM</th> <th>VRAM</th> <th>RAM</th> <th>VRAM</th> <th>RAM</th> <th>VRAM</th> </tr>
</thead>
<tr> <td>Default heightmap terrain</td> <td>300MB</td><td>150MB</td> <td>800MB</td><td>200MB</td> <td>1.8GB</td><td>400MB</td> </tr>
<tr> <td>Default flat terrain</td> <td>80MB</td><td>18MB</td> <td>160MB</td><td>80MB</td> <td>400MB</td><td>170MB</td> </tr>
<tr> <td>King's landing</td> <td>200MB</td><td>180MB</td> <td>500MB</td><td>550MB</td> <td>600MB</td><td>700MB</td> </tr>
</table>

## Starting game with launcher
### Single player
- Start launcher
- Press `New` in __worlds__ tab to create new world
- Select new world and press `Start`

### Multiplayer
- To start a server select world and press `Server` button.
- Connect to your server in `Connect` tab of `Play` menu.
- Select local server and press `Connect` at the bottom.
- To stop the server, go to the `Code` menu and hit `Stop` button of your server instance.

## Starting game with command line
- Executable must be started from `builds/default` folder.
- `voxelman --app=[client|server|combined] --world_name="new world" --name="Player"`.
- You can override any config options by passing switch in a form `--option=value`.
- Array config options are passed using comma between items. Like `--resolution=1280,800`.

## Server commands
- Can be inputted from server console inside launcher `Debug` menu, or from client console.
- `tp <x> [<y>] <z> | tp <player name>` - teleports to position or other player's location
- `tp u|d|l|r|f|b <num_blocks>` - teleports player in choosen direction
- `spawn` teleports to starting world position
- `spawn set` sets world spawn
- `dim_spawn` teleports to dimension spawn pos
- `dim_spawn set` sets dimension spawn pos

## Controls (Can be changed in `config/client.sdl`)
- `Q` to lock mouse.
- `WASD`, `LCtrl`, `Space` to move. `LShift` to boost.
- `Right` and `Left` to switch tools.
- `R` to rotate blocks.
- `RMB` to place
- `LMB` to remove.
- `MMB` to pick block.
- `~` open console.
- `[` and `]` to change view distance.
- Keypad `-` and `+` to change movement speed.
- `U` disable position update.
- `F` flying mode.
- `N` noclip.
- `KP+`, `KP-` change movement speed.
- `F2` chunk grid.
- `F5` update all meshes.
- `C` toggle frustum culling.
- `Y` toggle wireframe mode.

## Building from sources
### Linux 

Install compilers:
```
sudo wget http://master.dl.sourceforge.net/project/d-apt/files/d-apt.list -O /etc/apt/sources.list.d/d-apt.list
sudo apt-get update && sudo apt-get -y --allow-unauthenticated install --reinstall d-apt-keyring && sudo apt-get update
sudo apt-get install build-essential dmd-bin dub
```

Install dependencies:
```
sudo apt-get install liblmdb-dev liblz4-dev libglfw3-dev libenet-dev
```

Compile:
```
git clone --depth=50 https://github.com/MrSmith33/voxelman voxelman
cd voxelman
git submodule update --init --recursive
dub build
```


Run:
```
cd builds/default
voxelman --app=combined
```