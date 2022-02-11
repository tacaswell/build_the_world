import os
from pathlib import Path
import gidgethub
from cachetools import LRUCache
from functools import wraps

import asyncio

import aiohttp
from gidgethub.aiohttp import GitHubAPI
import yaml

with open(Path("~/.config/hub").expanduser(), "r") as f:
    oauth_token = f.read()

if 'GITHUB_USERNAME' in os.environ:
    requester = os.getenv('GITHUB_USERNAME')
else:
    raise ValueError(f'"GITHUB_USERNAME" env var must be set to proceed.')

try:
    cache
except NameError:
    cache = LRUCache(10_000)


def ensure_gh_binder(func):
    """Ensure a function has a github API object

    Assumes the object comes in named 'gh'

    If *gh* is in the kwargs passed to the wrapped function, just pass
    though.

    If *gh* is not on kwargs, create one based on global values and
    pass it in.

    There is probably a better way to collect the values for the
    default api object.

    """

    @wraps(func)
    async def inner(*args, **kwargs):
        # if we get a gh API object, just use it
        if "gh" in kwargs:
            return await func(*args, **kwargs)

        # else, make one
        async with aiohttp.ClientSession() as session:
            gh = GitHubAPI(session, requester, oauth_token=oauth_token, cache=cache)
            return await func(*args, **kwargs, gh=gh)

    return inner


@ensure_gh_binder
async def get_default_branch(org_name: str, repo: str, *, gh: GitHubAPI):
    """Given an org name, info on all of the repos in that org"""
    ret = await gh.getitem(
        "/repos/{owner}/{repo}", url_vars={"owner": org_name, "repo": repo}
    )
    return ret


@ensure_gh_binder
async def get_all_default_branches(fname="all_repos.yaml", *, gh: GitHubAPI):
    with open(fname) as fin:
        checkouts = list(yaml.unsafe_load_all(fin))

    for proj in checkouts:
        if proj["primary_remote"]['host'] == "github.com":
            try:
                ret = await get_default_branch(
                    proj["primary_remote"]["user"],
                    proj["primary_remote"]["repo_name"],
                )
            except gidgethub.BadRequest:
                print(f'The project {proj["name"]} has no upstream on '
                      f"{proj['primary_remote']['user']} with "
                      f"{proj['primary_remote']['repo_name']}")
                continue
            proj["primary_remote"]["default_branch"] = ret["default_branch"]

            for _, remote in proj["remotes"].items():
                if remote["host"] == "github.com":
                    remote['default_branch'] = proj["primary_remote"]["default_branch"]

    return checkouts


# info = asyncio.run(get_default_branch("matplotlib", "matplotlib"))
checkouts = asyncio.run(get_all_default_branches())


with open("all_repos.yaml", "w") as fout:
    yaml.dump_all(checkouts, fout)
