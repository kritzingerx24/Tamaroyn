extends Node
var peer = ENetMultiplayerPeer.new(); const PORT=7777; var players={}; var local_info={"team":0,"class":0, "map":""}
signal player_connected(id,info); signal game_over(w); signal chat_message_received(s,m); signal kill_feed_received(k,v,tk,tv)
func host_game(info):
	local_info=info; peer.create_server(PORT); multiplayer.multiplayer_peer=peer; players[1]=info
	multiplayer.peer_connected.connect(func(id): register_player.rpc(local_info))
	get_tree().change_scene_to_file("res://scenes/world_wrapper.tscn")
	await get_tree().process_frame; load_map.rpc(info["map"])
func join_game(addr,info): local_info=info; peer.create_client(addr,PORT); multiplayer.multiplayer_peer=peer
@rpc("call_local", "reliable", "any_peer") func load_map(path): var wrapper = get_tree().root.get_node_or_null("WorldWrapper"); if wrapper: wrapper.load_map_scene(path)
@rpc("any_peer","call_local","reliable") func register_player(info):
	var id=multiplayer.get_remote_sender_id(); players[id]=info; emit_signal("player_connected",id,info)
@rpc("call_local","reliable","any_peer") func trigger_game_over(w): emit_signal("game_over",w)
@rpc("any_peer","call_local","reliable") func send_chat(msg): var id=multiplayer.get_remote_sender_id(); chat_message_received.emit(id,msg)
@rpc("call_local","reliable") func broadcast_kill(k,v,tk,tv): kill_feed_received.emit(k,v,tk,tv)
