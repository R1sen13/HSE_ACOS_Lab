import sys

from server.server import PingPongServer
from shared import config
from shared.file_manager import FileManager


def main() -> int:
    manager = FileManager(config.SHARED_FILE_PATH)
    is_open = False
    exit_code = 0

    try:
        manager.open()
        is_open = True

        server = PingPongServer(
            manager,
            poll_interval=config.POLL_INTERVAL,
        )

        server.run()

    except KeyboardInterrupt:
        exit_code = 130

    except Exception as exc:
        print(f"Server terminated due to an unexpected error: {exc}", file=sys.stderr)
        exit_code = 1

    finally:
        if is_open:
            try:
                manager.close()
            except OSError as exc:
                print(f"Failed to close shared file: {exc}", file=sys.stderr)
                exit_code = 1

    return exit_code


if __name__ == "__main__":
    sys.exit(main())
