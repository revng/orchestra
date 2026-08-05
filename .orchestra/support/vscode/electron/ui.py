import asyncio
import signal
import sys
from asyncio.exceptions import CancelledError
from asyncio.subprocess import DEVNULL, STDOUT
from contextlib import suppress
from tempfile import NamedTemporaryFile

import click

from revng.internal.cli.common import CommandRegistry, cli_logger
from revng.support import get_root


def map_coroutines(*coroutines) -> list[asyncio.Task]:
    async def wrapper(index, coro):
        return (index, await coro)

    return [asyncio.create_task(wrapper(i, coro)) for i, coro in enumerate(coroutines)]


def apopen(*args, **kwargs):
    cli_logger.debug_log(f"Running command: {args}")
    return asyncio.create_subprocess_exec(*args, **kwargs)


async def arun(chdir: str):
    socket_path_out = NamedTemporaryFile(prefix="revng-ui-socket-path-")
    daemon_cmd = ["revng", "project", "daemon", "--socket-location-file", socket_path_out.name]
    daemon_kwargs = {"cwd": chdir, "stdout": DEVNULL, "stderr": STDOUT}
    daemon_process = await apopen(*daemon_cmd, **daemon_kwargs)
    daemon_alread_running = False
    while True:
        with open(socket_path_out.name) as f:
            socket_path = f.read()
        if socket_path.strip() != "":
            break
        else:
            await asyncio.sleep(0.05)

    with suppress(TimeoutError):
        await asyncio.wait_for(daemon_process.wait(), 1)

    if daemon_process.returncode is not None:
        if daemon_process.returncode == 4:
            cli_logger.debug_log("Daemon is already running in another instance")
            daemon_alread_running = True
        else:
            cli_logger.debug_log(f"Daemon process exited with {daemon_process.returncode}, exiting")
            sys.exit(1)

    uri = f"pipelinefs-direct://!unix{socket_path}/-/none/-/"
    vscode_binary = get_root() / "share/vscode-electron/bin/code-oss"

    if daemon_alread_running:
        # If there it means that there is an existing `revng ui` instance
        # running, focus its window.
        vscode_process = await apopen(vscode_binary, "--focus", "--wait", "--folder-uri", uri)
        await vscode_process.wait()
        sys.exit(0)

    vscode_process = await apopen(vscode_binary, "--new-window", "--wait", "--folder-uri", uri)

    stop = False
    while not stop:
        try:
            done, pending = await asyncio.wait(
                map_coroutines(daemon_process.wait(), vscode_process.wait()),
                return_when=asyncio.FIRST_COMPLETED,
            )
        except CancelledError:
            cli_logger.debug_log("SIGINT received, closing rev.ng UI")
            vscode_close_process = await apopen(vscode_binary, "--close", "--folder-uri", uri)
            await vscode_close_process.wait()
            await vscode_process.wait()
            await daemon_process.wait()
            return

        if list(done)[0].result()[0] == 0:
            # Daemon has stopped working, restart it
            cli_logger.debug_log("Daemon process exited, restarting it")
            daemon_process = await apopen(*daemon_cmd, **daemon_kwargs)
        else:
            # VSCode has been closed
            cli_logger.debug_log("rev.ng UI has been closed, stopping daemon and quitting")
            daemon_process.send_signal(signal.SIGINT)
            await daemon_process.wait()
            stop = True

        for task in pending:
            task.cancel()


@click.command(name="ui", help="Start rev.ng's UI\n\n\b\nLaunch a revng daemon with the UI")
@click.option("-C", "--chdir", help="Target directory for the daemon")
def ui(chdir: str):
    asyncio.run(arun(chdir))


def setup(registry: CommandRegistry):
    registry.register((), ui)
