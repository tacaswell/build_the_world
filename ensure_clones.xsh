$RAISE_SUBPROC_ERROR = True

from pathlib import Path
import yaml

# Handle git




bnl_orgs = {
    "networkx",
    "soft-matter",
    "zarr-developers",
    "pcdshub",
    "nsls-ii",
    "silx-kit",
    "dask",
    "bluesky",
    "h5py",
    "intake",
    "scikit-hep",
    "cgohlke",
    "nikea",
    "astropy",
}

def source_clone(org, repo, dest='other_source'):
    target = p'~/source' / dest / org
    target.mkdir(parents=True, exist_ok=True)
    cd @(target)
    if not (target / repo).exists():
        git clone --recursive @('git@github.com:' + '/'.join((org, repo)))



with open('used_repos.yaml') as fin:
    required_repos = list(yaml.unsafe_load_all(fin))

print(set(b["user"] for b in required_repos))

for remote in required_repos:
    if remote["user"].lower() in bnl_orgs:
        source_clone(remote['user'], remote['repo_name'], dest='bnl')
    else:
        source_clone(remote['user'] ,remote['repo_name'], dest='p')
