class_name InteriorBuilder
extends Node3D

const WALL_THICKNESS := 0.2
const DOOR_WIDTH := 1.6
const NAVIGATION_MARGIN := 0.45
const FURNITURE_COLOR := Color("76543b")
const INTERACTION_COLOR := Color("b7483e")

@export var location_id := ""

var _built := false


func _ready() -> void:
	if not _built and not location_id.is_empty():
		build_location(location_id)


func build_location(requested_location_id: String) -> bool:
	var repository := ContentRepository.new()
	if not repository.load_spring():
		return false
	for location in repository.locations:
		if (
			location.get("location_id", "") == requested_location_id
			and location.get("is_interior", false)
		):
			return build_from_location(location)
	return false


func build_from_location(location: Dictionary) -> bool:
	if not _is_valid_location(location):
		return false

	location_id = location["location_id"]
	_built = true
	set_meta("location_id", location_id)
	set_meta("purpose", location["purpose"])
	set_meta("dimensions", location["dimensions"].duplicate(true))
	set_meta("floor_color", location["floor_color"])
	set_meta("wall_color", location["wall_color"])

	_clear_generated_children($Room)
	_clear_generated_children($Furniture)
	_clear_generated_children($InteractionPoints)
	_build_room(location)
	_build_furniture(location)
	_build_interaction_points(location)
	_place_transition_markers(location)
	_build_navigation(location)
	return true


func get_location_id() -> String:
	return location_id


func get_spawn_point() -> Marker3D:
	return $PlayerSpawn


func get_exit_point() -> Marker3D:
	return $ExteriorExit


func get_navigation_region() -> NavigationRegion3D:
	return $NavigationRegion3D


func _is_valid_location(location: Dictionary) -> bool:
	for field in [
		"location_id",
		"is_interior",
		"purpose",
		"dimensions",
		"floor_color",
		"wall_color",
		"furniture_layout",
		"interaction_points",
	]:
		if not location.has(field):
			return false
	return (
		location["is_interior"]
		and location["dimensions"].has("width")
		and location["dimensions"].has("depth")
		and location["dimensions"].has("height")
	)


func _build_room(location: Dictionary) -> void:
	var dimensions: Dictionary = location["dimensions"]
	var width := float(dimensions["width"])
	var depth := float(dimensions["depth"])
	var height := float(dimensions["height"])
	var floor_color := Color(location["floor_color"])
	var wall_color := Color(location["wall_color"])
	_add_box(
		$Room,
		"Floor",
		Vector3(width, 0.2, depth),
		Vector3(0.0, -0.1, 0.0),
		floor_color,
		true,
	)

	var walls := Node3D.new()
	walls.name = "Walls"
	$Room.add_child(walls)
	_add_box(
		walls,
		"BackWall",
		Vector3(width, height, WALL_THICKNESS),
		Vector3(0.0, height * 0.5, -depth * 0.5),
		wall_color,
		true,
	)
	_add_box(
		walls,
		"LeftWall",
		Vector3(WALL_THICKNESS, height, depth),
		Vector3(-width * 0.5, height * 0.5, 0.0),
		wall_color,
		true,
	)
	_add_box(
		walls,
		"RightWall",
		Vector3(WALL_THICKNESS, height, depth),
		Vector3(width * 0.5, height * 0.5, 0.0),
		wall_color,
		true,
	)
	var front_segment_width := (width - DOOR_WIDTH) * 0.5
	var front_offset := (DOOR_WIDTH + front_segment_width) * 0.5
	for side in [-1.0, 1.0]:
		_add_box(
			walls,
			"Front%s" % ("Left" if side < 0.0 else "Right"),
			Vector3(front_segment_width, height, WALL_THICKNESS),
			Vector3(
				side * front_offset,
				height * 0.5,
				depth * 0.5,
			),
			wall_color,
			true,
		)


func _build_furniture(location: Dictionary) -> void:
	for item in location["furniture_layout"]:
		var furniture := _add_box(
			$Furniture,
			str(item["furniture_id"]).to_pascal_case(),
			Vector3(1.0, 1.0, 1.0),
			_content_position(location, item, 0.5),
			FURNITURE_COLOR,
			true,
		)
		furniture.set_meta("furniture_id", item["furniture_id"])
		furniture.set_meta("location_id", location_id)


func _build_interaction_points(location: Dictionary) -> void:
	for item in location["interaction_points"]:
		var point := Marker3D.new()
		point.name = str(item["interaction_id"]).to_pascal_case()
		point.position = _content_position(location, item, 0.1)
		point.set_meta("interaction_id", item["interaction_id"])
		point.set_meta("location_id", location_id)
		point.set_meta("purpose", location["purpose"])
		point.add_to_group("interior_interaction")
		$InteractionPoints.add_child(point)

		var marker := CSGCylinder3D.new()
		marker.name = "Marker"
		marker.radius = 0.18
		marker.height = 0.08
		marker.material = _material(INTERACTION_COLOR)
		point.add_child(marker)


func _place_transition_markers(location: Dictionary) -> void:
	var dimensions: Dictionary = location["dimensions"]
	var depth := float(dimensions["depth"])
	$PlayerSpawn.position = Vector3(0.0, 0.05, depth * 0.5 - 1.25)
	$PlayerSpawn.set_meta("location_id", location_id)
	$PlayerSpawn.add_to_group("interior_spawn")
	$ExteriorExit.position = Vector3(0.0, 0.05, depth * 0.5 - 0.35)
	$ExteriorExit.set_meta("location_id", location_id)
	$ExteriorExit.set_meta("interaction_id", "return_outdoors")
	$ExteriorExit.add_to_group("interior_exit")


func _build_navigation(location: Dictionary) -> void:
	var dimensions: Dictionary = location["dimensions"]
	var half_width := float(dimensions["width"]) * 0.5 - NAVIGATION_MARGIN
	var half_depth := float(dimensions["depth"]) * 0.5 - NAVIGATION_MARGIN
	var navigation_mesh := NavigationMesh.new()
	navigation_mesh.agent_height = 1.8
	navigation_mesh.agent_radius = NAVIGATION_MARGIN
	navigation_mesh.vertices = PackedVector3Array([
		Vector3(-half_width, 0.0, -half_depth),
		Vector3(half_width, 0.0, -half_depth),
		Vector3(half_width, 0.0, half_depth),
		Vector3(-half_width, 0.0, half_depth),
	])
	navigation_mesh.add_polygon(PackedInt32Array([0, 1, 2]))
	navigation_mesh.add_polygon(PackedInt32Array([0, 2, 3]))
	$NavigationRegion3D.navigation_mesh = navigation_mesh


func _content_position(
	location: Dictionary,
	item: Dictionary,
	y_position: float,
) -> Vector3:
	var dimensions: Dictionary = location["dimensions"]
	return Vector3(
		float(item["x"]) - float(dimensions["width"]) * 0.5 + 0.5,
		y_position,
		float(item["z"]) - float(dimensions["depth"]) * 0.5 + 0.5,
	)


func _clear_generated_children(parent: Node) -> void:
	for child in parent.get_children():
		parent.remove_child(child)
		child.free()


func _add_box(
	parent: Node3D,
	node_name: String,
	size: Vector3,
	box_position: Vector3,
	color: Color,
	use_collision: bool,
) -> CSGBox3D:
	var box := CSGBox3D.new()
	box.name = node_name
	box.size = size
	box.position = box_position
	box.material = _material(color)
	box.use_collision = use_collision
	parent.add_child(box)
	return box


func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.9
	return material
