extends Control

@onready var input_line = $VBox/InputLine
@onready var log_container = $VBox/ChatLog

var is_typing = false

func _ready():
	# Connect to network
	NetworkManager.chat_message_received.connect(_on_chat_received)
	NetworkManager.kill_feed_received.connect(_on_kill_feed)
	input_line.visible = false

func _input(event):
	if event.is_action_pressed("toggle_chat"):
		if !is_typing:
			start_typing()
		else:
			send_message()

func start_typing():
	is_typing = true
	input_line.visible = true
	input_line.grab_focus()
	# Tell player controller to stop inputs (handled via group check in controller)

func send_message():
	var msg = input_line.text.strip_edges()
	if msg != "":
		NetworkManager.send_chat.rpc(msg)
	
	input_line.text = ""
	input_line.release_focus()
	input_line.visible = false
	is_typing = false

func _on_chat_received(sender_id, msg):
	var line = Label.new()
	line.text = "Player " + str(sender_id) + ": " + msg
	log_container.add_child(line)
	_trim_log()

func _on_kill_feed(killer, victim, team_killer, team_victim):
	var line = Label.new()
	var k_color = "[color=red]" if team_killer == 0 else "[color=blue]"
	var v_color = "[color=red]" if team_victim == 0 else "[color=blue]"
	
	line.text = "Player " + str(killer) + " destroyed " + "Player " + str(victim)
	line.modulate = Color(1, 1, 0) # Yellow highlight for kills
	log_container.add_child(line)
	_trim_log()

func _trim_log():
	while log_container.get_child_count() > 10:
		log_container.get_child(0).queue_free()
