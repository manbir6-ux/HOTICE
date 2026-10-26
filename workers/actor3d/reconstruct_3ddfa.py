#!/usr/bin/env python3
"""Optional HOTICE private 3D face OBJ reconstruction worker.

Uses an independently installed, pinned 3DDFA_V2 engine's documented demo.py
CLI with -o obj --onnx. This worker never downloads models or calls an AI
provider, never runs from web/public, and never claims a scan is high fidelity.
Deploy only after code + checkpoint/data licences have been audited.
"""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import secrets
import shutil
import subprocess
import sys
import tempfile

MAX_SOURCE_BYTES = 25 * 1024 * 1024
MAX_MESH_BYTES = 40 * 1024 * 1024
MAX_TOTAL_OUTPUT_BYTES = 64 * 1024 * 1024
ALLOWED_EXTENSIONS = {".jpg", ".jpeg", ".png"}


def run_reconstruction(
    front_image: Path,
    engine_dir: Path,
    output_dir: Path,
    *,
    consent: bool,
    timeout_seconds: int = 180,
) -> dict:
    if not consent:
        raise ValueError("Explicit face-capture and processing consent is required.")
    image = front_image.resolve(strict=True)
    engine = engine_dir.resolve(strict=True)
    output = output_dir.resolve()
    if not image.is_file() or image.suffix.lower() not in ALLOWED_EXTENSIONS:
        raise ValueError("Only a captured JPG or PNG face photo is accepted.")
    if image.stat().st_size == 0 or image.stat().st_size > MAX_SOURCE_BYTES:
        raise ValueError("The source face image is empty or too large.")
    if not (engine / "demo.py").is_file():
        raise ValueError("3DDFA_V2 was not installed or pinned on this worker.")
    if output == engine or engine in output.parents:
        raise ValueError("Output must be in a private folder outside the engine.")
    if timeout_seconds < 1 or timeout_seconds > 900:
        raise ValueError("Invalid reconstruction timeout.")
    original_umask = os.umask(0o077)
    try:
        output.mkdir(parents=True, exist_ok=True)
        target_dir = engine / "examples" / "results"
        if target_dir.is_symlink():
            raise ValueError("Reconstruction output folder cannot be a symlink.")
        target_dir.mkdir(parents=True, exist_ok=True)
        token = secrets.token_hex(12)
        with tempfile.TemporaryDirectory(prefix="hotice_face_") as directory:
            source = Path(directory) / f"hotice_{token}{image.suffix.lower()}"
            shutil.copyfile(image, source)
            result_prefix = f"hotice_{token}_obj"
            try:
                command = [
                    sys.executable,
                    str(engine / "demo.py"),
                    "-f", str(source),
                    "-o", "obj",
                    "--onnx",
                    "--show_flag", "false",
                ]
                result = subprocess.run(
                    command, cwd=engine, timeout=timeout_seconds,
                    check=False, capture_output=True, text=True,
                )
                mesh = target_dir / (result_prefix + ".obj")
                if result.returncode != 0 or not mesh.exists():
                    # Never log photo paths or model output that may identify a
                    # face. Exact errors remain in the private worker logs.
                    raise RuntimeError(
                        "Reconstruction engine failed or returned no OBJ mesh."
                    )
                if mesh.is_symlink() or mesh.stat().st_size > MAX_MESH_BYTES:
                    raise RuntimeError("Unsafe reconstructed geometry output.")
                obj_data = mesh.read_text(errors="replace")
                if not any(line.startswith("v ") for line in obj_data.splitlines()):
                    raise RuntimeError("Reconstruction returned invalid geometry.")
                destinations = []
                total_size = 0
                files = [
                    file for file in target_dir.glob(result_prefix + ".*")
                    if file.suffix.lower() in {".obj", ".mtl", ".png", ".jpg", ".jpeg"}
                ]
                # Reject the entire result *before* copying any file to avoid
                # a partial unsafe Actor package on a failed operation.
                for file in files:
                    if file.is_symlink() or not file.is_file():
                        raise RuntimeError("Unsafe symbolic link in 3D output.")
                    total_size += file.stat().st_size
                    if total_size > MAX_TOTAL_OUTPUT_BYTES:
                        raise RuntimeError("3D output exceeds worker safety limit.")
                for file in files:
                    dest = output / (result_prefix + file.suffix.lower())
                    if dest.is_symlink() or dest.exists():
                        raise RuntimeError("Output file already exists.")
                    shutil.copyfile(file, dest)
                    dest.chmod(0o600)
                    destinations.append(str(dest))
                if not destinations:
                    raise RuntimeError("Reconstruction produced no usable output.")
                return {
                    "format": "obj",
                    "reconstruction": "3DDFA_V2 face geometry (approximate)",
                    "quality_verified": False,
                    "files": destinations,
                    "source_is_private": True,
                }
            finally:
                # 3DDFA's sample CLI writes into examples/results; purge the
                # intermediary geometry/textures even on failure.
                for file in target_dir.glob(result_prefix + ".*"):
                    if file.is_file() or file.is_symlink():
                        file.unlink(missing_ok=True)
    finally:
        os.umask(original_umask)


def main() -> int:
    parser = argparse.ArgumentParser(description="Private HOTICE face-to-OBJ worker")
    parser.add_argument("--front", type=Path, required=True)
    parser.add_argument("--engine-dir", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--consent", action="store_true")
    args = parser.parse_args()
    try:
        result = run_reconstruction(
            args.front, args.engine_dir, args.output_dir, consent=args.consent
        )
    except (OSError, ValueError, RuntimeError, subprocess.TimeoutExpired) as exc:
        print(f"Actor reconstruction refused/failed: {type(exc).__name__}", file=sys.stderr)
        return 1
    print(json.dumps(result))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
