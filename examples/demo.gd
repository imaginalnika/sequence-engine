extends SceneTree

func _initialize() -> void:
	var engine = preload("res://addons/sequence_engine/graph_sequence.gd").new()
	assert(engine.load_graph("res://examples/example_graph.json").is_empty())
	engine.variables["permission"] = true
	engine.begin_turn()
	var edge = engine.select_edge()
	engine.queue_transition(edge["to"])
	engine.commit_pending()
	print(JSON.stringify(engine.snapshot()))
	quit()
