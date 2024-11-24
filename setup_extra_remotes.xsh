from pathlib import Path
import re

import yaml
from collections import defaultdict

from xonsh.dirstack import with_pushd


$RAISE_SUBPROC_ERROR = False
$XONSH_TRACE_SUBPROC = False
$PIP_NO_BUILD_ISOLATION = 1

def fix_remotes():
    for j, r in enumerate($(git remote).strip().split('\n')):
        remote_url = $(git remote get-url @(r)).strip()
        if ret := re.search(r'git@github.com:(?P<org>.+)/(?P<repo>.*)', remote_url):
            git remote set-url @(r) f'https://github.com/{ret["org"]}/{ret["repo"]}'
            git remote set-url @(r) --push  f'git@github.com:{ret["org"]}/{ret["repo"]}'


def get_git_remotes(repo):
    """Given a path to a repository, get remotes
    """
    remotes = defaultdict(dict)

    with with_pushd(repo):
        for remote in !(git remote -v).itercheck():
            name, _, rest = remote.strip().partition('\t')
            url, _, direction = rest.partition(' (')
            direction = direction[:-1]
            remotes[name][direction] = url

    return dict(remotes)


with open('all_repos.yaml') as fin:
    checkouts = list(yaml.unsafe_load_all(fin))

local_checkouts = {co['name']: co for co in checkouts}
del checkouts

with open('extra_remotes.yaml') as fin:
    extra_remotes = {r['proj_name']: r for r in yaml.unsafe_load_all(fin)}


build_order = []
for order in  sorted(Path('build_order.d').glob('[!.]*yaml')):
    with open(order) as fin:
        build_order += [
            bs
            for bs in yaml.unsafe_load_all(fin)
            if bs['kind'] == 'source_install'
        ]

for step in build_order:
    lc = local_checkouts[step['proj_name']]
    wd = lc['local_checkout']
    print(step['proj_name'], wd)
    if project := extra_remotes.get(step['proj_name'], None):
        remotes = get_git_remotes(wd)
        with with_pushd(wd):
            fix_remotes()
            if project['remote_name'] not in remotes:
                git remote add @(project['remote_name']) @(project['remote']['url'])
            elif remotes[project['remote_name']]['push'] != project['remote']['url']:
                git remote set-url @(project['remote_name']) @(project['remote']['url'])
            git fetch @(project['remote_name'])
            if $(git branch --list @(project['branch'])):
                git reset --hard @(project['remote_name'])/@(project['branch'])
            else:
                git switch -c @(project['branch']) -t @(project['remote_name'])/@(project['branch'])
    else:
        with with_pushd(wd):
            fix_remotes()
            git switch @(step['default_branch'])
