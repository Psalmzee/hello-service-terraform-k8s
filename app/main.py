import os

from fastapi import FastAPI
from pydantic import BaseModel

APP_NAME = os.getenv("APP_NAME", "hello-service")
APP_VERSION = os.getenv("APP_VERSION", "0.1.0")

app = FastAPI(title=APP_NAME, version=APP_VERSION)


class Message(BaseModel):
    message: str


class Status(BaseModel):
    status: str


@app.get("/", response_model=Message)
def read_root() -> Message:
    """Basic greeting endpoint."""
    return Message(message=f"Hello World from {APP_NAME} v{APP_VERSION}")


@app.get("/health", response_model=Status)
def health() -> Status:
    """
    Liveness signal: process is up and able to handle requests.
    Kept dependency-free on purpose so a slow downstream (DB, cache, etc.)
    never causes Kubernetes to kill a perfectly healthy pod.
    """
    return Status(status="ok")


@app.get("/ready", response_model=Status)
def ready() -> Status:
    """
    Readiness signal: pod should receive traffic.
    This is the natural place to check downstream dependencies
    (DB connection, cache, migrations) in a real service. This demo
    app has no dependencies, so it always reports ready once started.
    """
    return Status(status="ready")
