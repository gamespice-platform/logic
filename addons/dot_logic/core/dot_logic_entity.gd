class_name DotLogicEntity
extends RefCounted

## One named logic entity. Its kind decides which inputs it understands and which outputs it fires:
##
##   relay    inputs Trigger, Enable, Disable, Toggle, CancelPending     outputs OnTrigger   key once
##   counter  inputs Add, Subtract, SetValue, Reset, Enable, Disable      outputs OnHitMin, OnHitMax, OutValue   keys min, max, start
##   timer    inputs Enable, Disable, Toggle, ResetTimer                  outputs OnTimer   key interval (seconds)
##   auto     no inputs                                                   outputs OnSpawn (fired by DotLogicGraph.start)
##   node     any input is handed to the game (DotLogicGraph.node_input) outputs the game fires with DotLogicGraph.emit_output
##
## Input and output names are not case sensitive. An entity changes only its own state and asks the graph to
## fire outputs; the graph owns the clock and the queue.

const KINDS := ["relay", "counter", "timer", "auto", "node"]

var name: String = ""
var kind: String = "relay"
var keys: Dictionary = {}
var enabled: bool = true
var value: float = 0.0
var spent: bool = false
var elapsed: float = 0.0


static func make(p_name: String, p_kind: String, p_keys: Dictionary) -> DotLogicEntity:
	var e := DotLogicEntity.new()
	e.name = p_name
	e.kind = p_kind
	e.keys = p_keys
	e.enabled = bool(p_keys.get("enabled", true))
	e.value = float(p_keys.get("start", 0.0)) if p_kind == "counter" else 0.0
	return e


func key_float(k: String, def: float) -> float:
	return float(keys.get(k, def))


## Applies an input. Returns false for an input this kind does not have.
func receive(graph: DotLogicGraph, input: String, param: String, activator: Variant) -> bool:
	match kind:
		"relay": return _relay(graph, input, activator)
		"counter": return _counter(graph, input, param, activator)
		"timer": return _timer(input)
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


func _relay(graph: DotLogicGraph, input: String, activator: Variant) -> bool:
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


func _counter(graph: DotLogicGraph, input: String, param: String, activator: Variant) -> bool:
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


## Advances a timer; fires OnTimer once per interval elapsed, never more than the time that passed allows.
func advance(graph: DotLogicGraph, dt: float) -> void:
	if kind != "timer" or not enabled:
		return
	var interval := key_float("interval", 1.0)
	if interval <= 0.0:
		return
	elapsed += dt
	while elapsed >= interval:
		elapsed -= interval
		graph.fire(self, "ontimer", null)
