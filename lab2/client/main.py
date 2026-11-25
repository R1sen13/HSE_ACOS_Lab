from __future__ import annotations

import argparse
import logging
import sys

from client.client import PingPongClient
from shared import config
from shared.file_manager import FileManager


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Ping-Pong IPC client (N1)")
    parser.add_argument(
        "--count",
        type=int,
        default=10,
        help="number of exchanges to perform (0 - infinite)",
    )
    parser.add_argument("-v", "--verbose", action="store_true")
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    logging.basicConfig(
        level=logging.DEBUG if args.verbose else logging.INFO,
        format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
    )
    log = logging.getLogger("client")

    manager = FileManager(config.SHARED_FILE_PATH)
    is_open = False
    exit_code = 0

    try:
        manager.open()
        is_open = True

        client = PingPongClient(manager)
        ok = client.run(None if args.count == 0 else args.count)
        log.info("done: %d successful exchange(s)", client.completed))
        if not ok:
            exit_code = 1

    except KeyboardInterrupt:
        log.info("interrupted by user")
        exit_code = 130

    except OSError as exc:
        log.error("cannot open shared file: %s", exc)
        exit_code = 1

    finally:
        if is_open:
            try:
                manager.close()
            except OSError as exc:
                log.error("failed to close shared file: %s", exc)
                exit_code = 1

    return exit_code


if __name__ == "__main__":
    sys.exit(main())