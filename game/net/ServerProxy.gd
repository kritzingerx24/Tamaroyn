extends Node

signal snapshot_received(snapshot: Dictionary)

# Call this every frame (or at a fixed rate) to send player input to the server.
func send_input(cmd: Dictionary) -> void:
	if multiplayer.multiplayer_peer == null:
		return
	# Server is always peer_id 1 in Godot's high-level multiplayer.
	rpc_id(1, "c_input", cmd)

# Receives snapshots from the authoritative server.
@rpc("authority", "call_remote", "unreliable")
func s_snapshot(snap: Dictionary) -> void:
	snapshot_received.emit(snap)
