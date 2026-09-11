extends RefCounted
## Turn-aware graph runtime. Question evaluation and persistence are supplied by the host.
signal transitioned(previous: String, current: String)
signal state_changed(snapshot: Dictionary)
signal terminal_reached(node: String)

const Validator = preload("graph_validator.gd")
const ARRIVAL_TURN := 1
var graph: Dictionary = {}
var current_node := ""
var turn := ARRIVAL_TURN
var visits: Dictionary = {}
var variables: Dictionary = {}
var var_types: Dictionary = {}
var end_pending := false
var action_query: Callable
var sync_variables: Callable
var _pending_node := ""
var _pending_turn := -1

func load_graph(path: String) -> Array:
	if not FileAccess.file_exists(path): return ["Graph file not found"]
	return configure(JSON.parse_string(FileAccess.get_file_as_string(path)))

func configure(data) -> Array:
	var errors: Array = Validator.validate(data)
	if not errors.is_empty(): return errors
	graph = data.duplicate(true)
	variables.clear()
	var_types.clear()
	var defs = graph.get("variables", {})
	if defs is Array:
		var normalized := {}
		for row in defs: normalized[row["name"]] = row
		defs = normalized
	for key in defs:
		var value = defs[key]
		var type = str(value.get("type", "string")) if value is Dictionary else ("boolean" if value is bool else "string")
		var_types[key] = type
		variables[key] = value.get("value", value.get("default", false if type == "boolean" else "")) if value is Dictionary else value
	reset()
	return []

func reset() -> void:
	current_node = graph.get("start", "")
	turn = ARRIVAL_TURN
	visits = {current_node: 1} if current_node != "" else {}
	end_pending = at_terminal_node() if current_node != "" else false
	clear_pending()

func transition_to(node_id: String) -> void:
	if not graph.get("nodes", {}).has(node_id) or node_id == current_node: return
	var previous := current_node
	current_node = node_id
	turn = ARRIVAL_TURN
	visits[node_id] = visits.get(node_id, 0) + 1
	end_pending = at_terminal_node()
	transitioned.emit(previous, current_node)
	save()
	if end_pending: terminal_reached.emit(current_node)

func snapshot() -> Dictionary:
	return {"node": current_node, "turn": turn, "visits": visits.duplicate(true), "variables": variables.duplicate(true)}

func save() -> void:
	state_changed.emit(snapshot())

func restore(data: Dictionary) -> void:
	reset()
	if graph.get("nodes", {}).has(data.get("node", "")):
		current_node = data["node"]
		turn = maxi(1, int(data.get("turn", ARRIVAL_TURN)))
		if data.get("visits") is Dictionary: visits = data["visits"].duplicate(true)
	if data.get("variables") is Dictionary:
		for key in data["variables"]:
			if var_types.has(key): variables[key] = data["variables"][key]
	end_pending = at_terminal_node()

func select_edge(answers: Dictionary = {}, silence := false) -> Dictionary:
	var edges := outgoing_edges()
	for edge in edges:
		if silence and not silence_eligible(edge, edges): continue
		if needed_question(edge.get("condition_ast"), answers) != "": return {}
		if evaluate_ast(edge.get("condition_ast"), answers): return edge
	return {}

func get_direction() -> String:
	var node_id = _pending_node if _pending_node != "" else current_node
	var d = graph["nodes"].get(node_id, {}).get("direction", "")
	return str(d).strip_edges()

func get_arrival_direction() -> String:
	if _pending_node != "" and _pending_node != current_node:
		return get_direction()
	if turn < ARRIVAL_TURN:
		return get_direction()
	return ""

func get_scripted_line() -> String:
	if _pending_node == "" or _pending_node == current_node:
		return ""
	var node = graph["nodes"].get(_pending_node, {})
	if node.get("type") != "script":
		return ""
	return str(node.get("direction", "")).strip_edges()

func first_message() -> String:
	var msg = graph["nodes"].get(current_node, {}).get("first_message")
	return "" if msg == null else str(msg).strip_edges()

func first_messages() -> Array:
	var out := []
	for line in first_message().replace("\\n", "\n").split("\n", false):
		line = str(line).strip_edges()
		if line != "":
			out.append(line)
	return out

func at_terminal_node() -> bool:
	return str(graph.get("nodes", {}).get(current_node, {}).get("type", "")) == "terminal"

func node_title(node_id: String) -> String:
	return str(graph.get("nodes", {}).get(node_id, {}).get("title", "")).strip_edges()

func begin_turn():
	variables.merge(sync_variables.call(), true) if sync_variables.is_valid() else null
	_pending_turn = turn + 1

func queue_transition(node_id: String):
	_pending_node = node_id

func commit_pending():
	if _pending_turn >= 0: turn = _pending_turn
	if _pending_node != "" and _pending_node != current_node:
		transition_to(_pending_node)
	else:
		save()
	clear_pending()

func clear_pending():
	_pending_turn = -1
	_pending_node = ""

func will_end() -> bool:
	var node_id = _pending_node if _pending_node != "" else current_node
	return end_pending if node_id == current_node else graph["nodes"].get(node_id, {}).get("type") == "terminal"

func outgoing_edges() -> Array:
	var edges = []
	for e in graph["edges"]:
		if e["from"] == current_node:
			edges.append(e)
	edges.sort_custom(func(a, b):
		var ap = a.get("priority")
		var bp = b.get("priority")
		if ap != null and bp != null: return ap < bp
		if ap != null: return true
		if bp != null: return false
		return false)
	return edges

func collect_questions(edges: Array) -> Array:
	var questions = []
	for e in edges:
		var ast = e.get("condition_ast")
		if ast: _collect_q(ast, questions)
	return questions

func _collect_q(ast, questions: Array):
	if not ast is Array: return
	match ast[0]:
		"q":
			if ast[1] not in questions: questions.append(ast[1])
		"var":
			if var_types.get(ast[1]) == "string":
				var val = str(variables.get(ast[1], ""))
				if val != "" and val not in questions: questions.append(val)
		"and", "or":
			for i in range(1, ast.size()): _collect_q(ast[i], questions)
		"not":
			_collect_q(ast[1], questions)

func needed_question(ast, answers: Dictionary) -> String:
	return str(_known_eval(ast, answers).get("question", ""))

func _known_eval(ast, answers: Dictionary) -> Dictionary:
	if ast == null: return {"known": true, "value": true}
	if not ast is Array: return {"known": true, "value": false}
	match ast[0]:
		"and":
			var question := ""
			for i in range(1, ast.size()):
				var r = _known_eval(ast[i], answers)
				if r.get("known", false):
					if not r.get("value", false): return {"known": true, "value": false}
				elif question == "":
					question = str(r.get("question", ""))
			return {"known": false, "question": question} if question != "" else {"known": true, "value": true}
		"or":
			var question := ""
			for i in range(1, ast.size()):
				var r = _known_eval(ast[i], answers)
				if r.get("known", false):
					if r.get("value", false): return {"known": true, "value": true}
				elif question == "":
					question = str(r.get("question", ""))
			return {"known": false, "question": question} if question != "" else {"known": true, "value": false}
		"not":
			var r = _known_eval(ast[1], answers)
			if not r.get("known", false): return r
			return {"known": true, "value": not r.get("value", false)}
		"var":
			var vname = ast[1]
			if var_types.get(vname) == "string":
				var q = str(variables.get(vname, ""))
				if q == "": return {"known": true, "value": false}
				return {"known": true, "value": answers.get(q, false)} if answers.has(q) else {"known": false, "question": q}
		"q":
			return {"known": true, "value": answers.get(ast[1], false)} if answers.has(ast[1]) else {"known": false, "question": ast[1]}
	return {"known": true, "value": evaluate_ast(ast, answers)}

func evaluate_ast(ast, answers: Dictionary) -> bool:
	if ast == null: return true
	if not ast is Array: return false
	match ast[0]:
		"and":
			for i in range(1, ast.size()):
				if not evaluate_ast(ast[i], answers): return false
			return true
		"or":
			for i in range(1, ast.size()):
				if evaluate_ast(ast[i], answers): return true
			return false
		"not": return not evaluate_ast(ast[1], answers)
		"turn":
			var t = _pending_turn if _pending_turn >= 0 else turn
			return _compare(t, ast[1], int(ast[2]))
		"visit":
			var v = visits.get(ast[3], 0)
			return _compare(v, ast[1], int(ast[2]))
		"action": return (bool(action_query.call(ast[1])) if action_query.is_valid() else false)
		"var":
			var vname = ast[1]
			if var_types.get(vname) == "boolean":
				return _truthy(variables.get(vname, false))
			elif var_types.get(vname) == "string":
				return answers.get(str(variables.get(vname, "")), false)
			return false
		"q": return answers.get(ast[1], false)
	return false

func _compare(a: int, op: String, b: int) -> bool:
	match op:
		">=": return a >= b
		"<=": return a <= b
		">": return a > b
		"<": return a < b
		"=": return a == b
		"==": return a == b
	return false

func _truthy(val) -> bool:
	if val is bool: return val
	return str(val).to_lower().strip_edges() in ["true", "1", "yes"]

func silence_eligible(edge: Dictionary, all_edges: Array) -> bool:
	var ast = edge.get("condition_ast")
	if _sat_true(ast):
		return true
	var atoms = _judged_atoms(ast)
	if atoms.size() != 1: return false
	var key = atoms[0][1]
	var want_sign = not atoms[0][0]
	for other in all_edges:
		if is_same(other, edge): continue
		var oa = _judged_atoms(other.get("condition_ast"))
		if oa.size() == 1 and oa[0][1] == key and oa[0][0] == want_sign:
			return true
	return false

func _sat_true(ast) -> bool:
	if not ast is Array or ast.is_empty(): return true
	match ast[0]:
		"q": return false
		"var": return var_types.get(ast[1]) != "string"
		"and":
			for i in range(1, ast.size()):
				if not _sat_true(ast[i]): return false
			return true
		"or":
			for i in range(1, ast.size()):
				if _sat_true(ast[i]): return true
			return false
		"not": return _sat_false(ast[1])
	return true

func _sat_false(ast) -> bool:
	if not ast is Array or ast.is_empty(): return false
	match ast[0]:
		"q": return true
		"var": return true
		"and":
			for i in range(1, ast.size()):
				if _sat_false(ast[i]): return true
			return false
		"or":
			for i in range(1, ast.size()):
				if not _sat_false(ast[i]): return false
			return true
		"not": return _sat_true(ast[1])
	return true

func _judged_atoms(ast, negated := false, out := []) -> Array:
	if not ast is Array or ast.is_empty(): return out
	match ast[0]:
		"q": out.append([negated, "q:" + str(ast[1])])
		"var":
			if var_types.get(ast[1]) == "string":
				out.append([negated, "var:" + str(ast[1])])
		"and", "or":
			for i in range(1, ast.size()): _judged_atoms(ast[i], negated, out)
		"not": _judged_atoms(ast[1], not negated, out)
	return out

func increment_turn():
	turn += 1

func node_type(node_id: String):
	return graph["nodes"].get(node_id, {}).get("type")
