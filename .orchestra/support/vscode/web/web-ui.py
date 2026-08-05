import asyncio
import json
import signal
import webbrowser
from contextlib import asynccontextmanager
from subprocess import Popen

from starlette.applications import Starlette
from starlette.requests import Request
from starlette.responses import JSONResponse
from starlette.routing import Mount, Route
from starlette.staticfiles import StaticFiles

import click
from hypercorn.asyncio import serve
from hypercorn.config import Config

from revng.internal.cli.common import CommandRegistry, cli_logger
from revng.support import get_root

ROOT = (get_root() / "share/vscode-web").resolve()


@click.command(
    name="web-ui",
    help=(
        "Start rev.ng's Web UI\n\n\b\n"
        "Launch a server that allows access to the vscode web interface"
    ),
)
@click.option("-p", "--port", type=int, default=8090, help="Port to use")
@click.option("-o", "--open", "open_browser", is_flag=True, help="Open in web browser")
@click.option("--daemon", is_flag=True, help="Also start the daemon process")
@click.option("-C", "--chdir", help="Target directory for the daemon")
def web_ui(port: int, open_browser: bool, daemon: bool, chdir: str):
    process = None
    if daemon:
        process = Popen(["revng", "project", "daemon", "--bind", "127.0.0.1:8000"], cwd=chdir)

    @asynccontextmanager
    async def lifespan(app):
        cli_logger.log(f"serving at vscode web at 127.0.0.1:{port}")
        if open_browser:
            webbrowser.open(f"http://127.0.0.1:{port}/")

        yield

        if process is not None:
            process.send_signal(signal.SIGINT)
            process.wait()

    async def product(request: Request):
        with open(ROOT / "product.json") as f:
            data = json.load(f)

        data["webviewEndpoint"] = f"http://127.0.0.1:{port}" + data["webviewEndpoint"]
        return JSONResponse(data)

    app = Starlette(
        routes=[
            Route("/product.json", product),
            Mount("/", app=StaticFiles(directory=str(ROOT), html=True)),
        ],
        lifespan=lifespan,
    )

    config = Config.from_mapping(bind=[f"127.0.0.1:{port}"])
    asyncio.run(serve(app, config))


def setup(registry: CommandRegistry):
    registry.register((), web_ui)
