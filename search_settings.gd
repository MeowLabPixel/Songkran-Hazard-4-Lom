@tool
extends EditorScript

func _run():
	print("--- JOLT SETTINGS ---")
	for prop in ProjectSettings.get_property_list():
		if "jolt" in prop.name.to_lower() or "scale" in prop.name.to_lower():
			print(prop.name, " = ", ProjectSettings.get_setting(prop.name))
