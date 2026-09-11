extends SceneTree
var checks := 0

func check(value: bool, label: String) -> void:
	if not value:
		push_error(label)
		quit(1)
		assert(value, label)
	checks += 1

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var engine = preload("res://addons/sequence_engine/graph_sequence.gd").new()
	check(engine.load_graph("res://examples/example_graph.json").is_empty(), "valid graph")
	check(not engine.configure({}).is_empty(), "invalid graph rejected")
	engine.variables["permission"] = true
	engine.begin_turn()
	check(engine.evaluate_ast(["turn", "=", 2], {}), "pending turn visible")
	check(engine.select_edge().get("to") == "complete", "select edge")
	engine.clear_pending()
	check(engine.turn == 1, "cancel leaves turn unchanged")
	engine.begin_turn()
	engine.queue_transition("complete")
	engine.commit_pending()
	check(engine.at_terminal_node(), "terminal reached")
	check(engine.visits["complete"] == 1, "visit count")
	var saved = engine.snapshot()
	engine.reset()
	engine.restore(saved)
	check(engine.at_terminal_node(), "restore terminal")
	engine.restore({"node": "removed"})
	check(engine.current_node == "welcome", "stale state fallback")
	engine.action_query = func(action): return action == "confirm"
	check(engine.evaluate_ast(["action", "confirm"], {}), "action callback")
	check(engine.needed_question(["and", ["q", "ready?"], ["q", "next?"]], {}) == "ready?", "lazy question")
	check(engine.needed_question(["and", ["q", "ready?"], ["q", "next?"]], {"ready?": false}) == "", "short circuit")
	var edge = {"condition_ast": ["q", "ready?"]}
	check(not engine.silence_eligible(edge, [edge]), "silence does not trigger lone question")
	check(engine.silence_eligible(edge, [edge, {"condition_ast": ["not", ["q", "ready?"]]}]), "paired silence branches")
	var runner = preload("res://addons/sequence_engine/question_runner.gd").new()
	engine.graph["edges"][0]["condition_ast"] = ["q", "ready?"]
	var result: Dictionary = await runner.evaluate(engine, func(_q, _h): return true)
	check(result["status"] == "ready" and engine.current_node == "welcome", "judge prepares without committing")
	engine.commit_pending()
	check(engine.current_node == "complete", "commit judged transition")
	print("PASS sequence-engine: %d checks" % checks)
	quit()
