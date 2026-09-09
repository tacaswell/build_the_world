import argparse
from typing import Dict, Optional
from collections import defaultdict
from pathlib import Path
import sys
from dataclasses import dataclass, asdict
import os
import subprocess
import tqdm
from concurrent.futures import ThreadPoolExecutor, as_completed

import yaml

parser = argparse.ArgumentParser(description='Find source repos.')
parser.add_argument("path", help='Top path to start searching for repos in.', type=Path)
parser.add_argument("--update-used", help="If the used repo yaml should be updated.", action='store_true')
args = parser.parse_args()

path = args.path


def find_git_repos(path):
    for candidate in $(find @(path) -type d -name '.git').split():
        candidate = candidate.strip()
        if '.tox' in str(candidate):
            continue
        if 'crabby-rathbun' in str(candidate):
            continue
        yield Path(candidate).resolve().parent


def find_hg_repos(path):
    for candidate in !(find @(path) -type d -name '.hg'):
        candidate = candidate.strip()
        yield Path(candidate).resolve().parent

def _git(repo, *args):
    """Run a git command in a repo using stdlib subprocess (thread-safe)."""
    return subprocess.run(
        ["git", "-C", str(repo), *args],
        capture_output=True, text=True, check=True,
    ).stdout


def fix_git_protcol_to_https(repo):
    for ln in _git(repo, "remote", "-v").splitlines():
        if not ln.strip():
            continue
        try:
            name, url, _ = ln.split()
        except Exception:
            print(repo, ln)
            continue
        if url.startswith('git://') and 'github.com' in url:
            new_url = url.replace('git://', 'https://')
            print(url, '->', new_url)
            subprocess.run(
                ["git", "-C", str(repo), "remote", "set-url", name, new_url],
                check=True,
            )


def get_git_remotes(repo):
    """Given a path to a repository, return its remotes."""
    remotes = defaultdict(dict)

    for remote in _git(repo, "remote", "-v").splitlines():
        if not remote.strip():
            continue
        name, _, rest = remote.strip().partition('\t')
        url, _, direction = rest.partition(' (')
        direction = direction[:-1]
        remotes[name][direction] = url

    return dict(remotes)


def get_work_trees(repo):
    a = _git(repo, "worktree", "list", "--porcelain")

    primary, *rest = [
        {
            k: v
            for k, v in [
                ___.split(" ") if " " in ___ else ("branch", None) for ___ in __
            ]
        }
        for __ in [_.split("\n") for _ in a.split("\n\n") if len(_)]
    ]

    return primary, rest


def get_hg_remotes(repo):
    """Given a path to a repository, return its remotes."""
    remotes = {}

    ret = subprocess.run(
        ["hg", "-R", str(repo), "paths"],
        capture_output=True, text=True,
    )
    if ret.returncode not in (0, 1):
        print(f"warning: hg paths in {repo} exited {ret.returncode}: {ret.stderr.strip()}")
    out = ret.stdout
    for remote in out.splitlines():
        if not remote.strip():
            continue
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


def process_git_repo(repo_path):
    """Process a single git repo; returns a Project or None. Safe to call from threads."""
    base, worktrees = get_work_trees(repo_path)
    if str(repo_path) != base['worktree']:
        return None
    remotes = {}
    fix_git_protcol_to_https(repo_path)
    for k, v in get_git_remotes(repo_path).items():
        parsed = {direction: parse_git_name(url) for direction, url in v.items()}
        assert len(parsed) == 2
        remotes[k] = parsed["fetch"]
    if not len(remotes):
        return None
    for k in ["upstream", "origin"]:
        if k in remotes:
            primary_remote = remotes[k]
            break
    else:
        primary_remote = next(iter(remotes.values()))
    if primary_remote is None:
        return None
    return Project(
        name=primary_remote.repo_name,
        primary_remote=primary_remote,
        remotes=remotes,
        local_checkout=str(repo_path),
    )


def process_hg_repo(repo_path):
    """Process a single hg repo; returns a Project or None. Safe to call from threads."""
    remotes = {}
    for k, url in get_hg_remotes(repo_path).items():
        remotes[k] = parse_hg_name(url)
    if not len(remotes):
        return None
    for k in ["origin", "default"]:
        if k in remotes:
            primary_remote = remotes[k]
            break
    else:
        primary_remote = next(iter(remotes.values()))
    if primary_remote is None:
        return None
    return Project(
        name=primary_remote.repo_name,
        primary_remote=primary_remote,
        remotes=remotes,
        local_checkout=str(repo_path),
    )


print(sys.version_info)

# Use 2x CPU count workers: git subprocess calls are I/O-bound so threads
# can overlap while waiting on disk/network.
_workers = (os.cpu_count() or 1) * 2

projects = []

git_repos = list(find_git_repos(path))
with ThreadPoolExecutor(max_workers=_workers) as executor:
    futures = {executor.submit(process_git_repo, repo_path): repo_path for repo_path in git_repos}
    for future in tqdm.tqdm(as_completed(futures), total=len(git_repos), desc="git repos"):
        result = future.result()
        if result is not None:
            projects.append(result)


hg_repos = list(find_hg_repos(path))
with ThreadPoolExecutor(max_workers=_workers) as executor:
    futures = {executor.submit(process_hg_repo, repo_path): repo_path for repo_path in hg_repos}
    for future in tqdm.tqdm(as_completed(futures), total=len(hg_repos), desc="hg repos"):
        result = future.result()
        if result is not None:
            projects.append(result)


with open("all_repos.yaml", "w") as fout:
    yaml.dump_all([asdict(_) for _ in projects], fout)

if args.update_used:
    local_checkouts = {co.name: co for co in projects}

    repos = []

    for order in sorted(Path('build_order.d').glob('[!.]*yaml')):
        with open(order) as fin:
            build_order = list(yaml.safe_load_all(fin))

        for step in build_order:
            if step['kind'] != 'source_install':
                continue
            lc = local_checkouts[step['proj_name']]
            repos.append(asdict(lc.primary_remote))
    repos.append(asdict(local_checkouts['cpython'].primary_remote))
    repos = filter(lambda x: x['vc'] == 'git', repos)
    with open("used_repos.yaml", "w") as fout:
        yaml.dump_all(sorted(repos, key=lambda x: (x['user'], x['repo_name'])), fout)
