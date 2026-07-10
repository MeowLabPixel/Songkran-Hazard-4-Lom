# In your main plugin.gd file (the one that adds the importer)
@tool
extends EditorPlugin

var importer
var watcher

const SETTING_SCAN_MODE = "psd_importer/scan_mode"
const SETTING_SCAN_MATERIALS = "psd_importer/scan_materials"
const SETTING_DEBUG_PRINTS = "psd_importer/debug_prints"


func _enter_tree():
	# Register project settings
	_setup_project_settings()
	importer = preload("res://addons/psdImports/importer.gd").new()
	add_import_plugin(importer)
	

	watcher = preload("res://addons/psdImports/watcher.gd").new()
	add_child(watcher)
	#watcher._enter_tree()
	
	print("PSD Importer registered")

func _exit_tree():
	remove_import_plugin(importer)
	importer = null
	
	if watcher:
		remove_child(watcher)
		watcher.queue_free()
		watcher = null
		# Clean up project settings
		_remove_project_settings()
	#if watcher:
		#watcher._exit_tree()  # Manually call its cleanup
		#watcher.free()
		#watcher = null


func _setup_project_settings():
	if not ProjectSettings.has_setting(SETTING_SCAN_MODE):
		ProjectSettings.set_setting(SETTING_SCAN_MODE, 0)
	
	ProjectSettings.set_initial_value(SETTING_SCAN_MODE, 0)
	ProjectSettings.add_property_info({
		"name": SETTING_SCAN_MODE,
		"type": TYPE_INT,
		"hint": PROPERTY_HINT_ENUM,
		"hint_string": "Open Scene Only (Fast),All Scenes (Slow),Disabled"
	})
	

	if not ProjectSettings.has_setting(SETTING_SCAN_MATERIALS):
		ProjectSettings.set_setting(SETTING_SCAN_MATERIALS, false)
	
	ProjectSettings.set_initial_value(SETTING_SCAN_MATERIALS, false)
	ProjectSettings.add_property_info({
		"name": SETTING_SCAN_MATERIALS,
		"type": TYPE_BOOL,
		"hint": PROPERTY_HINT_NONE
	})
	

	if not ProjectSettings.has_setting(SETTING_DEBUG_PRINTS):
		ProjectSettings.set_setting(SETTING_DEBUG_PRINTS, false)
	
	ProjectSettings.set_initial_value(SETTING_DEBUG_PRINTS, false)
	ProjectSettings.add_property_info({
		"name": SETTING_DEBUG_PRINTS,
		"type": TYPE_BOOL,
		"hint": PROPERTY_HINT_NONE
	})
	
	ProjectSettings.save()


func _remove_project_settings():
	if ProjectSettings.has_setting(SETTING_SCAN_MODE):
		ProjectSettings.set_setting(SETTING_SCAN_MODE, null)
		ProjectSettings.clear(SETTING_SCAN_MODE)
	
	if ProjectSettings.has_setting(SETTING_SCAN_MATERIALS):
		ProjectSettings.set_setting(SETTING_SCAN_MATERIALS, null)
		ProjectSettings.clear(SETTING_SCAN_MATERIALS)
	
	if ProjectSettings.has_setting(SETTING_DEBUG_PRINTS):
		ProjectSettings.set_setting(SETTING_DEBUG_PRINTS, null)
		ProjectSettings.clear(SETTING_DEBUG_PRINTS)
	

	ProjectSettings.save()
	
	
