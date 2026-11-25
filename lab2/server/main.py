
import logging
import sys

from server.server import PingPongServer
from shared import config
from shared.file_manager import FileManager


def main() -> int:
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
    )

    log = logging.getLogger("server")
    manager = FileManager(config.SHARED_FILE_PATH)

    is_open = False
    exit_code = 0

    try:
        manager.open()
        is_open = True

        log.info("Shared file opened")

        server = PingPongServer(
            manager,
            poll_interval=config.POLL_INTERVAL,
        )

        server.run()

    except KeyboardInterrupt:
        log.info("Server interrupted by user")
        exit_code = 130

    except Exception:
        log.exception("Server terminated due to an unexpected error")
        exit_code = 1

    finally:
        if is_open:
            try:
                manager.close()
                log.info("Shared file closed")
            except OSError:
                log.exception("Failed to close shared file")
                exit_code = 1

    return exit_code


if __name__ == "__main__":
    sys.exit(main())
