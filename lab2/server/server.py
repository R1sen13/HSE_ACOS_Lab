from __future__ import annotations

import logging
import time
from enum import Enum, auto
from typing import Any, Callable

from shared import protocol

log = logging.getLogger("server")


class ServerState(Enum):
    WAIT_REQUEST = auto()
    PROCESS_REQUEST = auto()
    SEND_RESPONSE = auto()
    HANDLE_ERROR = auto()


class ServerError(Exception):
    """Raised when the server cannot continue safely."""


class PingPongServer:
    def __init__(
        self,
        manager: Any,
        *,
        poll_interval: float = 0.1,
        sleep: Callable[[float], None] = time.sleep,
    ) -> None:
        if poll_interval <= 0:
            raise ValueError("poll_interval must be positive")

        self._manager = manager
        self._poll_interval = poll_interval
        self._sleep = sleep

        self._running = False
        self._request: dict[str, Any] | None = None
        self.completed = 0

    def stop(self) -> None:
        """Request a graceful server shutdown."""
        self._running = False

    def run(self, max_requests: int | None = None) -> int:
        if max_requests is not None and max_requests < 0:
            raise ValueError("max_requests must not be negative")

        self._running = True
        state = ServerState.WAIT_REQUEST

        while self._running:
            if max_requests is not None and self.completed >= max_requests:
                break

            if state is ServerState.WAIT_REQUEST:
                state = self._wait_request()
            elif state is ServerState.PROCESS_REQUEST:
                state = self._process_request()
            elif state is ServerState.SEND_RESPONSE:
                state = self._send_response()
            elif state is ServerState.HANDLE_ERROR:
                state = self._handle_error()
            else:
                raise ServerError(f"Unknown server state: {state}")

        log.info("server stopped; processed %d request(s)", self.completed)
        return self.completed

    def _wait_request(self) -> ServerState:
        message = self._manager.read_message()
        protocol.validate_message(message)

        if message["state"] == protocol.STATE_EMPTY:
            self._sleep(self._poll_interval)
            return ServerState.WAIT_REQUEST

        if message["state"] == protocol.STATE_REQUEST:
            self._request = message
            return ServerState.PROCESS_REQUEST

        self._sleep(self._poll_interval)
        return ServerState.WAIT_REQUEST

    def _process_request(self) -> ServerState:
        if self._request is None:
            raise ServerError("No request to process")

        if self._request["message"] != protocol.MESSAGE_PING:
            raise ServerError("Unexpected message")

        return ServerState.SEND_RESPONSE

    def _send_response(self) -> ServerState:
        if self._request is None:
            raise ServerError("No request to respond to")

        response = {
            "state": protocol.STATE_RESPONSE,
            "request_id": self._request["request_id"],
            "message": protocol.MESSAGE_PONG,
        }

        self._manager.write_message(response)

        log.info("sent pong (request_id=%s)", self._request["request_id"])

        self.completed += 1
        self._request = None

        return ServerState.WAIT_REQUEST
