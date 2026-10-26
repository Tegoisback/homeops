import json
import os
from datetime import datetime, timezone


def handler(event, context):
    body = {
        "status": "ok",
        "service": "homeops-api",
        "version": os.environ.get("APP_VERSION", "dev"),
        "time": datetime.now(timezone.utc).isoformat(),
    }
    return {
        "statusCode": 200,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(body),
    }