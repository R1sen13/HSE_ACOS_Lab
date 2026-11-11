"""Small file descriptor owner for file-based IPC (Unix, Python 3.11+)."""

import os


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

    def close(self) -> None:
        """Close the owned descriptor; reject operations after closing.

        Forget the descriptor before closing, even if os.close raises: retrying
        close could otherwise close a descriptor reused by another operation.
        """
        fd = self._get_fd()
        self._fd = None
        os.close(fd)
