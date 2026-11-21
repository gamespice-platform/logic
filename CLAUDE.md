# GameSpice Logic

Godot 4.7+ addon for map-side logic as data: named entities with inputs and outputs, trigger, relay and action graphs, delays, counters and timers, in the style converted Source maps already carry. Read the family [CLAUDE.md](../../CLAUDE.md) first. **The distributable is `addons/gs_logic/`**; it requires [GameSpice Core](../gs-core) only (`ln -s ../../gs-core/addons/gs_core addons/gs_core`, gitignored).

| Path | What |
| --- | --- |
| `core/gs_logic_config.gd` | `GSLogicConfig`: every tunable, `from_files()` |
| `core/gs_logic_entity.gd` | `GSLogicEntity`: kinds relay, counter, timer, auto, branch, compare, case, node and what each does with an input |
| `runtime/gs_logic_graph.gd` | `GSLogicGraph`: `load_document`, `start`, `input`, `update(dt)`, `snapshot()`/`restore()`; signals `node_input`, `fired`, `overflow`; delayed queue |
| `examples/logic_selftest.tscn` | the suite (8 sections, 53 checks plus the two summary checks) |

- **Boundary.** gs-logic is the generic, scene-free, clock-driven graph (relay, counter, timer, auto, node). gs-map owns the Source entity classes (`addons/gs_map/io`: `GSMapRelay`, `GSMapTrigger`, `GSMapCounter`, ...) and the map loader; gs-map-convert only keeps logic entities as data. gs-script is the community rule document. gs-logic never looks at the world: the game calls `input()` and acts on `node_input`.
- **No hard caps**: every limit is a config field, 0 means unlimited, and a refusal says why. Nothing is clamped silently.
- **No autoloads, no scene paths**, no class_name reliance in shipped scripts.
- **Validate**: `--import`, parse every `.gd`, run the suite through `hv`.
