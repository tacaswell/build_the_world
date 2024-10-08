$RAISE_SUBPROC_ERROR = True

from pathlib import Path
import yaml

import argparse


parser = argparse.ArgumentParser(description='Clone all of the needed source repos.')
parser.add_argument("--target", help="Path to clone into", type=str, default='~/source')
parser.add_argument("--caswell", help="If Caswell's sorting should be applied", action='store_true')
args = parser.parse_args()


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
    target = Path(args.target).expanduser() / dest / org
    target.mkdir(parents=True, exist_ok=True)
    cd @(target)
    if not (target / repo).exists():
        git clone --recursive @('https://github.com/' + '/'.join((org, repo)))
    else:
        cd @(target / repo)
        git remote update



with open('used_repos.yaml') as fin:
    required_repos = list(yaml.unsafe_load_all(fin))

print(set(b["user"] for b in required_repos))

for remote in required_repos:
    if not args.caswell:
        source_clone(remote['user'], remote['repo_name'], dest='')
    elif remote["user"].lower() in bnl_orgs:
        source_clone(remote['user'], remote['repo_name'], dest='bnl')
    else:
        source_clone(remote['user'] ,remote['repo_name'], dest='p')
