@tool
extends EditorScenePostImport

const MATERIALS_ROOT := "res://assets/materials/"
const MATERIAL_EXTENSIONS := ["tres", "res", "material", "resource"]


func _post_import(scene: Node) -> Object:
	print_rich("[MaterialImportAssigner] Processing: ", scene.scene_file_path)
	var mesh := _find_first_mesh(scene)
	if mesh == null:
		print_rich("[MaterialImportAssigner]   [color=orange]No MeshInstance3D found[/color]")
		return scene
	_assign_materials(mesh)
	return scene


func _find_first_mesh(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node
	for child in node.get_children():
		var found := _find_first_mesh(child)
		if found:
			return found
	return null


func _assign_materials(mesh: MeshInstance3D) -> void:
	var count := mesh.mesh.get_surface_count() if mesh.mesh else 0
	for i in count:
		var current := mesh.get_active_material(i)
		var mat_name := current.resource_name if current else ""
		if mat_name.is_empty():
			continue
		var replacement := _find_material(mat_name)
		if replacement:
			mesh.set_surface_override_material(i, replacement)
			print_rich("[MaterialImportAssigner]   Slot %d '%s' -> %s" % [i, mat_name, replacement.resource_path])
		else:
			mesh.set_surface_override_material(i, _make_default_material(mat_name))
			print_rich("[MaterialImportAssigner]   Slot %d '%s' [color=orange]no match, using pink default[/color]" % [i, mat_name])


func _make_default_material(mat_name: String) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.0, 1.0)
	mat.resource_name = mat_name
	return mat


func _find_material(mat_name: String) -> Material:
	return _search(MATERIALS_ROOT, mat_name)


func _search(dir_path: String, target: String) -> Material:
	var dir := DirAccess.open(dir_path)
	if not dir:
		print_rich("[MaterialImportAssigner]   [color=orange]Cannot open[/color] ", dir_path)
		return null

	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if entry != "." and entry != "..":
			var full := dir_path.path_join(entry)
			if dir.current_is_dir():
				var result := _search(full + "/", target)
				if result:
					dir.list_dir_end()
					return result
			elif entry.get_basename() == target and entry.get_extension() in MATERIAL_EXTENSIONS:
				var res := load(full)
				if res is Material:
					dir.list_dir_end()
					return res
		entry = dir.get_next()

	dir.list_dir_end()
	return null
