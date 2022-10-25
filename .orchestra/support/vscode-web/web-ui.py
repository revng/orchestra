import os
import signal
import sys
import webbrowser
from argparse import ArgumentParser, RawDescriptionHelpFormatter
from subprocess import Popen

from starlette.applications import Starlette
from starlette.routing import Mount
from starlette.staticfiles import StaticFiles

import uvicorn

from revng.cli.commands_registry import Command, CommandsRegistry, Options
from revng.support import get_root

ROOT = str((get_root() / "share/vscode-web").resolve())


def log(msg: str):
    sys.stderr.write(f"{msg}\n")
    sys.stderr.flush()


class VSCodeWebCommand(Command):
    def __init__(self):
        super().__init__(("web-ui",), "Start rev.ng's web ui")
        self.process = None
        self.app = Starlette(
            routes=[Mount("/", app=StaticFiles(directory=ROOT, html=True))],
            on_startup=[self.startup],
            on_shutdown=[self.shutdown],
        )

    def startup(self):
        log(f"serving at vscode web at 127.0.0.1:{self.args.port}")
        if self.args.open:
            webbrowser.open(f"http://127.0.0.1:{self.args.port}/")

    def shutdown(self):
        if self.process is not None:
            self.process.send_signal(signal.SIGINT)
            self.process.wait()

    def register_arguments(self, parser: ArgumentParser):
        parser.formatter_class = RawDescriptionHelpFormatter
        parser.description = "Launch a server that allows access to the vscode web interface"
        parser.add_argument("-p", "--port", type=int, default=8090, help="Port to use")
        parser.add_argument("-o", "--open", action="store_true", help="Open in web browser")
        parser.add_argument("--daemon", action="store_true", help="Also start the daemon process")

    def run(self, options: Options):
        self.args = options.parsed_args
        port = options.parsed_args.port
        if options.parsed_args.daemon:
            env = {
                **os.environ,
                "REVNG_ORIGINS": f"vscode-file://vscode-app,http://127.0.0.1:{port}",
            }
            self.process = Popen(["revng", "daemon"], env=env)
        uvicorn.run(self.app, host="127.0.0.1", port=port, log_level="info", access_log=False)


def setup(commands_registry: CommandsRegistry):
    commands_registry.register_command(VSCodeWebCommand())
