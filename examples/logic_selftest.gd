extends Node

## gs-logic's headless suite (res://examples/logic_selftest.tscn).
## Counts sections run to their last line as well as checks, because a script error
## aborts a section and not the run.

const EXPECTED_SECTIONS := 8
const EXPECTED_CHECKS := 53

var _passed := 0
var _failed := 0
var _sections := 0


func _ready() -> void:
	print("gs-logic")
	_config()
	_document()
	_relay()
	_counter()
	_timer_and_delay()
	_limits()
	_decision_kinds()
	_save()
	print("")
	_check(_sections == EXPECTED_SECTIONS, "every section ran to its last line (%d of %d)" % [_sections, EXPECTED_SECTIONS])
	_check(_passed + _failed == EXPECTED_CHECKS, "and the suite ran all %d of its checks (%d)" % [EXPECTED_CHECKS, _passed + _failed])
	print("%d passed, %d failed" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _graph(doc: Dictionary) -> GSLogicGraph:
	var g := GSLogicGraph.new()
	var r := g.load_document(doc)
	if not r.ok:
		print("  load failed: ", r.error.message)
	return g


func _link(from: String, out: String, to: String, inp: String, extra: Dictionary = {}) -> Dictionary:
	var d := {"from": from, "output": out, "to": to, "input": inp}
	d.merge(extra, true)
	return d


func _recorder(g: GSLogicGraph) -> Array:
	var seen: Array = []
	g.node_input.connect(func(e: String, i: String, p: String, _a: Variant) -> void: seen.append([e, i, p]))
	return seen


func _config() -> void:
	var c := GSLogicConfig.new()
	_check(c.validate().ok and c.max_chain == 1000, "defaults validate")
	c.max_pending = -1
	_check(not c.validate().ok, "a negative limit is refused, 0 means unlimited")
	var names: Array = GSLogicConfig.profile_schemas()["logic"]["schema"].map(func(f: Dictionary) -> Variant: return f["name"])
	_check(names.has("max_chain") and names.size() == c.config_keys().size(), "profile schema lists every key", str(names.size()))
	var applied := c.apply_dictionary({"max_pending": 9, "enabled": false})
	_check(applied.size() == 2 and c.max_pending == 9 and not c.enabled, "a dictionary layer sets values", str(applied))
	_check(c.env_prefix() == "GS_LOGIC_" and c.cli_prefix() == "--logic-", "env and command-line prefixes")
	var r := GSLogicConfig.from_files()
	_check(r.ok and (r.value as GSLogicConfig).describe().begins_with("logic"), "from_files returns a config")
	_sections += 1


func _document() -> void:
	var g := GSLogicGraph.new()
	_check(not g.load_document([]).ok, "a list is not a document")
	var bad := g.load_document({"entities": [{"name": "a", "class": "nope"}, {"name": "a", "class": "relay"}, {"class": "relay"}],
		"connections": [_link("a", "OnTrigger", "ghost", "Trigger"), _link("a", "", "a", "x"), _link("a", "o", "a", "i", {"delay": -1})]})
	_check(not bad.ok and bad.error.message.split("\n").size() >= 5, "every problem is listed", bad.error.message if not bad.ok else "")
	var ok := g.load_document({"entities": [{"name": "a", "class": "relay"}]})
	_check(ok.ok and g.entity("a") != null and g.entity("zzz") == null, "a good document loads")
	_check(not g.load_document({"entities": [{"name": "x", "class": "nope"}]}).ok and g.entity("a") != null, "a refused document leaves the loaded graph alone")
	var parsed: Variant = JSON.parse_string(JSON.stringify({"entities": [{"name": "a", "class": "counter", "max": 3}]}))
	_check(g.load_document(parsed).ok, "a JSON round trip loads")
	g.config.max_entities = 1
	_check(not g.load_document({"entities": [{"name": "a", "class": "relay"}, {"name": "b", "class": "relay"}]}).ok, "max_entities is enforced")
	g.config.max_entities = 0
	_check(g.load_document({"entities": [{"name": "a", "class": "relay"}, {"name": "b", "class": "relay"}]}).ok, "max_entities 0 is unlimited")
	_sections += 1


func _relay() -> void:
	var g := _graph({"entities": [{"name": "r", "class": "relay"}, {"name": "once", "class": "relay", "once": true}, {"name": "door", "class": "node"}, {"name": "boot", "class": "auto"}],
		"connections": [_link("r", "OnTrigger", "door", "Open", {"param": "fast"}), _link("once", "OnTrigger", "door", "Close"), _link("boot", "OnSpawn", "door", "Lock")]})
	var seen := _recorder(g)
	g.start()
	_check(seen == [["door", "lock", ""]], "an auto entity fires OnSpawn at start", str(seen))
	seen.clear()
	g.input("r", "Trigger")
	_check(seen == [["door", "open", "fast"]], "a relay trigger fires its connection with the param", str(seen))
	seen.clear()
	g.input("r", "Disable")
	g.input("r", "Trigger")
	_check(seen.is_empty(), "a disabled relay does nothing")
	g.input("r", "Toggle")
	g.input("r", "Trigger")
	_check(seen.size() == 1, "toggle turns it back on")
	seen.clear()
	g.input("once", "Trigger")
	g.input("once", "Trigger")
	_check(seen == [["door", "close", ""]], "a once relay fires once")
	g.input("r", "NoSuchInput")
	_check(g.errors.size() == 1 and g.errors[0].contains("no input"), "an input an entity lacks is recorded, not swallowed", str(g.errors))
	g.config.enabled = false
	seen.clear()
	_check(not g.input("r", "Trigger") and seen.is_empty(), "a disabled graph refuses inputs")
	_sections += 1


func _counter() -> void:
	var g := _graph({"entities": [{"name": "c", "class": "counter", "min": 0, "max": 3}, {"name": "out", "class": "node"}],
		"connections": [_link("c", "OnHitMax", "out", "Done"), _link("c", "OnHitMin", "out", "Empty"), _link("c", "OutValue", "out", "Show")]})
	var seen := _recorder(g)
	g.input("c", "Add")
	g.input("c", "Add", "1")
	_check(g.entity("c").value == 2.0 and seen == [["out", "show", "1.0"], ["out", "show", "2.0"]], "add steps the value and OutValue reports it", str(seen))
	seen.clear()
	g.input("c", "Add")
	_check(seen == [["out", "show", "3.0"], ["out", "done", ""]], "reaching max fires OnHitMax once", str(seen))
	seen.clear()
	g.input("c", "Add")
	_check(seen.is_empty() and g.entity("c").value == 3.0, "past max it clamps and stays quiet")
	g.input("c", "SetValue", "0")
	_check(seen.back() == ["out", "empty", ""], "reaching min fires OnHitMin", str(seen))
	g.input("c", "Disable")
	seen.clear()
	g.input("c", "Add")
	_check(g.entity("c").value == 0.0 and seen.is_empty(), "a disabled counter ignores add")
	g.input("c", "Enable")
	g.input("c", "SetValue", "2")
	g.input("c", "Reset")
	_check(g.entity("c").value == 0.0, "reset returns to start")
	_sections += 1


func _timer_and_delay() -> void:
	var g := _graph({"entities": [{"name": "t", "class": "timer", "interval": 2.0, "enabled": false}, {"name": "r", "class": "relay"}, {"name": "n", "class": "node"}],
		"connections": [_link("t", "OnTimer", "n", "Tick"), _link("r", "OnTrigger", "n", "Late", {"delay": 1.5}), _link("r", "OnTrigger", "n", "Soon", {"delay": 0.5}), _link("r", "OnTrigger", "n", "Now")]})
	var seen := _recorder(g)
	g.update(5.0)
	_check(seen.is_empty(), "a timer that starts disabled does not tick")
	g.input("t", "Enable")
	g.update(2.0)
	_check(seen.size() == 1 and seen[0][1] == "tick", "a timer fires once per interval", str(seen))
	g.update(4.5)
	_check(seen.size() == 3, "a long step fires every interval it covers", str(seen.size()))
	seen.clear()
	g.input("t", "Disable")
	g.input("r", "Trigger")
	_check(seen.map(func(s: Array) -> Variant: return s[1]) == ["now"] and g.pending() == 2, "a delayed connection waits", str(seen))
	g.update(0.6)
	_check(seen.map(func(s: Array) -> Variant: return s[1]) == ["now", "soon"], "and comes due in order of time", str(seen))
	g.update(1.0)
	_check(seen.size() == 3 and seen[2][1] == "late" and g.pending() == 0, "the later one follows")
	seen.clear()
	g.input("r", "Trigger")
	g.input("r", "CancelPending")
	g.update(5.0)
	_check(seen.map(func(s: Array) -> Variant: return s[1]) == ["now"], "CancelPending drops what the relay had queued", str(seen))
	var once := _graph({"entities": [{"name": "r", "class": "relay"}, {"name": "n", "class": "node"}], "connections": [_link("r", "OnTrigger", "n", "Hi", {"once": true})]})
	var s2 := _recorder(once)
	once.input("r", "Trigger")
	once.input("r", "Trigger")
	_check(s2.size() == 1, "a once connection fires one time")
	var ext := _graph({"entities": [{"name": "vol", "class": "node"}, {"name": "n", "class": "node"}], "connections": [_link("vol", "OnStartTouch", "n", "Open")]})
	var s3 := _recorder(ext)
	ext.emit_output("vol", "OnStartTouch", 7)
	_check(s3 == [["n", "open", ""]], "the game fires a node's output, for a trigger volume", str(s3))
	_sections += 1


func _limits() -> void:
	var loop := {"entities": [{"name": "a", "class": "relay"}, {"name": "b", "class": "relay"}], "connections": [_link("a", "OnTrigger", "b", "Trigger"), _link("b", "OnTrigger", "a", "Trigger")]}
	var g := _graph(loop)
	g.config.max_chain = 50
	var over: Array = []
	g.overflow.connect(func(n: int) -> void: over.append(n))
	g.input("a", "Trigger")
	_check(over == [50] and g.errors.size() >= 1 and g.errors[0].contains("chain"), "a loop with no delay stops loudly at max_chain", str(over))
	_check(g.pending() == 0, "and leaves nothing behind")
	var slow := _graph({"entities": [{"name": "a", "class": "relay"}, {"name": "b", "class": "relay"}], "connections": [_link("a", "OnTrigger", "b", "Trigger", {"delay": 0.1}), _link("b", "OnTrigger", "a", "Trigger", {"delay": 0.1})]})
	var fires: Array = [0]
	slow.fired.connect(func(_e: String, _o: String) -> void: fires[0] += 1)
	slow.input("a", "Trigger")
	for i in 10:
		slow.update(0.1)
	_check(fires[0] >= 10 and slow.errors.is_empty(), "a loop with a delay is a clock, not a hang", str(fires))
	var p := _graph({"entities": [{"name": "r", "class": "relay"}, {"name": "n", "class": "node"}], "connections": [_link("r", "OnTrigger", "n", "A", {"delay": 1}), _link("r", "OnTrigger", "n", "B", {"delay": 1}), _link("r", "OnTrigger", "n", "C", {"delay": 1})]})
	p.config.max_pending = 2
	p.input("r", "Trigger")
	_check(p.pending() == 2 and p.dropped == 1 and p.errors.size() == 1, "max_pending drops and counts, loudly", str(p.pending()))
	p.config.max_pending = 0
	p.input("r", "Trigger")
	_check(p.pending() == 5, "max_pending 0 is unlimited")
	var unl := _graph(loop)
	unl.config.max_chain = 0
	_check(unl.config.max_chain == 0, "max_chain 0 is unlimited (not exercised: it would hang)")
	_sections += 1


func _decision_kinds() -> void:
	var g := _graph({"entities": [{"name": "b", "class": "branch"}, {"name": "n", "class": "node"}],
		"connections": [_link("b", "OnTrue", "n", "Yes"), _link("b", "OnFalse", "n", "No")]})
	var seen := _recorder(g)
	g.input("b", "Test")
	g.input("b", "SetValue", "1")
	g.input("b", "Test")
	g.input("b", "SetValue", "0")
	g.input("b", "Test")
	_check(seen.map(func(x: Array) -> Variant: return x[1]) == ["no", "yes", "no"], "a branch sends OnTrue or OnFalse by its value", str(seen))
	g.input("b", "Disable")
	g.input("b", "Test")
	_check(seen.size() == 3, "a disabled branch stays quiet")
	var c := _graph({"entities": [{"name": "c", "class": "compare", "compare_value": 5}, {"name": "n", "class": "node"}],
		"connections": [_link("c", "OnLessThan", "n", "Lt"), _link("c", "OnEqualTo", "n", "Eq"), _link("c", "OnGreaterThan", "n", "Gt")]})
	var cs := _recorder(c)
	for v in ["3", "5", "9"]:
		c.input("c", "SetValue", v)
		c.input("c", "Compare")
	c.input("c", "SetCompareValue", "10")
	c.input("c", "Compare")
	_check(cs.map(func(x: Array) -> Variant: return x[1]) == ["lt", "eq", "gt", "lt"], "a compare reports less, equal, greater, and takes a new operand", str(cs))
	var k := _graph({"entities": [{"name": "k", "class": "case", "case1": "red", "case2": "blue"}, {"name": "n", "class": "node"}],
		"connections": [_link("k", "OnCase1", "n", "One"), _link("k", "OnCase2", "n", "Two"), _link("k", "OnDefault", "n", "Other")]})
	var ks := _recorder(k)
	for v in ["blue", "red", "green"]:
		k.input("k", "InValue", v)
	_check(ks.map(func(x: Array) -> Variant: return x[1]) == ["two", "one", "other"], "a case picks its output by text, with a default", str(ks))
	_check(not k.input("ghost", "InValue") and k.entity_count() == 2 and k.entity_names().size() == 2, "unknown targets say so, and the entities can be listed")
	_sections += 1


func _save() -> void:
	var doc := {"entities": [{"name": "r", "class": "relay", "once": true}, {"name": "ct", "class": "counter", "max": 10}, {"name": "n", "class": "node"}],
		"connections": [_link("r", "OnTrigger", "n", "Go", {"delay": 2.0}), _link("r", "OnTrigger", "ct", "Add", {"once": true})]}
	var g := _graph(doc)
	g.input("r", "Trigger")
	g.update(0.5)
	var snap := g.snapshot()
	var h := _graph(doc)
	var seen := _recorder(h)
	var r := h.restore(JSON.parse_string(JSON.stringify(snap)))
	_check(r.ok and r.value == 0 and is_equal_approx(h.time, 0.5), "a snapshot restores through JSON, no ids unknown")
	_check(h.entity("ct").value == 1.0 and h.entity("r").spent and h.pending() == 1, "state, spent flags and the waiting input come back")
	h.update(1.0)
	_check(seen.size() == 0, "a restored input is not early")
	h.update(0.6)
	_check(seen.size() == 1 and seen[0][1] == "go", "and fires when its time comes", str(seen))
	h.input("r", "Trigger")
	_check(h.entity("ct").value == 1.0, "a spent once connection stays spent")
	_check(not h.restore({"entities": 3}).ok, "a malformed snapshot is refused")
	_sections += 1


func _check(ok: bool, what: String, extra: String = "") -> void:
	if ok:
		_passed += 1
		print("  ok    ", what)
	else:
		_failed += 1
		print("  FAIL  ", what, "  ", extra)
