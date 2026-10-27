tool
extends SceneTree

func _initialize():
	# Load the scene without instancing
	var scene = load("res://scenes/vehicle.tscc")
	if scene == null:
		scene = load("res://scenes/vehicle.tscn")
	
	if scene == null:
		print("ERROR: Could not load vehicle scene")
		quit()
		return
	
	var vehicle = scene.instantiate()
	root.add_child(vehicle)
	
	# Set the vehicle to a known position
	vehicle.position = Vector3(3.5, 0, 5)
	
	# Wait for physics to settle
	for i in range(10):
		physics_process(0.016)
	
	var sphere = vehicle.get_node("Sphere")
	var sphere_shape = sphere.get_node("CollisionShape").shape
	var container = vehicle.get_node("Container")
	var model = container.get_node("Model")
	
	print("=== Sphere ===")
	print("Position: ", sphere.position)
	print("Radius: ", sphere_shape.radius)
	
	print("\n=== Container (vehicle_model) ===")
	print("Position: ", container.position)
	
	print("\n=== Model ===")
	print("Transform basis: ", model.transform.basis)
	print("Scale: ", model.scale)
	print("Position: ", model.position)
	
	# Get model's AABB in world space
	var model_aabb = model.get_aabb()
	print("Model AABB (local): ", model_aabb)
	print("Model AABB position: ", model_aabb.position)
	print("Model AABB size: ", model_aabb.size)
	
	print("\n=== Position Analysis ===")
	print("Sphere Y: ", sphere.position.y)
	print("Sphere radius: ", sphere_shape.radius)
	print("Sphere bottom (relative to Vehicle): ", sphere.position.y - sphere_shape.radius)
	print("Container Y: ", container.position.y)
	print("Model Y (local to Container): ", model.position.y)
	print("Model origin (relative to Vehicle): ", container.position.y + model.position.y)
	
	# Model bottom in Vehicle local space
	var model_bottom_local = container.position.y + model.position.y + model_aabb.position.y
	print("Model bottom (Vehicle local Y): ", model_bottom_local)
	print("Sphere bottom (Vehicle local Y): ", sphere.position.y - sphere_shape.radius)
	print("Gap (model bottom - sphere bottom): ", model_bottom_local - (sphere.position.y - sphere_shape.radius))
	
	# Try to get wheel info
	for child in model.get_children():
		if child is MeshInstance3D:
			var aabb = child.get_aabb()
			print(f"Mesh '{child.name}': local AABB = {aabb}")
	
	quit()
