bl_info = {
    "name": "GoXport",
    "author": "Daniel",
    "version": (1, 0, 0),
    "blender": (4, 0, 0),
    "location": "3D View > Sidebar > GoXport",
    "description": "Export selected objects to GLB/glTF, resetting to origin on export",
    "category": "Import-Export",
}

import bpy
import os
import re
from bpy.props import StringProperty, EnumProperty
from bpy.types import Operator, Panel


def _preset_items(self, context):
    items = [("__NONE__", "None (use defaults)", "")]
    for path in bpy.utils.preset_paths("operator"):
        preset_dir = os.path.join(path, "export_scene.gltf")
        if os.path.isdir(preset_dir):
            for f in sorted(os.listdir(preset_dir)):
                if f.endswith(".py"):
                    name = f[:-3]
                    items.append((name, name, ""))
    return items


def _load_preset(filepath):
    settings = {}
    with open(filepath) as f:
        for match in re.finditer(r"op\.(\w+)\s*=\s*(.+)$", f.read(), re.MULTILINE):
            name = match.group(1)
            if name in (
                "filepath",
                "use_selection",
                "export_apply",
                "export_image_format",
            ):
                continue
            try:
                settings[name] = eval(match.group(2))
            except Exception:
                pass
    return settings


class GOXPORT_OT_export(Operator):
    bl_idname = "goxport.export"
    bl_label = "Export Selected"
    bl_description = "Move selected objects to origin, export, then restore positions"
    bl_options = {"REGISTER", "UNDO"}

    @classmethod
    def poll(cls, context):
        return bool(context.selected_objects)

    def execute(self, context):
        export_dir = context.scene.goxport_export_directory

        if not export_dir:
            self.report(
                {"ERROR"}, "No export directory set — set one in the GoXport panel"
            )
            return {"CANCELLED"}

        if not os.path.isdir(export_dir):
            self.report({"ERROR"}, f"Directory does not exist: {export_dir}")
            return {"CANCELLED"}

        ext = ".glb" if context.scene.goxport_export_format == "GLB" else ".gltf"

        preset = context.scene.goxport_export_preset
        preset_settings = {}
        if preset != "__NONE__":
            for path in bpy.utils.preset_paths("operator"):
                preset_path = os.path.join(path, "export_scene.gltf", f"{preset}.py")
                if os.path.isfile(preset_path):
                    preset_settings = _load_preset(preset_path)
                    break

        selected = context.selected_objects
        active = context.view_layer.objects.active

        mesh_prefix = context.scene.goxport_mesh_prefix
        mat_prefix = context.scene.goxport_material_prefix

        # skip objects whose ancestor is also selected (they export under that ancestor)
        skip = set()
        for obj in selected:
            parent = obj.parent
            while parent:
                if parent in selected:
                    skip.add(obj)
                    break
                parent = parent.parent

        exported = 0
        try:
            for root in selected:
                if root in skip:
                    continue

                hierarchy = [root] + list(root.children_recursive)

                saved_root_name = root.name
                if mesh_prefix and root.name.startswith(mesh_prefix):
                    root.name = root.name[len(mesh_prefix) :]

                saved_mat_names = {}
                if mat_prefix:
                    seen = set()
                    for obj in hierarchy:
                        for slot in obj.material_slots:
                            mat = slot.material
                            if mat and mat not in seen:
                                seen.add(mat)
                                if mat.name.startswith(mat_prefix):
                                    saved_mat_names[mat] = mat.name
                                    mat.name = mat.name[len(mat_prefix) :]

                saved_loc = root.location.copy()
                root.location = (0.0, 0.0, 0.0)

                bpy.ops.object.select_all(action="DESELECT")
                for obj in hierarchy:
                    obj.select_set(True)
                context.view_layer.objects.active = root

                filepath = os.path.join(export_dir, f"{mesh_prefix}{root.name}{ext}")

                bpy.ops.export_scene.gltf(
                    filepath=filepath,
                    use_selection=True,
                    export_apply=True,
                    export_image_format="AUTO",
                    **preset_settings,
                )

                root.location = saved_loc
                root.name = saved_root_name
                for mat, name in saved_mat_names.items():
                    mat.name = name

                exported += 1

        except Exception as exc:
            self.report({"ERROR"}, f"Export failed: {exc}")
            return {"CANCELLED"}
        finally:
            bpy.ops.object.select_all(action="DESELECT")
            for obj in selected:
                obj.select_set(True)
            context.view_layer.objects.active = active

        count = exported
        self.report(
            {"INFO"},
            f"Exported {count} object{'s' if count > 1 else ''} → {export_dir}",
        )
        return {"FINISHED"}


class GOXPORT_PT_panel(Panel):
    bl_label = "GoXport"
    bl_idname = "GOXPORT_PT_panel"
    bl_space_type = "VIEW_3D"
    bl_region_type = "UI"
    bl_category = "GoXport"

    def draw(self, context):
        layout = self.layout

        layout.prop(context.scene, "goxport_export_directory")
        layout.prop(context.scene, "goxport_export_format")
        layout.prop(context.scene, "goxport_export_preset")
        layout.prop(context.scene, "goxport_mesh_prefix")
        layout.prop(context.scene, "goxport_material_prefix")

        col = layout.column(align=True)
        col.scale_y = 1.6
        col.operator("goxport.export", text="Export Selected", icon="EXPORT")

        if not context.selected_objects:
            col = layout.column()
            col.label(text="Select objects to export", icon="INFO")


CLASSES = (
    GOXPORT_OT_export,
    GOXPORT_PT_panel,
)


def register():
    for cls in CLASSES:
        bpy.utils.register_class(cls)
    bpy.types.Scene.goxport_export_directory = StringProperty(
        name="Export Folder",
        subtype="DIR_PATH",
        description="Destination folder for exported files",
        default="//",
    )
    bpy.types.Scene.goxport_export_format = EnumProperty(
        name="Format",
        description="Output file format",
        items=[
            ("GLB", "GLB Binary (.glb)", "Single-file binary GLB"),
            ("GLTF", "glTF (.gltf)", "glTF JSON with external resources"),
        ],
        default="GLB",
    )
    bpy.types.Scene.goxport_export_preset = EnumProperty(
        name="Preset",
        description="glTF export operator preset to use",
        items=_preset_items,
    )
    bpy.types.Scene.goxport_mesh_prefix = StringProperty(
        name="Mesh Prefix",
        description="Prefix to strip from object names on export (e.g. sm_)",
        default="sm_",
    )
    bpy.types.Scene.goxport_material_prefix = StringProperty(
        name="Material Prefix",
        description="Prefix to strip from material names on export (e.g. mat_)",
        default="mat_",
    )


def unregister():
    del bpy.types.Scene.goxport_export_directory
    del bpy.types.Scene.goxport_export_format
    del bpy.types.Scene.goxport_export_preset
    del bpy.types.Scene.goxport_mesh_prefix
    del bpy.types.Scene.goxport_material_prefix
    for cls in reversed(CLASSES):
        bpy.utils.unregister_class(cls)


if __name__ == "__main__":
    register()
