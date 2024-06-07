import yaml
from pathlib import Path

with open('all_repos.yaml') as fin:
    checkouts = list(yaml.unsafe_load_all(fin))

local_checkouts = {co['name']: co for co in checkouts}

repos = []


for order in sorted(Path('build_order.d').glob('[!.]*yaml')):
    with open(order) as fin:
        build_order = list(yaml.unsafe_load_all(fin))

    for step in build_order:
        if step['kind'] != 'source_install':
            continue
        lc = local_checkouts[step['proj_name']]
        repos.append(lc['primary_remote'])

with open("used_repos.yaml", "w") as fout:
    yaml.dump_all(repos, fout)
