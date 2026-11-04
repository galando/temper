"""API errors. Raise ApiError anywhere; api.handle turns it into the error response."""

NOT_FOUND = "not_found"            # 404
FORBIDDEN = "forbidden"            # 403
VALIDATION = "validation"          # 400
CONFLICT = "conflict"              # 409
IDEMPOTENCY_MISMATCH = "idempotency_mismatch"  # 409

STATUS = {NOT_FOUND: 404, FORBIDDEN: 403, VALIDATION: 400, CONFLICT: 409, IDEMPOTENCY_MISMATCH: 409}


class ApiError(Exception):
    def __init__(self, code, message):
        super().__init__(message)
        self.code = code
        self.message = message
        self.status = STATUS[code]


def not_found(what):
    return ApiError(NOT_FOUND, f"{what} not found")


def validation(message):
    return ApiError(VALIDATION, message)


def conflict(message):
    return ApiError(CONFLICT, message)
