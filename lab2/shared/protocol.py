from . import config

STATE_EMPTY = config.STATE_EMPTY
STATE_REQUEST = config.STATE_REQUEST
STATE_RESPONSE = config.STATE_RESPONSE
STATE_ERROR = config.STATE_ERROR
MESSAGE_PING = config.MESSAGE_PING
MESSAGE_PONG = config.MESSAGE_PONG


def make_empty() -> dict:
    return {"state": STATE_EMPTY}


def make_request(request_id: int) -> dict:
    return {
        "state": STATE_REQUEST,
        "request_id": request_id,
        "message": MESSAGE_PING,
    }


def make_response(request_id: int) -> dict:
    return {
        "state": STATE_RESPONSE, 
        "request_id": request_id,
        "message": MESSAGE_PONG,
    }


def make_error(error_message: str) -> dict:
    return {
        "state": STATE_ERROR,
        "message": error_message,
    }


def validate_message(data: dict) -> bool:
    if not isinstance(data, dict):
        raise ValueError("Message must be a dict")

    data_state = data.get("state")
    if data_state is None:
        raise ValueError("'state' is missing")
    if data_state not in [
        STATE_EMPTY,
        STATE_ERROR,
        STATE_REQUEST,
        STATE_RESPONSE,
    ]:
        raise ValueError("State value is incorrect")

    if data_state == STATE_EMPTY and len(data) != 1 :
        raise ValueError("If state is EMPTY, message must contain only 'state'")

    if data_state == STATE_ERROR:
        if "message" not in data:
            raise ValueError("'message' is missing")
        if not isinstance(data["message"], str):
            raise ValueError("'message' must be str")

    if data_state == STATE_REQUEST:
        if "request_id" not in data:
            raise ValueError("'request_id' is missing")
        if not isinstance(data["request_id"], int):
            raise ValueError("'request_id' must be int")
        if data.get("message") != MESSAGE_PING:
            raise ValueError("'message' must be 'ping'")

    if data_state == STATE_RESPONSE:
        if "request_id" not in data:
            raise ValueError("'request_id' is missing")
        if not isinstance(data["request_id"], int):
            raise ValueError("'request_id' must be int")
        if data.get("message") != MESSAGE_PONG:
            raise ValueError("'message' must be 'pong'")

    return True
