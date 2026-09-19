#!/usr/bin/env python3
"""Offline repository consistency checks; not a complete Actions/YAML validator."""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path
from urllib.parse import unquote, urlsplit

from check_reference_target import validate_target
from traceability_report import build_report


def push_cancellation_errors(name: str, text: str) -> list[str]:
    """Reject a workflow that cancels superseded pushes.

    Cancellation is keyed on the concurrency group, and a push's group is its
    ref, so an unconditional `cancel-in-progress` cancels `main` exactly as it
    cancels a pull request. A push to `main` carries the merged tree and is the
    last opportunity to compile it, so merging faster than one native build
    otherwise leaves the merged result never built while the required check
    still reports success.
    """
    if not re.search(r"(?m)^\s{2}push:\s*$", text):
        return []
    if re.search(r"(?m)^\s*cancel-in-progress:\s*true\s*$", text):
        return [f"Workflow cancels superseded pushes in {name}: scope cancel-in-progress to "
                "pull requests so a merged tree is always compiled"]
    return []

ROOT = Path(__file__).resolve().parents[1]
IGNORED = {".git", ".build", ".venv-fixtures", ".swiftpm", "__pycache__", "local-private", "build-logs", "artifacts", "dist"}
REQUIRED = (
    "docs/ACCELERATOR.md", "scripts/run-accelerator-checks.py",
    "Fixtures/generated/manifest.json",
    "START-HERE.md", "README.md", "AGENTS.md", "EPIC.md", "LICENSE", "SECURITY.md",
    "CONTRIBUTING.md", "docs/ARCHITECTURE.md", "docs/CONTRACTS.md",
    "docs/VALIDATION-PLAN.md", "docs/REFERENCES.md", "docs/PROGRESS.json",
    "docs/requirements.json", "docs/milestones.json",
    "docs/ACCEPTANCE-EVIDENCE.json", "scripts/traceability_report.py",
    # CI runs both diagnostics below. One that has gone missing must fail here rather than
    # vanish from the build as a silently skipped step.
    "scripts/evidence_currency.py", "scripts/manifest_audit.py", "MANIFEST.sha256",
    # The manifest is enforced, so the one command that refreshes it must not vanish:
    # a contributor without it pays the coverage tax by hand, which is how drift returns.
    "scripts/refresh_manifest.py",
    "docs/adr/0004-manifest-integrity-scope.md",
    "docs/SPRINT-BASELINE.md", "docs/reference-target.json", "docs/LOCAL-SIGNING.md",
    "docs/RELEASE-SCOPES.md", "docs/SCOPE-STATUS.json", "docs/hardware/GC420D.md",
    "scripts/host-preflight.sh", "scripts/sign-local-diagnostic.sh",
    "Packages/LabelCore/Package.swift", "Packages/LabelMac/Package.swift",
    ".github/workflows/ci.yml", ".github/workflows/compatibility.yml",
)


def files_under(root: Path):
    for path in root.rglob("*"):
        relative = path.relative_to(root)
        if any(part in IGNORED for part in relative.parts):
            continue
        if path.is_symlink():
            yield path
        elif path.is_file():
            yield path


def markdown_links(text: str):
    """Extract simple inline destinations outside fenced examples."""
    text = re.sub(r"(?ms)^```.*?^```[^\n]*", "", text)
    for match in re.finditer(r"!?\[[^\]]*\]\(([^)]+)\)", text):
        yield match.group(1).strip().split(' "', 1)[0].strip("<>")


def check(root: Path) -> list[str]:
    root = root.resolve()
    errors: list[str] = []
    for name in REQUIRED:
        if not (root / name).is_file():
            errors.append(f"Missing required file: {name}")
    for path in files_under(root):
        name = str(path.relative_to(root))
        if path.is_symlink():
            errors.append(f"Review/remove unexpected repository symlink: {name}")
            continue
        if path.suffix not in {".md", ".json", ".yml", ".yaml", ".swift", ".py", ".sh"}:
            continue
        try:
            text = path.read_text(encoding="utf-8")
        except (OSError, UnicodeError) as exc:
            errors.append(f"Unreadable UTF-8 file {name}: {exc}")
            continue
        if not text.endswith("\n"):
            errors.append(f"Missing final newline: {name}")
        if path.suffix == ".json":
            try:
                json.loads(text)
            except json.JSONDecodeError as exc:
                errors.append(f"Invalid JSON {name}: {exc}")
        if path.suffix == ".md":
            for link in markdown_links(text):
                split = urlsplit(link)
                if split.scheme or split.netloc or link.startswith("#"):
                    continue
                target = (path.parent / unquote(split.path)).resolve()
                if not target.is_relative_to(root):
                    errors.append(f"Relative link escapes repo in {name}: {link}")
                elif not target.exists():
                    errors.append(f"Broken relative link in {name}: {link}")
                elif re.fullmatch(r"r\d{2}", split.fragment) and target.is_file():
                    if f'id="{split.fragment}"' not in target.read_text(encoding="utf-8"):
                        errors.append(f"Missing reference anchor in {name}: {link}")
        if path.parent == root / ".github/workflows":
            for use in re.findall(r"(?m)^\s*(?:-\s*)?uses:\s*([^\s#]+)", text):
                if not use.startswith("./") and not re.fullmatch(r"[^@]+@[0-9a-f]{40}", use):
                    errors.append(f"Action must be SHA-pinned in {name}: {use}")
            for forbidden in ("pull_request_target:", "self-hosted", "-xlarge", "-large"):
                if forbidden in text:
                    errors.append(f"Review forbidden workflow configuration in {name}: {forbidden}")
            errors.extend(push_cancellation_errors(name, text))
    try:
        errors.extend(validate_target(json.loads((root / "docs/reference-target.json").read_text())))
        for package in ("LabelCore", "LabelMac"):
            manifest = (root / f"Packages/{package}/Package.swift").read_text()
            if 'platforms: [.macOS("26.0")]' not in manifest:
                errors.append(f"{package}: expected confirmed 26.0 minimum deployment declaration")
        for workflow in ("ci.yml", "compatibility.yml"):
            content = (root / ".github/workflows" / workflow).read_text()
            if re.search(r"macos-(?:13|14|15)(?:[-\s,\]]|$)", content):
                errors.append(f"Older macOS runner outside baseline: {workflow}")
            if "macos-26" not in content:
                errors.append(f"Expected Tahoe native runner: {workflow}")
        scoped = json.loads((root / "docs/SCOPE-STATUS.json").read_text())["scopes"]
        if {item["id"] for item in scoped} != {"S1-GC420d-local", "S2-broader-parity", "S3-trusted-public-binaries"}:
            errors.append("Scope status identifiers changed or are incomplete")
        for item in scoped:
            if item["state"] not in {"not-run", "in-progress", "pass", "fail", "blocked", "deferred"}:
                errors.append(f"Invalid scope state: {item['id']}")
            if item["state"] == "pass" and not item["evidence"]:
                errors.append(f"Scope pass without evidence: {item['id']}")
        milestones = json.loads((root / "docs/milestones.json").read_text())
        expected = {f"M{item['n']}" for item in milestones}
        acceptance = set()
        for item in milestones:
            base = root / "docs/milestones" / item["slug"]
            for leaf in ("SPEC.md", "ACCEPTANCE.md", "INSTRUCTIONS.md", "VALIDATION.md"):
                if not (base / leaf).is_file():
                    errors.append(f"Missing milestone document: {base.name}/{leaf}")
            acceptance.update(f"M{item['n']}-AC{i:02d}" for i in range(1, len(item["criteria"]) + 1))
            view = (base / "ACCEPTANCE.md").read_text()
            found = re.findall(r"\| \[[ xX]\] \| (M\d-AC\d+) \|", view)
            expected_ids = [f"M{item['n']}-AC{i:02d}" for i in range(1, len(item["criteria"]) + 1)]
            if found != expected_ids:
                errors.append(f"Acceptance view/metadata mismatch: {item['slug']}")
            for _, _, description in item["criteria"]:
                if description not in view:
                    errors.append(f"Acceptance wording out of sync: {item['slug']}")
        progress = json.loads((root / "docs/PROGRESS.json").read_text())
        ids = [item["id"] for item in progress["milestones"]]
        if set(ids) != expected or len(ids) != len(set(ids)):
            errors.append("Progress milestone IDs are missing, duplicated or unexpected")
        implementation_states = {"not-started", "in-progress", "complete", "blocked"}
        validation_states = {"not-run", "pass", "fail", "blocked", "not-applicable"}
        for item in progress["milestones"]:
            if item["implementation"] not in implementation_states:
                errors.append(f"Invalid implementation state: {item['id']}")
            if not (root / item["directory"]).is_dir():
                errors.append(f"Invalid milestone directory: {item['id']}")
            for key in ("automatedValidation", "macOSIntegration", "hardwareValidation", "releaseValidation"):
                if item[key] not in validation_states:
                    errors.append(f"Invalid {key} state: {item['id']}")
                if item[key] == "pass" and not item["evidence"]:
                    errors.append(f"Pass without evidence references: {item['id']} {key}")
        requirements = json.loads((root / "docs/requirements.json").read_text())["requirements"]
        seen = set()
        for item in requirements:
            if item["id"] in seen:
                errors.append(f"Duplicate requirement: {item['id']}")
            seen.add(item["id"])
            if not item["acceptanceIDs"]:
                errors.append(f"Requirement has no acceptance mapping: {item['id']}")
            for identifier in item["acceptanceIDs"]:
                if identifier not in acceptance:
                    errors.append(f"Unknown acceptance ID: {identifier}")
        # Validate schema/references, never manufacture a current qualification
        # from preflight. The CLI independently binds the actual source/worktree.
        build_report(root, "0" * 40, workspace_dirty=True)
    except (OSError, KeyError, TypeError, ValueError, RecursionError, UnicodeError) as exc:
        errors.append(f"Cannot validate project metadata: {exc}")
    return errors


def main() -> int:
    errors = check(ROOT)
    if errors:
        for error in errors:
            print(f"ERROR: {error}", file=sys.stderr)
        return 1
    print("Repository preflight passed (links, metadata, milestone files, action pins).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
