import json
import pymongo
import sys

import time
import uuid
import yaml

$XONSH_TRACE_SUBPROC = True
$PIP_NO_BUILD_ISOLATION = 1


if sys.platform == 'darwin':
    # make sure we find openblas from homebrew      
    $LDFLAGS = "-L/opt/homebrew/opt/openblas/lib"
    $CPPFLAGS = "-I/opt/homebrew/opt/openblas/include"
    $PKG_CONFIG_PATH = "/opt/homebrew/opt/openblas/lib/pkgconfig"

class BuildLog:
    def __init__(self):
        self.conn = pymongo.MongoClient()
        self.db = self.conn.get_database('bleeding_build')
        self.col = self.db.get_collection('log')

    def get_run(self, uid):
        return self.col.find_one({'uid': uid})

    def get_latest(self):
        return self.col.find_one(sort=[('start_time', -1)])['uid']


bl = BuildLog()

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
    git pull
    cur_branch = $(git branch --show-current).strip()
    upstream = f'{upstream_remote}/{upstream_branch}'
    # git fetch @(upstream_remote)
    git remote update
    if cur_branch in  {'main', 'master', 'develop'}:
        git merge @(upstream)
    else:
        is_merged = !(git merge-base --is-ancestor  HEAD @(upstream))
        if is_merged:
            print('Done')
            git checkout main
            git merge @(upstream)
            git branch -d @(cur_branch)


def cleanup_cython():
    generated_files = [_ for _ in $(ack -l "Generated by Cython").split("\n") if _.strip()]
    if generated_files:
        rm @(generated_files)


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
    pip install -r requirements-dev.txt --no-build-isolation    --use-feature=2020-resolver
    pip install -r requirements.txt --no-build-isolation    --use-feature=2020-resolver
    return main_build(**kwargs)


def numcodecs_build(**kwargs):
    auto_main(**kwargs)
    git clean -xfd
    git submodule init
    git submodule update
    cleanup_cython()
    rm -rf numcodecs/*.c
    return !(pip install --no-use-pep517 --no-build-isolation    .)


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
    CFLAGS = (" -Wall -O2 -pipe -fomit-frame-pointer  "
              "-fno-strict-aliasing -Wmaybe-uninitialized  "
              "-Wdeprecated-declarations -Wimplicit-function-declaration  "
              "-march=native")
    with ${...}.swap(CFLAGS=CFLAGS):
        return main_build(**kwargs)


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
    git pull || echo failed
    auto_main(**kwargs)
    git clean -xfd
    cleanup_cython()
    cythonize @(name)/*.pyx
    return !(pip install --no-build-isolation     .)

def build_aiohttp(**kwargs):
    # aiohttp has a makefile, but it pins to specific versions of cython which
    # defeats the point here!
    git pull || echo failed
    auto_main(**kwargs)
    git clean -xfd
    cleanup_cython()
    cd vendor/llhttp/
    npm install
    make generate
    popd
    python tools/gen.py
    cythonize -3 aiohttp/*.pyx
    return !(pip install --no-build-isolation     .)


def pycurl_build(**kwargs):
    git pull || echo failed
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




if '--continue' in sys.argv:
    uid = bl.get_latest()
    record = bl.get_run(uid)
elif 'BUILD_UID' in ${...}:
    record = bl.get_run($BUILD_UID)
    uid = $BUILD_UID
else:
    uid = str(uuid.uuid4())
    print(f'The uid is {uid}')
    record = {'start_time': time.time(),
              'build_steps': [],
              'uid': uid,
              }
    bl.col.replace_one({'uid': uid}, record, upsert=True)


def add_build_record(build_data):
    record['build_steps'].append(build_data)
    bl.col.replace_one({'uid': uid}, record, upsert=True)


pre_done = set()
for build_step in record['build_steps']:
    if build_step['returncode'] == 0:
        if build_step['name'] == 'pip':
            pre_done.add(build_step['args'])
        else:
            pre_done.add(build_step['name'])
print(pre_done)
try:
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
                print(f"cd {step['wd']}")
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
finally:
    print(f'The uid is {uid}')
