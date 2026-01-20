extends CanvasLayer

@onready var status_label: Label = $Margin/VBox/Status
@onready var help_label: Label = $Margin/VBox/Help
@onready var toast_label: Label = $Margin/VBox/Toast

var _toast_seq: int = 0

func set_status(text: String) -> void:
	status_label.text = text

func set_help(text: String) -> void:
	help_label.text = text

func flash_message(text: String, duration: float = 1.0) -> void:
	if toast_label == null:
		return
	_toast_seq += 1
	var my_seq: int = _toast_seq
	toast_label.text = text
	toast_label.visible = true
	var t: SceneTreeTimer = get_tree().create_timer(duration)
	t.timeout.connect(func() -> void:
		if not is_instance_valid(toast_label):
			return
		if my_seq != _toast_seq:
			return
		toast_label.visible = false
	)
