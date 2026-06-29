extends Area2D
class_name FightHurtbox

## A fighter's vulnerable volume: carries a back-reference to its owner so
## hitboxes and grabboxes can identify who they struck.


#region Public state

var owner_fighter: CharacterBody2D

#endregion


#region Public API

## Binds the owning fighter and sets the hurtbox collision layers.
func setup(owner_body: CharacterBody2D) -> void:
	owner_fighter = owner_body
	collision_layer = 4
	collision_mask = 0

#endregion
