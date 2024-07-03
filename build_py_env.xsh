import json
import sys

import time
import uuid
import yaml
import datetime
from pathlib import Path

from subprocess import CalledProcessError

from xonsh.dirstack import with_pushd


$RAISE_SUBPROC_ERROR = False
$XONSH_TRACE_SUBPROC = True
$PIP_NO_BUILD_ISOLATION = 1

$CXXFLAGS = ' '.join(('-fpermissive', ${...}.get('CXXFLAGS', '')))

MESON_LAPACK = ''

if sys.platform == 'darwin':
    # make sure we find openblas from homebrew
    $LDFLAGS = ' '.join(
        (
        "-L/opt/homebrew/opt/openblas/lib",
        "-L/opt/homebrew/Cellar/libxcb/1.15/lib/",
        '-L/opt/homebrew/Cellar/libyaml/0.2.5/lib/',
        '-L/opt/homebrew/Cellar/librdkafka/1.9.0/lib',
        '-L/opt/homebrew/Cellar/libxcb/1.15/lib',
        )
    )
    $LD_LIBRARY_PATH = '/opt/homebrew/Cellar/libxcb/1.15/lib/'
    $CPPFLAGS = "-I/opt/homebrew/opt/openblas/include"
    $PKG_CONFIG_PATH = "/opt/homebrew/opt/openblas/lib/pkgconfig"
    $CFLAGS = ' '.join(
        (
        '-I/opt/homebrew/Cellar/libyaml/0.2.5/include/',
        '-I/opt/homebrew/Cellar/graphviz/3.0.0/include',
        '-I/opt/homebrew/Cellar/librdkafka/1.9.0/include',
        '-I/opt/homebrew/Cellar/libxcb/1.15/include',
        ${...}.get('CFLAGS', '')
        )
    )
    $HDF5_DIR = '/opt/homebrew/Cellar/hdf5/1.12.2_2'
    # un-comment these to build freetype with CF compilers
    # del $host_alias
    # del $build_alias
    os = 'OSX'
else:
    os_release = {}
    with open('/etc/os-release') as fin:
        for ln in fin:
            k, _, v = ln.strip().partition('=')
            os_release[k] = v
    if os_release['ID'] == 'fedora':
       MESON_LAPACK = '-Csetup-args=-Dblas=flexiblas -Csetup-args=-Dlapack=flexiblas'
$CFLAGS='-DCYTHON_FAST_THREAD_STATE=0'


build_order = []
for order in  sorted(Path('build_order.d').glob('[!.]*yaml')):
    with open(order) as fin:
        build_order += list(yaml.unsafe_load_all(fin))

with open('all_repos.yaml') as fin:
    checkouts = list(yaml.unsafe_load_all(fin))

local_checkouts = {co['name']: co for co in checkouts}

for step in build_order:
    if step['kind'] != 'source_install':
        continue
    lc = local_checkouts[step['proj_name']]
    # get the working directory
    step['wd'] = lc['local_checkout']

    step.setdefault('kwargs', {})
    step['kwargs']['upstream_branch'] = step['default_branch']

    step['kwargs']['upstream_remote'] = next(
            n for n, r in lc['remotes'].items() if r['url'] == lc['primary_remote']['url']
        )


def extract_git_shas():
    headsha = $(git rev-parse HEAD).strip()
    describe = $(git describe --tags --abbrev=11 --long --dirty --always).strip()
    return {'head': headsha, 'describe': describe}


def auto_main(upstream_remote='origin', upstream_branch='master'):
    with ${...}.swap(RAISE_SUBPROC_ERROR=True):
        git remote update
    with ${...}.swap(RAISE_SUBPROC_ERROR=False):
        tracking = !(git rev-parse --abbrev-ref --symbolic-full-name '@{u}')
        has_tracking = bool(tracking)
        tracking_branch = tracking.output.strip()
    with ${...}.swap(RAISE_SUBPROC_ERROR=True):
        if has_tracking:
            git merge @(tracking_branch)
        git submodule update
        cur_branch = $(git branch --show-current).strip()
        upstream = f'{upstream_remote}/{upstream_branch}'
        # git fetch @(upstream_remote)
        if cur_branch in  {'main', 'master', 'develop', upstream_branch}:
            git merge @(upstream)
        else:
            with ${...}.swap(RAISE_SUBPROC_ERROR=False):
                is_merged = bool(!(git merge-base --is-ancestor  HEAD @(upstream)))
            if is_merged:
                print('Done')
                git checkout @(upstream_branch)
                git merge @(upstream)
                if len(cur_branch):
                    git branch -d @(cur_branch)
            else:
                git push tacaswell


def cleanup_cython():
    try:
        to_remove = [_ for _ in $(ack -l "Generated by Cython" --type=cc).split("\n") if _.strip()]
    except CalledProcessError:
        to_remove = []
    if to_remove:
        rm @(to_remove)


def setuptools_build(**kwargs):
    auto_main(**kwargs)
    git clean -xfd
    cleanup_cython()
    python bootstrap.py
    return !(pip install --no-build-isolation    .)

def git_cleanup():

    meson_packagecache = gp`subprojects/packagecache/*`
    print(meson_packagecache)
    for p in meson_packagecache:
        cp @(p) /tmp/@(p.name)

    git clean -xfd
    git submodule init
    git submodule update
    cleanup_cython()
    if meson_packagecache:
        mkdir -p subprojects/packagecache
    for p in meson_packagecache:
        cp /tmp/@(p.name) @(p)



def flit_build(**kwargs):
    auto_main(**kwargs)
    git_cleanup()
    with with_pushd('flit_core'):
        whl = $(python -m flit_core.wheel).split('\n')[1].split(' ')[-1]
        python bootstrap_install.py @(whl)
    return !(pip install --no-build-isolation .)


def main_build(**kwargs):
    auto_main(**kwargs)
    git_cleanup()
    return !(pip install --no-build-isolation .)


def setup_py_build(**kwargs):
    auto_main(**kwargs)
    git_cleanup()
    return !(python setup.py install)


def numcodecs_build(**kwargs):
    auto_main(**kwargs)
    git clean -xfd
    git submodule init
    git submodule update
    cleanup_cython()
    rm -rf numcodecs/*.c
    with ${...}.swap(DISABLE_NUMCODECS_AVX2=1):
        return !(pip install --no-build-isolation -v  .)


def cython_build(**kwargs):
    auto_main(**kwargs)
    git clean -xfd
    git submodule update
    return !(pip install --upgrade --no-use-pep517 --no-build-isolation     .)


def awkward_build(**kwargs):
    auto_main(**kwargs)
    git clean -xfd
    git submodule init
    git submodule update
    cleanup_cython()
    # this is what nox -s prepare does but without needing nox
    python dev/copy-cpp-headers.py
    python dev/generate-kernel-signatures.py
    python dev/generate-tests.py
    python dev/generate-kernel-docs.py
    return !(pip install -v ./awkward-cpp --no-build-isolation) and !(pip install --no-build-isolation .)


def numpy_build(**kwargs):
    auto_main(**kwargs)
    git clean -xfd
    cleanup_cython()
    git submodule update

    CFLAGS = (" -Wall -O2 -pipe -fomit-frame-pointer  "
              "-fno-strict-aliasing -Wmaybe-uninitialized  "
              "-Wdeprecated-declarations -Wimplicit-function-declaration  "
              "-march=native -DCYTHON_FAST_THREAD_STATE=0")
    # CFLAGS = ""
    with ${...}.swap(CFLAGS=CFLAGS):
        ret = !(python -m build --no-isolation --skip-dependency-check @(MESON_LAPACK.split()) .)
        if ret:
            wheel_file, = g`dist/*.whl`
            ret2 = !(pip install @(wheel_file))
            if not ret2:
                return ret2

        return ret



def scipy_build(**kwargs):
    auto_main(**kwargs)
    git clean -xfd
    git submodule update
    cleanup_cython()

    ret = !(python -m build --no-isolation --skip-dependency-check @(MESON_LAPACK.split()) .)
    if ret:
        wheel_file, = g`dist/*.whl`
        pip install @(wheel_file)
    return ret

def pandas_build(**kwargs):
    auto_main(**kwargs)
    git clean -xfd
    cleanup_cython()
    git submodule update
    ret = !(pip install -v  --no-build-isolation     .)
    bool(ret)
    return ret

def build_pyarrow(**kwargs):
    patch = """diff --git a/cpp/cmake_modules/Findlz4Alt.cmake b/cpp/cmake_modules/Findlz4Alt.cmake
index 77a22957f..ce35d81eb 100644
--- a/cpp/cmake_modules/Findlz4Alt.cmake
+++ b/cpp/cmake_modules/Findlz4Alt.cmake
@@ -33,6 +33,9 @@ if(lz4_FOUND)
   if(NOT TARGET LZ4::lz4 AND TARGET lz4::lz4)
     add_library(LZ4::lz4 ALIAS lz4::lz4)
   endif()
+  if(NOT TARGET LZ4::lz4 AND TARGET LZ4::lz4_shared)
+    add_library(LZ4::lz4 ALIAS LZ4::lz4_shared)
+  endif()
   return()
 endif()

"""
    auto_main(**kwargs)
    git stash
    git clean -xfd
    cleanup_cython()
    git stash pop
    $PARQUET_TEST_DATA=$PWD+"/cpp/submodules/parquet-testing/data"
    $PARQUET_TEST_DATA
    $ARROW_TEST_DATA=$PWD+"/testing/data"
    cd ../
    mkdir dist
    $ARROW_HOME=$PWD +'/dist'
    $LD_LIBRARY_PATH= [$PWD+"/dist/lib"]
    $CMAKE_PREFIX_PATH=[$ARROW_HOME]
    # patch from Arch packages
    # patch < lz4-cmake.patch  -p 1
    cmake -S arrow/cpp -B arrow/cpp/build \
               -DCMAKE_INSTALL_PREFIX=$ARROW_HOME \
               --preset ninja-release-python
    cmake --build arrow/cpp/build --target install -j
    pushd arrow/python
    git clean -xfd
    $PYARROW_WITH_PARQUET=1
    $PYARROW_WITH_DATASET=1
    $PYARROW_PARALLEL=25
    return !(pip install -v . --no-build-isolation)

def build_yarl(name, **kwargs):
    auto_main(**kwargs)
    git clean -xfd
    cleanup_cython()
    cythonize @(name)/*.pyx
    return !(pip install --no-build-isolation     .)

def build_aiohttp(**kwargs):
    # aiohttp has a makefile, but it pins to specific versions of cython which
    # defeats the point here!
    auto_main(**kwargs)
    git clean -xfd
    cleanup_cython()
    pushd vendor/llhttp/
    npm install
    make generate
    popd
    python tools/gen.py
    cythonize -3 aiohttp/*.pyx
    return !(pip install --no-build-isolation     .)


def imagecodecs_build(upstream_branch, **kwargs):
    # nuke the c files to force cython to run
    git remote update
    git rebase origin/@(upstream_branch)
    cleanup_cython()
    # rm imagecodecs/_*.c || true
    return !(pip install -v --no-build-isolation    .)


def build_cffi():
    hg purge
    hg pull
    hg update
    cleanup_cython()
    return !(pip install --no-use-pep517 --no-build-isolation     .)


def build_scipp(**kwargs):
    auto_main(**kwargs)
    git clean -xfd
    install_dir = $(python -c 'import site; print(site.getsitepackages()[0].strip(), end="")')
    py_ex = $(which python)
    cmake   -GNinja   -DCMAKE_BUILD_TYPE=Debug   -DPYTHON_EXECUTABLE=@(py_ex) -DCMAKE_INSTALL_PREFIX=@(install_dir)   -DCMAKE_INTERPROCEDURAL_OPTIMIZATION=OFF   -DDYNAMIC_LIB=ON  ..

    return !(cmake --build . --target install)


class JsonBuildRecord:
    @classmethod
    def start_record(cls, *, directory='logs'):
        p = Path(directory)
        p.mkdir(exist_ok=True, parents=True)
        uid = str(uuid.uuid4())
        now = datetime.datetime.now()
        fname = f'{now:%Y%m%dT%H%M}.json'

        record = {'start_time': now.isoformat(),
                  'build_steps': [],
                  'uid': uid,
                  }
        with open(p / fname, 'w') as fin:
            json.dump(record, fin)

        return cls(p / fname)

    def __init__(self, fname):
        self._fname = Path(fname).absolute()
        with open(fname, 'r') as fin:
            self._data = json.load(fin)

    def add_build_record(self, build_data):
        self._data['build_steps'].append(build_data)
        with open(self._fname, 'w') as fin:
            json.dump(self._data, fin)

    @property
    def steps(self):
        for record in self._data['build_steps']:
            yield record


if '--continue' in sys.argv:
    p, *_ = sorted(Path('logs').glob('*.json'), reverse=True)
    record = JsonBuildRecord(p)
else:
    record = JsonBuildRecord.start_record()

add_build_record = record.add_build_record


pre_done = set()
for build_step in record.steps:
    if build_step['returncode'] == 0:
        if build_step['name'] == 'pip':
            pre_done.add(build_step['packages'])
        else:
            pre_done.add(build_step['name'])
print(pre_done)
for j, step in enumerate(build_order):
    print('*'*45)
    print(f'{"  " + step.get("name", step.get("packages", "")) + "  ":*^45s}')
    print('*'*45)
    if step.get('name', 'pip') == 'pip':
        if step['packages'] in pre_done:
            continue
    elif step['name'] in pre_done:
        continue

    if step['kind'] == 'source_install':
        echo @(step['wd'])
        with ${...}.swap(RAISE_SUBPROC_ERROR=True):
            pushd @(step['wd'])
        try:
            echo @(step['function'])
            func_name = step['function']
            func = locals()[func_name]
            if step.get('vc', 'git') == 'git':
                shas = extract_git_shas()
            else:
                shas = {}
            start_time = time.time()
            kwargs = step.get('kwargs', {})
            branch = step.get('project', {}
                              ).get('primary_remote', {}
                                    ).get('default_branch', None)
            if branch is not None:
                kwargs.setdefault('upstream_branch', branch)
            build_log = func(**kwargs)
            succcesss = bool(build_log)
            stop_time = time.time()
            pl = json.loads($(pip list --format json))

            add_build_record(
                {
                    'stdout': build_log.lines,
                    'stderr': build_log.errors,
                    'pip list': pl,
                    'start_time': start_time,
                    'stop_time': stop_time,
                    'shas': shas,
                    'step_inedx': j,
                    'name': step['name'],
                    'returncode': build_log.returncode
                }
            )
        finally:
            popd

        if not build_log:
            print(''.join(build_log.lines))
            print(''.join(build_log.errors) if build_log.errors is not None else None)
            print(f"pushd {step['wd']}")
            raise Exception

    elif step['kind'] == 'pip' or step['kind'] == 'pip-remove':
        if step['kind'] == 'pip':
            cmd = 'install'
        elif step['kind'] == 'pip-remove':
            cmd ='uninstall'
        else:
            raise Exception('womp womp')
        build_log = !(pip @(cmd) @(step['flags'].split()) @(step['packages'].split()))
        succcesss = bool(build_log)
        pl = json.loads($(pip list --format json))
        add_build_record(
            {
                'stdout': build_log.lines,
                'stderr': build_log.errors,
                'pip list': pl,
                'start_time': build_log.starttime,
                'stop_time': build_log.endtime,
                'packages': step['packages'],
                'flags': step['flags'],
                'step_inedx': j,
                'name': step['packages'],
                'returncode': build_log.returncode
            }
        )
        if not build_log:
            print(''.join(build_log.lines))
            print(''.join(build_log.errors) if build_log.errors is not None else None)
            raise Exception
    else:
       raise Exception("womp womp")
