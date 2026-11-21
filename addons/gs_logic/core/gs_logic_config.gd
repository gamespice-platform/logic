class_name GSLogicConfig
extends GSConfig

## Every tunable of Logic. Layered like any config: defaults, `cfg/addon/gs_logic/*.yml`, the game tier, `GS_LOGIC_*` environment, then `--logic-*` flags. A value of 0 on a limit means unlimited.

const ADDON := "gs-logic"

## Master switch: off, a graph accepts no inputs and runs nothing.
@export var enabled: bool = true

@export_group("Limits")
## The most delayed inputs waiting at once; one past it is dropped and counted. 0 is unlimited.
@export_range(0, 1000000, 1) var max_pending: int = 4096
## The most inputs one [method GSLogicGraph.update] or one fire may dispatch before the graph stops with an error (a loop with no delay). 0 is unlimited, and then a loop hangs the caller.
@export_range(0, 1000000, 1) var max_chain: int = 1000
## The most entities a document may declare. 0 is unlimited.
@export_range(0, 1000000, 1) var max_entities: int = 4096

func env_prefix() -> String:
	return "GS_LOGIC_"


func cli_prefix() -> String:
	return "--logic-"


func validate() -> GSResult:
	for k in ["max_pending", "max_chain", "max_entities"]:
		if int(get(k)) < 0:
			return GSResult.fail(GSError.CODE_INVALID, "logic %s must be 0 (unlimited) or more, got %d" % [k, int(get(k))])
	return GSResult.success(self)

func describe() -> String:
	return "logic %s pending<=%d chain<=%d entities<=%d" % ["on" if enabled else "disabled", max_pending, max_chain, max_entities]


## The `logic` profile schema (the shape of GameSpice Profile's field()), read from the exports so it cannot drift; GameSpice Profile's profile_check finds it here.
static func schema() -> Array:
	var out: Array = []
	var cfg := GSLogicConfig.new()
	for prop: Dictionary in cfg.get_property_list():
		if not (int(prop["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE) or not (int(prop["usage"]) & PROPERTY_USAGE_EDITOR):
			continue
		var type := ""
		match int(prop["type"]):
			TYPE_BOOL: type = "bool"
			TYPE_INT: type = "int"
			TYPE_FLOAT: type = "float"
			TYPE_STRING: type = "string"
			TYPE_PACKED_STRING_ARRAY: type = "list"
		if type == "":
			continue
		var key := str(prop["name"])
		var def: Variant = cfg.get(key)
		var f := {"name": key, "type": type, "default": Array(def) if def is PackedStringArray else def}
		if int(prop["hint"]) == PROPERTY_HINT_RANGE and type != "string":
			var parts := str(prop["hint_string"]).split(",")
			f["min"] = parts[0].to_int() if type == "int" else parts[0].to_float()
			f["max"] = parts[1].to_int() if type == "int" else parts[1].to_float()
		out.append(f)
	return out


## Kind to schema for GameSpice Profile's profile_check (a game's `cfg/game/<game>/logic/game.yml`).
static func profile_schemas() -> Dictionary:
	return {"logic": {"schema": schema(), "children": {}}}


## Defaults, then `cfg/addon/gs_logic/*.yml` and the game tier, then environment and command line.
static func from_files() -> GSResult:
	var cfg := GSLogicConfig.new()
	var files := GSAddonConfig.load_dir(ADDON)
	if not files.ok:
		return files
	cfg.apply_dictionary(files.value as Dictionary, "yml")
	return cfg.load_layered()


