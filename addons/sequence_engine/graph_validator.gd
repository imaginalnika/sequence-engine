extends RefCounted

static func validate(data) -> Array:
	var errors := []
	if not data is Dictionary: return ["Graph must be an object"]
	if not data.get("nodes") is Dictionary or data["nodes"].is_empty(): return ["nodes must be a nonempty object"]
	var nodes: Dictionary = data["nodes"]
	if not nodes.has(data.get("start", "")): errors.append("start must identify a node")
	for key in nodes:
		if not nodes[key] is Dictionary: errors.append("Node must be an object: " + str(key))
	if not data.get("edges") is Array: return errors + ["edges must be an array"]
	var variables = data.get("variables", {})
	if variables is Array:
		var normalized := {}
		for row in variables:
			if not row is Dictionary or not row.get("name") is String: return errors + ["Variable rows require a name"]
			normalized[row["name"]] = row
		variables = normalized
	if not variables is Dictionary: return errors + ["variables must be an object or array"]
	for key in variables:
		var value = variables[key]
		if value is Dictionary and value.get("type", "string") not in ["boolean", "string"]:
			errors.append("Unsupported variable type: " + str(key))
	for edge in data["edges"]:
		if not edge is Dictionary:
			errors.append("Edge must be an object")
			continue
		if not nodes.has(edge.get("from", "")) or not nodes.has(edge.get("to", "")):
			errors.append("Edge refers to an unknown node")
		if edge.get("priority") != null and not (edge["priority"] is int or edge["priority"] is float):
			errors.append("Edge priority must be numeric")
		_check_ast(edge.get("condition_ast"), variables, nodes, errors)
	return errors

static func _check_ast(ast, variables: Dictionary, nodes: Dictionary, errors: Array) -> void:
	if ast == null: return
	if not ast is Array or ast.is_empty():
		errors.append("Condition must be a nonempty array")
		return
	match ast[0]:
		"and", "or":
			if ast.size() < 2: errors.append("Boolean operator requires operands")
			for child in ast.slice(1): _check_ast(child, variables, nodes, errors)
		"not":
			if ast.size() != 2: errors.append("not requires one operand")
			else: _check_ast(ast[1], variables, nodes, errors)
		"var", "q", "action":
			if ast.size() != 2 or not ast[1] is String: errors.append("Condition requires a string argument")
			elif ast[0] == "var" and not variables.has(ast[1]): errors.append("Undeclared variable: " + ast[1])
		"turn", "visit":
			if ast.size() != (3 if ast[0] == "turn" else 4):
				errors.append("Invalid counter condition")
				return
			if ast[1] not in [">=", "<=", ">", "<", "=", "=="]: errors.append("Invalid comparison")
			if not (ast[2] is int or ast[2] is float): errors.append("Counter threshold must be numeric")
			if ast[0] == "visit" and not nodes.has(ast[3]): errors.append("Unknown visit node")
		_: errors.append("Unknown condition operator")
