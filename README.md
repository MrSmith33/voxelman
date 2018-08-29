Voxelman [![Build Status](https://travis-ci.org/MrSmith33/voxelman.svg?branch=master)](https://travis-ci.org/MrSmith33/voxelman)
========

Plugin-based engine written in D language.

Voxelman plugin pack includes plugins for a voxel-based game(s).

Launcher will allow for any plugin combination, while master-server will host all plugins and online server list.

## Screenshots and videos

[Twitter](https://twitter.com/MrSmith33)

[Imgur album](https://imgur.com/a/CLTCZ)

See [releases](https://github.com/MrSmith33/voxelman/releases) for binaries.

See [youtube channel](https://www.youtube.com/channel/UCFiCQez_ZT2ZoBBJadUv3cA) for videos.

## Contacts
* Report issues [here](https://github.com/MrSmith33/voxelman/issues)
* Submit pull requests [here](https://github.com/MrSmith33/voxelman/pulls)
* Edit [wiki](https://github.com/MrSmith33/voxelman/wiki)

Join Discord servers:

* [D language discord](https://discord.gg/S9yzYuA)
* [Voxelgamedev discord](https://discord.gg/kg47XNV)

## Installing game
- Download [latest build](https://github.com/MrSmith33/voxelman/releases);
- Unpack;
- Follow instructions below.

## Compiler
Any D compiler with frontend version of 2.075 and newer.

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

## Starting game from launcher
### Single player
- Start launcher
- Press `New` in __worlds__ tab to create new world
- Select new world and press `Start`

### Multiplayer
- To start a server select world and press `Server` button;
- Connect to your server in `Connect` tab of `Play` menu;
- Select local server and press `Connect` at the bottom;
- To stop the server, go to the `Code` menu and hit `Stop` button of your server instance.

## Starting game from command line
- Executable must be started from `builds/default` folder;
- `voxelman --app=[client|server|combined] --world_name="new world" --name="Player"`;
- You can override any config option with a switch of a form: `--option=value`;
- Array config options are passed using comma between items. Like `--resolution=1280,800`.

## Server commands
- Can be inputted from server console inside launcher `Debug` menu, or from client's in-game console;
- `tp <x> [<y>] <z> | tp <player name>` - teleports to position or other player's location;
- `tp u|d|l|r|f|b <num_blocks>` - teleports player in choosen direction
- `spawn` teleports to starting world position;
- `spawn set` sets world spawn;
- `dim_spawn` teleports to dimension spawn pos;
- `dim_spawn set` sets dimension spawn pos.

## Controls (Can be changed in `config/client.sdl`)
- `Q` to lock mouse;
- `WASD`, `LCtrl`, `Space` to move. `LShift` to boost;
- `Right` and `Left` to switch tools;
- `R` to rotate blocks;
- `RMB` to place;
- `LMB` to remove;
- `MMB` to pick block;
- `~` open console;
- `[` and `]` to change view distance;
- Keypad `-` and `+` to change movement speed;
- `U` disable position update;
- `F` flying mode;
- `N` noclip;
- `KP+`, `KP-` change movement speed;
- `F2` chunk grid;
- `F5` update all meshes;
- `C` toggle frustum culling;
- `Y` toggle wireframe mode.

## Building from sources

### Installing compilers

#### Linux 
```
sudo wget http://master.dl.sourceforge.net/project/d-apt/files/d-apt.list -O /etc/apt/sources.list.d/d-apt.list
sudo apt-get update && sudo apt-get -y --allow-unauthenticated install --reinstall d-apt-keyring && sudo apt-get update
sudo apt-get install build-essential dmd-bin dub
```

#### Windows
https://dlang.org/download.html

### Installing dependencies

#### Linux 
```
sudo apt-get install liblmdb-dev liblz4-dev libglfw3-dev libenet-dev
```

#### Windows

Download compiled static libs [from here]()

Unpack `lib` folder inside `voxelman` folder

### Compile

```
git clone --depth=50 https://github.com/MrSmith33/voxelman voxelman
cd voxelman
git submodule update --init --recursive
dub build
```

With sources and dependencies you can now also compile & run via launcher.

### Run
```
cd builds/default
voxelman --app=combined
```
