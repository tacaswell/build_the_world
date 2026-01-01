#! /usr/env xonsh
import sys
import argparse
from pathlib import Path
import re

import yaml


from xonsh.dirstack import with_pushd

xonsh_abs_path = str(Path(sys.executable).parent / 'xonsh')

$RAISE_SUBPROC_ERROR = True

$XONSH_TRACE_SUBPROC = True
$PIP_NO_BUILD_ISOLATION = 1

parser = argparse.ArgumentParser(description='Build the world.')
parser.add_argument("--target", help="name of env to create", type=str, default=None)
parser.add_argument("--branch", help="CPython branch to build", type=str, default=None)
parser.add_argument("--no-pull", help="Do not try to pull before building cpython (if on a branch)", action='store_true')
parser.add_argument("--clang", help="Use clang", action='store_true')
parser.add_argument("--debug", help="Debug build of CPython", action='store_true')
parser.add_argument("--freethread", help="Try to use freethreading (no GIL)", action='store_true')
parser.add_argument("--jit", help="Try to use the experimental jit", action='store_true')
args = parser.parse_args()

target = args.target
branch = args.branch
if target is None and branch is not None:
    if branch == 'main':
        target = 'cp315'
    elif re.match(r'3\.[0-9]+', branch):
        target = f'cp{branch.replace(".", "")}'

    if args.freethread:
        target += 't'
    if args.jit:
        target += '-jit'

    if args.clang:
        target += '-clang'

if target is None:
    raise ValueError("Can not guess env name, specify target")


if target.startswith('py'):
    print("stop using pyXX env names")
    sys.exit(-1)


with open('all_repos.yaml') as fin:
    checkouts = list(yaml.unsafe_load_all(fin))
wd_mapping = {co['name']: co['local_checkout'] for co in checkouts}

wd = wd_mapping['cpython']

prefix = ${'HOME'}+f"/.pybuild/{target}"
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
        --enable-shared LDFLAGS=@(f"-Wl,-rpath,$HOME/.pybuild/{target}/lib") \
        --enable-optimizations \
        --with-lto \
        @('--with-pydebug' if args.debug else '')  \
        @('--disable-gil' if args.freethread else '') \
        @('--enable-experimental-jit' if args.jit else '')
    nproc = $(nproc)
    make -j@(nproc)
    make install

$HOME/.pybuild/@(target)/bin/python3 -m venv --copies --clear ~/.virtualenvs/@(target)
# the build package seems to require this?
ln $HOME/.pybuild/@(target)/bin/python3 $HOME/.pybuild/@(target)/bin/python


source-bash  f'~/.virtualenvs/{target}/bin/activate'

pip install --upgrade pip

pip cache remove '*cp313?-linux*' || true
pip cache remove '*cp314?-linux*' || true
pip cache remove '*cp315?-linux*' || true
pip cache remove '*cp316?-linux*' || true


@(xonsh_abs_path) build_py_env.xsh
