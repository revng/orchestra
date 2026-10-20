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
from string import Template
from subprocess import Popen, run
from tempfile import NamedTemporaryFile, TemporaryDirectory

import click
from xdg import xdg_data_home

from revng.internal.cli.common import CommandRegistry
from revng.support import get_root

DESKTOP_FILE = """[Desktop Entry]
Type=Application
Name=rev.ng UI
Exec=${executable_path}
Icon=revng-ui
StartupWMClass=revng-ui
NoDisplay=true
"""


def _install_revng_ui_desktop(executable_path: Path):
    """
    This lazily creates the `revng-ui.desktop` file and symlinks the needed
    icons in `~/.local/share`. These steps are needed to guarantee that Window
    Managers use the correct icon. WMs can pick one of 3 icon sources:
    1. The `_NET_WM_ICON` X11 property
    2. The `xdg-toplevel-icon` protocol, which is the wayland equivalent of (1)
    3. The `.desktop` file
    WMs implement a subset of these 3 sources, and each one has a different
    order of precedence. The most common is (3) so the files are installed to
    allow the correct icon to show up. Electron also sets (1) when setting the
    `.icon` property, so the this covers sources (3) and (1).
    """

    contents = Template(DESKTOP_FILE).substitute(executable_path=str(executable_path.resolve()))
    desktop_file = xdg_data_home() / "applications/revng-ui.desktop"
    if desktop_file.is_file() and desktop_file.read_text() == contents:
        return

    desktop_file.parent.mkdir(parents=True, exist_ok=True)
    desktop_file.write_text(contents)

    def symlink_icon(size: str, source: Path, target: str):
        icon_dir = xdg_data_home() / f"icons/hicolor/{size}/apps"
        icon_dir.mkdir(parents=True, exist_ok=True)
        image_file = icon_dir / target
        if image_file.exists():
            image_file.unlink()
        image_file.symlink_to(source)

    # Symlink the logos
    logo_dir = get_root() / "share/revng-ui/logos"
    symlink_icon("scalable", logo_dir / "logo.svg", "revng-ui.svg")
    for size in (16, 24, 32, 48, 64, 128, 256, 512):
        symlink_icon(f"{size}x{size}", logo_dir / f"{size}.png", "revng-ui.png")

    # Force re-check of icons
    (xdg_data_home() / "icons/hicolor").touch(exist_ok=True)


def _run_vscode(no_manager: bool, wait: bool, uri: str | None):
    if not no_manager:
        run(["revng", "internal", "daemon-manager"], check=True)

    vscode_binary = get_root() / "share/vscode-electron/bin/code-oss"
    _install_revng_ui_desktop(vscode_binary)
    cmd: list[str] = [str(vscode_binary), "--force-workspace", "--new-window"]
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
