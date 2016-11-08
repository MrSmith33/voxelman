Voxelman [![Build Status](https://travis-ci.org/MrSmith33/voxelman.svg?branch=master)](https://travis-ci.org/MrSmith33/voxelman) [![Join the chat at https://gitter.im/MrSmith33/voxelman](https://badges.gitter.im/Join%20Chat.svg)](https://gitter.im/MrSmith33/voxelman?utm_source=badge&utm_medium=badge&utm_campaign=pr-badge&utm_content=badge)
========

Plugin-based engine written in D language.

Voxelman plugin pack includes plugins for a voxel-based game(s).

Launcher will allow for any plugin combination, while master-server will host all plugins and online server list.

## Screenshots and videos
[Imgur album](http://imgur.com/a/L5g1B)

See [releases](https://github.com/MrSmith33/voxelman/releases) for binaries.

See [youtube channel](https://www.youtube.com/channel/UCFiCQez_ZT2ZoBBJadUv3cA) for videos.

## Installing game
- Download [latest build](https://github.com/MrSmith33/voxelman/releases).
- Unpack.
- Follow instructions below.

## Starting game with launcher
### Single player
- Start launcher
- Press `New` in __worlds__ tab to create new world
- Select new world and press `Start`

### Multiplayer
- To start a server select world and press `Server` button.
- Connect to your server in `Connect` tab
- Select local server and press `Connect` at the bottom.
- To stop the server, go to the `Code` menu and hit `Stop` button of your server instance.

## Starting game with command line
- `voxelman --app=[client|server|combined] --world_name="new world" --name="Player"`.
- You can override any config options by passing switch in a form `--option=value`.
- Array config options are passed using comma between items. Like `--resolution=1280,800`.

## Server commands
- `tp <x> [<y>] <z> | tp <player name>` - teleports to position or other player's location
- `spawn` teleports to starting world position

## Controls (Can be changed in `config/client.sdl`)
- `Q` to lock mouse.
- `WASD`, `LCtrl`, `Space` to move. `LShift` to boost.
- `Right` and `Left` to switch tools.
- `R` to rotate rails.
- `RMB` to place
- `LMB` to remove.
- `[` and `]` to change view distance.
- Keypad `-` and `+` to change movement speed.
- `U` disable position update.
- `F` flying mode.
- `N` noclip.
