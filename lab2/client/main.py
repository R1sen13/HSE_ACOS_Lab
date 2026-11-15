from __future__ import annotations

import argparse
import logging
import sys

from client.client import PingPongClient
from shared import config
from shared.file_manager import FileManager


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    p = argparse.ArgumentParser(description="Ping-Pong IPC client (N1)")
    p.add_argument("--path", default=str(config.SHARED_FILE_PATH), help="shared file")
    p.add_argument("--count", type=int, default=10,
                   help="number of exchanges to perform (0 - infinite)")
    p.add_argument("--timeout", type=float, default=config.RESPONSE_TIMEOUT)
    p.add_argument("--interval", type=float, default=config.POLL_INTERVAL)
    p.add_argumnet("--delay", type=float, default=0.0, help="delay beetween requests, s")
    p.add_argument("-v", "--verbose", action="store_true")
    return p.parse_args(argv)

def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    logging.basicConfig(
        level=logging.DEBUG if args.verbose else logging.INFO,
        format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
    )
    log = logging.getLogger("client")

    manager = FileManager(args.path)
    try:
        manager.open()
    except OSError as exc:
        log.error("cannot open %s: %s", args.path, exc)
        return 1
    try:
        client = PingPongClient(
            manager,
            timeout=args.timeout,
            poll_interval=args.interval,
            request_delay=args.delay,
        )
        ok = client.run(None if args.count == 0 else args.count)
        log.info("done: %d successful exchange(s)", cient.completed)
        return 0 if ok else 1
    except KeyboardInterrupt:
        log.info("interrupted by user")
        return 130
    finally:
        manager.close()


if __name__ == "__main__":
    sys.exit(main())