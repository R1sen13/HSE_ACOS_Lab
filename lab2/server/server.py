
import logging
import time
from enum import Enum, auto
from typing import Callable, cast

from shared import config, protocol
from shared.file_manager import FileManager


log = logging.getLogger(__name__)


class ServerState(Enum):
    WAIT_REQUEST = auto()
    PROCESS_REQUEST = auto()
    SEND_RESPONSE = auto()
    HANDLE_ERROR = auto()


class ServerError(Exception):
    pass


class PingPongServer:
    def __init__(
        self,
        manager: FileManager,
        *,
        poll_interval: float = config.POLL_INTERVAL,
        sleep: Callable[[float], None] = time.sleep,
    ) -> None:
        if poll_interval <= 0:
            raise ValueError("poll_interval must be positive")

        self._manager = manager
        self._poll_interval = poll_interval
        self._sleep = sleep

        self._running = False
        self._request: dict[str, object] | None = None
        self._last_error: Exception | None = None
        self.completed = 0

    def stop(self) -> None:
        self._running = False

    def run(self, max_requests: int | None = None) -> int:
        if max_requests is not None and max_requests < 0:
            raise ValueError("max_requests must not be negative")

        initial_completed = self.completed
        self._running = True
        state = ServerState.WAIT_REQUEST

        log.info("Server started")

        try:
            while self._running:
                if (
                    max_requests is not None
                    and self.completed - initial_completed >= max_requests
                ):
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

        finally:
            self._running = False
            processed = self.completed - initial_completed

            log.info(
                "Server stopped. Processed requests: %d",
                processed,
            )

        return self.completed - initial_completed

    def _wait_request(self) -> ServerState:
        try:
            message = self._manager.read_message()
        except (OSError, ValueError, TypeError, KeyError) as exc:
            log.error("Failed to read shared message: %s", exc)
            self._last_error = exc
            self._request = None
            return ServerState.HANDLE_ERROR

        if not isinstance(message, dict):
            self._last_error = ServerError(
                "Shared file must contain a JSON object"
            )
            self._request = None
            return ServerState.HANDLE_ERROR

        if message.get("state") == protocol.STATE_REQUEST:
            self._request = message

        try:
            protocol.validate_message(message)
        except (ValueError, TypeError, KeyError) as exc:
            log.warning("Invalid message received: %s", exc)
            self._last_error = exc
            return ServerState.HANDLE_ERROR

        message_state = message["state"]

        if message_state == protocol.STATE_EMPTY:
            self._sleep(self._poll_interval)
            return ServerState.WAIT_REQUEST

        if message_state == protocol.STATE_REQUEST:
            return ServerState.PROCESS_REQUEST

        self._sleep(self._poll_interval)
        return ServerState.WAIT_REQUEST

    def _process_request(self) -> ServerState:
        if self._request is None:
            self._last_error = ServerError(
                "No request available to process"
            )
            return ServerState.HANDLE_ERROR

        log.info(
            "Received Ping. request_id=%s",
            self._request["request_id"],
        )

        return ServerState.SEND_RESPONSE

    def _send_response(self) -> ServerState:
        if self._request is None:
            self._last_error = ServerError(
                "No request available to answer"
            )
            return ServerState.HANDLE_ERROR

        request_id = cast(int, self._request["request_id"])
        response = protocol.make_response(request_id)

        self._manager.write_message(response)

        log.info(
            "Sent Pong. request_id=%s",
            request_id,
        )

        self.completed += 1
        self._request = None
        self._last_error = None

        return ServerState.WAIT_REQUEST

    def _handle_error(self) -> ServerState:
        if self._request is None:
            log.error(
                "Cannot send ERROR response. "
                "No valid request context. Stopping server."
            )
            self._running = False
            return ServerState.WAIT_REQUEST

        error = self._last_error or ServerError("Invalid request")
        error_message = protocol.make_error(str(error))

        self._manager.write_message(error_message)

        log.warning(
            "Sent ERROR response to client: %s",
            error,
        )

        self._request = None
        self._last_error = None

        return ServerState.WAIT_REQUEST
