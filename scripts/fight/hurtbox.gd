extends Area2D
class_name FightHurtbox

var owner_fighter: CharacterBody2D


func setup(owner: CharacterBody2D) -> void:
	owner_fighter = owner
	collision_layer = 4
	collision_mask = 0
