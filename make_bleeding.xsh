#! /usr/env xonsh
import sys
import argparse
from pathlib import Path

import yaml


from xonsh.dirstack import with_pushd

xonsh_abs_path = str(Path(sys.executable).parent / 'xonsh')

$RAISE_SUBPROC_ERROR = True

$XONSH_TRACE_SUBPROC = True
$PIP_NO_BUILD_ISOLATION = 1

parser = argparse.ArgumentParser(description='Build the world.')
parser.add_argument("--target", help="name of env to create", type=str, default='bleeding')
parser.add_argument("--branch", help="CPython branch to build", type=str, default=None)
parser.add_argument("--no-pull", help="Try pull before building cpython (if on a branch)", action='store_true')
parser.add_argument("--clang", help="Try to use clang", action='store_true')
parser.add_argument("--freethread", help="Try to use freethreading (no GIL)", action='store_true')
parser.add_argument("--jit", help="Try to use the experimental jit", action='store_true')
args = parser.parse_args()




with open('all_repos.yaml') as fin:
    checkouts = list(yaml.unsafe_load_all(fin))
wd_mapping = {co['name']: co['local_checkout'] for co in checkouts}

wd = wd_mapping['cpython']

prefix = ${'HOME'}+f"/.pybuild/{args.target}"
prefix_as_path = Path(prefix)
if prefix_as_path.exists():
    rm -rf @(prefix)
prefix_as_path.mkdir(parents=True)

with with_pushd(wd):
    if args.branch is not None:
        git checkout @(args.branch)
    cur_branch = $(git branch --show-current).strip()
    if not args.no_pull and len(cur_branch):
        git pull
    git clean -xfd
    if args.clang:
        $CC = 'clang'
        $CXX = 'clang++'
    ./configure \
        --prefix=@(prefix) \
        --enable-shared LDFLAGS=@(f"-Wl,-rpath,$HOME/.pybuild/{args.target}/lib") \
        @('--disable-gil' if args.freethread else '') \
        @('--enable-experimental-jit' if args.jit else '')
    make -j
    make install

$HOME/.pybuild/@(args.target)/bin/python3 -m venv --copies --clear ~/.virtualenvs/@(args.target)
# the build package seems to require this?
ln $HOME/.pybuild/@(args.target)/bin/python3 $HOME/.pybuild/@(args.target)/bin/python


source-bash  f'~/.virtualenvs/{args.target}/bin/activate'

pip install --upgrade pip

pip cache remove '*cp313?-linux*' || true
pip cache remove '*cp314?-linux*' || true
pip cache remove '*cp315?-linux*' || true
pip cache remove '*cp316?-linux*' || true


@(xonsh_abs_path) build_py_env.xsh
