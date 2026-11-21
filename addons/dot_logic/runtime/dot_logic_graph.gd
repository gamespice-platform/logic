class_name DotLogicGraph
extends RefCounted

## A graph of [DotLogicEntity] joined by connections, run on a clock the caller advances. Plain data in
## (a Dictionary from JSON), plain events out; no scene tree, no Node, no wall clock, so a server and a
## test run the same graph the same way.
##
##   {"entities": [{"name": "door_relay", "class": "relay", "once": true},
##                 {"name": "door", "class": "node"}],
##    "connections": [{"from": "door_relay", "output": "OnTrigger", "to": "door", "input": "Open", "delay": 0.5}]}
##
## A connection takes `param` (a string handed to the input) and `once` (it fires one time only).

signal node_input(entity: String, input: String, param: String, activator: Variant)
signal fired(entity: String, output: String)
## The graph stopped a run of inputs that did not end; `dispatched` is how many ran.
signal overflow(dispatched: int)

var config: DotLogicConfig = DotLogicConfig.new()
var time: float = 0.0
## Inputs dropped because max_pending was reached.
var dropped: int = 0
## Everything the graph refused or stopped, for a log line and a test.
var errors: PackedStringArray = PackedStringArray()

var _entities: Dictionary = {}
var _links: Dictionary = {}
var _pending: Array = []
var _seq: int = 0


## Validates and loads a document. Failure lists every problem; the graph keeps what it had.
func load_document(doc: Variant) -> DotResult:
	var errs := PackedStringArray()
	if not doc is Dictionary:
		return DotResult.fail(DotError.CODE_PARSE, "a logic document must be an object")
	var d: Dictionary = doc
	var ents: Dictionary = {}
	var list: Variant = d.get("entities", [])
	if not list is Array:
		return DotResult.fail(DotError.CODE_INVALID, "entities must be a list")
	if config.max_entities > 0 and (list as Array).size() > config.max_entities:
		errs.append("%d entities is over max_entities %d" % [(list as Array).size(), config.max_entities])
	for e: Variant in list:
		if not e is Dictionary or str((e as Dictionary).get("name", "")).is_empty():
			errs.append("every entity needs a name")
			continue
		var ed: Dictionary = e
		var n := str(ed["name"])
		var k := str(ed.get("class", ""))
		if ents.has(n):
			errs.append("duplicate entity '%s'" % n)
		elif not DotLogicEntity.KINDS.has(k):
			errs.append("entity '%s' has unknown class '%s'" % [n, k])
		else:
			ents[n] = DotLogicEntity.make(n, k, ed)
	var links: Dictionary = {}
	var conns: Variant = d.get("connections", [])
	if not conns is Array:
		errs.append("connections must be a list")
		conns = []
	for c: Variant in conns:
		if not c is Dictionary:
			errs.append("a connection must be an object")
			continue
		var cd: Dictionary = c
		var from := str(cd.get("from", ""))
		var to := str(cd.get("to", ""))
		if not ents.has(from) or not ents.has(to):
			errs.append("connection %s -> %s names an entity that does not exist" % [from, to])
			continue
		if str(cd.get("output", "")).is_empty() or str(cd.get("input", "")).is_empty():
			errs.append("connection %s -> %s needs an output and an input" % [from, to])
			continue
		var delay := float(cd.get("delay", 0.0))
		if delay < 0.0 or is_nan(delay):
			errs.append("connection %s -> %s has a negative delay" % [from, to])
			continue
		var key := from + "." + str(cd["output"]).to_lower()
		if not links.has(key):
			links[key] = []
		(links[key] as Array).append({"to": to, "input": str(cd["input"]).to_lower(), "param": str(cd.get("param", "")),
			"delay": delay, "once": bool(cd.get("once", false)), "used": false})
	if not errs.is_empty():
		return DotResult.fail(DotError.CODE_INVALID, "\n".join(errs))
	_entities = ents
	_links = links
	_pending.clear()
	time = 0.0
	dropped = 0
	errors.clear()
	return DotResult.success(ents.size())


func entity(n: String) -> DotLogicEntity:
	return _entities.get(n) as DotLogicEntity


func pending() -> int:
	return _pending.size()


## Fires every `auto` entity's OnSpawn. Call once when the map is ready.
func start() -> void:
	for n: String in _entities:
		var e: DotLogicEntity = _entities[n]
		if e.kind == "auto":
			fire(e, "onspawn", null)
	_drain()


## Sends an input from outside (a button the game spawned, a console command).
func input(target: String, name: String, param: String = "", delay: float = 0.0, activator: Variant = null) -> bool:
	if not config.enabled or not _entities.has(target):
		return false
	var ok := _enqueue(target, name.to_lower(), param, delay, activator, "")
	_drain()
	return ok


## A `node` entity's output, fired by the game (a trigger volume was entered).
func emit_output(entity_name: String, output: String, activator: Variant = null) -> void:
	var e := entity(entity_name)
	if e == null or not config.enabled:
		return
	fire(e, output.to_lower(), activator)
	_drain()


## Called by an entity: queues every connection of one of its outputs.
func fire(e: DotLogicEntity, output: String, activator: Variant, override_param: String = "") -> void:
	fired.emit(e.name, output)
	var key := e.name + "." + output
	if not _links.has(key):
		return
	for link: Dictionary in _links[key]:
		if bool(link["once"]) and bool(link["used"]):
			continue
		link["used"] = true
		_enqueue(str(link["to"]), str(link["input"]), override_param if (str(link["param"]).is_empty() and not override_param.is_empty()) else str(link["param"]),
			float(link["delay"]), activator, e.name)


func cancel_pending(source: String) -> int:
	var before := _pending.size()
	_pending = _pending.filter(func(p: Dictionary) -> bool: return str(p["source"]) != source)
	return before - _pending.size()


## Moves the clock on, advances timers, and dispatches every input that has come due, in order.
func update(dt: float) -> void:
	if not config.enabled or dt < 0.0:
		return
	time += dt
	for n: String in _entities:
		(_entities[n] as DotLogicEntity).advance(self, dt)
	_drain()


func _enqueue(target: String, name: String, param: String, delay: float, activator: Variant, source: String) -> bool:
	if config.max_pending > 0 and _pending.size() >= config.max_pending:
		dropped += 1
		errors.append("pending queue full (%d): dropped %s.%s" % [config.max_pending, target, name])
		return false
	_seq += 1
	var item := {"due": time + delay, "seq": _seq, "target": target, "input": name, "param": param, "activator": activator, "source": source}
	var i := _pending.size()
	while i > 0 and float((_pending[i - 1] as Dictionary)["due"]) > float(item["due"]):
		i -= 1
	_pending.insert(i, item)
	return true


func _drain() -> void:
	var n := 0
	while not _pending.is_empty() and float((_pending[0] as Dictionary)["due"]) <= time:
		if config.max_chain > 0 and n >= config.max_chain:
			var left := 0
			while not _pending.is_empty() and float((_pending[0] as Dictionary)["due"]) <= time:
				_pending.pop_front()
				left += 1
			errors.append("chain of %d inputs without ending: stopped, %d dropped" % [n, left])
			overflow.emit(n)
			return
		var p: Dictionary = _pending.pop_front()
		n += 1
		var e := entity(str(p["target"]))
		if e != null and not e.receive(self, str(p["input"]), str(p["param"]), p["activator"]):
			errors.append("%s has no input '%s'" % [e.name, p["input"]])
