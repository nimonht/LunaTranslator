"""Unit tests for lunatranslator-ocr (no display / no OCR binaries required).

Run: python -m pytest linux/tests/  -q
 or: python linux/tests/test_ocr.py
"""
import importlib.util
import os
import sys
import unittest
from unittest import mock

# Load the hyphenated, extensionless script as a module.
_HERE = os.path.dirname(os.path.abspath(__file__))
_SRC = os.path.join(_HERE, "..", "bin", "lunatranslator-ocr")
_spec = importlib.util.spec_from_loader(
    "lt_ocr", importlib.machinery.SourceFileLoader("lt_ocr", _SRC)
)
ocr = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(ocr)


def have_factory(present):
    """Return a fake `have()` that reports the given commands as present."""
    return lambda cmd: cmd in present


class BackendSelection(unittest.TestCase):
    def test_wayland_with_grim_and_slurp(self):
        b = ocr.detect_capture_backend(
            env={"WAYLAND_DISPLAY": "wayland-0"},
            _have=have_factory({"grim", "slurp"}),
        )
        self.assertEqual(b, "grim")

    def test_wayland_without_grim_falls_back_to_portal(self):
        b = ocr.detect_capture_backend(
            env={"WAYLAND_DISPLAY": "wayland-0"},
            _have=have_factory(set()),
        )
        self.assertEqual(b, "portal")

    def test_wayland_with_only_grim_no_slurp_is_portal(self):
        b = ocr.detect_capture_backend(
            env={"WAYLAND_DISPLAY": "wayland-0"},
            _have=have_factory({"grim"}),
        )
        self.assertEqual(b, "portal")

    def test_x11_uses_mss(self):
        b = ocr.detect_capture_backend(env={}, _have=have_factory({"grim", "slurp"}))
        self.assertEqual(b, "mss")


class TesseractCmd(unittest.TestCase):
    def test_lang_and_image_threaded_through(self):
        cmd = ocr.build_tesseract_cmd("/tmp/x.png", "jpn+eng")
        self.assertEqual(cmd[0], "tesseract")
        self.assertIn("/tmp/x.png", cmd)
        self.assertIn("stdout", cmd)
        self.assertEqual(cmd[cmd.index("-l") + 1], "jpn+eng")


class ArgParsing(unittest.TestCase):
    def test_defaults(self):
        with mock.patch.dict(os.environ, {}, clear=True):
            a = ocr.parse_args([])
        self.assertEqual(a.lang, "jpn+eng")
        self.assertEqual(a.engine, "tesseract")
        self.assertIsNone(a.backend)

    def test_env_overrides(self):
        with mock.patch.dict(
            os.environ, {"LT_OCR_LANG": "jpn", "LT_OCR_ENGINE": "manga-ocr"}, clear=True
        ):
            a = ocr.parse_args([])
        self.assertEqual(a.lang, "jpn")
        self.assertEqual(a.engine, "manga-ocr")

    def test_flag_overrides_env(self):
        with mock.patch.dict(os.environ, {"LT_OCR_LANG": "jpn"}, clear=True):
            a = ocr.parse_args(["--lang", "eng", "--backend", "grim"])
        self.assertEqual(a.lang, "eng")
        self.assertEqual(a.backend, "grim")


class ClipboardPush(unittest.TestCase):
    def test_push_invokes_wl_copy_with_text(self):
        with mock.patch.object(ocr, "have", return_value=True), mock.patch.object(
            ocr.subprocess, "run"
        ) as run:
            ocr.push_clipboard("こんにちは")
        run.assert_called_once()
        args, kwargs = run.call_args
        self.assertEqual(args[0], ["wl-copy"])
        self.assertEqual(kwargs["input"], "こんにちは")

    def test_push_without_wl_copy_errors(self):
        with mock.patch.object(ocr, "have", return_value=False):
            with self.assertRaises(SystemExit):
                ocr.push_clipboard("x")


class OcrDispatch(unittest.TestCase):
    def test_engine_routes_to_tesseract(self):
        with mock.patch.object(ocr, "ocr_tesseract", return_value="T") as t, \
             mock.patch.object(ocr, "ocr_mangaocr", return_value="M") as m:
            self.assertEqual(ocr.run_ocr("i.png", "tesseract", "jpn"), "T")
            t.assert_called_once()
            m.assert_not_called()

    def test_engine_routes_to_mangaocr(self):
        with mock.patch.object(ocr, "ocr_tesseract", return_value="T") as t, \
             mock.patch.object(ocr, "ocr_mangaocr", return_value="M") as m:
            self.assertEqual(ocr.run_ocr("i.png", "manga-ocr", "jpn"), "M")
            m.assert_called_once()
            t.assert_not_called()


class MainFlow(unittest.TestCase):
    def test_main_captures_ocrs_and_pushes(self):
        with mock.patch.object(ocr, "detect_capture_backend", return_value="grim"), \
             mock.patch.object(ocr, "capture") as cap, \
             mock.patch.object(ocr, "run_ocr", return_value="text") as ro, \
             mock.patch.object(ocr, "push_clipboard") as push:
            rc = ocr.main(["--lang", "jpn"])
        self.assertEqual(rc, 0)
        cap.assert_called_once()
        ro.assert_called_once()
        push.assert_called_once_with("text")

    def test_main_returns_2_on_empty_text(self):
        with mock.patch.object(ocr, "detect_capture_backend", return_value="grim"), \
             mock.patch.object(ocr, "capture"), \
             mock.patch.object(ocr, "run_ocr", return_value=""), \
             mock.patch.object(ocr, "push_clipboard") as push:
            rc = ocr.main([])
        self.assertEqual(rc, 2)
        push.assert_not_called()


if __name__ == "__main__":
    unittest.main(verbosity=2)
