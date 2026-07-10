## ItemManager — autoload singleton.
## Owns the player's inventory and coin count.
## Any ItemPickup in any scene connects its collected signal here.
## The shop system will read/write this later.
extends Node

signal inventory_changed(inventory: Dictionary)
signal coins_changed(total: int)

## Current inventory. Keys are item_type strings, values are int counts.
var inventory: Dictionary = {}

func _ready() -> void:
	pass

func reset() -> void:
	inventory.clear()
	inventory_changed.emit(inventory)
	coins_changed.emit(0)

## Called by ItemPickup when the player collects an item.
func add_item(item_type: String, value: int) -> void:
	if item_type == "coin":
		inventory["coin"] = inventory.get("coin", 0) + value
		coins_changed.emit(inventory["coin"])
	else:
		inventory[item_type] = inventory.get(item_type, 0) + value
	inventory_changed.emit(inventory)

## Returns current coin total.
func get_coins() -> int:
	return inventory.get("coin", 0)

## Returns count of any item type.
func get_item(item_type: String) -> int:
	return inventory.get(item_type, 0)

## Spend coins. Returns false if insufficient funds.
func spend_coins(amount: int) -> bool:
	if get_coins() < amount:
		return false
	inventory["coin"] = get_coins() - amount
	coins_changed.emit(inventory["coin"])
	inventory_changed.emit(inventory)
	return true
