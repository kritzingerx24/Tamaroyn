extends Control
func _ready(): visible = false
func show_winner(team): visible = true; var t_name="RED" if team==0 else "BLUE"; var col=Color(1,0,0) if team==0 else Color(0,0,1); $Label.text=t_name+" WINS!"; $Label.modulate=col; $WinSound.play()
