extends "res://scripts/tank_base.gd"
enum State { IDLE, CHASE, ATTACK }
var state = State.IDLE
var target: Node3D = null
var update_timer = 0.0
func _ready():
	super._ready()
	target = get_tree().get_first_node_in_group("player")
func _physics_process(delta):
	if !is_instance_valid(target):
		target = get_tree().get_first_node_in_group("player")
		input_move = 0
		input_fire = false
		super._physics_process(delta)
		return
	update_timer += delta
	if update_timer > 0.2:
		update_timer = 0
		decide_logic()
	aim_at_target(delta)
	super._physics_process(delta)
func decide_logic():
	var dist = global_position.distance_to(target.global_position)
	if dist < 80.0: state = State.ATTACK
	elif dist < 300.0: state = State.CHASE
	else: state = State.IDLE
	match state:
		State.IDLE:
			input_move = 0
			input_fire = false
		State.CHASE:
			input_move = 1.0
			input_fire = false
			steer_towards(target.global_position)
		State.ATTACK:
			input_move = sin(Time.get_ticks_msec() / 1000.0) 
			input_fire = true
			steer_towards(target.global_position)
func steer_towards(pos):
	var local_target = to_local(pos)
	if local_target.x > 2.0: input_turn = -1.0
	elif local_target.x < -2.0: input_turn = 1.0
	else: input_turn = 0.0
func aim_at_target(delta):
	var aim_pos = target.global_position
	aim_pos.y = turret_node.global_position.y
	turret_node.look_at(aim_pos, Vector3.UP)
	turret_node.rotate_object_local(Vector3.UP, PI)
