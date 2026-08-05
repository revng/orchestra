import asyncio
import signal
import sys
from argparse import ArgumentParser, RawDescriptionHelpFormatter
from asyncio.exceptions import CancelledError
from asyncio.subprocess import DEVNULL, STDOUT
from contextlib import suppress
from tempfile import NamedTemporaryFile

from revng.internal.cli.commands_registry import Command, CommandsRegistry, Options
from revng.support import get_root

verbose = False


def log(message: str):
    if verbose:
        sys.stderr.write(f"{message}\n")


def map_coroutines(*coroutines) -> list[asyncio.Task]:
    async def wrapper(index, coro):
        return (index, await coro)

    return [asyncio.create_task(wrapper(i, coro)) for i, coro in enumerate(coroutines)]


def apopen(*args, **kwargs):
    log(f"Running command: {args}")
    return asyncio.create_subprocess_exec(*args, **kwargs)


class RevngUICommand(Command):
    def __init__(self):
        super().__init__(("ui",), "Start rev.ng's UI")

    def register_arguments(self, parser: ArgumentParser):
        parser.formatter_class = RawDescriptionHelpFormatter
        parser.description = "Launch a revng daemon with the UI"
        parser.add_argument("-C", "--chdir", help="Target directory")

    def run(self, options: Options):
        global verbose
        verbose = options.verbose
        asyncio.run(self.arun(options.parsed_args))

    async def arun(self, args):
        socket_path_out = NamedTemporaryFile()
        daemon_cmd = ["revng", "project", "daemon", "--socket-location-file", socket_path_out.name]
        daemon_kwargs = {"cwd": args.chdir, "stdout": DEVNULL, "stderr": STDOUT}
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
                log("Daemon is already running in another instance")
                daemon_alread_running = True
            else:
                log(f"Daemon process exited with {daemon_process.returncode}, exiting")
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
                log("SIGINT received, closing rev.ng UI")
                vscode_close_process = await apopen(vscode_binary, "--close", "--folder-uri", uri)
                await vscode_close_process.wait()
                await vscode_process.wait()
                await daemon_process.wait()
                return

            if list(done)[0].result()[0] == 0:
                # Daemon has stopped working, restart it
                log("Daemon process exited, restarting it")
                daemon_process = await apopen(*daemon_cmd, **daemon_kwargs)
            else:
                # VSCode has been closed
                log("rev.ng UI has been closed, stopping daemon and quitting")
                daemon_process.send_signal(signal.SIGINT)
                await daemon_process.wait()
                stop = True

            for task in pending:
                task.cancel()


def setup(commands_registry: CommandsRegistry):
    commands_registry.register_command(RevngUICommand())
