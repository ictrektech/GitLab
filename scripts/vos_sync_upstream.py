#!/usr/bin/env python3
"""Merge a shallow upstream snapshot without importing upstream history."""

import argparse
import fcntl
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile


INCOMING_REF = "refs/vos/upstream-incoming"


def git(root, *args, input=None, capture=True, check=True):
    return subprocess.run(
        ["git", "-C", str(root), *args], input=input, text=True,
        stdout=subprocess.PIPE if capture else None,
        stderr=subprocess.PIPE if capture else None, check=check,
    )


def value(root, *args):
    return git(root, *args).stdout.strip()


def save(path, data):
    path.write_text(json.dumps(data, indent=2) + "\n")


def exists(root, ref):
    return git(root, "rev-parse", "--verify", "--quiet", ref, check=False).returncode == 0


def finish(root, pending_path, pending):
    if value(root, "rev-parse", "HEAD") != pending["start_head"]:
        raise RuntimeError("HEAD changed during sync. Inspect the pending merge before continuing.")
    if not exists(root, "MERGE_HEAD"):
        raise RuntimeError("No pending Git merge. Use --abort to clear an unsuccessful sync.")
    if value(root, "rev-parse", "MERGE_HEAD") != pending["upstream"]["snapshot_commit"]:
        raise RuntimeError("MERGE_HEAD does not match the pending upstream snapshot.")
    if value(root, "diff", "--name-only", "--diff-filter=U"):
        raise RuntimeError("Resolve conflicts and git add each resolution, then run --continue.")
    if value(root, "diff", "--name-only"):
        raise RuntimeError("Stage all conflict resolutions with git add before --continue.")
    save(root / "UPSTREAM", pending["upstream"])
    git(root, "add", "--", "UPSTREAM")
    sha = pending["upstream"]["commit"]
    git(root, "commit", "-m", f"Merge upstream GitLab snapshot {sha[:12]}", capture=False)
    git(root, "update-ref", "-d", INCOMING_REF)
    pending_path.unlink()
    print(f"Updated to upstream {sha}. Review and test before pushing.")


def synchronize(root, args):
    metadata = root / "UPSTREAM"
    git_dir = Path(value(root, "rev-parse", "--absolute-git-dir"))
    pending_path = git_dir / "vos-upstream-sync.json"
    if args.continue_sync or args.abort:
        if not pending_path.exists():
            raise RuntimeError("No upstream sync is pending.")
        pending = json.loads(pending_path.read_text())
        if args.continue_sync:
            finish(root, pending_path, pending)
        else:
            if value(root, "rev-parse", "HEAD") != pending["start_head"]:
                raise RuntimeError("HEAD changed. Refusing to abort over a new commit.")
            if exists(root, "MERGE_HEAD"):
                git(root, "merge", "--abort", capture=False)
            elif value(root, "status", "--porcelain"):
                raise RuntimeError("No Git merge exists and the worktree is dirty. Inspect it first.")
            git(root, "update-ref", "-d", INCOMING_REF)
            pending_path.unlink()
            print("Upstream sync aborted. The previous baseline is unchanged.")
        return
    if pending_path.exists():
        raise RuntimeError("A sync is pending. Use --continue or --abort.")
    if not value(root, "symbolic-ref", "--quiet", "--short", "HEAD"):
        raise RuntimeError("Check out a development branch before syncing.")
    if value(root, "status", "--porcelain"):
        raise RuntimeError("Commit or stash local changes before syncing.")
    for marker in ("MERGE_HEAD", "CHERRY_PICK_HEAD", "REVERT_HEAD", "rebase-merge", "rebase-apply"):
        if (git_dir / marker).exists():
            raise RuntimeError("Finish the current Git operation before syncing.")
    baseline = json.loads(metadata.read_text())
    old_snapshot = baseline["snapshot_commit"]
    if value(root, "rev-parse", f"{old_snapshot}^{{tree}}") != baseline["tree"]:
        raise RuntimeError("UPSTREAM does not match the saved snapshot tree.")
    git(root, "merge-base", "--is-ancestor", old_snapshot, "HEAD")
    if args.check:
        latest = value(root, "ls-remote", "--exit-code", "--", baseline["repository"],
                       f"refs/heads/{baseline['branch']}").split()[0]
        print(f"Baseline: {baseline['commit']}\nLatest:   {latest}")
        print("Already up to date." if latest == baseline["commit"] else
              "An upstream update is available. No local files were changed.")
        return
    start_head = value(root, "rev-parse", "HEAD")
    build_root = Path(os.environ.get("VOS_UPSTREAM_BUILD_ROOT", str(Path.home() / "dev/build/gitlab-upstream")))
    build_root.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="fetch-", dir=build_root) as directory:
        temporary = Path(directory)
        git(temporary, "init", "--bare", "--quiet")
        # Reuse local source objects while the temporary repo exists.
        objects = Path(value(root, "rev-parse", "--git-path", "objects"))
        if not objects.is_absolute():
            objects = root / objects
        (temporary / "objects/info/alternates").write_text(str(objects.resolve()) + "\n")
        print(f"Fetching {baseline['branch']} with --depth=1 and --no-tags...", flush=True)
        git(temporary, "fetch", "--depth=1", "--no-tags", "--no-recurse-submodules",
            "--", baseline["repository"], f"refs/heads/{baseline['branch']}", capture=False)
        upstream_commit = value(temporary, "rev-parse", "FETCH_HEAD")
        print(f"Baseline: {baseline['commit']}\nLatest:   {upstream_commit}")
        if upstream_commit == baseline["commit"]:
            print("Already up to date.")
            return
        tree = value(temporary, "rev-parse", "FETCH_HEAD^{tree}")
        message = f"Import upstream GitLab snapshot {upstream_commit[:12]}\n\nUpstream-Commit: {upstream_commit}\n"
        # Parent only the previous synthetic snapshot, never the real upstream commit.
        author_env = {**os.environ,
                      "GIT_AUTHOR_NAME": value(root, "config", "user.name"),
                      "GIT_AUTHOR_EMAIL": value(root, "config", "user.email"),
                      "GIT_COMMITTER_NAME": value(root, "config", "user.name"),
                      "GIT_COMMITTER_EMAIL": value(root, "config", "user.email")}
        snapshot_commit = subprocess.check_output(
            ["git", "-C", str(temporary), "commit-tree", tree, "-p", old_snapshot],
            input=message, text=True, env=author_env,
        ).strip()
        git(temporary, "update-ref", "refs/heads/snapshot", snapshot_commit)
        git(root, "fetch", "--no-tags", "--no-write-fetch-head", "--no-recurse-submodules",
            str(temporary), f"refs/heads/snapshot:{INCOMING_REF}", capture=False)
    updated = {**baseline, "commit": upstream_commit, "tree": tree, "snapshot_commit": snapshot_commit}
    pending = {"start_head": start_head, "upstream": updated}
    save(pending_path, pending)
    result = git(root, "merge", "--no-ff", "--no-commit", snapshot_commit, capture=False, check=False)
    if result.returncode:
        raise RuntimeError("Sync paused. Resolve conflicts, git add, and run --continue, or run --abort.")
    finish(root, pending_path, pending)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    group = parser.add_mutually_exclusive_group()
    group.add_argument("--check", action="store_true", help="Check the latest upstream commit without merging")
    group.add_argument("--continue", dest="continue_sync", action="store_true", help="Commit a resolved sync merge")
    group.add_argument("--abort", action="store_true", help="Abort the pending sync merge")
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    try:
        git_dir = Path(value(root, "rev-parse", "--absolute-git-dir"))
        with (git_dir / "vos-upstream-sync.lock").open("a") as lock:
            try:
                fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError:
                raise RuntimeError("Another upstream sync is running.") from None
            synchronize(root, args)
    except (RuntimeError, subprocess.CalledProcessError, OSError, KeyError, ValueError) as error:
        print(f"Error: {error}", file=sys.stderr)
        if isinstance(error, subprocess.CalledProcessError) and error.stderr:
            print(error.stderr.strip(), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
