class_name ShopItemData
extends Resource

## ShopItemData
## Configurable shop item resource for the Merchant Shop Menu.
## Each item has its own display name, price, stats subtitle, GunController index,
## and an assignable 3D model (PackedScene) that dynamically appears inside the Shop Bucket.

@export var item_name: String = "Water Splash Gun"
@export var item_stats: String = "Heavy spread blast | High soak capacity"
@export var price: int = 50
@export var model_scene: PackedScene = null
@export var gun_index: int = 1

@export_group("Bucket 3D Placement (Fallback if not pre-placed in Shop_Bucket)")
@export var bucket_position: Vector3 = Vector3(0.061352, 0.507422, -0.068138)
@export var bucket_rotation_degrees: Vector3 = Vector3(-84.8, 94.0, -4.0)
@export var bucket_scale: Vector3 = Vector3(0.455, 0.455, 0.455)
