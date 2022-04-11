import yaml

with open("build_order.yaml") as fin:
    build_order = list(yaml.unsafe_load_all(fin))

with open('all_repos.yaml') as fin:
    checkouts = list(yaml.unsafe_load_all(fin))

local_checkouts = {co['name']: co for co in checkouts}

for step in build_order:
    if step['kind'] != 'source_install':
        continue
    lc = local_checkouts[step['proj_name']]
    step['project']['primary_remote'] = lc['primary_remote']


with open("build_order.yaml", "w") as fout:
    yaml.dump_all(build_order, fout)
