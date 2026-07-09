@tool
extends RayCast3D
class_name AudioListenerRayCast

## The angle (in degrees) from the forward direction within which sounds are heard normally.
## Sounds outside this angle (behind the listener) will start to muffle.
@export_range(0.0, 180.0) var receive_angle_degrees: float = 90.0

## The width of the transition zone (in degrees) over which the muffling increases to maximum.
@export_range(1.0, 180.0) var transition_width_degrees: float = 30.0


func _enter_tree() -> void:
	# Create a visual helper arrow for the editor and debug builds
	if Engine.is_editor_hint() or OS.is_debug_build():
		_create_visual_arrow()


func _ready() -> void:
	# Set default target position to point forward along negative Z
	if target_position == Vector3(0, -1, 0): # Default Godot RayCast3D value
		target_position = Vector3(0, 0, -2.0)
		
	# Create visual helper if it doesn't exist yet
	if Engine.is_editor_hint() or OS.is_debug_build():
		_create_visual_arrow()


func _create_visual_arrow() -> void:
	var existing = get_node_or_null("DebugArrow")
	if existing:
		return
		
	var arrow = Node3D.new()
	arrow.name = "DebugArrow"
	add_child(arrow)
	
	# Cylinder shaft
	var shaft = MeshInstance3D.new()
	shaft.name = "Shaft"
	var shaft_mesh = CylinderMesh.new()
	shaft_mesh.top_radius = 0.03
	shaft_mesh.bottom_radius = 0.03
	shaft_mesh.height = 1.0
	shaft.mesh = shaft_mesh
	
	# Position/rotate cylinder to lie along Z axis (CylinderMesh is Y-aligned by default)
	shaft.rotation.x = PI / 2.0
	shaft.position.z = -0.5
	arrow.add_child(shaft)
	
	# Cone tip (Procedurally created using a CylinderMesh with top_radius = 0.0)
	var tip = MeshInstance3D.new()
	tip.name = "Tip"
	var tip_mesh = CylinderMesh.new()
	tip_mesh.top_radius = 0.0
	tip_mesh.bottom_radius = 0.08
	tip_mesh.height = 0.3
	tip.mesh = tip_mesh
	
	# Position/rotate cone to point along negative Z axis
	tip.rotation.x = -PI / 2.0
	tip.position.z = -1.15
	arrow.add_child(tip)
	
	# Apply a nice color material to the meshes
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.1, 0.8, 0.2) # Neon Green
	mat.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	
	shaft.material_override = mat
	tip.material_override = mat
