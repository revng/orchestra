import asyncio
import json
import signal
import sys
import webbrowser
from argparse import ArgumentParser, RawDescriptionHelpFormatter
from contextlib import asynccontextmanager
from subprocess import Popen

from starlette.applications import Starlette
from starlette.requests import Request
from starlette.responses import JSONResponse
from starlette.routing import Mount, Route
from starlette.staticfiles import StaticFiles

from hypercorn.asyncio import serve
from hypercorn.config import Config

from revng.internal.cli.commands_registry import Command, CommandsRegistry, Options
from revng.support import get_root

ROOT = (get_root() / "share/vscode-web").resolve()


def log(msg: str):
    sys.stderr.write(f"{msg}\n")
    sys.stderr.flush()


class VSCodeWebCommand(Command):
    def __init__(self):
        super().__init__(("web-ui",), "Start rev.ng's Web UI")

    def register_arguments(self, parser: ArgumentParser):
        parser.formatter_class = RawDescriptionHelpFormatter
        parser.description = "Launch a server that allows access to the vscode web interface"
        parser.add_argument("-p", "--port", type=int, default=8090, help="Port to use")
        parser.add_argument("-o", "--open", action="store_true", help="Open in web browser")
        parser.add_argument("--daemon", action="store_true", help="Also start the daemon process")
        parser.add_argument("-C", "--chdir", help="Target directory for the daemon")

    def run(self, options: Options):
        args = options.parsed_args
        process = None
        if args.daemon:
            process = Popen(["revng", "project", "daemon"], cwd=args.chdir)

        @asynccontextmanager
        async def lifespan(app):
            log(f"serving at vscode web at 127.0.0.1:{args.port}")
            if args.open:
                webbrowser.open(f"http://127.0.0.1:{args.port}/")

            yield

            if process is not None:
                process.send_signal(signal.SIGINT)
                process.wait()

        async def product(request: Request):
            with open(ROOT / "product.json") as f:
                data = json.load(f)

            data["webviewEndpoint"] = f"http://127.0.0.1:{args.port}" + data["webviewEndpoint"]
            return JSONResponse(data)

        app = Starlette(
            routes=[
                Route("/product.json", product),
                Mount("/", app=StaticFiles(directory=str(ROOT), html=True)),
            ],
            lifespan=lifespan,
        )

        config = Config.from_mapping(bind=[f"127.0.0.1:{args.port}"])
        asyncio.run(serve(app, config))


def setup(commands_registry: CommandsRegistry):
    commands_registry.register_command(VSCodeWebCommand())
