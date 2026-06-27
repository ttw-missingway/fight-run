extends Area2D
class_name FightHurtbox

var owner_fighter: CharacterBody2D


func setup(owner_body: CharacterBody2D) -> void:
	owner_fighter = owner_body
	collision_layer = 4
	collision_mask = 0
