@tool
extends EditorPlugin

const IMPORT_SCRIPT := "res://addons/material_assigner/import_script.gd"
var _dock: Control


func _enter_tree() -> void:
	_dock = _create_dock()
	add_control_to_container(CONTAINER_SPATIAL_EDITOR_SIDE_LEFT, _dock)
	call_deferred("_apply_to_all_files")


func _exit_tree() -> void:
	if _dock:
		remove_control_from_container(CONTAINER_SPATIAL_EDITOR_SIDE_LEFT, _dock)
		_dock.queue_free()


func _create_dock() -> Control:
	var panel := PanelContainer.new()
	var vb := VBoxContainer.new()
	panel.add_child(vb)

	var btn := Button.new()
	btn.text = "Assign Materials"
	btn.pressed.connect(_apply_to_all_files)
	vb.add_child(btn)

	var label := Label.new()
	label.name = "StatusLabel"
	label.text = ""
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(label)

	return panel


func _apply_to_all_files() -> void:
	var to_reimport: PackedStringArray = []
	_scan_dir("res://", to_reimport)

	var label := _dock.get_node_or_null("VBoxContainer/StatusLabel") as Label if _dock else null
	if label:
		label.text = "Found %d files to configure" % to_reimport.size()

	if not to_reimport.is_empty():
		var fs := get_editor_interface().get_resource_filesystem()
		fs.reimport_files(to_reimport)
		if label:
			label.text = "Configured and reimporting %d files" % to_reimport.size()
	else:
		if label:
			label.text = "All GLB/glTF files already configured"


func _scan_dir(dir_path: String, to_reimport: PackedStringArray) -> void:
	var dir := DirAccess.open(dir_path)
	if not dir:
		return

	dir.list_dir_begin()
	var entry := dir.get_next()

	while entry != "":
		if entry == "." or entry == "..":
			entry = dir.get_next()
			continue

		var full := dir_path.path_join(entry)

		if dir.current_is_dir():
			if not entry.begins_with("."):
				_scan_dir(full + "/", to_reimport)
		elif entry.get_extension() in ["glb", "gltf"]:
			var import_path := full + ".import"
			if _set_import_script(import_path):
				to_reimport.append(full)

		entry = dir.get_next()

	dir.list_dir_end()


func _set_import_script(import_path: String) -> bool:
	var config := ConfigFile.new()
	var err := config.load(import_path)
	if err != OK:
		print_rich("[MaterialAssigner] [color=red]Skip missing[/color] ", import_path)
		return false

	var current := config.get_value("params", "nodes/import_script", "")
	if current == IMPORT_SCRIPT:
		return false

	config.set_value("params", "nodes/import_script", IMPORT_SCRIPT)
	err = config.save(import_path)
	if err != OK:
		print_rich("[MaterialAssigner] [color=red]Save failed[/color] ", import_path, " err=", err)
		return false

	get_editor_interface().get_resource_filesystem().update_file(import_path)
	print_rich("[MaterialAssigner] Set: ", import_path)
	return true
