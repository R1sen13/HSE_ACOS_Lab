from __future__ import annotations

import logging
import time
from enum import Enum, auto
from typing import Any, Callable

from shared import protocol

log = logging.getLogger("client")


class ClientState(Enum):
    CREATE_REQUEST = auto()
    WAIT_RESPONSE = auto()
    READ_RESPONSE = auto()
    HANDLE_ERROR = auto()
    DONE = auto()


class ClientError(Exception):
    def __init__(self, message: str, *, retryable: bool = False) -> None:
        super().__init__(message)
        self.retryable = retryable


class PingPongClient:
    def __init__(
        self,
        manager: Any,
        *,
        timeout: float = 5.0,
        poll_interval: float = 0.1,
        request_delay: float = 0.0,
        max_retries: int = 3,
        sleep: Callable[[float], None] = time.sleep,
        clock: Callable[[], float] = time.monotonic,
    ) -> None:
        self._manager = manager
        self._timeout = timeout
        self._poll = poll_interval
        self._delay = request_delay
        self._max_retries = max_retries
        self._sleep = sleep
        self._clock = clock

        self.request_id = 1
        self.completed = 0
        self._retries = 0
        self._last_error: ClientError | None = None

    def run(self, count: int | None = None) -> bool:
        state = ClientState.CREATE_REQUEST
        while True:
            try:
                if state is ClientState.CREATE_REQUEST:
                    if count is not None and self.completed >= count:
                        return True
                    state = self._create_request()
                elif state is ClientState.WAIT_RESPONSE:
                    state = self._wait_response()
                elif state is ClientState.READ_RESPONSE:
                    state = self._read_response()
                elif state is ClientState.HANDLE_ERROR:
                    state = self._handle_error()
                else:
                    return False
            except ClientError as exc:
                self._last_error = exc
                state = ClientState.HANDLE_ERROR

    def _create_request(self) -> ClientState:
        deadline = self._clock() + self._timeout
        while True:
            msg = self._read_checked()
            if msg["state"] == protocol.STATE_EMPTY:
                break
            if self._clock() >= deadline:
                raise ClientError(
                    f"file is busy (state={msg['state']}), cannot send request"
                )
            self._sleep(self._poll)

        self._write(protocol.make_request(self.request_id))
        log.info("-> ping (request_id=%d)", self.request_id)
        return ClientState.WAIT_RESPONSE

    def _wait_response(self) -> ClientState:
        deadline = self._clock() + self._timeout
        while True:
            msg = self._read_checked()
            state = msg["state"]
            if state == protocol.STATE_RESPONSE:
                return ClientState.READ_RESPONSE
            if state == protocol.STATE_ERROR:
                raise ClientError(
                    f"server reported ERROR: {msg.get('message')!r}", retryable=True
                )
            if state == protocol.STATE_EMPTY:
                raise ClientError("invalid transition: file is EMPTY while waiting")
            if self._clock() >= deadline:
                raise ClientError(
                    f"timeout: no pong for request_id={self.request_id} "
                    f"in {self._timeout} s"
                )
            self._sleep(self._poll)

    def _read_response(self) -> ClientState:
        msg = self._read_checked()
        if msg["state"] != protocol.STATE_RESPONSE:
            raise ClientError(f"unexpected state {msg['state']!r}, expected RESPONSE")
        if msg["request_id"] != self.request_id:
            raise ClientError(
                f"request_id mismatch: expected {self.request_id}, "
                f"got {msg['request_id']}"
            )
        if msg["message"] != protocol.MESSAGE_PONG:
            raise ClientError(f"unexpected message {msg['message']!r}, expected 'pong'")

        self._write(protocol.make_empty())
        log.info("<- pong (request_id=%d)", self.request_id)

        self.completed += 1
        self.request_id += 1
        self._retries = 0
        if self._delay:
            self._sleep(self._delay)
        return ClientState.CREATE_REQUEST

    def _handle_error(self) -> ClientState:
        err = self._last_error
        log.error("error: %s", err)

        if err is None or not err.retryable or self._retries >= self._max_retries:
            log.error("stopping client; if neeeded, reset the file manually "
                      'to {"state": "EMPTY"} with both apps stopped')
            return ClientState.DONE

        self._retries += 1
        try:
            msg = self._read_checked()
            if msg["state"] == protocol.STATE_ERROR:
                self._write(protocol.make_empty())
        except ClientError as exc:
            log.error("cannot recover: %s", exc)
            return ClientState.DONE
        log.warning("retry %d/%d for request_id=%d",
                    self._retries, self._max_retries, self.request_id)
        return ClientState.CREATE_REQUEST

    def _read_checked(self) -> dict[str, Any]:
        try:
            msg = self._manager.read_message()
            protocol.validate_message(msg)
        except ValueError as exc:
            raise ClientError(f"invalid message in file: {exc}") from exc
        except OSError as exc:
            raise ClientError(f"file I/O error: {exc}") from exc
        return msg

    def _write(self, message: dict[str, Any]) -> None:
        try:
            self._manager.write_message(message)
        except OSError as exc:
            raise ClientError(f"file write error: {exc}") from exc