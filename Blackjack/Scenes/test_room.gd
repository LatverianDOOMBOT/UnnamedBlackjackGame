extends Node3D




# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	$BlackjackManager.Table = get_node("Table")
	$BlackjackManager.new_shoe()
	$BlackjackManager.start_new_game()
	$BlackjackManager.new_round()
	

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	$BlackjackManager.continue_round()
