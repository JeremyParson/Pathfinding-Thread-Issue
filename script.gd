extends Node

@onready var navigation_map: NavigationMap = $NavigationMap;

func _ready():
	$AnimationPlayer.play("new_animation")
	navigation_map.generate_map();
	test();

func test():
	while true:
		await get_tree().create_timer(3).timeout
		var start_position = Vector2(1, 1);
		var end_position = Vector2(6, 13);
		var max_jump = 5;
		Pathfinder.add_request(start_position, end_position, max_jump, navigation_map);
