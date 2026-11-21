class_name GSLogicEntity
extends RefCounted

## One named logic entity. Its kind decides which inputs it understands and which outputs it fires:
##
##   relay    inputs Trigger, Enable, Disable, Toggle, CancelPending     outputs OnTrigger   key once
##   counter  inputs Add, Subtract, SetValue, Reset, Enable, Disable      outputs OnHitMin, OnHitMax, OutValue   keys min, max, start
##   timer    inputs Enable, Disable, Toggle, ResetTimer                  outputs OnTimer   key interval (seconds)
##   auto     no inputs                                                   outputs OnSpawn (fired by GSLogicGraph.start)
##   branch   inputs SetValue, Test, Enable, Disable             outputs OnTrue, OnFalse   key start (0 or 1)
##   compare  inputs SetValue, SetCompareValue, Compare                   outputs OnLessThan, OnEqualTo, OnGreaterThan   keys start, compare_value
##   case     inputs InValue                                              outputs OnCase<key>, OnDefault   keys case<key> (the text that selects it)
##   node     any input is handed to the game (GSLogicGraph.node_input) outputs the game fires with GSLogicGraph.emit_output
##
## Input and output names are not case sensitive. An entity changes only its own state and asks the graph to
## fire outputs; the graph owns the clock and the queue.

const KINDS := ["relay", "counter", "timer", "auto", "branch", "compare", "case", "node"]

var name: String = ""
var kind: String = "relay"
var keys: Dictionary = {}
var enabled: bool = true
var value: float = 0.0
var spent: bool = false
var elapsed: float = 0.0
## The second operand of a compare entity.
var other: float = 0.0


static func make(p_name: String, p_kind: String, p_keys: Dictionary) -> GSLogicEntity:
	var e := GSLogicEntity.new()
	e.name = p_name
	e.kind = p_kind
	e.keys = p_keys
	e.enabled = bool(p_keys.get("enabled", true))
	e.value = float(p_keys.get("start", 0.0)) if p_kind in ["counter", "branch", "compare"] else 0.0
	e.other = float(p_keys.get("compare_value", 0.0))
	return e


func key_float(k: String, def: float) -> float:
	return float(keys.get(k, def))


## Applies an input. Returns false for an input this kind does not have.
func receive(graph: GSLogicGraph, input: String, param: String, activator: Variant) -> bool:
	match kind:
		"relay": return _relay(graph, input, activator)
		"counter": return _counter(graph, input, param, activator)
		"timer": return _timer(input)
		"branch": return _branch(graph, input, param, activator)
		"compare": return _compare(graph, input, param, activator)
		"case": return _case(graph, input, param, activator)
		"node":
			graph.node_input.emit(name, input, param, activator)
			return true
	return false


func _switch(input: String) -> bool:
	match input:
		"enable": enabled = true
		"disable": enabled = false
		"toggle": enabled = not enabled
		_: return false
	return true


func _relay(graph: GSLogicGraph, input: String, activator: Variant) -> bool:
	if _switch(input):
		return true
	match input:
		"trigger":
			if enabled and not spent:
				spent = bool(keys.get("once", false))
				graph.fire(self, "ontrigger", activator)
			return true
		"cancelpending":
			graph.cancel_pending(name)
			return true
	return false


func _counter(graph: GSLogicGraph, input: String, param: String, activator: Variant) -> bool:
	if _switch(input):
		return true
	var lo := key_float("min", 0.0)
	var hi := key_float("max", 1.0)
	var before := value
	match input:
		"add": value += param.to_float() if not param.is_empty() else 1.0
		"subtract": value -= param.to_float() if not param.is_empty() else 1.0
		"setvalue": value = param.to_float()
		"reset": value = key_float("start", 0.0)
		_: return false
	if not enabled:
		value = before
		return true
	value = clampf(value, lo, hi)
	if value != before:
		graph.fire(self, "outvalue", activator, str(value))
		if value >= hi:
			graph.fire(self, "onhitmax", activator)
		elif value <= lo:
			graph.fire(self, "onhitmin", activator)
	return true


func _timer(input: String) -> bool:
	if _switch(input):
		return true
	if input == "resettimer":
		elapsed = 0.0
		return true
	return false


func _branch(graph: GSLogicGraph, input: String, param: String, activator: Variant) -> bool:
	if _switch(input):
		return true
	match input:
		"setvalue": value = 1.0 if param.to_float() != 0.0 or param.to_lower() == "true" else 0.0
		"test":
			if enabled:
				graph.fire(self, "ontrue" if value != 0.0 else "onfalse", activator)
		_: return false
	return true


func _compare(graph: GSLogicGraph, input: String, param: String, activator: Variant) -> bool:
	match input:
		"setvalue": value = param.to_float()
		"setcomparevalue": other = param.to_float()
		"compare":
			graph.fire(self, "onlessthan" if value < other else ("onequalto" if value == other else "ongreaterthan"), activator)
		_: return false
	return true


func _case(graph: GSLogicGraph, input: String, param: String, activator: Variant) -> bool:
	if input != "invalue":
		return false
	for k: String in keys:
		if k.begins_with("case") and str(keys[k]) == param:
			graph.fire(self, "on" + k.to_lower(), activator)
			return true
	graph.fire(self, "ondefault", activator)
	return true


## Advances a timer; fires OnTimer once per interval elapsed, never more than the time that passed allows.
func advance(graph: GSLogicGraph, dt: float) -> void:
	if kind != "timer" or not enabled:
		return
	var interval := key_float("interval", 1.0)
	if interval <= 0.0:
		return
	elapsed += dt
	while elapsed >= interval:
		elapsed -= interval
		graph.fire(self, "ontimer", null)
