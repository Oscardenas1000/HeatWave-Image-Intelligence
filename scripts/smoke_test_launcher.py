#!/usr/bin/env python3
from __future__ import annotations

import os
import shlex
import signal
import socket
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
LAUNCHER = REPO_ROOT / "run_heatwave_image_intelligence.command"
FIXTURE_IMAGE = REPO_ROOT / "BluebonnetLonghorn.png"
PACKAGE_APP_PROCESS_NAME = "HeatWaveImageIntelligenceMac"
BUNDLE_APP_PROCESS_NAME = "HeatWaveImageIntelligenceMacApp"

WAIT_FOR_WINDOW_SCRIPT = r"""
on run argv
    set processName to item 1 of argv

    tell application "System Events"
        repeat with _ from 1 to 240
            if exists process processName then
                tell process processName
                    if (count of windows) > 0 then return "ok"
                end tell
            end if
            delay 0.5
        end repeat
    end tell

    error "Timed out waiting for the launcher-started app window."
end run
"""

QUIT_SCRIPT = r"""
on run argv
    set processName to item 1 of argv

    tell application "System Events"
        if exists process processName then
            tell process processName to set frontmost to true
            keystroke "q" using command down
        end if
    end tell

    return "ok"
end run
"""


def pick_free_port() -> int:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        sock.bind(("127.0.0.1", 0))
        return sock.getsockname()[1]


def wait_for_json_endpoint(url: str, timeout_seconds: int) -> str:
    deadline = time.time() + timeout_seconds

    while time.time() < deadline:
        try:
            with urllib.request.urlopen(url, timeout=1.5) as response:
                if response.status == 200:
                    return response.read().decode("utf-8", errors="replace")
        except (OSError, urllib.error.URLError):
            pass
        time.sleep(0.5)

    raise RuntimeError(f"Timed out waiting for {url}")


def run_osascript(script: str, *args: str) -> str:
    result = subprocess.run(
        ["osascript", "-", *args],
        input=script,
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode != 0:
        stderr = result.stderr.strip() or result.stdout.strip()
        raise RuntimeError(f"UI automation failed: {stderr}")
    return result.stdout.strip()


def existing_process_running(process_name: str) -> bool:
    result = subprocess.run(
        [
            "osascript",
            "-e",
            f'tell application "System Events" to return exists process "{process_name}"',
        ],
        capture_output=True,
        text=True,
        check=False,
    )
    return result.returncode == 0 and result.stdout.strip().lower() == "true"


def quit_existing_app(process_name: str, timeout_seconds: int = 15) -> None:
    if not existing_process_running(process_name):
        return

    run_osascript(QUIT_SCRIPT, process_name)

    deadline = time.time() + timeout_seconds
    while time.time() < deadline:
        if not existing_process_running(process_name):
            return
        time.sleep(0.5)

    subprocess.run(
        ["pkill", "-x", process_name],
        capture_output=True,
        text=True,
        check=False,
    )

    deadline = time.time() + 10
    while time.time() < deadline:
        if not existing_process_running(process_name):
            return
        time.sleep(0.5)

    raise RuntimeError(f"Could not close the existing {process_name} process before smoke testing.")


def tail_text(path: Path, limit: int = 80) -> str:
    if not path.exists():
        return "<missing>"
    lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
    return "\n".join(lines[-limit:])


def wait_for_text_in_file(path: Path, expected_text: str, timeout_seconds: int) -> None:
    deadline = time.time() + timeout_seconds

    while time.time() < deadline:
        if path.exists():
            text = path.read_text(encoding="utf-8", errors="replace")
            if expected_text in text:
                return
        time.sleep(0.5)

    raise RuntimeError(f"Timed out waiting for {expected_text!r} to appear in {path}")


def wait_for_process_to_stop(process_name: str, timeout_seconds: int) -> bool:
    deadline = time.time() + timeout_seconds
    while time.time() < deadline:
        if not existing_process_running(process_name):
            return True
        time.sleep(0.5)
    return not existing_process_running(process_name)


def force_quit_process(process_name: str) -> None:
    subprocess.run(
        ["pkill", "-x", process_name],
        capture_output=True,
        text=True,
        check=False,
    )


def cleanup_process(process: subprocess.Popen[str] | None) -> None:
    if process is None or process.poll() is not None:
        return

    try:
        os.killpg(process.pid, signal.SIGTERM)
    except ProcessLookupError:
        return

    try:
        process.wait(timeout=10)
    except subprocess.TimeoutExpired:
        try:
            os.killpg(process.pid, signal.SIGKILL)
        except ProcessLookupError:
            return
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            return


def main() -> int:
    use_built_app = "--built-app" in sys.argv[1:]
    app_process_name = BUNDLE_APP_PROCESS_NAME if use_built_app else PACKAGE_APP_PROCESS_NAME

    if not LAUNCHER.exists():
        raise SystemExit(f"Launcher not found: {LAUNCHER}")
    if not FIXTURE_IMAGE.exists():
        raise SystemExit(f"Fixture image not found: {FIXTURE_IMAGE}")

    port = pick_free_port()
    base_url = f"http://127.0.0.1:{port}"
    run_stamp = f"launcher-smoke-{time.strftime('%Y%m%dT%H%M%SZ', time.gmtime())}"

    launcher_log_file = tempfile.NamedTemporaryFile(
        prefix="heatwave-launcher-smoke-",
        suffix=".log",
        delete=False,
    )
    launcher_log_file.close()
    launcher_log = Path(launcher_log_file.name)

    env = os.environ.copy()
    env.update(
        {
            "HEATWAVE_BACKEND_PORT": str(port),
            "HEATWAVE_BUILD_STAMP": run_stamp,
            "HEATWAVE_LAUNCH_SOURCE": "scripts/smoke_test_launcher.py",
            "HEATWAVE_MOCK_IMAGE_PATH": str(FIXTURE_IMAGE),
            "HEATWAVE_UI_TEST_IMAGE_PATH": str(FIXTURE_IMAGE),
        }
    )

    process: subprocess.Popen[str] | None = None
    teardown_notes: list[str] = []

    try:
        print("Clearing any stale package app process...", flush=True)
        quit_existing_app(app_process_name)

        launcher_command = f"cd {shlex.quote(str(REPO_ROOT))} && {shlex.quote(str(LAUNCHER))} --mock-backend"
        if use_built_app:
            launcher_command = f"{launcher_command} --built-app"
        print("Starting launcher under a PTY...", flush=True)
        process = subprocess.Popen(
            [
                "script",
                "-q",
                str(launcher_log),
                "/bin/zsh",
                "-lc",
                launcher_command,
            ],
            cwd=REPO_ROOT,
            env=env,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.STDOUT,
            text=True,
            start_new_session=True,
        )

        print(f"Waiting for backend health at {base_url}/health ...", flush=True)
        wait_for_json_endpoint(f"{base_url}/health", timeout_seconds=45)
        print(f"Waiting for backend app info at {base_url}/app-info ...", flush=True)
        wait_for_json_endpoint(f"{base_url}/app-info", timeout_seconds=15)
        print("Waiting for the launcher-started app window...", flush=True)
        run_osascript(WAIT_FOR_WINDOW_SCRIPT, app_process_name)

        time.sleep(3)
        if not existing_process_running(app_process_name):
            raise RuntimeError("The launcher-started app exited before the smoke test finished.")

        print("Quitting the launcher-started app...", flush=True)
        try:
            run_osascript(QUIT_SCRIPT, app_process_name)
        except RuntimeError as error:
            teardown_notes.append(str(error))

        if not wait_for_process_to_stop(app_process_name, timeout_seconds=8):
            teardown_notes.append("The app stayed open after Command-Q, so the smoke test forced it to quit.")
            force_quit_process(app_process_name)
            if not wait_for_process_to_stop(app_process_name, timeout_seconds=8):
                raise RuntimeError("The launcher-started app could not be closed during smoke testing.")

        if process.poll() is None:
            print("Waiting for the launcher process to exit cleanly...", flush=True)
            try:
                process.wait(timeout=30)
            except subprocess.TimeoutExpired:
                teardown_notes.append("The launcher PTY wrapper stayed alive after startup was verified, so the smoke test cleaned it up.")
                cleanup_process(process)
                process = None

        if process is not None and process.returncode not in (0, None):
            teardown_notes.append(
                f"The launcher exited with status {process.returncode} after startup verification."
            )

        print("Waiting for the launcher log to flush the run stamp...", flush=True)
        wait_for_text_in_file(launcher_log, run_stamp, timeout_seconds=10)

        if teardown_notes:
            print("Launcher smoke test passed after cleanup on shutdown.", flush=True)
            for note in teardown_notes:
                print(f"- {note}", flush=True)
        else:
            print("Launcher smoke test passed.", flush=True)
        print(f"Run stamp: {run_stamp}")
        print(f"Backend URL: {base_url}")
        print(f"Launcher log: {launcher_log}")
        return 0
    except Exception as error:  # noqa: BLE001
        print(f"Launcher smoke test failed: {error}", file=sys.stderr)
        print(f"Launcher log: {launcher_log}", file=sys.stderr)
        print(tail_text(launcher_log), file=sys.stderr)
        return 1
    finally:
        cleanup_process(process)


if __name__ == "__main__":
    raise SystemExit(main())
