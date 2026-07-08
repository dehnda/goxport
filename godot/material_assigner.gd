@tool
extends EditorScenePostImport

const MATERIALS_ROOT := "res://assets/materials/"


func _post_import(scene: Node) -> Object:
	_assign_materials(scene)
	return scene


func _assign_materials(node: Node) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		for i in mi.get_surface_override_material_count():
			var mat := mi.get_surface_override_material(i)
			if mat:
				var replacement := _find_material(mat.resource_name)
				if replacement:
					mi.set_surface_override_material(i, replacement)

	for child in node.get_children():
		_assign_materials(child)


func _find_material(name: String) -> Material:
	if name.is_empty():
		return null
	return _search(MATERIALS_ROOT, name)


func _search(dir_path: String, target: String) -> Material:
	var dir := DirAccess.open(dir_path)
	if not dir:
		return null

	dir.list_dir_begin()
	var entry := dir.get_next()

	while entry != "":
		if entry == "." or entry == "..":
			entry = dir.get_next()
			continue

		var full := dir_path.path_join(entry)

		if dir.current_is_dir():
			var result := _search(full + "/", target)
			if result:
				dir.list_dir_end()
				return result
		else:
			if entry.get_basename() == target and entry.get_extension() in ["tres", "material", "resource"]:
				var res := load(full)
				if res and res is Material:
					dir.list_dir_end()
					return res

		entry = dir.get_next()

	dir.list_dir_end()
	return null
