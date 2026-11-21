import errno
import fcntl
import json
import os
from typing import Any


class FileManager:
    def __init__(self, path: str | os.PathLike[str]) -> None:
        self.path = path
        self._fd: int | None = None

    def open(self) -> int:
        if self._fd is not None:
            raise ValueError("File is already open")
        self._fd = os.open(self.path, os.O_RDWR | os.O_CREAT, 0o600)
        return self._fd

    def _get_fd(self) -> int:
        if self._fd is None:
            raise ValueError("File is not open or has already been closed")
        return self._fd

    def read_message(self) -> dict[str, Any]:
        fd = self._get_fd()
        fcntl.flock(fd, fcntl.LOCK_EX)
        try:
            os.lseek(fd, 0, os.SEEK_SET)
            data = bytearray()
            while chunk := os.read(fd, 65536):
                data.extend(chunk)
            if not data:
                raise ValueError("Shared file is empty")
            message = json.loads(data.decode("utf-8"))
            if not isinstance(message, dict):
                raise ValueError("Shared file must contain a JSON object")
            return message
        finally:
            fcntl.flock(fd, fcntl.LOCK_UN)

    def write_message(self, message: dict[str, Any]) -> None:
        fd = self._get_fd()
        if not isinstance(message, dict):
            raise TypeError("Message must be a dictionary")
        data = json.dumps(message, ensure_ascii=False, allow_nan=False).encode("utf-8")
        fcntl.flock(fd, fcntl.LOCK_EX)
        try:
            os.lseek(fd, 0, os.SEEK_SET)
            os.ftruncate(fd, 0)
            remaining = memoryview(data)
            while remaining:
                written = os.write(fd, remaining)
                if written == 0:
                    raise OSError(errno.EIO, "JSON write made no progress")
                remaining = remaining[written:]
        finally:
            fcntl.flock(fd, fcntl.LOCK_UN)

    def close(self) -> None:
        fd = self._get_fd()
        self._fd = None
        os.close(fd)
