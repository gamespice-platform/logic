extends Node
## Walk-through: a button opens a door after a delay, a counter gates it, and the state is saved and restored.


func _ready() -> void:
	var g := GSLogicGraph.new()
	var r := g.load_document({
		"entities": [{"name": "button", "class": "node"}, {"name": "presses", "class": "counter", "max": 2}, {"name": "door", "class": "node"}],
		"connections": [
			{"from": "button", "output": "OnPressed", "to": "presses", "input": "Add"},
			{"from": "presses", "output": "OnHitMax", "to": "door", "input": "Open", "delay": 1.0},
		]})
	if not r.ok:
		push_error(r.error.message)
		return
	g.node_input.connect(func(entity: String, input: String, _p: String, _a: Variant) -> void: print("%s <- %s" % [entity, input]))
	g.emit_output("button", "OnPressed")
	g.emit_output("button", "OnPressed")
	var saved := g.snapshot()
	g.update(1.0)
	print("restoring: %d unknown" % g.restore(saved).value)
	g.update(1.0)
