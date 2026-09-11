extends RefCounted
## Host judge: async Callable(question: String, history: Array) -> bool.
## Cancellation invalidates pending work without committing a transition.
var _generation := 0

func cancel(engine) -> void:
	_generation += 1
	engine.clear_pending()

func evaluate(engine, judge: Callable, history: Array = [], silence := false) -> Dictionary:
	_generation += 1
	var generation := _generation
	engine.clear_pending()
	engine.begin_turn()
	var answers := {}
	var edges: Array = engine.outgoing_edges()
	for edge in edges:
		if silence and not engine.silence_eligible(edge, edges): continue
		while true:
			var question: String = engine.needed_question(edge.get("condition_ast"), answers)
			if question == "": break
			if not judge.is_valid():
				engine.clear_pending()
				return {"status": "question_required", "question": question}
			var answer = await judge.call(question, history.duplicate(true))
			if generation != _generation: return {"status": "cancelled"}
			if not answer is bool:
				engine.clear_pending()
				return {"status": "judge_error"}
			answers[question] = answer
		if engine.evaluate_ast(edge.get("condition_ast"), answers):
			engine.queue_transition(edge["to"])
			return {"status": "ready", "edge": edge.duplicate(true), "answers": answers}
	return {"status": "ready", "edge": {}, "answers": answers}
