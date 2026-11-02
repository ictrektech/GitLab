#!/usr/bin/env python3
"""Exercise the updater against local repositories, without network access."""

import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / "vos_sync_upstream.py"
if not SCRIPT.exists():
    SCRIPT = Path(__file__).with_name("vos_sync_upstream.py")


class SyncTests(unittest.TestCase):
    def git(self, root, *args):
        return subprocess.check_output(["git", "-C", str(root), *args], text=True, stderr=subprocess.PIPE).strip()

    def commit(self, root, message):
        self.git(root, "add", "-A")
        self.git(root, "commit", "-qm", message)
        return self.git(root, "rev-parse", "HEAD")

    def setUp(self):
        build = Path.home() / "dev/build/gitlab-upstream-tests"
        build.mkdir(parents=True, exist_ok=True)
        self.temp = tempfile.TemporaryDirectory(dir=build)
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.env = {**os.environ, "VOS_UPSTREAM_BUILD_ROOT": str(self.root / "fetches"),
                    "GIT_CONFIG_NOSYSTEM": "1", "GIT_CONFIG_GLOBAL": os.devnull,
                    "GIT_AUTHOR_NAME": "Test Author", "GIT_AUTHOR_EMAIL": "test@example.com",
                    "GIT_COMMITTER_NAME": "Test Author", "GIT_COMMITTER_EMAIL": "test@example.com"}
        self.upstream = self.root / "upstream"
        self.repo = self.root / "fork"
        for path, branch in ((self.upstream, "master"), (self.repo, "main")):
            path.mkdir()
            self.git(path, "init", "-q", "-b", branch)
            self.git(path, "config", "user.name", "Test Author")
            self.git(path, "config", "user.email", "test@example.com")
        (self.upstream / "code.txt").write_text("base\n")
        self.oldest = self.commit(self.upstream, "Old upstream history")
        (self.upstream / "other.txt").write_text("base\n")
        self.baseline = self.commit(self.upstream, "Upstream baseline source")
        for name in ("code.txt", "other.txt"):
            shutil.copy2(self.upstream / name, self.repo / name)
        self.snapshot = self.commit(self.repo, "Import source snapshot")
        self.metadata = {"repository": self.upstream.as_uri(), "branch": "master",
                         "commit": self.baseline, "tree": self.git(self.upstream, "rev-parse", "HEAD^{tree}"),
                         "snapshot_commit": self.snapshot}
        (self.repo / "UPSTREAM").write_text(json.dumps(self.metadata) + "\n")
        (self.repo / "scripts").mkdir()
        shutil.copy2(SCRIPT, self.repo / "scripts/vos_sync_upstream.py")
        self.commit(self.repo, "Add updater tooling")

    def run_sync(self, *args, expected=0, repo=None):
        repo = repo or self.repo
        result = subprocess.run(["python3", str(repo / "scripts/vos_sync_upstream.py"), *args],
                                text=True, capture_output=True, env=self.env)
        self.assertEqual(result.returncode, expected, result.stdout + result.stderr)
        self.assertEqual(list((self.root / "fetches").glob("fetch-*")), [])
        return result

    def advance(self, name="other.txt", text="updated\n"):
        (self.upstream / name).write_text(text)
        return self.commit(self.upstream, "Change upstream source")

    def assert_history(self, repo):
        history = self.git(repo, "rev-list", "HEAD").splitlines()
        self.assertNotIn(self.oldest, history)
        self.assertNotIn(self.baseline, history)
        self.assertEqual(self.git(repo, "rev-parse", "--is-shallow-repository"), "false")
        self.assertEqual(self.git(repo, "status", "--porcelain"), "")

    def test_repeated_sync_preserves_local_changes_without_upstream_history(self):
        (self.repo / "code.txt").write_text("VOS customization\n")
        self.commit(self.repo, "Customize local behavior")
        latest = self.advance()
        self.run_sync()
        self.assertEqual((self.repo / "code.txt").read_text(), "VOS customization\n")
        self.assertEqual((self.repo / "other.txt").read_text(), "updated\n")
        self.assertEqual(json.loads((self.repo / "UPSTREAM").read_text())["commit"], latest)
        self.advance("new.txt", "second sync\n")
        self.run_sync()
        self.assertEqual((self.repo / "new.txt").read_text(), "second sync\n")
        count = self.git(self.repo, "rev-list", "--count", "HEAD")
        self.run_sync()
        self.assertEqual(self.git(self.repo, "rev-list", "--count", "HEAD"), count)
        self.assert_history(self.repo)

    def test_check_does_not_change_head_or_metadata(self):
        head = self.git(self.repo, "rev-parse", "HEAD")
        metadata = (self.repo / "UPSTREAM").read_bytes()
        self.advance()
        self.run_sync("--check")
        self.assertEqual(self.git(self.repo, "rev-parse", "HEAD"), head)
        self.assertEqual((self.repo / "UPSTREAM").read_bytes(), metadata)
        self.assert_history(self.repo)

    def test_upstream_deletions_preserve_unrelated_local_files(self):
        (self.repo / "vos-only.txt").write_text("keep local integration\n")
        self.commit(self.repo, "Add local integration")
        (self.upstream / "other.txt").unlink()
        self.commit(self.upstream, "Remove upstream source")
        self.run_sync()
        self.assertFalse((self.repo / "other.txt").exists())
        self.assertEqual((self.repo / "vos-only.txt").read_text(), "keep local integration\n")
        self.assert_history(self.repo)

    def test_dirty_worktree_is_rejected(self):
        (self.repo / "code.txt").write_text("unsaved\n")
        self.run_sync(expected=1)
        self.assertEqual((self.repo / "code.txt").read_text(), "unsaved\n")

    def conflict(self):
        (self.repo / "code.txt").write_text("local change\n")
        self.commit(self.repo, "Change local source")
        self.advance("code.txt", "upstream change\n")
        self.run_sync(expected=1)
        self.assertIn("<<<<<<<", (self.repo / "code.txt").read_text())

    def test_conflict_abort_restores_previous_baseline(self):
        self.conflict()
        self.run_sync("--abort")
        self.assertEqual((self.repo / "code.txt").read_text(), "local change\n")
        self.assertEqual(json.loads((self.repo / "UPSTREAM").read_text())["commit"], self.baseline)
        self.assert_history(self.repo)

    def test_conflict_continue_requires_staged_resolution(self):
        self.conflict()
        self.run_sync("--continue", expected=1)
        (self.repo / "code.txt").write_text("resolved change\n")
        self.run_sync("--continue", expected=1)
        self.git(self.repo, "add", "code.txt")
        self.run_sync("--continue")
        self.assertEqual((self.repo / "code.txt").read_text(), "resolved change\n")
        self.assert_history(self.repo)

    def test_fresh_clone_can_sync_without_extra_refs(self):
        self.advance()
        self.run_sync()
        clone = self.root / "fresh-clone"
        subprocess.run(["git", "clone", "-q", "--no-local", str(self.repo), str(clone)], check=True)
        self.git(clone, "config", "user.name", "Test Author")
        self.git(clone, "config", "user.email", "test@example.com")
        self.advance("new.txt", "from fresh clone\n")
        self.run_sync(repo=clone)
        self.assertEqual((clone / "new.txt").read_text(), "from fresh clone\n")
        self.assert_history(clone)

    def test_fetch_failure_keeps_worktree_and_baseline(self):
        self.metadata["repository"] = (self.root / "missing").as_uri()
        (self.repo / "UPSTREAM").write_text(json.dumps(self.metadata) + "\n")
        head = self.commit(self.repo, "Use missing upstream")
        self.run_sync(expected=1)
        self.assertEqual(self.git(self.repo, "rev-parse", "HEAD"), head)
        self.assert_history(self.repo)


if __name__ == "__main__":
    unittest.main(verbosity=2)
