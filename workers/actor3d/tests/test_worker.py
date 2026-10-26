import tempfile
import unittest
from pathlib import Path

from workers.actor3d.reconstruct_3ddfa import run_reconstruction


class ReconstructionWorkerContractTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.engine = self.root / "engine"
        self.engine.mkdir()
        self.front = self.root / "front.jpg"
        self.front.write_bytes(b"test face photo content")
        self.output = self.root / "private"
        demo = """
import argparse
from pathlib import Path
parser = argparse.ArgumentParser()
parser.add_argument('-f')
parser.add_argument('-o')
parser.add_argument('--onnx', action='store_true')
parser.add_argument('--show_flag')
a = parser.parse_args()
name = Path(a.f).stem
folder = Path('examples/results')
folder.mkdir(parents=True, exist_ok=True)
(folder / (name + '_obj.obj')).write_text('v 0 0 0\\nv 0 1 0\\nv 1 0 0\\nf 1 2 3\\n')
"""
        (self.engine / "demo.py").write_text(demo)

    def tearDown(self):
        self.tmp.cleanup()

    def test_fails_closed_without_explicit_consent(self):
        with self.assertRaisesRegex(ValueError, 'consent'):
            run_reconstruction(self.front, self.engine, self.output,
                               consent=False)
        self.assertFalse(self.output.exists())

    def test_optional_worker_produces_real_mesh_file_and_purges_staging(self):
        result = run_reconstruction(self.front, self.engine, self.output,
                                    consent=True)
        self.assertEqual(result['format'], 'obj')
        self.assertFalse(result['quality_verified'])
        self.assertEqual(len(result['files']), 1)
        mesh = Path(result['files'][0])
        self.assertEqual(mesh.suffix, '.obj')
        self.assertIn('v 0 0 0', mesh.read_text())
        self.assertFalse(list((self.engine / 'examples/results').glob('hotice_*')))
        self.assertTrue(mesh.exists())

    def test_does_not_copy_symlinked_mesh_sidecars(self):
        secret = self.root / "private-secret.txt"
        secret.write_text("DO NOT COPY")
        with (self.engine / "demo.py").open("a") as script:
            script.write("\\n(folder / (name + '_obj.png')).symlink_to(" +
                         repr(str(secret)) + ")\\n")
        with self.assertRaisesRegex(RuntimeError, 'Unsafe symbolic link'):
            run_reconstruction(self.front, self.engine, self.output,
                               consent=True)
        self.assertFalse(list(self.output.glob("*")))
        self.assertFalse(list((self.engine / "examples/results").glob("hotice_*")))

    def test_rejects_oversized_output_before_reading_entire_obj(self):
        with (self.engine / "demo.py").open("a") as script:
            script.write(
                "\\nwith (folder / (name + '_obj.obj')).open('ab') as mesh:\\n"
                "    mesh.truncate(41 * 1024 * 1024)\\n"
            )
        with self.assertRaisesRegex(RuntimeError, 'Unsafe reconstructed geometry'):
            run_reconstruction(self.front, self.engine, self.output,
                               consent=True)
        self.assertFalse(list(self.output.glob("*")))

    def test_refuses_engine_directory_as_public_output(self):
        with self.assertRaisesRegex(ValueError, 'private folder'):
            run_reconstruction(self.front, self.engine, self.engine / "private",
                               consent=True)

    def test_invalid_source_is_not_passed_to_external_model(self):
        invalid = self.root / "front.txt"
        invalid.write_text("not a picture")
        with self.assertRaisesRegex(ValueError, 'JPG or PNG'):
            run_reconstruction(invalid, self.engine, self.output,
                               consent=True)


if __name__ == '__main__':
    unittest.main()
