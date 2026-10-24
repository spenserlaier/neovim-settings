#!/usr/bin/env python3
"""Parser, real-jj integration, and picker handoff tests for jjr."""

import importlib.util
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location("jjr", Path(__file__).with_name("jjr.py"))
jjr = importlib.util.module_from_spec(spec)
spec.loader.exec_module(jjr)


class ReviewTests(unittest.TestCase):
    def test_hunk_destinations_and_context(self):
        diff = "diff --git a/a b/a\n--- a/a\n+++ b/a\n@@ -1,4 +1,4 @@\n context\n-old\n+new\n tail\n@@ -40,2 +40,0 @@\n-deleted\n-lines\n"
        hunks = jjr.split_hunks(diff)
        self.assertEqual([h["line"] for h in hunks], [2, 40])
        self.assertIn(" context\n", hunks[0]["patch"])
        self.assertNotIn("deleted", hunks[0]["patch"])
        self.assertTrue(hunks[1]["patch"].startswith("diff --git"))

    def test_real_jj_changes_and_literal_paths(self):
        with tempfile.TemporaryDirectory(prefix="jjr-test-") as directory:
            root = Path(directory)

            def jj(*args):
                return jjr.run_jj(root, *args)

            jj("git", "init", ".")
            for name in ["edit.py", "gone.txt", "old.txt", "binary", 'odd (x)*\t".txt']:
                (root / name).write_text("".join(f"{name} line {i}\n" for i in range(40)))
            jj("describe", "-m", "baseline")
            jj("new")
            (root / "edit.py").write_text("".join("changed\n" if i in (2, 30) else f"edit.py line {i}\n" for i in range(40)))
            (root / "gone.txt").unlink()
            (root / "old.txt").rename(root / "renamed.txt")
            (root / "binary").write_bytes(b"\0binary")
            (root / 'odd (x)*\t".txt').write_text("new content\n")
            (root / "added.txt").write_text("added\n")
            entries = jjr.collect(root)
            files = {e["path"]: e for e in entries if not e["key"][1]}
            self.assertEqual(files["gone.txt"]["status"], "D")
            self.assertEqual(files["added.txt"]["status"], "A")
            self.assertEqual(files["renamed.txt"]["status"], "R")
            self.assertIn("rename from old.txt", files["renamed.txt"]["patch"])
            self.assertIn("new content", files['odd (x)*\t".txt']["patch"])
            self.assertNotIn("\t", jjr.label(files['odd (x)*\t".txt']))
            hunks = [e for e in entries if e["path"] == "edit.py" and e["key"][1]]
            self.assertEqual([e["line"] for e in hunks], [3, 31])
            binary = [e for e in entries if e["path"] == "binary" and e["key"][1]]
            self.assertEqual(binary[0]["heading"], "[no text hunks]")
            with patch.object(jjr, "show_patch") as show, patch.object(jjr.subprocess, "run") as run:
                jjr.open_entry(root, files["gone.txt"])
                jjr.open_entry(root, files["binary"])
                self.assertEqual(show.call_count, 2)
                run.assert_not_called()
            with patch.object(jjr.subprocess, "run") as run:
                jjr.open_entry(root, {**files["edit.py"], "line": 1000})
                self.assertEqual(run.call_args.args[0][1], "+40")

    def test_picker_keeps_query_and_selects_corresponding_file(self):
        entries = [
            {"path": "a.py", "key": ["a.py", 0], "status": "M", "heading": ""},
            {"path": "b.py", "key": ["b.py", 0], "status": "M", "heading": ""},
            {"path": "b.py", "key": ["b.py", 1], "status": "M", "heading": "@@ -1 +1 @@"},
        ]
        real_run = subprocess.run
        calls = []

        def fake_picker(command, **kwargs):
            if command[0] == "fzf":
                return real_run(command, **kwargs)
            calls.append(command)
            self.assertEqual(kwargs["env"]["VI_FZF_MODE_FILE"], "/tmp/state.vi-mode")
            return subprocess.CompletedProcess(command, 0, "b.py\nctrl-g\n1\tM b.py\n")

        with patch.object(jjr.subprocess, "run", side_effect=fake_picker):
            result = jjr.pick(entries, "files", "b.py", ["b.py", 1], "/tmp/state")
        self.assertEqual(result[:2], ("b.py", "ctrl-g"))
        self.assertEqual(result[2]["path"], "b.py")
        self.assertIn("start:pos(1)", calls[0])
        self.assertIn("--query", calls[0])


if __name__ == "__main__":
    unittest.main()
