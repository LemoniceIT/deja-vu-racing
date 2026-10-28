extends Node

func _ready():
	var out: Array = []
	var scene = load("res://scenes/vehicle.tscn") as PackedScene
	if scene == null:
		out.append("Could not load vehicle.tscn")
	else:
		var root: Node = scene.instantiate()
		out.append("=== vehicle.tscn root: %s name=%s" % [root.get_class(), root.name])
		_print(root, 0, out)

		var model: Node = root.get_node_or_null("Container/Model")
		if model == null:
			out.append("Container/Model NOT FOUND")
			var c = root.get_node_or_null("Container")
			out.append("Container found: %s" % c)
			if c != null:
				for ch in c.get_children():
					out.append("  Container child: %s %s" % [ch.get_class(), ch.name])
		else:
			out.append("=== tree under Container/Model ===")
			_print(model, 1, out)
			out.append("=== find wheels/Car under Model ===")
			for n in ["Car", "RootNode", "Wheel1", "Wheel2", "Wheel3", "Wheel4"]:
				var f = _find_by_name(model, n)
				if f != null:
					out.append("%s -> %s path=%s" % [n, f.get_class(), str(f.get_path())])
				else:
					out.append("%s -> NOT FOUND" % n)
			# Try explicit paths
			out.append("=== get_node_or_null tries (relative to Container) ===")
			var container = root.get_node_or_null("Container")
			var tries = [
				"Model/RootNode/Car/Wheel1",
				"Model/Car/Wheel1",
				"Model/Wheel1",
				"Model/RootNode/Car",
			]
			for p in tries:
				var g = container.get_node_or_null(NodePath(p))
				out.append("Container.%s -> %s" % [p, str(g) if g != null else "null"])

	var s = "\n".join(out) + "\n"
	var f := FileAccess.open("user://tree_output.txt", FileAccess.WRITE)
	if f != null:
		f.store_string(s)
		f.close()
	print(s)
	get_tree().quit()

func _find_by_name(node: Node, name: String) -> Node:
	for child in node.get_children():
		if child.name == name:
			return child
		var r = _find_by_name(child, name)
		if r != null:
			return r
	return null

func _print(node: Node, depth: int, buf: Array):
	var indent = "  ".repeat(depth)
	buf.append("%s- %s name=%s path=%s" % [indent, node.get_class(), node.name, node.get_path()])
	for child in node.get_children():
		_print(child, depth + 1, buf)
