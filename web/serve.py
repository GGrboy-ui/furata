"""Serve this checkout's complete web UI without caching older module versions."""

import argparse
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path


class WebHandler(SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header("Cache-Control", "no-store")
        super().end_headers()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", type=int, default=8767)
    args = parser.parse_args()
    web_root = Path(__file__).resolve().parent
    handler = partial(WebHandler, directory=str(web_root))
    with ThreadingHTTPServer(("127.0.0.1", args.port), handler) as server:
        print(f"Web directory: {web_root}", flush=True)
        print(f"Furuta POS1 / VEL3: http://localhost:{args.port}/", flush=True)
        try:
            server.serve_forever()
        except KeyboardInterrupt:
            pass


if __name__ == "__main__":
    main()
