extends Node3D
class_name Card
@onready var cardFront = $CardFront
var value : int = 0
var color : String = ""
var type : String = ""
var letterValues : Dictionary = {"King" : 10, "Queen": 10, "Jack" : 10, "A" : 11}

func set_card(type_card : String, color_card : String, value_card : String):
	var file_path = "res://Textures/cards/{color}/{type}_{value}_{color}.png".format({
		"color": color_card,
		"type": type_card,
		"value": value_card
	})
	var new_texture = load(file_path) as CompressedTexture2D
	var material = cardFront.get_active_material(0) as StandardMaterial3D
	
	if material:
		material.albedo_texture = new_texture
	color = color_card
	type = type_card
	if not value_card.is_valid_int():
		value = letterValues[value_card]
		
	else:
		value = value_card.to_int()

func set_card_file(file_name: String):
	var file_path = "res://Textures/cards/black/" + file_name + ".png"
	var new_texture = load(file_path) as CompressedTexture2D

	# Create an independent material for this card
	var material = cardFront.get_active_material(0).duplicate() as StandardMaterial3D

	if material:
		cardFront.set_surface_override_material(0, material)
		material.albedo_texture = new_texture

	color = "black"
	type = file_name.get_slice("_", 0)

	var string_value = file_name.get_slice("_", 1)

	if not string_value.is_valid_int():
		value = letterValues[string_value]
	else:
		value = string_value.to_int()

	print(color, type, value)

	
	
