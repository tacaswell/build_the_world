import argparse
from typing import Dict, Optional
from collections import defaultdict
from pathlib import Path
import sys
from dataclasses import dataclass, asdict

import yaml

from xonsh.dirstack import with_pushd
from xonsh.tools import XonshCalledProcessError

parser = argparse.ArgumentParser(description='Find source repos.')
parser.add_argument("path", help='Top path to start searching for repos in.', type=Path)
parser.add_argument("--update-used", help="If the used repo yaml should be updated.", action='store_true')
args = parser.parse_args()

path = args.path


def find_git_repos(path):
    for candidate in !(find @(path) -type d -name '.git'):
        candidate = candidate.strip()
        if '.tox' in str(candidate):
            continue
        yield Path(candidate).resolve().parent


def find_hg_repos(path):
    for candidate in !(find @(path) -type d -name '.hg'):
        candidate = candidate.strip()
        yield Path(candidate).resolve().parent

def fix_git_protcol_to_https(repo):
    with with_pushd(repo):
        for ln in !(git remote -v).itercheck():
            if not ln.strip():
                continue
            name, url, _ = ln.split()
            if url.startswith('git://') and 'github.com' in url:
                print(url, '->', url.replace('git://', 'https://'))
                git remote set-url @(name) @(url.replace('git://', 'https://'))

def get_git_remotes(repo):
    """Given a path to a repository,
    """
    remotes = defaultdict(dict)

    with with_pushd(repo):
        for remote in !(git remote -v).itercheck():
            name, _, rest = remote.strip().partition('\t')
            url, _, direction = rest.partition(' (')
            direction = direction[:-1]
            remotes[name][direction] = url

    return dict(remotes)

def get_work_trees(repo):
    with with_pushd(repo):
        primary, *worktrees = [Path(_.split()[0]) for _ in !(git worktree list).itercheck()]

    return primary, worktrees

def get_hg_remotes(repo):
    """Given a path to a repository,
    """
    remotes = {}

    with with_pushd(repo):
        for remote in !(hg paths).itercheck():
            name, _, url = [_.strip() for _ in remote.strip().partition('=')]
            remotes[name] = url

    return dict(remotes)


@dataclass
class Remote:
    url: str
    protocol: str
    host: str
    user: Optional[str]
    repo_name: Optional[str]
    ssh_user: Optional[str] = None
    vc: str = "git"


@dataclass
class Project:
    name: str
    primary_remote: Remote
    remotes: Dict[str, Remote]
    local_checkout: str


def strip_dotgit(repo_name):
    return repo_name[:-4] if repo_name.endswith(".git") else repo_name


def parse_git_name(git_url):
    if git_url.startswith("git@"):
        _, _, rest = git_url.partition("@")
        host, _, rest = rest.partition(":")
        parts = rest.split("/")
        if len(parts) == 1:
            user = None
            (repo_name,) = parts
        elif len(parts) == 2:
            user, repo_name = parts
        else:
            user, *rest = parts
            repo_name = "/".join(rest)
        return Remote(
            url=git_url,
            host=host,
            user=user,
            repo_name=strip_dotgit(repo_name),
            ssh_user="git",
            protocol="ssh",
        )
    elif git_url.startswith("git://"):
        rest = git_url[len("git://") :]
        parts = rest.split("/")
        if len(parts) == 1:
            raise ValueError(f"this should not happen {git_url} {parts}")
        elif len(parts) == 2:
            host, repo_name = parts
            user = None
        elif len(parts) == 3:
            host, user, repo_name = parts
        else:
            host, user, *rest = parts
            repo_name = "/".join(rest)
        return Remote(
            url=f'git@{host}:{user}/{repo_name}',
            host=host,
            user=user,
            repo_name=strip_dotgit(repo_name),
            ssh_user='git',
            protocol="ssh",
        )
    elif git_url.startswith("ssh://") or git_url.startswith("ssh+git://"):
        _, _, rest = git_url.partition(":")
        rest = rest[2:]
        if "@" in rest:
            ssh_user, _, rest = git_url.partition("@")
        else:
            ssh_user = ${'USER'}
        host, _, repo_name = rest.partition("/")
        return Remote(
            url=git_url,
            host=host,
            user=None,
            repo_name=strip_dotgit(repo_name),
            ssh_user=ssh_user,
            protocol="ssh",
        )
    elif git_url.startswith("https://"):
        rest = git_url[len("https://") :]
        parts = rest.split("/")
        if len(parts) >= 3:
            host, user, *rest = parts
            repo_name = "/".join(rest)
        elif len(parts) == 2:
            host, repo_name = parts
            user = None
        elif len(parts) < 2:
            raise ValueError(f"do not think this can happen {git_url} {parts}")
        return Remote(
            url=git_url,
            host=host,
            user=user,
            repo_name=strip_dotgit(repo_name),
            protocol="https",
        )
        return "http"
    elif "@" in git_url:
        ssh_user, _, rest = git_url.partition("@")
        host, _, rest = rest.partition(":")
        user, _, repo_name = rest.partition("/")
        return Remote(
            url=git_url,
            host=host,
            user=user,
            repo_name=strip_dotgit(repo_name),
            ssh_user=ssh_user,
            protocol="ssh",
        )
    elif git_url.startswith("/") or git_url.startswith("."):
        return Remote(
            url=git_url, host="localhost", user=None, repo_name=None, protocol="file"
        )
    elif ":" in git_url:
        host, _, repo_name = git_url.partition(":")
        ssh_user = ${'USER'}
        return Remote(
            url=git_url,
            host=host,
            user=None,
            repo_name=strip_dotgit(repo_name),
            ssh_user=ssh_user,
            protocol="ssh",
        )
    else:
        raise ValueError(f"unknown scheme: {git_url}")


def parse_hg_name(hg_url):
    if hg_url.startswith("http"):
        proto, _, rest = hg_url.partition("://")
        host, *parts = [_ for _ in rest.split("/") if len(_)]
        if parts[0] == "hg":
            parts = parts[1:]
        if len(parts) == 1:
            (repo_name,) = parts
            user = None
        elif len(parts) == 2:
            user, repo_name = parts
        else:
            user, *rest = parts
            repo_name = "/".join(parts)
        return Remote(
            url=hg_url,
            host=host,
            user=user,
            repo_name=repo_name,
            ssh_user=None,
            protocol=proto,
            vc="hg",
        )
    elif hg_url.startswith("ssh"):
        proto, _, rest = hg_url.partition("://")
        if "@" in rest:
            ssh_user, _, rest = rest.partition("@")
        else:
            ssh_user = ${'USER'}
        host, *parts = [_ for _ in rest.split("/") if len(_)]
        if parts[0] == "hg":
            parts = parts[1:]
        if len(parts) == 1:
            (repo_name,) = parts
            user = None
        elif len(parts) == 2:
            user, repo_name = parts
        else:
            user, *rest = parts
            repo_name = "/".join(parts)
        return Remote(
            url=hg_url,
            host=host,
            user=user,
            repo_name=repo_name,
            ssh_user=ssh_user,
            protocol=proto,
            vc="hg",
        )


print(sys.version_info)

projects = []

for repo_path in find_git_repos(path):
    print(repo_path)
    remotes = {}
    fix_git_protcol_to_https(repo_path)
    for k, v in get_git_remotes(repo_path).items():
        print(f"\t{k}")
        parsed = {direction: parse_git_name(url) for direction, url in v.items()}
        assert len(parsed) == 2
        remotes[k] = parsed["fetch"]
    if not len(remotes):
        continue
    for k in ["upstream", "origin"]:
        if k in remotes:
            primary_remote = remotes[k]
            break
    else:
        primary_remote = next(iter(remotes.values()))
    if primary_remote is None:
        continue
    projects.append(
        Project(
            name=primary_remote.repo_name,
            primary_remote=primary_remote,
            remotes=remotes,
            local_checkout=str(repo_path),
        )
    )


for repo_path in find_hg_repos(path):
    print(repo_path)
    remotes = {}
    for k, url in get_hg_remotes(repo_path).items():
        print(f"\t{k}")
        remotes[k] = parse_hg_name(url)
    if not len(remotes):
        continue
    for k in ["origin", "default"]:
        if k in remotes:
            primary_remote = remotes[k]
            break
    else:
        primary_remote = next(iter(remotes.values()))
    if primary_remote is None:
        continue
    projects.append(
        Project(
            name=primary_remote.repo_name,
            primary_remote=primary_remote,
            remotes=remotes,
            local_checkout=str(repo_path),
        )
    )


with open("all_repos.yaml", "w") as fout:
    yaml.dump_all([asdict(_) for _ in projects], fout)

if args.update_used:
    local_checkouts = {co.name: co for co in projects}

    repos = []

    for order in sorted(Path('build_order.d').glob('[!.]*yaml')):
        with open(order) as fin:
            build_order = list(yaml.unsafe_load_all(fin))

        for step in build_order:
            if step['kind'] != 'source_install':
                continue
            lc = local_checkouts[step['proj_name']]
            repos.append(asdict(lc.primary_remote))
    repos.append(asdict(local_checkouts['cpython'].primary_remote))

    with open("used_repos.yaml", "w") as fout:
        yaml.dump_all(sorted(repos, key=lambda x: (x['user'], x['repo_name'])), fout)
