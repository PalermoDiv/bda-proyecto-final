import os
from pymongo import MongoClient
from dotenv import load_dotenv

load_dotenv()

_client = None


def _get_db():
    global _client
    if _client is None:
        _client = MongoClient(os.getenv("MONGO_URI", "mongodb://localhost:27017/"))
    return _client[os.getenv("MONGO_DB", "alzmonitor")]


def col(name):
    return _get_db()[name]
