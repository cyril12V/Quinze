#!/usr/bin/env python3
"""Type-checks and unit-tests the Foundation-only part of the iOS app on Linux.

The iOS app cannot be compiled outside macOS, but the files that only depend on Foundation
(shared App Group state, restriction slot engine, slot logic, sync DTOs, AI models, tutor fallback)
can. This script builds a throwaway SwiftPM package from those files (symlinked, not copied), adds
the few value types they need from Apple-dependent files (extracted verbatim) plus two Linux shims,
and runs the matching XCTest files.

Usage: python3 tools/linux_app_check.py [--keep DIR]
Requires the Swift toolchain (source /opt/swiftlang/env.sh, or swift on PATH).
"""
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

SOURCES = [
    "Shared/AppGroup.swift", "Shared/ScreenTimeNames.swift", "Shared/SharedState.swift",
    "Shared/SharedStateStore.swift", "Shared/SlotEngine.swift",
    "App/Sources/Services/AIModels.swift", "App/Sources/Services/Records.swift",
    "App/Sources/Services/SlotLogic.swift", "App/Sources/Services/SyncDTO.swift",
    "App/Sources/Services/TutorFallback.swift",
]
TESTS = [
    "App/Tests/ScreenTime/SharedStateTests.swift", "App/Tests/ScreenTime/SlotEngineTests.swift",
    "App/Tests/Services/SlotLogicTests.swift", "App/Tests/Services/SyncDTOTests.swift",
    "App/Tests/Services/ServiceModelsTests.swift",
]
# (file, start marker, end marker or None = up to the first top-level "}\n" after start)
EXTRACTS = [
    ("Shared/ShieldController.swift", "protocol ShieldControlling", None),
    ("App/Sources/ScreenTime/RestrictionManager.swift", "enum RestrictionMode", None),
    ("App/Sources/ScreenTime/RestrictionManager.swift", "extension RestrictionMode", None),
    ("App/Sources/Core/TutorService.swift", "enum TutorDetail", "@MainActor"),
    ("App/Sources/Core/LearningStore.swift", "enum SlotStatus", "@MainActor"),
]

SHIMS = """// Linux-only shims for Apple APIs (type-checking harness, never shipped).
import Foundation
import LearningCore
import LearningPrimitives

#if os(Linux)
struct SystemShieldController: ShieldControlling {
    func apply(slot: SessionSlot, selectionData: Data?, mode: StoredMode) -> Bool { false }
    func clear(slot: SessionSlot) {}
}

extension FileManager {
    func containerURL(forSecurityApplicationGroupIdentifier groupIdentifier: String) -> URL? { nil }
}
#endif
"""


def extract(path, start, end):
    src = (ROOT / path).read_text(encoding="utf-8")
    i = src.index(start)
    j = src.index(end, i) if end else src.index("\n}\n", i) + 3
    return f"\n// ---- extracted from {path} ----\n" + src[i:j]


def main():
    keep = None
    if "--keep" in sys.argv:
        keep = Path(sys.argv[sys.argv.index("--keep") + 1])
    work = keep or Path(tempfile.mkdtemp(prefix="quinze-linux-"))
    if work.exists():
        shutil.rmtree(work)
    (work / "Sources/Quinze").mkdir(parents=True)
    (work / "Tests/QuinzeTests").mkdir(parents=True)
    for f in SOURCES:
        os.symlink(ROOT / f, work / "Sources/Quinze" / Path(f).name)
    for f in TESTS:
        os.symlink(ROOT / f, work / "Tests/QuinzeTests" / Path(f).name)
    (work / "Sources/Quinze/LinuxShims.swift").write_text(
        SHIMS + "".join(extract(*e) for e in EXTRACTS), encoding="utf-8")
    (work / "Package.swift").write_text(f"""// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "QuinzeLinuxCheck",
    platforms: [.macOS(.v14)],
    dependencies: [.package(path: "{ROOT / 'Packages/LearningCore'}")],
    targets: [
        .target(name: "Quinze", dependencies: [
            .product(name: "LearningCore", package: "LearningCore"),
            .product(name: "LearningPrimitives", package: "LearningCore")]),
        .testTarget(name: "QuinzeTests", dependencies: ["Quinze"]),
    ]
)
""", encoding="utf-8")
    code = subprocess.call(["swift", "test"], cwd=work)
    if not keep:
        shutil.rmtree(work, ignore_errors=True)
    sys.exit(code)


if __name__ == "__main__":
    main()
