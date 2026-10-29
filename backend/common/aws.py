"""AWS runtime clients use task/function roles. Local tests inject mocked clients."""
import os
from functools import lru_cache

import boto3
from botocore.config import Config

CONFIG = Config(connect_timeout=2, read_timeout=5, retries={"mode": "standard", "max_attempts": 3})


@lru_cache
def client(service: str):
    return boto3.client(service, region_name=os.getenv("AWS_REGION", "us-west-2"), config=CONFIG)


@lru_cache
def dynamodb():
    return boto3.resource("dynamodb", region_name=os.getenv("AWS_REGION", "us-west-2"), config=CONFIG)
