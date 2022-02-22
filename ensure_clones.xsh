from pathlib import Path
import yaml

with open("build_order.yaml") as fin:
    build_order = list(yaml.unsafe_load_all(fin))

build_order = [b for b in build_order if b["kind"] == "source_install"]

build_order = [
    b for b in build_order if b["project"]["primary_remote"].get("vc", None) == "git"
]

build_order = [
    b
    for b in build_order
    if b["project"]["primary_remote"].get("host", None) == "github.com"
]

print(set(b["project"]["primary_remote"]["user"] for b in build_order))

bnl_orgs = {
    "networkx",
    "soft-matter",
    "zarr-developers",
    "pcdshub",
    "NSLS-II",
    "silx-kit",
    "dask",
    "bluesky",
    "h5py",
    "intake",
    "scikit-hep",
    "cgohlke",
    "Nikea",
    "astropy",
}

def source_clone(org, repo, dest='other_source'):
    target = p'~/source' / dest / org
    target.mkdir(parents=True, exist_ok=True)
    cd @(target)
    hub clone --recursive @('/'.join((org, repo)))
    cd @(repo)


def sc_wrapper(target, org, repo, fork=True):
    source_clone(org, repo, dest=target)
    if fork:
        hub fork


for b in build_order:
    remote = b["project"]["primary_remote"]
    if remote["user"] in bnl_orgs:
        sc_wrapper('bnl', remote['user'],remote['repo_name'])
    else:
        sc_wrapper('p', remote['user'],remote['repo_name'])
