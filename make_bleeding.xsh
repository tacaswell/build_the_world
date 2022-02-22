#! /usr/env xonsh
import sys
import argparse

import yaml

from xonsh.dirstack import with_pushd



$XONSH_TRACE_SUBPROC = True
$PIP_NO_BUILD_ISOLATION = 1

parser = argparse.ArgumentParser(description='Build the world.')
parser.add_argument("--target", help="name of env to create", type=str, default='bleeding')
parser.add_argument("--branch", help="CPython branch to build", type=str, default='main')
args = parser.parse_args()




with open('all_repos.yaml') as fin:
    checkouts = list(yaml.unsafe_load_all(fin))
wd_mapping = {co['name']: co['local_checkout'] for co in checkouts}

wd = wd_mapping['cpython']

prefix = ${'HOME'}+f"/.pybuild/{args.target}"

with with_pushd(wd):
    git remote update
    git checkout @(args.branch)
    git pull
    git clean -xfd
    ./configure --prefix=@(prefix) --enable-shared LDFLAGS=-Wl,-rpath=$HOME/.pybuild/@(args.target)/lib
    make -j
    make install

$HOME/.pybuild/@(args.target)/bin/python3 -m venv --copies --clear ~/.virtualenvs/@(args.target)

source-bash  f'~/.virtualenvs/{args.target}/bin/activate'

pip install --upgrade pip
pip cache remove '*cp311-linux*' || true

xonsh build_py_env.xsh
