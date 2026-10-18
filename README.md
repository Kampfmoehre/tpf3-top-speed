# Top Speed Reached (Transport Fever 3)

A small UI mod for Transport Fever 3 that shows the **highest speed a vehicle
has actually reached**, next to the top speed its consist is capable of and
the highest speed limit of the line's track:

    Reached: 97 / 115 km/h · track 100 km/h

- In every vehicle window, as a row below the noise and pollution line.
- In every line window: the highest speed on that line, with the vehicle that
  reached it in the tooltip, against the highest top speed among the line's
  vehicles.
- The text turns green once the measured speed reaches 97 % of the consist's
  own top speed. If it runs at a track limit below that (once all sections of
  the line are known; until then it reads "track ≥ …"), the text stays normal
  and the track limit is highlighted: an upgrade of the track would help.
- Lines without vehicles show "no vehicles".
- Useful to see whether a fast vehicle is ever driven at its top speed on a
  given line, or whether a cheaper, slower one would do.
- Purely cosmetic, achievements stay enabled. English and German.

The game does not record speeds, only the current speed of a vehicle. The
mod therefore samples the speed of every vehicle on your lines every two
seconds while a game is loaded and keeps the maximum per vehicle for the
session. Consequences:

- After loading a game the measurement starts from scratch; give it a few
  cycles.
- Short peaks between two samples are missed, so the value can sit a little
  below the real maximum. That is why green starts at 97 %, not 100 %.
- Cost: one speed query per vehicle every two seconds. Measured on a save
  with 402 vehicles: no visible difference in frame rate or CPU load.
- The track speed limit is read section by section while vehicles drive it
  (about 3 ms of reading every 2 s, lines with an open window first; each
  section again after 5 minutes, or when its line's window is opened, so a
  track upgrade shows within seconds once a vehicle drives the section). It can be
  turned off with the mod option "Track speed limit"; then no track data is
  read at all.

There is deliberately no red or yellow state. A tram reaching 51 of 80 km/h
is fine in a city and wasteful on a rural line, and the mod cannot tell the
two apart.

Available on mod.io: <https://mod.io/g/transportfever3/m/top-speed-reached>

## Installation

Subscribe on mod.io or in the in-game Mod-Hub, then enable the mod when
loading or creating a game.

Manual installation: copy the folder `kampfmoehre_top_speed_1` into the
game's local mod directory, on Linux
`~/.local/share/Steam/userdata/<steam-id>/3493540/local/mods/`.

## How it works

Transport Fever 3's UI is written in Lua/Teal on top of an in-house,
React-like component system. Mods hook into it through `react-plugin`
resources:

- `entry.res.lua` registers a plugin at the game's `ModEntryPointExtension`.
  Its recipe runs a step timer (`react.onStepTimer`) that collects the
  vehicles of all player lines (`lineSystem.getLinesForPlayer`,
  `transportVehicleSystem.getLineVehicles`) every 10 s and samples
  `api.engine.util.vehicle.getSpeed` every 2 s. Because the plugin lives in
  the game UI root, the timer only runs while a game is loaded.
- `vehicle.res.lua` / `line.res.lua` register the rows at the
  `VehicleEowExtensionPoint` and `LineEowExtensionPoint`; they re-render once
  per second from the sampled data.
- The consist's top speed comes from the same helpers the game's condition
  card uses: `vehicle_store_util.makeMultipleVehiclesFromParts` on the
  vehicle's parts and `collectVehicleData` with the vehicle's maintenance
  modifiers, cached for 30 s per vehicle.
- Track speed limit (`track_limits.lua`): a vehicle's `MOVE_PATH` component
  holds exactly the section it is driving, from the previous stop to the stop
  `TransportVehicle.stopIndex` (identical for all vehicles of a line; at a
  terminal only the short path inside the station, so only `EN_ROUTE`
  vehicles are read). Each path edge points into a `TRANSPORT_NETWORK`
  component whose edge carries `speedLimit` and `curveSpeedLimit` (m/s; tree
  avenues already carry the halved value). Per edge the smaller of the two
  counts; a section's limit is the highest speed that holds for at least
  `MIN_RUN` (200 m, half the section if it is shorter) at a stretch, so a
  crossing at 40 km/h in a 20 km/h avenue does not count. One
  long section (400+ edges) costs up to ~40 ms, most cost 0.2-4 ms, hence
  the time budget per step (`TIME_BUDGET`, at least one section). Windows
  call `want(line)` every second while open; a `want` after more than
  `WANT_SECONDS` without one counts as opening the window and marks the line's
  sections stale (old values stay shown until re-read). The collector is shared with Line Rate Preview through
  the field `kampfmoehre_track_limits` of the `builtin` module table, which
  all GUI scripts share (the copy with the highest `API_VERSION` wins;
  `rawget`/`rawset` do not exist in the GUI Lua state), so with both mods every section is read only once.
- Green uses the game's `success` text class (the `positive` class is the
  blue used for money).

Tunables at the top of `top_speed.script.lua`: `SAMPLE_INTERVAL`,
`LIST_INTERVAL`, `REACHED_FRACTION`; in `track_limits.lua`:
`TIME_BUDGET`, `MAX_SECTIONS_PER_STEP`, `MAX_AGE`, `MIN_RUN`.

### Per section

The card can be expanded (arrow on the card, like the game's own cards) to a
table with one row per section of the line, numbered by its stops as in the
line window (`1 → 2`, …, `n → 1`): the steepest climb (mean uphill grade
over the steepest 200 m in travel direction, from the track heights; `–`
below 0.5 %; an average would hide a ramp on a section that goes up and down
again), the highest speed measured on that section as a bar (filled to its
share of min(consist top speed, track limit)) and the section's track limit
(highest limit that holds for 200 m, see above). Colours: green when the
consist reached its own top speed (97 %); when it reached a track limit below
its top speed the bar stays blue and the track limit is highlighted (an
upgrade of the track would help); yellow below 50 %. In
the vehicle window the row of the section the vehicle is driving is highlighted. The sampler keeps the maximum per section as well, keyed by the stop
the vehicle is heading to (`TransportVehicle.stopIndex`, only while en route);
the vehicle window shows that vehicle, the line window the maximum over the
line's vehicles. `–` for sections not driven or read yet since loading. The
collapsed row looks as before.

## Development

```
kampfmoehre_top_speed_1/           the mod (this is what gets published)
  mod.json                         mod id, option "Track speed limit"
  strings.json                     translations (en, de)
  _metadata/modinfo.json           name, summary, description (+ de)
  _metadata/0.png                  title image, 1920x1080
  _metadata/1.png, 2.png           gallery (2.png: vehicle window with track limit)
  content/gui/kampfmoehre_top_speed/
    entry.res.lua                  sampler registration (entry point)
    vehicle.res.lua, line.res.lua  row registrations
    top_speed.script.lua           the actual code
    track_limits.lua               track speed limits per line section
test/track_limits_test.lua         unit tests (luajit test/track_limits_test.lua)
sync.sh                            copies the mod into the game's staging area
```

Workflow:

1. Edit the files in `kampfmoehre_top_speed_1/`.
2. Run `./sync.sh`. It copies the mod into the game's staging area
   (`.../userdata/<steam-id>/3493540/local/staging_area/`), where the game
   loads it as a development mod. Returning to the main menu and reloading
   the savegame is enough to pick up changes, no restart needed.
3. Lua errors show up as a red error screen in the game ("Copy to clipboard")
   and in `.../3493540/local/crash_dump/stdout.txt`. The script logs with the
   prefix `[kampfmoehre_top_speed]`. The game's Lua is 5.1-compatible; check syntax with
   `luajit -bl file.lua`, not `luac` 5.4.
4. Before uploading a new version through the in-game Mod-Hub, increase
   `revision` in `mod.json`. mod.io rejects a package whose content is
   byte-identical to an already uploaded one.

The staging copy also contains files generated by the game (`.cooked_*`,
`_metadata/mod.io_fileid.txt`). `sync.sh` leaves them alone and they are
ignored by git.

## License

MIT, see `LICENSE`.
