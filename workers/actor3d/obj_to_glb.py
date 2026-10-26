"""Blender-side private OBJ -> GLB conversion for HOTICE Actor meshes.

Run: blender -b --python workers/actor3d/obj_to_glb.py --
     --input /private/face.obj --output /private/face.glb

Blender must be installed on a separate worker; NOT on a shared Namecheap
PHP webhost. Exported geometry is an approximation until artist reviewed.
"""
import argparse
import sys
from pathlib import Path


def convert(input_path: Path, output_path: Path) -> None:
    import bpy  # Only available within the Blender Python runtime.
    if not input_path.is_file() or input_path.suffix.lower() != ".obj":
        raise ValueError("Only a private OBJ mesh can be converted.")
    if output_path.suffix.lower() != ".glb":
        raise ValueError("The requested output must be a GLB file.")
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.wm.obj_import(filepath=str(input_path.resolve()))
    if not any(obj.type == "MESH" for obj in bpy.context.scene.objects):
        raise RuntimeError("OBJ did not import any mesh.")
    output_path.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=str(output_path.resolve()),
        export_format="GLB",
        use_selection=False,
        export_apply=True,
    )
    if not output_path.exists() or output_path.read_bytes()[:4] != b"glTF":
        raise RuntimeError("Blender did not generate a valid GLB header.")
    output_path.chmod(0o600)


def main():
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    opts = parser.parse_args(args)
    convert(opts.input, opts.output)


if __name__ == "__main__":
    main()
