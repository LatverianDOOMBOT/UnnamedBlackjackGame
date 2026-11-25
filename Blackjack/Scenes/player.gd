extends Node3D
@export var mouse_sensitivity: float = 0.002

@onready var head: Node3D = $Head # Ensure this matches your Node3D layout
var TurnTaken : bool = false
func _ready() -> void:
	# Captures the mouse cursor and hides it inside the game window
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _unhandled_input(event: InputEvent) -> void:
	# Check if the player is moving the mouse
	if event is InputEventMouseMotion:
		# 1. Rotate the entire character body horizontally (Y-axis)
		rotate_y(-event.relative.x * mouse_sensitivity)
		
		# 2. Rotate the head vertically (X-axis)
		head.rotate_x(-event.relative.y * mouse_sensitivity)
		
		# 3. Clamp the vertical rotation so the player can't flip upside down
		# -89 to 89 degrees converted to radians (approx -1.55 to 1.55)
		head.rotation.x = clamp(head.rotation.x, deg_to_rad(-89), deg_to_rad(89))

func _process(_delta: float) -> void:
	# Optional: Allow pressing UI_CANCEL (usually 'Escape') to free the mouse
	if Input.is_action_just_pressed("ui_cancel"):
		if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		else:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	
func hit_or_stand():
	if Input.is_action_just_pressed("Hit"):
		return true

	elif Input.is_action_just_pressed("Stand"):
		TurnTaken = true
		return false

	return null
	
func death():
	pass
