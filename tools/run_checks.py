"""Run portable Lua logic checks; this does not exercise native macOS automation.

Development dependency only: Python 3.10+ and ``lupa`` with its Lua 5.4 module.
Neither Python nor lupa is required to use the controller in Hammerspoon.
Install lupa into an isolated environment, or pass --lua-python-path to a local
directory installed with ``python -m pip install --target DIR lupa``.
"""
from __future__ import annotations

import argparse
import csv
import hashlib
import importlib
import json
from pathlib import Path
import shutil
import sys
import tempfile
from typing import Any


def main() -> int:
    package = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua-python-path", type=Path,
                        default=package / ".dev-cache" / "python")
    parser.add_argument("--report", type=Path,
                        default=package / "docs" / "LOCAL_CHECKS.json")
    parser.add_argument("--export-examples", type=Path,
                        help="Copy the successful group-1 dummy session to a new directory.")
    parser.add_argument("--suite", action="append", choices=["model", "integration", "controller"],
                        help="Defaults to model/integration and controller when present.")
    parser.add_argument("--verbose", action="store_true")
    args = parser.parse_args()
    if args.lua_python_path.exists():
        sys.path.insert(0, str(args.lua_python_path.resolve()))
    try:
        lua54 = importlib.import_module("lupa.lua54")
    except ImportError:
        print("Checks require the development-only lupa package with Lua 5.4.", file=sys.stderr)
        print("Install it in an isolated environment or use --lua-python-path DIR.", file=sys.stderr)
        return 2

    suites = args.suite or (["model", "integration"] +
                            (["controller"] if (package / 'tests/controller_spec.lua').is_file() else []))
    temp_parent = package / ".dev-cache"
    temp_parent.mkdir(parents=True, exist_ok=True)
    messages: list[str] = []
    results: list[dict[str, Any]] = []
    syntax: list[dict[str, Any]] = []
    exported = None

    with tempfile.TemporaryDirectory(prefix="hci-controller-tests-", dir=temp_parent) as temp_name:
        test_root = Path(temp_name).resolve()

        def allowed_path(value: str) -> bool:
            return Path(value).resolve().is_relative_to(test_root)

        def checked_path(value: str) -> Path:
            path = Path(value).resolve()
            if not path.is_relative_to(test_root):
                raise ValueError(f"Test filesystem access outside temporary root: {path}")
            return path

        def build_runtime():
            runtime = lua54.LuaRuntime(unpack_returned_tuples=True)

            def to_python(value: Any) -> Any:
                if lua54.lua_type(value) == "table":
                    pairs = list(value.items())
                    keys = [key for key, _ in pairs]
                    if keys and all(isinstance(k, (int, float)) and k == int(k) for k in keys):
                        numbered = sorted(int(k) for k in keys)
                        if numbered == list(range(1, len(keys) + 1)):
                            return [to_python(value[index]) for index in numbered]
                    return {str(key): to_python(item) for key, item in pairs}
                return value

            def to_lua(value: Any) -> Any:
                if isinstance(value, dict):
                    return runtime.table_from({key: to_lua(item) for key, item in value.items()})
                if isinstance(value, list):
                    return runtime.table_from([to_lua(item) for item in value])
                return value

            def attributes(value: str):
                path = checked_path(value)
                if not path.exists():
                    return None
                return to_lua({"mode": "directory" if path.is_dir() else "file",
                               "size": path.stat().st_size})

            def mkdir(value: str):
                try:
                    checked_path(value).mkdir()
                    return True
                except OSError as error:
                    return None, str(error)

            def rmdir(value: str):
                try:
                    checked_path(value).rmdir()
                    return True
                except OSError as error:
                    return None, str(error)

            def encode(value: Any, pretty: bool = False) -> str:
                return json.dumps(to_python(value), indent=2 if pretty else None,
                                  ensure_ascii=False, allow_nan=False)

            def decode(value: str):
                try:
                    return to_lua(json.loads(value))
                except (ValueError, TypeError):
                    return None

            def csv_rows(value: str):
                with checked_path(value).open(encoding="utf-8-sig", newline="") as stream:
                    return to_lua(list(csv.DictReader(stream)))

            def find_csv(value: str, columns: Any):
                required = list(to_python(columns))
                for path in sorted(checked_path(value).rglob("*.csv")):
                    with path.open(encoding="utf-8-sig", newline="") as stream:
                        header = next(csv.reader(stream), [])
                    if all(column in header for column in required):
                        return path.as_posix()
                return None

            def write_file(value: str, text: str):
                checked_path(value).write_text(text, encoding="utf-8")
                return True

            def read_file(value: str):
                return checked_path(value).read_text(encoding="utf-8")

            def files(value: str):
                return to_lua([path.as_posix() for path in sorted(checked_path(value).rglob("*"))
                               if path.is_file()])

            globals_ = runtime.globals()
            globals_.PACKAGE_ROOT = package.as_posix()
            globals_.TEST_ROOT = test_root.as_posix()
            globals_.TEST_BRIDGE = runtime.table_from({
                "attributes": attributes, "mkdir": mkdir, "rmdir": rmdir,
                "json_encode": encode, "json_decode": decode,
                "csv_rows": csv_rows, "find_csv": find_csv,
                "write_file": write_file, "read_file": read_file,
                "files": files, "allowed_path": allowed_path,
            })
            globals_.print = lambda *values: messages.append(" ".join(map(str, values)))
            runtime.execute(r'''
                package.path = PACKAGE_ROOT .. "/?.lua;" .. PACKAGE_ROOT .. "/?/init.lua;" .. package.path
                local originalOpen, originalRemove, originalRename = io.open, os.remove, os.rename
                io.open = function(path, mode)
                    mode = mode or "r"
                    if mode:find("[wa+]") and not TEST_BRIDGE.allowed_path(path) then
                        return nil, "Test write blocked outside temporary root"
                    end
                    if TEST_FAIL_OPEN_PREFIX and mode:find("[wa+]")
                        and path:sub(1, #TEST_FAIL_OPEN_PREFIX) == TEST_FAIL_OPEN_PREFIX then
                        return nil, "Injected write failure"
                    end
                    return originalOpen(path, mode)
                end
                os.remove = function(path)
                    if not TEST_BRIDGE.allowed_path(path) then return nil, "Test removal blocked" end
                    return originalRemove(path)
                end
                os.rename = function(old, new)
                    if not TEST_BRIDGE.allowed_path(old) or not TEST_BRIDGE.allowed_path(new) then
                        return nil, "Test rename blocked"
                    end
                    return originalRename(old, new)
                end
            ''')
            return runtime, to_python

        checker, _ = build_runtime()
        loader = checker.eval("function(source, name) local fn, err = load(source, name); return fn ~= nil, err end")
        for path in sorted(package.rglob("*.lua")):
            ok, error = loader(path.read_text(encoding="utf-8-sig"), path.relative_to(package).as_posix())
            syntax.append({"file": path.relative_to(package).as_posix(), "passed": bool(ok),
                           "error": error})

        for suite in suites:
            runtime, convert = build_runtime()
            spec = package / "tests" / f"{suite}_spec.lua"
            if not spec.is_file():
                results.append({"suite": suite, "passed": False, "error": "Suite file missing"})
                continue
            try:
                returned = runtime.execute(spec.read_text(encoding="utf-8-sig"), name=spec.as_posix())
                value = convert(returned)
                if isinstance(value, list):
                    failures = [case for case in value if not case.get("passed")]
                    results.append({"suite": suite, "passed": not failures,
                                    "case_count": len(value), "cases": value})
                else:
                    results.append({"suite": suite, "passed": True, "case_count": int(value)})
            except Exception as error:
                results.append({"suite": suite, "passed": False, "error": str(error)})

        if args.export_examples is not None:
            if not all(item["passed"] for item in syntax + results):
                print("Examples not exported because the checks failed.")
            elif not (test_root / "full-24-group-1").is_dir():
                results.append({"suite": "example_export", "passed": False,
                                "error": "Run the integration suite before exporting a dummy session."})
            elif args.export_examples.exists():
                results.append({"suite": "example_export", "passed": False,
                                "error": "Example destination already exists; choose a new path to preserve it."})
            else:
                shutil.copytree(test_root / "full-24-group-1", args.export_examples,
                                ignore=shutil.ignore_patterns("*.previous-*", "*.tmp-*"))
                (args.export_examples / "SIMULATED_TEST_DATA.md").write_text(
                    "# Simulated test records\n\n"
                    "These records were generated by portable Lua integration tests.\n"
                    "They are not participant results and must not enter the study dataset.\n"
                    "The fixture runs all 24 scheduled group-1 entries in test mode,\n"
                    "with artificial timings/counts. Final video-coded measures are blank.\n"
                    "No real Mac, Chrome, Hammerspoon input hooks or OBS recording was used.\n",
                    encoding="utf-8")
                exported = str(args.export_examples.resolve())

    passed = all(item["passed"] for item in syntax + results)
    report = {
        "passed": passed,
        "runtime": "Lua 5.4 via development-only Python lupa",
        "package_root": str(package), "syntax": syntax, "suites": results,
        "exported_simulated_examples": exported,
        "native_macos_tested": False,
        "limitations": ["No real Chrome tabs, Hammerspoon APIs, input hooks or OBS capture were exercised.",
                        "Passing portable checks does not establish study-device readiness."],
        "source_hashes": {path.relative_to(package).as_posix(): hashlib.sha256(path.read_bytes()).hexdigest()
                          for path in sorted(package.rglob("*.lua"))},
    }
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(report, indent=2), encoding="utf-8")
    print(f"Lua syntax: {sum(item['passed'] for item in syntax)}/{len(syntax)} passed")
    for suite in results:
        print(f"{suite['suite']}: {'PASS' if suite['passed'] else 'FAIL'}"
              + (f" ({suite['case_count']} cases)" if 'case_count' in suite else ''))
        if not suite["passed"]:
            if "error" in suite:
                print(suite["error"])
            for case in suite.get("cases", []):
                if not case["passed"]:
                    print(case["name"] + ": " + case.get("error", "Unknown failure"))
    if args.verbose:
        print("\n".join(messages))
    print(f"Report: {args.report.resolve()}")
    print("Native macOS / Chrome / OBS validation remains required.")
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
