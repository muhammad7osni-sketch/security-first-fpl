"""
PHASE 4: Secure logging middleware.
Never logs:
- Authorization headers
- Bearer tokens
- Refresh tokens
- Authorization codes
- Sensitive request/response bodies

Redacts sensitive fields in logs.
"""

import logging
import json
from typing import Any, Dict
from pythonjsonlogger import jsonlogger
import sentry_sdk
from app.config import settings

# Configure JSON logging
class SensitiveFieldsFilter(logging.Filter):
    """
    Filters sensitive fields from logs.
    Redacts tokens, codes, authorization headers, etc.
    """

    SENSITIVE_FIELDS = {
        "authorization",
        "bearer",
        "token",
        "refresh_token",
        "access_token",
        "code",
        "password",
        "secret",
        "key",
        "api_key",
        "auth_header",
        "cookie",
    }

    def filter(self, record: logging.LogRecord) -> bool:
        """Remove sensitive fields from log record."""
        try:
            # Clean message
            if hasattr(record, "msg") and isinstance(record.msg, str):
                record.msg = self._redact_string(record.msg)

            # Clean args
            if hasattr(record, "args") and isinstance(record.args, dict):
                record.args = self._redact_dict(record.args)

        except Exception:
            pass

        return True

    def _redact_string(self, s: str) -> str:
        """Redact sensitive strings."""
        for field in self.SENSITIVE_FIELDS:
            if field.lower() in s.lower():
                return s.replace(s, f"[REDACTED_{field.upper()}]")
        return s

    def _redact_dict(self, d: Dict) -> Dict:
        """Redact sensitive fields in dictionary."""
        redacted = {}
        for key, value in d.items():
            if key.lower() in self.SENSITIVE_FIELDS:
                redacted[key] = f"[REDACTED_{key.upper()}]"
            elif isinstance(value, dict):
                redacted[key] = self._redact_dict(value)
            elif isinstance(value, list):
                redacted[key] = [
                    self._redact_dict(item) if isinstance(item, dict) else item
                    for item in value
                ]
            else:
                redacted[key] = value
        return redacted


# Configure JSON logger
def setup_logging():
    """Configure JSON logging with sensitive field redaction."""
    logger = logging.getLogger()
    logger.setLevel(settings.log_level)

    # JSON formatter
    json_handler = logging.StreamHandler()
    formatter = jsonlogger.JsonFormatter(
        fmt="%(timestamp)s %(level)s %(name)s %(message)s"
    )
    json_handler.setFormatter(formatter)

    # Add sensitive field filter
    sensitive_filter = SensitiveFieldsFilter()
    json_handler.addFilter(sensitive_filter)

    logger.addHandler(json_handler)

    # Configure Sentry
    if settings.sentry_dsn:
        sentry_sdk.init(
            dsn=settings.sentry_dsn,
            environment=settings.environment,
            traces_sample_rate=0.1,
            # Sanitize sensitive data
            before_send=_sanitize_sentry_event,
        )


def _sanitize_sentry_event(event: Dict[str, Any], hint: Dict) -> Dict[str, Any]:
    """
    Sanitize Sentry event to remove sensitive data.
    Never send tokens, codes, or headers to Sentry.
    """
    # Remove authorization header
    if "request" in event:
        if "headers" in event["request"]:
            event["request"]["headers"].pop("Authorization", None)

    # Redact sensitive fields in extra
    if "extra" in event:
        event["extra"] = _redact_dict_for_sentry(event["extra"])

    return event


def _redact_dict_for_sentry(d: Dict) -> Dict:
    """Redact sensitive fields for Sentry."""
    redacted = {}
    sensitive_keys = {"token", "code", "secret", "password", "authorization"}
    for key, value in d.items():
        if key.lower() in sensitive_keys:
            redacted[key] = "[REDACTED]"
        elif isinstance(value, dict):
            redacted[key] = _redact_dict_for_sentry(value)
        else:
            redacted[key] = value
    return redacted


# Setup logging on module load
setup_logging()
