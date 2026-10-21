"""Run with python3 scripts/test-jj-remote-prompt.py (requires jj and git)."""

import importlib.util
import json
import os
from pathlib import Path
import shlex
import shutil
import subprocess
import tempfile
import unittest


SOURCE = Path(__file__).resolve().parents[1] / "starship/jj-remote-prompt.py"
SPEC = importlib.util.spec_from_file_location("remote_prompt", SOURCE)
prompt = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(prompt)


class RemotePromptTest(unittest.TestCase):
    def test_merge_distances_use_shortest_path(self):
        graph = [["wc", "left", "right"], ["left", "base"],
                 ["right", "middle"], ["middle", "base"], ["base", "old"]]
        self.assertEqual(prompt.ancestor_distances(graph, 2),
                         {"wc": 0, "left": 1, "right": 1, "base": 2, "middle": 2})

    def test_wrap_preserves_full_names_and_unicode_width(self):
        entries = ["long-feature-name@origin~2", "界面@upstream", "third@origin"]
        output = prompt.wrap_entries(entries, 35)
        self.assertIn("\n", output)
        for entry in entries:
            self.assertIn(entry, output)
        self.assertTrue(all(prompt.visible_width(line) <= 35
                            for line in output.splitlines()))
        self.assertEqual(prompt.wrap_entries([], 35), "")

    def test_real_remote_refs(self):
        with tempfile.TemporaryDirectory(prefix="jj-remote-test-") as temporary:
            directory = Path(temporary) / "repo"
            directory.mkdir()
            env = dict(os.environ, JJ_CONFIG=os.devnull, COLUMNS="120")

            def run(*args):
                return subprocess.run(args, cwd=directory, env=env, check=True,
                                      capture_output=True, text=True).stdout.strip()

            def jj(*args):
                return run("jj", "--config", 'user.name="Prompt test"',
                           "--config", 'user.email="prompt@example.invalid"', *args)

            def commit_id():
                return jj("log", "--no-graph", "-r", "@", "-T", "commit_id")

            jj("git", "init")
            jj("describe", "-m", "base")
            base = commit_id()
            if shutil.which("starship"):
                config = SOURCE.with_name("starship.toml").read_text()
                config = config.replace(
                    'command = "jj-remote-prompt"',
                    "command = " + json.dumps("python3 " + shlex.quote(str(SOURCE))),
                )
                config_path = Path(temporary) / "prompt.toml"
                config_path.write_text(config)
                env["STARSHIP_CONFIG"] = str(config_path)
                self.assertEqual(run("starship", "module", "custom.jj_remote"), "")
            jj("new", "-m", "local")
            local = commit_id()
            for name in ("feature", "diverged", "synced"):
                jj("bookmark", "create", name)
            jj("new", "-m", "ahead")
            ahead = commit_id()
            jj("new", base, "-m", "other side")
            diverged = commit_id()
            jj("edit", local)
            for name, target in (("feature", ahead), ("diverged", diverged),
                                 ("synced", local), ("remote-only", base),
                                 ("unrelated", diverged)):
                run("git", "update-ref", f"refs/remotes/origin/{name}", target)
            jj("git", "import")
            # Import may create an empty WC child when a remote makes it immutable.
            jj("edit", "--ignore-immutable", local)
            output = run("python3", str(SOURCE))
            self.assertIn("feature@origin↑1", output)
            self.assertIn("diverged@origin↔↑1↓1", output)
            self.assertIn("remote-only@origin~1", output)
            self.assertIn("synced@origin", output)
            self.assertNotIn("synced@origin~", output)
            self.assertNotIn("unrelated", output)
            self.assertNotIn("@git", output)
            if shutil.which("starship"):
                rendered = run("starship", "module", "custom.jj_remote")
                self.assertIn("remote ", rendered)
                self.assertIn("feature@origin↑1", rendered)

    def test_non_repository_is_silent(self):
        with tempfile.TemporaryDirectory(prefix="jj-no-repo-") as directory:
            result = subprocess.run(["python3", str(SOURCE)], cwd=directory,
                                    capture_output=True, text=True, check=True)
            self.assertEqual(result.stdout, "")
            self.assertEqual(result.stderr, "")


if __name__ == "__main__":
    unittest.main()
