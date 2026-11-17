from __future__ import annotations

import logging
import time
from enum import Enum, auto
from typing import Any, Callable

from shared import protocol

log = logging.getLogger("server")


class ServerState(Enum):
    """States of the server-side finite state machine."""

    WAIT_REQUEST = auto()
    PROCESS_REQUEST = auto()
    SEND_RESPONSE = auto()
    HANDLE_ERROR = auto()


class ServerError(Exception):
    """Raised when the server cannot continue safely."""


class PingPongServer:
    """Server that processes Ping requests from the shared file."""

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
        self._last_error: Exception | None = None
        self.completed = 0

    def stop(self) -> None:
        """Request graceful server shutdown."""
        self._running = False

    def run(self, max_requests: int | None = None) -> int:
        """Run until stopped or the request limit is reached."""
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
                raise ServerError(f"Unknown server state: {state!r}")

        log.info(
            "Server stopped. Processed requests: %d",
            self.completed,
        )
        return self.completed

    def _wait_request(self) -> ServerState:
        """Wait for a new request without holding the file lock."""
        try:
            message = self._manager.read_message()
            protocol.validate_message(message)

        except (ValueError, TypeError, KeyError) as exc:
            self._last_error = exc
            return ServerState.HANDLE_ERROR

        state = message.get("state")

        if state == protocol.STATE_EMPTY:
            self._sleep(self._poll_interval)
            return ServerState.WAIT_REQUEST

        if state == protocol.STATE_REQUEST:
            self._request = message
            return ServerState.PROCESS_REQUEST

        # RESPONSE and ERROR are not requests for this server.
        self._sleep(self._poll_interval)
        return ServerState.WAIT_REQUEST

    def _process_request(self) -> ServerState:
        """Validate the received Ping request."""
        if self._request is None:
            self._last_error = ServerError(
                "No request available to process"
            )
            return ServerState.HANDLE_ERROR

        if self._request["message"] != protocol.MESSAGE_PING:
            self._last_error = ServerError(
                f"Unexpected message: {self._request['message']!r}"
            )
            return ServerState.HANDLE_ERROR

        return ServerState.SEND_RESPONSE

    def _send_response(self) -> ServerState:
        """Write Pong with the same request_id."""
        if self._request is None:
            self._last_error = ServerError(
                "No request available to answer"
            )
            return ServerState.HANDLE_ERROR

        response = {
            "state": protocol.STATE_RESPONSE,
            "request_id": self._request["request_id"],
            "message": protocol.MESSAGE_PONG,
        }

        self._manager.write_message(response)

        log.info(
            "Sent Pong. request_id=%s",
            self._request["request_id"],
        )

        self.completed += 1
        self._request = None
        self._last_error = None

        return ServerState.WAIT_REQUEST

    def _handle_error(self) -> ServerState:
        """Log an error without overwriting unknown shared-file contents."""
        if self._last_error is not None:
            log.error(
                "Cannot process shared-file message: %s",
                self._last_error,
            )

        self._request = None
        self._last_error = None

        self._sleep(self._poll_interval)

        return ServerState.WAIT_REQUEST
