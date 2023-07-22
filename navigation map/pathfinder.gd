extends Node
signal path_found ()

var _thread: Thread;
var _mutex: Mutex;
var _semaphore: Semaphore;
var _exit_thread = false;
var pathfinding_request_queue = [];
var current_request;

# setup the thread
func _ready():
	_mutex = Mutex.new();
	_semaphore = Semaphore.new();
	_exit_thread = false;
	_thread = Thread.new();
	_thread.start(_thread_function);

# after the pathfinding thread is finished running, start it up again if there are any requests 
func _process(delta):
	_mutex.lock();
	var request_queue_size = pathfinding_request_queue.size();
	_mutex.unlock();
	if request_queue_size == 0: return
	_semaphore.post();

# cleanup the thread
func _exit_tree():
	_mutex.lock();
	_exit_thread = true;
	_mutex.unlock();
	_semaphore.post();
	_thread.wait_to_finish();

# add a pathfinding request
func add_request (start_position: Vector2, end_position: Vector2, jump: int, map: NavigationMap):
	var request = PathfindingRequest.new(start_position, end_position, jump, map);
	_mutex.lock();
	pathfinding_request_queue.push_back(request);
	_mutex.unlock();
	return request;

func _create_node(map_position: Vector2, parent=null, jump=0, cost: int=0, g: float=0, can_strafe=true):
	return {
		"position": map_position,
		"cost": cost,
		"g": g,
		"jump": jump,
		"parent": parent,
		"can_strafe": can_strafe,
	}

func _sort_by_lowset_heuristic (a, b) -> bool:
	return b.g < a.g;

func _get_cell_type (position: Vector2, map: NavigationMap):
	return map.get_cell_at(position);

func _create_adjacent_node (direction: Vector2, jump_value: int, current_node: Dictionary, g: float, can_strafe: bool):
	return _create_node(current_node.position + direction, current_node, jump_value, current_node.cost + 1, g, can_strafe)

# scans a list for an equivalent node
func _is_contains_node(list, node):
	for index in range(list.size()):
		var current_node = list[index];
		if current_node.jump == node.jump and current_node.position == node.position and current_node.can_strafe == node.can_strafe:
			return index;
	return -1;

func _calculate_heuristic(start_position: Vector2, end_position: Vector2, cost):
	return abs(start_position.x - end_position.x) + abs(start_position.y - end_position.y) + cost;

func _is_in_bounds(cell_position: Vector2, map: NavigationMap):
	if cell_position.x < 0 or cell_position.x >= map._area_size.x:
		return false;
	if cell_position.y < 0 or cell_position.y >= map._area_size.y:
		return false;
	return true;

func _is_landing_or_jumping (current_node, node_path, index, map: NavigationMap):
	if _get_cell_type(current_node.position, map) != "G": return false;
	var previous_node = node_path[index - 1];
	if previous_node.jump != 0: return true;
	var next_node = node_path[index + 1];
	if next_node.jump != 0: return true;
	return false

func _is_avoiding_obstacle (current_node, node_path, opt_path, index, map: NavigationMap):
	var previous_optimized_position = opt_path.back();
	var next_node = node_path[index + 1];
	if next_node.position == Vector2(5, 10):
		pass
	var a = map.map_to_world(previous_optimized_position) + map._half_cell_size;
	var b = map.map_to_world(next_node.position) + map._half_cell_size;
	var space_state = map.get_world_3d().direct_space_state;
	var query = PhysicsRayQueryParameters3D.create(a, b);
	var collision = space_state.intersect_ray(query);
	return collision.has("collider");

func _is_peak_of_jump (current_node, node_path, index):
	var previous_node = node_path[index - 1];
	var next_node = node_path[index + 1];
	return previous_node.position.y < current_node.position.y and next_node.position.y < current_node.position.y;

func _is_strafe_jump (current_node, node_path, opt_path, index, map: NavigationMap):
	if index + 2 > node_path.size() - 1: return false;
	if index - 2 < 0: return false;
	var previous_node = node_path[index - 1];
	var next_node = node_path[index + 1];
	var landing_node = node_path[index + 2];
	var case_a = previous_node.position.y < current_node.position.y and next_node.position.y == current_node.position.y and _get_cell_type(previous_node.position, map) != "G";
	var case_b = next_node.position.y == current_node.position.y and next_node.position.y > landing_node.position.y;
	return case_a and case_b;

func _is_node_needed (node, node_path, optimized_path, i, map: NavigationMap):
	if node.position == Vector2(6, 11):
		pass
	#if _is_avoiding_obstacle(node, node_path, optimized_path, i, map): return true;
	if _is_landing_or_jumping(node, node_path, i, map): return true;
	if _is_peak_of_jump(node, node_path, i): return true;
	if _is_strafe_jump(node, node_path, optimized_path, i, map): return true;
	return false;

func _get_optimized_path(end_node, map: NavigationMap):
	var current_node = end_node;
	var node_path = [current_node];
	while current_node.parent:
		current_node = current_node.parent
		node_path.push_back(current_node);
	node_path.reverse()
	current_node = node_path[0];
	var optimized_path = [current_node.position];
	
	for i in range(1, node_path.size() - 1):
		var node = node_path[i];
		var is_needed = _is_node_needed(node, node_path, optimized_path, i, map);
		if is_needed: optimized_path.push_back(node.position);
	optimized_path.push_back(node_path.back().position);
	
	optimized_path.reverse();
	return optimized_path;

func _get_path (_end_node) -> Array:
	var path = [];
	var current_node = _end_node;
	while current_node.parent:
		path.push_back(current_node.position);
		current_node = current_node.parent;
	return path;

func _map_path_to_world(path, map: NavigationMap):
	var world_path = []
	for step in path:
		var world_position = map.map_to_world(step) + map._half_cell_size;
		world_path.push_back(world_position);
	return world_path;

func find_path(request) -> Array:
	var start_position = request._start;
	var end_position = request._end;
	var max_jump = request._jump;
	var map = request._map;
	var start_jump_value = 0 if _get_cell_type(start_position, map) == "G" else -1;
	var open = [_create_node(start_position, null, start_jump_value)];
	var closed = [];
	while open.size():
		open.sort_custom(_sort_by_lowset_heuristic);
		var current_node = open.pop_back();
		if current_node.position == end_position:
			var optimized_path = _get_optimized_path(current_node, map);
			var unoptimized_path = _get_path(current_node);
			return _map_path_to_world(optimized_path, map);
		closed.push_back(current_node);
		var valid_neighbors = [];
		var is_on_ground = _get_cell_type(current_node.position, map) == "G";
		var is_wall_above = _get_cell_type(current_node.position + Vector2.DOWN, map) == "W";
		if !is_on_ground:
			var fall_jump_value = -1 if current_node.jump > 0 else current_node.jump - 1;
			var fall_node = _create_adjacent_node(Vector2.UP, fall_jump_value, current_node, 0, true);
			valid_neighbors.push_back(fall_node);
			if current_node.jump > 0 and current_node.jump < max_jump and not is_wall_above:
				var jump_node = _create_adjacent_node(Vector2.DOWN, current_node.jump + 1, current_node, 0, true);
				valid_neighbors.push_back(jump_node);
		elif !is_wall_above:
			var jump_node = _create_adjacent_node(Vector2.DOWN, 1, current_node, 0, true);
			valid_neighbors.push_back(jump_node);
		
		if current_node.can_strafe and current_node.jump < max_jump:
			for direction in [Vector2.LEFT, Vector2.RIGHT]:
				var adjacent_position = current_node.position + direction;
				if !_is_in_bounds(adjacent_position, map): continue;
				var adjacent_is_on_ground = _get_cell_type(adjacent_position, map) == "G";
				var jump_value = 0 if adjacent_is_on_ground else current_node.jump + 1;
				var cell_type = _get_cell_type(adjacent_position, map);
				if cell_type == "W": continue;
				var side_node = _create_adjacent_node(direction, jump_value, current_node, 0, adjacent_is_on_ground);
				valid_neighbors.push_back(side_node);
		
		for neighbor in valid_neighbors:
			neighbor.g = _calculate_heuristic(neighbor.position, end_position, neighbor.cost);
			var closed_list_index = _is_contains_node(closed, neighbor);
			var open_list_index = _is_contains_node(open, neighbor);
			if neighbor.g < current_node.g and closed_list_index != -1:
				closed[closed_list_index] = neighbor;
			elif neighbor.g < current_node.g and open_list_index != -1:
				open[open_list_index] = neighbor;
			elif closed_list_index == -1 and open_list_index == -1:
				open.push_back(neighbor);
	return [];

func _thread_function():
	while true:
		_semaphore.wait();
		
		_mutex.lock();
		var should_exit = _exit_thread;
		current_request = pathfinding_request_queue.pop_back();
		_mutex.unlock();
		
		if should_exit:
			break;
		
		_mutex.lock()
		var path = find_path(current_request);
		current_request.path = path;
		current_request.set_is_complete();
		_mutex.unlock();

class PathfindingRequest:
	var _start;
	var _end;
	var _map;
	var _jump;
	var _is_complete = false;
	var path;
	func _init(start: Vector2, end: Vector2, jump: int, map: NavigationMap):
		_start = start;
		_end = end;
		_map = map;
		_jump = jump;
	
	func set_is_complete():
		_is_complete = true;
