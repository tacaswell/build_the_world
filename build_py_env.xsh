import json
import sys

import time
import uuid
import yaml
import datetime
from pathlib import Path

from subprocess import CalledProcessError

$RAISE_SUBPROC_ERROR = False
$XONSH_TRACE_SUBPROC = True
$PIP_NO_BUILD_ISOLATION = 1

$CFLAGS = ' '.join(('-fpermissive', ${...}.get('CFLAGS', '')))

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
        $CFLAGS
        )
    )
    $HDF5_DIR = '/opt/homebrew/Cellar/hdf5/1.12.2_2'
    # un-comment these to build freetype with CF compilers
    # del $host_alias
    # del $build_alias

with open("build_order.yaml") as fin:
    build_order = list(yaml.unsafe_load_all(fin))

with open('all_repos.yaml') as fin:
    checkouts = list(yaml.unsafe_load_all(fin))

local_checkouts = {co['name']: co for co in checkouts}

for step in build_order:
    if step['kind'] != 'source_install':
        continue
    lc = local_checkouts[step['proj_name']]
    # get the working directory
    step['wd'] = lc['local_checkout']
    # set the default branch
    if step['project']['primary_remote']['vc'] != 'git':
        continue

    step.setdefault('kwargs', {})
    step['kwargs']['upstream_branch'] = step['project']['primary_remote']['default_branch']

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


def cleanup_cython():
    try:
        to_remove = [_ for _ in $(ack -l "Generated by Cython").split("\n") if _.strip()]
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
    git clean -xfd
    git submodule init
    git submodule update
    cleanup_cython()


def main_build(**kwargs):
    auto_main(**kwargs)
    git_cleanup()
    return !(pip install --no-build-isolation .)


def setup_py_build(**kwargs):
    auto_main(**kwargs)
    git_cleanup()
    return !(python setup.py install)


def suitcaseserver_build(**kwargs):
    pip install -r requirements-dev.txt --no-build-isolation    --use-feature=2020-resolver --pre
    pip install -r requirements.txt --no-build-isolation    --use-feature=2020-resolver --pre
    return main_build(**kwargs)


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
    return !(pip install --no-build-isolation     .)


def numpy_build(**kwargs):
    auto_main(**kwargs)
    git clean -xfd
    cleanup_cython()
    git submodule update
    prefix = $(python -c 'import sys; from pathlib import Path;print(Path(sys.executable).parent.parent)').strip()
    CFLAGS = (" -Wall -O2 -pipe -fomit-frame-pointer  "
              "-fno-strict-aliasing -Wmaybe-uninitialized  "
              "-Wdeprecated-declarations -Wimplicit-function-declaration  "
              "-march=native")
    with ${...}.swap(CFLAGS=CFLAGS):
        meson setup build --prefix=@(prefix)
        ninja -C build
        return !(meson install -C build)

def scipy_build(**kwargs):
    auto_main(**kwargs)
    git clean -xfd
    git submodule update
    cleanup_cython()
    prefix = $(python -c 'import sys; from pathlib import Path;print(Path(sys.executable).parent.parent)').strip()
    meson setup build --prefix=@(prefix) -Dblas=flexiblas -Dlapack=flexiblas
    ninja -C build
    return !(meson install -C build)

def pandas_build(**kwargs):
    auto_main(**kwargs)
    git clean -xfd
    cleanup_cython()
    git submodule update
    ret = !(pip install -v  --no-build-isolation     .)
    bool(ret)
    return ret


def sip_build():
    hg purge
    hg pull
    hg update tip
    return !(pip install --no-build-isolation     .)


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


def pycurl_build(**kwargs):
    auto_main(**kwargs)
    git clean -xfd
    make gen
    python setup.py build
    return !(python setup.py install)


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
    p, *_ = sorted(Path('logs').glob('*.json'))
    record = JsonBuildRecord(p)
else:
    record = JsonBuildRecord.start_record()

add_build_record = record.add_build_record


pre_done = set()
for build_step in record.steps:
    if build_step['returncode'] == 0:
        if build_step['name'] == 'pip':
            pre_done.add(build_step['args'])
        else:
            pre_done.add(build_step['name'])
print(pre_done)
for j, step in enumerate(build_order):
    print('*'*45)
    print(f'{"  " + step.get("name", step.get("args", "")) + "  ":*^45s}')
    print('*'*45)
    if step.get('name', 'pip') == 'pip':
        if step['args'] in pre_done:
            continue
    elif step['name'] in pre_done:
        continue

    if step['kind'] == 'source_install':
        echo @(step['wd'])
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
            print(build_log.lines)
            print(build_log.errors)
            print(f"pushd {step['wd']}")
            raise Exception

    elif step['kind'] == 'pip':

        build_log = !(pip @(step['args'].split()))
        succcesss = bool(build_log)
        pl = json.loads($(pip list --format json))
        add_build_record(
            {
                'stdout': build_log.lines,
                'stderr': build_log.errors,
                'pip list': pl,
                'start_time': build_log.starttime,
                'stop_time': build_log.endtime,
                'args': step['args'],
                'step_inedx': j,
                'name': step['args'] if step.get('name', 'pip') == 'pip' else step['name'],
                'returncode': build_log.returncode
            }
        )
        if not build_log:
            print(build_log.lines)
            print(build_log.errors)
            raise Exception
    else:
       raise Exception("womp womp")
