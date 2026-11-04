"""An in-memory post store."""
from src import textutil

_POSTS = []


def create_post(title, body):
    post = {"id": len(_POSTS) + 1, "title": title, "body": body, "summary": textutil.truncate(body, 80)}
    _POSTS.append(post)
    return post


def all_posts():
    return list(_POSTS)
