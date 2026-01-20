extends Node

# A simple manager to play 2D UI sounds or non-spatial one-offs
# For 3D sounds, we usually attach players to the objects themselves.

func play_sound(stream: AudioStream, pitch: float = 1.0):
	if !stream: return
	var p = AudioStreamPlayer.new()
	p.stream = stream
	p.pitch_scale = pitch
	p.finished.connect(p.queue_free)
	add_child(p)
	p.play()
