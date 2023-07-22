extends GridMap;
class_name NavigationMap;

signal area_size_updated (new_value);
signal start_position_updated (new_value);

@export var _area_size: Vector2 : set = set_area_size;
@export var _start_position: Vector3: set = set_start_position;
@export var _target_grid_map_path: NodePath;
@export_flags_3d_physics var collision_flags;

@onready var _half_cell_size: Vector3 = cell_size / 2;

var _map = [];

func set_area_size (area_size: Vector2):
	_area_size = area_size;
	emit_signal("area_size_updated", area_size);

func set_start_position (start_position: Vector3):
	_start_position = start_position;
	emit_signal("start_position_updated", start_position);

func get_cell_at(pos: Vector2):
	return _map[pos.y][pos.x];

func world_to_map(pos: Vector3):
	return (pos / cell_size).floor()

func map_to_world(pos: Vector2):
	var pos_3 = Vector3(pos.x, pos.y, _start_position.z);
	return pos_3 * cell_size;

func generate_map():
	_map = [];
	for y in range(_area_size.y):
		_map.push_back([]);
		for x in range(_area_size.x):
			var tile_type = "";
			var current_cell_position = Vector3(x, y, 0) + _start_position;
			var bottom_cell_position = Vector3(x, y - 1, 0) + _start_position;
			var right_cell_position = Vector3(x + 1, y, 0) + _start_position;
			var left_cell_position = Vector3(x - 1, y, 0) + _start_position;
			var bottom_left_cell_position = Vector3(x - 1, y - 1, 0) + _start_position;
			var bottom_right_cell_position = Vector3(x + 1, y - 1, 0) + _start_position;
			var current_cell_item = get_cell_item(current_cell_position);
			var bottom_cell_item = get_cell_item(bottom_cell_position);
			var right_cell_item = get_cell_item(right_cell_position);
			var left_cell_item = get_cell_item(left_cell_position);
			var bottom_left_cell_item = get_cell_item(bottom_left_cell_position);
			var bottom_right_cell_item = get_cell_item(bottom_right_cell_position);
			
			var is_wall_on_left = left_cell_item != -1;
			var is_wall_on_right = right_cell_item != -1;
			var is_bottom_right_wall = bottom_right_cell_item != -1;
			var is_bottom_left_wall = bottom_left_cell_item != -1;
			var is_wall = current_cell_item != -1;
			var is_floor_below = bottom_cell_item != -1;
			var is_at_bottom = y - 1 == -1;
			
			if is_wall:
				tile_type = "W";
			elif !is_at_bottom and is_floor_below:
				tile_type = "G";
			elif !is_at_bottom and ((is_bottom_left_wall and !is_wall_on_left) or (is_bottom_right_wall and !is_wall_on_right)):
				tile_type = "L";
			else:
				tile_type = "A";
			_map[y].push_back(tile_type);
	for y in range(_area_size.y - 1, -1, -1):
		var line = "";
		for x in range(_area_size.x):
			line += _map[y][x];
		print(line);
