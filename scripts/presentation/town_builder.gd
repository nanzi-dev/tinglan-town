class_name TownBuilder
extends Node3D

const DISTRICT_IDS := [
	"west_life",
	"central_market",
	"east_craft",
]
const BRIDGE_IDS := [
	"tingyu_bridge",
	"south_market_bridge",
]
const RIVER_ROTATION_DEGREES := 18.0
const NAVIGATION_RIVER_HALF_WIDTH := 3.75
const BRIDGE_HALF_DEPTH := 1.3
const ENTRANCE_LAYOUT := {
	"player_home": Vector3(-17.0, 0.0, -10.0),
	"shen_home": Vector3(-10.0, 0.0, -11.0),
	"gu_home": Vector3(-18.0, 0.0, 7.0),
	"qiao_home": Vector3(-10.0, 0.0, 10.0),
	"tea_house": Vector3(-8.0, 0.0, -2.5),
	"general_store": Vector3(8.0, 0.0, -2.5),
	"clinic": Vector3(10.0, 0.0, 9.0),
	"workshop": Vector3(18.0, 0.0, 8.0),
	"bookshop": Vector3(10.0, 0.0, -10.0),
	"community_center": Vector3(18.0, 0.0, -7.0),
}

const WHITE_WALL := Color("e8e7df")
const TILE_BLUE := Color("405f67")
const WILLOW_GREEN := Color("79a95b")
const DARK_GREEN := Color("456b43")
const WOOD := Color("8b5f3c")
const ROAD := Color("aaa68f")
const WATER := Color("4f9aaa")
const STONE := Color("777d76")
const SEAL_RED := Color("a94639")

@onready var _districts: Node3D = $Districts
@onready var _river: Node3D = $River
@onready var _bridges: Node3D = $Bridges
@onready var _entrances: Node3D = $Entrances
@onready var _scenery: Node3D = $Scenery
@onready var _navigation_region: NavigationRegion3D = $NavigationRegion3D

var _entrance_nodes: Dictionary = {}
var _navigation_vertices := PackedVector3Array()
var _navigation_vertex_indices: Dictionary = {}
var _navigation_polygons: Array[PackedInt32Array] = []


func _ready() -> void:
	_build_navigation()
	_build_town()


func get_district_ids() -> Array[String]:
	return DISTRICT_IDS.duplicate()


func has_continuous_river() -> bool:
	var river_channel := _river.get_node_or_null("ContinuousRiver")
	return (
		river_channel != null
		and river_channel.is_in_group("river")
		and river_channel.get_meta("continuous", false)
	)


func get_bridge_ids() -> Array[String]:
	return BRIDGE_IDS.duplicate()


func get_entrance_ids() -> Array[String]:
	var result: Array[String] = []
	for entrance_id in ENTRANCE_LAYOUT:
		result.append(entrance_id)
	result.sort()
	return result


func get_entrance(entrance_id: String) -> Node3D:
	return _entrance_nodes.get(entrance_id) as Node3D


func get_navigation_region() -> NavigationRegion3D:
	return _navigation_region


func is_navigation_ready() -> bool:
	return (
		_navigation_region.navigation_mesh != null
		and _navigation_region.navigation_mesh.get_polygon_count() > 0
	)


func is_point_navigable(point: Vector3) -> bool:
	if not is_inside_tree():
		return false
	var closest := NavigationServer3D.map_get_closest_point(
		get_world_3d().navigation_map,
		point,
	)
	return Vector2(closest.x, closest.z).distance_to(
		Vector2(point.x, point.z),
	) <= 0.05


func _build_navigation() -> void:
	_navigation_vertices.clear()
	_navigation_vertex_indices.clear()
	_navigation_polygons.clear()

	for segment in [
		{"z_range": Vector2(-18.0, -7.0 - BRIDGE_HALF_DEPTH), "bridge": false},
		{
			"z_range": Vector2(
				-7.0 - BRIDGE_HALF_DEPTH,
				-7.0 + BRIDGE_HALF_DEPTH,
			),
			"bridge": true,
		},
		{
			"z_range": Vector2(
				-7.0 + BRIDGE_HALF_DEPTH,
				7.0 - BRIDGE_HALF_DEPTH,
			),
			"bridge": false,
		},
		{
			"z_range": Vector2(
				7.0 - BRIDGE_HALF_DEPTH,
				7.0 + BRIDGE_HALF_DEPTH,
			),
			"bridge": true,
		},
		{"z_range": Vector2(7.0 + BRIDGE_HALF_DEPTH, 18.0), "bridge": false},
	]:
		_add_navigation_segment(segment.z_range, segment.bridge)

	var navigation_mesh := NavigationMesh.new()
	navigation_mesh.agent_height = 1.8
	navigation_mesh.agent_radius = 0.45
	navigation_mesh.vertices = _navigation_vertices
	for polygon in _navigation_polygons:
		navigation_mesh.add_polygon(polygon)
	_navigation_region.navigation_mesh = navigation_mesh
	NavigationServer3D.map_force_update(get_world_3d().navigation_map)


func _add_navigation_segment(z_range: Vector2, bridge: bool) -> void:
	var north_center := _river_center_x(z_range.x)
	var south_center := _river_center_x(z_range.y)
	var north_west_bank := north_center - NAVIGATION_RIVER_HALF_WIDTH
	var north_east_bank := north_center + NAVIGATION_RIVER_HALF_WIDTH
	var south_west_bank := south_center - NAVIGATION_RIVER_HALF_WIDTH
	var south_east_bank := south_center + NAVIGATION_RIVER_HALF_WIDTH
	_add_navigation_quad(
		Vector2(-24.0, z_range.x),
		Vector2(north_west_bank, z_range.x),
		Vector2(south_west_bank, z_range.y),
		Vector2(-24.0, z_range.y),
	)
	if bridge:
		_add_navigation_quad(
			Vector2(north_west_bank, z_range.x),
			Vector2(north_east_bank, z_range.x),
			Vector2(south_east_bank, z_range.y),
			Vector2(south_west_bank, z_range.y),
		)
	_add_navigation_quad(
		Vector2(north_east_bank, z_range.x),
		Vector2(24.0, z_range.x),
		Vector2(24.0, z_range.y),
		Vector2(south_east_bank, z_range.y),
	)


func _add_navigation_quad(
	north_west: Vector2,
	north_east: Vector2,
	south_east: Vector2,
	south_west: Vector2,
) -> void:
	var north_west_index := _navigation_vertex(north_west.x, north_west.y)
	var north_east_index := _navigation_vertex(north_east.x, north_east.y)
	var south_east_index := _navigation_vertex(south_east.x, south_east.y)
	var south_west_index := _navigation_vertex(south_west.x, south_west.y)
	_navigation_polygons.append(PackedInt32Array([
		north_west_index,
		north_east_index,
		south_east_index,
	]))
	_navigation_polygons.append(PackedInt32Array([
		north_west_index,
		south_east_index,
		south_west_index,
	]))


func _river_center_x(z_position: float) -> float:
	return tan(deg_to_rad(RIVER_ROTATION_DEGREES)) * z_position


func _navigation_vertex(x: float, z: float) -> int:
	var key := "%0.3f:%0.3f" % [x, z]
	if _navigation_vertex_indices.has(key):
		return _navigation_vertex_indices[key]
	var index := _navigation_vertices.size()
	_navigation_vertices.append(Vector3(x, 0.0, z))
	_navigation_vertex_indices[key] = index
	return index


func _build_town() -> void:
	_build_ground_and_roads()
	_build_districts()
	_build_river()
	_build_bridges()
	_build_scenery()


func _build_ground_and_roads() -> void:
	_add_box(
		_scenery,
		"Ground",
		Vector3(52.0, 0.35, 42.0),
		Vector3(0.0, -0.35, 0.0),
		WILLOW_GREEN,
	)
	for road in [
		{
			"name": "WestLoop",
			"size": Vector3(12.0, 0.08, 31.0),
			"position": Vector3(-13.0, -0.1, 0.0),
		},
		{
			"name": "EastLoop",
			"size": Vector3(12.0, 0.08, 31.0),
			"position": Vector3(13.0, -0.1, 0.0),
		},
		{
			"name": "NorthConnector",
			"size": Vector3(34.0, 0.08, 3.0),
			"position": Vector3(0.0, -0.08, -13.5),
		},
		{
			"name": "SouthConnector",
			"size": Vector3(34.0, 0.08, 3.0),
			"position": Vector3(0.0, -0.08, 13.5),
		},
	]:
		_add_box(
			_scenery,
			road.name,
			road.size,
			road.position,
			ROAD,
		)


func _build_districts() -> void:
	var district_nodes := {}
	for district_id in DISTRICT_IDS:
		var district := Node3D.new()
		district.name = district_id.to_pascal_case()
		district.set_meta("district_id", district_id)
		district.add_to_group("town_district")
		_districts.add_child(district)
		district_nodes[district_id] = district

	for entrance_id in ENTRANCE_LAYOUT:
		var district_id := _district_for_entrance(entrance_id)
		var building_position: Vector3 = ENTRANCE_LAYOUT[entrance_id]
		_build_building(
			district_nodes[district_id],
			entrance_id,
			building_position,
		)
		_build_entrance(entrance_id, building_position)

	var market := district_nodes["central_market"] as Node3D
	_add_box(
		market,
		"MarketCanopy",
		Vector3(5.0, 0.25, 3.0),
		Vector3(0.0, 2.0, 1.5),
		SEAL_RED,
	)
	_add_box(
		market,
		"NoticeBoard",
		Vector3(0.3, 2.0, 2.5),
		Vector3(-4.3, 1.0, 2.0),
		WOOD,
	)


func _district_for_entrance(entrance_id: String) -> String:
	if entrance_id in ["player_home", "shen_home", "gu_home", "qiao_home"]:
		return "west_life"
	if entrance_id in ["tea_house", "general_store"]:
		return "central_market"
	return "east_craft"


func _build_building(
	parent: Node3D,
	location_id: String,
	building_position: Vector3,
) -> void:
	var building := Node3D.new()
	building.name = location_id.to_pascal_case()
	building.position = building_position
	building.set_meta("location_id", location_id)
	parent.add_child(building)
	_add_box(
		building,
		"Walls",
		Vector3(4.5, 2.8, 3.8),
		Vector3(0.0, 1.4, 0.0),
		WHITE_WALL,
	)
	_add_box(
		building,
		"Roof",
		Vector3(5.1, 0.55, 4.4),
		Vector3(0.0, 3.0, 0.0),
		TILE_BLUE,
		0.0,
		Vector3(0.0, 0.0, 5.0),
	)
	_add_box(
		building,
		"Door",
		Vector3(1.0, 1.8, 0.18),
		Vector3(0.0, 0.9, 2.0),
		WOOD,
	)


func _build_entrance(entrance_id: String, building_position: Vector3) -> void:
	var entrance := Marker3D.new()
	entrance.name = "Entrance_%s" % entrance_id
	entrance.position = building_position + Vector3(0.0, 0.1, 2.7)
	entrance.set_meta("entrance_id", entrance_id)
	entrance.set_meta("location_id", entrance_id)
	entrance.add_to_group("interior_entrance")
	_entrances.add_child(entrance)
	_entrance_nodes[entrance_id] = entrance
	_add_box(
		entrance,
		"Threshold",
		Vector3(1.2, 0.12, 0.7),
		Vector3.ZERO,
		SEAL_RED,
	)


func _build_river() -> void:
	var channel := _add_box(
		_river,
		"ContinuousRiver",
		Vector3(5.5, 0.28, 55.0),
		Vector3(0.0, -0.12, 0.0),
		WATER,
		RIVER_ROTATION_DEGREES,
	)
	channel.set_meta("continuous", true)
	channel.set_meta("flow", "northwest_to_southeast")
	channel.add_to_group("river")
	for side in [-1.0, 1.0]:
		_add_box(
			_river,
			"Riverbank%s" % ("West" if side < 0.0 else "East"),
			Vector3(1.0, 0.45, 55.0),
			Vector3(side * 3.1, 0.0, 0.0),
			STONE,
			RIVER_ROTATION_DEGREES,
		)


func _build_bridges() -> void:
	var layouts := {
		"tingyu_bridge": Vector3(_river_center_x(-7.0), 0.2, -7.0),
		"south_market_bridge": Vector3(_river_center_x(7.0), 0.2, 7.0),
	}
	for bridge_id in BRIDGE_IDS:
		var bridge := Node3D.new()
		bridge.name = bridge_id.to_pascal_case()
		bridge.position = layouts[bridge_id]
		bridge.rotation_degrees.y = RIVER_ROTATION_DEGREES
		bridge.set_meta("bridge_id", bridge_id)
		bridge.add_to_group("town_bridge")
		_bridges.add_child(bridge)
		_add_box(
			bridge,
			"Deck",
			Vector3(9.0, 0.35, BRIDGE_HALF_DEPTH * 2.0),
			Vector3.ZERO,
			WOOD,
		)
		for rail_z in [-1.15, 1.15]:
			_add_box(
				bridge,
				"Rail%s" % rail_z,
				Vector3(9.0, 0.45, 0.16),
				Vector3(0.0, 0.45, rail_z),
				DARK_GREEN,
			)


func _build_scenery() -> void:
	for garden_position in [
		Vector3(-21.0, 0.0, -2.0),
		Vector3(-20.0, 0.0, 2.0),
		Vector3(-15.0, 0.0, 14.0),
	]:
		_add_box(
			_scenery,
			"VegetablePlot",
			Vector3(3.0, 0.25, 2.0),
			garden_position,
			DARK_GREEN,
		)
	for willow_position in [
		Vector3(-5.0, 0.0, -14.0),
		Vector3(5.0, 0.0, -12.0),
		Vector3(-5.0, 0.0, 12.0),
		Vector3(5.0, 0.0, 14.0),
	]:
		_add_willow(willow_position)
	_add_box(
		_scenery,
		"FestivalBay",
		Vector3(12.0, 0.08, 5.0),
		Vector3(7.0, -0.08, 17.0),
		ROAD,
	)
	_add_box(
		_scenery,
		"Dock",
		Vector3(7.0, 0.3, 2.5),
		Vector3(6.5, 0.05, 12.0),
		WOOD,
		RIVER_ROTATION_DEGREES,
	)


func _add_willow(willow_position: Vector3) -> void:
	var willow := Node3D.new()
	willow.name = "Willow"
	willow.position = willow_position
	_scenery.add_child(willow)
	_add_box(
		willow,
		"Trunk",
		Vector3(0.45, 2.8, 0.45),
		Vector3(0.0, 1.4, 0.0),
		WOOD,
	)
	_add_box(
		willow,
		"Canopy",
		Vector3(2.2, 1.8, 2.2),
		Vector3(0.0, 3.0, 0.0),
		WILLOW_GREEN,
	)


func _add_box(
	parent: Node3D,
	node_name: String,
	size: Vector3,
	box_position: Vector3,
	color: Color,
	rotation_y_degrees: float = 0.0,
	extra_rotation_degrees: Vector3 = Vector3.ZERO,
) -> CSGBox3D:
	var box := CSGBox3D.new()
	box.name = node_name
	box.size = size
	box.position = box_position
	box.rotation_degrees = extra_rotation_degrees + Vector3(
		0.0,
		rotation_y_degrees,
		0.0,
	)
	box.material = _material(color)
	parent.add_child(box)
	return box


func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.9
	return material
