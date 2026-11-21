# GameSpice Logic

Godot 4.7+ addon for map-side logic as data: named entities with inputs and outputs, trigger, relay and action graphs, delays, counters and timers, in the style converted Source maps already carry. Read the family [CLAUDE.md](../../CLAUDE.md) first. **The distributable is `addons/dot_logic/`**; it requires [GameSpice Core](../dot-core) only (`ln -s ../../dot-core/addons/dot_core addons/dot_core`, gitignored).

| Path | What |
| --- | --- |
| `core/dot_logic_config.gd` | `DotLogicConfig`: every tunable, `from_files()` |
| `core/dot_logic_entity.gd` | `DotLogicEntity`: kinds relay, counter, timer, auto, branch, compare, case, node and what each does with an input |
| `runtime/dot_logic_graph.gd` | `DotLogicGraph`: `load_document`, `start`, `input`, `update(dt)`, `snapshot()`/`restore()`; signals `node_input`, `fired`, `overflow`; delayed queue |
| `examples/logic_selftest.tscn` | the suite (8 sections, 53 checks plus the two summary checks) |

- **Boundary.** dot-logic is the generic, scene-free, clock-driven graph (relay, counter, timer, auto, node). dot-map owns the Source entity classes (`addons/dot_map/io`: `DotMapRelay`, `DotMapTrigger`, `DotMapCounter`, ...) and the map loader; dot-map-convert only keeps logic entities as data. dot-script is the community rule document. dot-logic never looks at the world: the game calls `input()` and acts on `node_input`.
- **No hard caps**: every limit is a config field, 0 means unlimited, and a refusal says why. Nothing is clamped silently.
- **No autoloads, no scene paths**, no class_name reliance in shipped scripts.
- **Validate**: `--import`, parse every `.gd`, run the suite through `hv`.
