from enum import Enum, auto
from typing import Any


class ServerState(Enum):
    WAIT_REQUEST = auto()
    PROCESS_REQUEST = auto()
    SEND_RESPONSE = auto()
    HANDLE_ERROR = auto()


class PingPongServer:
    def __init__(
        self,
        manager: Any,
        *,
        poll_interval: float = 0.1,
    ) -> None:
        if poll_interval <= 0:
            raise ValueError("poll_interval must be positive")

        self._manager = manager
        self._poll_interval = poll_interval
