# This file implements 3 closely related commands, which all do the the
# following:
# 1. Spawn the revng daemon manager
# 2. Run vscode in a new window, with optionally a `--folder-uri`
# Each command does things slightly differently:
# * `revng ui`: spawns the UI without additional arguments
# * `revng project ui`: adds a `--folder-uri` for the current project directory
# * `revng quick ui`: creates a temporary project directory and pre-fills the
#                     UI with the correct `--folder-uri`

import signal
from pathlib import Path
from subprocess import Popen, run
from tempfile import NamedTemporaryFile, TemporaryDirectory

import click

from revng.internal.cli.common import CommandRegistry
from revng.support import get_root


def _run_vscode(no_manager: bool, wait: bool, uri: str | None):
    if not no_manager:
        run(["revng", "internal", "daemon-manager"], check=True)

    vscode_binary = get_root() / "share/vscode-electron/bin/code-oss"
    cmd: list[str] = [str(vscode_binary), "--new-window"]
    if uri is not None:
        cmd.extend(("--folder-uri", uri))

    if wait:
        with NamedTemporaryFile() as temp_file:
            cmd.extend(("--wait", "--window-id-file", temp_file.name))
            vscode_process = Popen(cmd)

            def sigint_handler(signo, frame):
                window_id = ""
                while window_id == "":
                    with open(temp_file.name, "r") as f:
                        window_id = f.read()
                run([vscode_binary, "--close-window-id", window_id], check=True)

            signal.signal(signal.SIGINT, sigint_handler)
            vscode_process.wait()
    else:
        run(cmd, check=True)


no_manager_option = click.option(
    "--no-manager", is_flag=True, hidden=True, help="Don't start the daemon manager"
)
wait_option = click.option("--wait", is_flag=True, help="Wait for the UI instance to close")


@click.command(name="ui", help="Start rev.ng's UI with a temporary project")
def quick_ui():
    with TemporaryDirectory(prefix="tmp.revng-quick-ui.") as tmp_dir:
        (Path(tmp_dir) / "revng.yml").touch()
        _run_vscode(False, True, f"pipelinefs-direct://!unix{tmp_dir}/revng.sock/-/none/-/")


@click.command(name="ui", help="Start rev.ng's UI, opening the current project")
@click.option("-C", "--chdir", help="Target directory for the daemon")
@no_manager_option
@wait_option
def project_ui(no_manager: bool, wait: bool, chdir: str | None):
    socket_path = ((Path.cwd() if chdir is None else Path(chdir)) / "revng.sock").resolve()
    _run_vscode(no_manager, wait, f"pipelinefs-direct://!unix{socket_path!s}/-/none/-/")


@click.command(name="ui", help="Start rev.ng's UI")
@no_manager_option
@wait_option
def ui(no_manager: bool, wait: bool):
    _run_vscode(no_manager, wait, None)


def setup(registry: CommandRegistry):
    registry.register((), ui)
    registry.register(("project",), project_ui)
    registry.register(("quick",), quick_ui)
