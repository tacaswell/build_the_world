import json
import sys

import time
import yaml
from pathlib import Path

from subprocess import CalledProcessError

from xonsh.dirstack import with_pushd

$RAISE_SUBPROC_ERROR = False
$XONSH_TRACE_SUBPROC = False
$PIP_NO_BUILD_ISOLATION = 1
# $PYO3_USE_ABI3_FORWARD_COMPATIBILITY=1


def extract_git_shas():
    headsha = $(git rev-parse HEAD).strip()
    describe = $(git describe --tags --abbrev=11 --long --dirty --always).strip()
    return {'head': headsha, 'describe': describe}

build_order = []
for order in  sorted(Path('build_order.d').glob('[!.]*yaml')):
    with open(order) as fin:
        build_order += list(yaml.unsafe_load_all(fin))

with open('all_repos.yaml') as fin:
    checkouts = list(yaml.unsafe_load_all(fin))

local_checkouts = {co['name']: co for co in checkouts}

out = {}



for step in build_order:
    if step['kind'] != 'source_install':
        continue
    lc = local_checkouts[step['proj_name']]
    # get the working directory
    step['wd'] = lc['local_checkout']
    # set the default branch
    if step['project']['primary_remote']['vc'] != 'git':
        continue

    upstream_remote = next(
            n for n, r in lc['remotes'].items() if r['url'] == lc['primary_remote']['url']
        )
    upstream_branch = step['project']['primary_remote']['default_branch']

    def foo(upstream_branch, checkout):
        with with_pushd(checkout):
            with ${...}.swap(RAISE_SUBPROC_ERROR=False):
                tracking = !(git rev-parse --abbrev-ref --symbolic-full-name '@{u}')
                has_tracking = bool(tracking)
                tracking_branch = tracking.output.strip()
                del tracking
            with ${...}.swap(RAISE_SUBPROC_ERROR=True):
                cur_branch = $(git branch --show-current).strip()
                upstream = f'{upstream_remote}/{upstream_branch}'
            with ${...}.swap(RAISE_SUBPROC_ERROR=False):
                is_merged = bool(!(git merge-base --is-ancestor  HEAD @(upstream)))
            shas = extract_git_shas()
            return locals()
    out[step['name']] = foo(upstream_branch, lc['local_checkout'])


for k, v in out.items():
    if v['cur_branch'] != v['upstream_branch']:
        print(f"{k} ({v['checkout']})")
        print(f"   default: {v['upstream_branch']}")
        print(f"   on: {v['cur_branch']} ({v['tracking_branch'] if v['has_tracking'] else '-'})")
