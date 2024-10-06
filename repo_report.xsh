import json
import sys

import time
import yaml
from pathlib import Path

from subprocess import CalledProcessError

from xonsh.dirstack import with_pushd
import sys

$RAISE_SUBPROC_ERROR = False
$XONSH_TRACE_SUBPROC = False


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
    if lc['primary_remote']['vc'] != 'git':
        continue

    upstream_remote = next(
            n for n, r in lc['remotes'].items() if r['url'] == lc['primary_remote']['url']
        )
    upstream_branch = step['default_branch']

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
    out[step['proj_name']] = foo(upstream_branch, lc['local_checkout'])

extra_remotes = []

for k, v in out.items():
    off_dflt_branch = v['cur_branch'] != v['upstream_branch']
    dirty_src = 'dirty' in v['shas']['describe']
    if off_dflt_branch or dirty_src:
        print(f"{k} ({v['checkout']})")
        if off_dflt_branch:
            print(f"   default: {v['upstream_branch']}")
            print(f"   on: {v['cur_branch']} [{v['shas']['describe']}]({v['tracking_branch'] if v['has_tracking'] else '-'})")
            if v['has_tracking']:
                remote_name, *junk = v['tracking_branch'].partition('/')
                extra_remotes.append(
                    {'proj_name': k, 'branch': v['cur_branch'], 'remote': local_checkouts[k]['remotes'][remote_name], 'remote_name': remote_name}
                )
        if dirty_src:
            print("   DIRTY")

with open('extra_remotes.yaml', 'w') as fout:
    yaml.dump_all(sorted(extra_remotes, key=lambda x: x['proj_name']), fout)
