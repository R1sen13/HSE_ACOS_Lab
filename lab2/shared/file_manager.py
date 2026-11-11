"""Small file descriptor owner for file-based IPC (Unix, Python 3.11+)."""

import errno
import fcntl
import json
import os
from typing import Any


class FileManager:
    """Each process must create and open its own manager after starting.

    The returned descriptor belongs to this manager: do not close it directly
    or share the manager between threads. Parent directories must already exist.
    """

    def __init__(self, path: str | os.PathLike[str]) -> None:
        self.path = path
        self._fd: int | None = None

    def open(self) -> int:
        """Open or create the file without truncating it; propagate OSError."""
        if self._fd is not None:
            raise ValueError("File is already open")
        self._fd = os.open(self.path, os.O_RDWR | os.O_CREAT, 0o600)
        return self._fd

    def _get_fd(self) -> int:
        if self._fd is None:
            raise ValueError("File is not open or has already been closed")
        return self._fd

    def read_message(self) -> dict[str, Any]:
        """Read JSON under an exclusive lock; propagate OS and JSON errors."""
        fd = self._get_fd()
        fcntl.flock(fd, fcntl.LOCK_EX)
        try:
            os.lseek(fd, 0, os.SEEK_SET)
            data = bytearray()
            while chunk := os.read(fd, 65536):
                data.extend(chunk)
            return json.loads(data.decode("utf-8"))
        finally:
            fcntl.flock(fd, fcntl.LOCK_UN)

    def write_message(self, message: dict[str, Any]) -> None:
        """Replace file contents with UTF-8 JSON under an exclusive lock."""
        fd = self._get_fd()
        data = json.dumps(message, ensure_ascii=False).encode("utf-8")
        fcntl.flock(fd, fcntl.LOCK_EX)
        try:
            os.lseek(fd, 0, os.SEEK_SET)
            os.ftruncate(fd, 0)
            if os.write(fd, data) != len(data):
                raise OSError(errno.EIO, "Incomplete JSON write")
        finally:
            fcntl.flock(fd, fcntl.LOCK_UN)

    def close(self) -> None:
        """Close the owned descriptor; reject operations after closing.

        Forget the descriptor before closing, even if os.close raises: retrying
        close could otherwise close a descriptor reused by another operation.
        """
        fd = self._get_fd()
        self._fd = None
        os.close(fd)
