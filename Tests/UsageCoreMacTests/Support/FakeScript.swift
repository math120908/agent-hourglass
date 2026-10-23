import Foundation

/// Shell prologue for fake executables: `--warmup` exits before the script body runs.
let fakeScriptWarmupGuard = "[ \"$1\" = --warmup ] && exit 0\n"

/// The first exec of a freshly written script pays a one-off macOS policy scan (~0.3 s idle,
/// multiple seconds under load). Pay it up front so tests measure the code under test, not that
/// scan. The script must start with `fakeScriptWarmupGuard` so the warm-up has no side effects.
func warmUpFakeScript(at path: String) throws {
    let warm = Process()
    warm.executableURL = URL(fileURLWithPath: path)
    warm.arguments = ["--warmup"]
    try warm.run()
    warm.waitUntilExit()
}
