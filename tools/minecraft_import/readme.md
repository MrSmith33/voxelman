This is tool for converting minecraft saves to voxelman worlds.


## Example
```
minecraft_import -i"S:\Games\Minecraft\KingsLanding" -o"S:\voxelman\saves\Kings_landing.db" --center -d1
```


## Options
- `-i|--input` - minecraft folder that contains `region` folder.
- `-o|--output` - resulting world file. Needs to end with `.db`.
- `--center` - align imported regions so that 0 coordinates are at the center.
- `-d|--dimension` - dimension in resulting world file in which chunks will be written.