"""Trust only authorizer claims overwritten by API Gateway on protected routes.

The ALB is private and accepts only VPC Link traffic. Tasks accept only ALB
traffic. Never expose these services directly or forward user-supplied identity
headers without overwriting them. See docs/SECURITY.md.
"""
import os

from fastapi import HTTPException, Request


def identity(request: Request, role: str) -> str:
    sub = request.headers.get("x-identity-sub", "")
    issuer = request.headers.get("x-identity-issuer", "")
    audience = request.headers.get("x-identity-audience", "")
    expected_issuer = os.getenv(f"{role.upper()}_ISSUER", "")
    expected_client = os.getenv(f"{role.upper()}_CLIENT_ID", "")
    if (not expected_issuer or not expected_client or not sub or len(sub) > 128
            or issuer != expected_issuer or audience != expected_client):
        raise HTTPException(403, "This account cannot perform that action")
    return sub
