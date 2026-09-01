from __future__ import annotations

import os

from fastapi import HTTPException, status


def prototype_api_enabled() -> bool:
    """Return whether the unauthenticated in-memory engineering routes are enabled."""
    value = os.getenv("RECOVERYSENSE_ENABLE_PROTOTYPE_API", "false")
    return value.strip().lower() in {"1", "true", "yes", "on"}


def require_prototype_api_enabled() -> None:
    """Fail closed unless an engineer explicitly enables prototype routes.

    The current FastAPI routes use process-local memory and do not authenticate
    callers. They are useful for local integration tests but are not a research
    storage service and must never be exposed by accident.
    """
    if prototype_api_enabled():
        return
    raise HTTPException(
        status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
        detail=(
            "The unauthenticated in-memory prototype API is disabled. Set "
            "RECOVERYSENSE_ENABLE_PROTOTYPE_API=true only for an isolated local "
            "engineering test."
        ),
    )
