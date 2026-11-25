extends Node3D

class_name Demon
@export var risk_chance : float
@export var demon_model : MeshInstance3D
@export var animation_player : AnimationPlayer



func hit_or_stand(value_of_cards : int):
	var p = (value_of_cards/21.0) * 100.0
	if p > risk_chance:
		var chance_of_risk_taking = randf_range(0.0, 100.0)
		if chance_of_risk_taking > risk_chance:
			print("risk taken: ", chance_of_risk_taking, " against ", risk_chance, " ", self.name)
			return true
			
		else:
			print("risk not_taken: ", chance_of_risk_taking, " against ", risk_chance, " ", self.name)
			return false
		
	else:
		return true
		
func death():
	pass
