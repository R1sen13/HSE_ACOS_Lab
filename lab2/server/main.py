
import logging

from server.server import PingPongServer
from shared import config
from shared.file_manager import FileManager


def main() -> None:
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
    )

    log = logging.getLogger("server")

    manager = FileManager(config.SHARED_FILE_PATH)

    try:
        manager.open()
        log.info("Server started")

        server = PingPongServer(
            manager,
            poll_interval=config.POLL_INTERVAL,
        )

        server.run()

    except KeyboardInterrupt:
        log.info("Server interrupted by user")

    except (OSError, ValueError, TypeError) as exc:
        log.exception("Server error: %s", exc)

    finally:
        try:
            manager.close()
            log.info("Shared file closed")
        except ValueError:
            # FileManager was not opened successfully.
            pass
        except OSError:
            log.exception("Failed to close shared file")


if __name__ == "__main__":
    main()
