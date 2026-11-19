import os

SHARED_FILE_PATH: str = os.path.abspath(
    os.path.join(
        os.path.dirname(__file__),
        "..",
        "data",
        "shared_file.json",
    )
)

RESPONSE_TIMEOUT = 5.0  # 5 seconds
POLL_INTERVAL = 0.1  # 0.1 seconds

STATE_EMPTY = "EMPTY"
STATE_REQUEST = "REQUEST"
STATE_RESPONSE = "RESPONSE"
STATE_ERROR = "ERROR"

MESSAGE_PING = "ping"
MESSAGE_PONG = "pong"
