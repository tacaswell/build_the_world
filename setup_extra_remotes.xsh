import yaml
from collections import defaultdict

from xonsh.dirstack import with_pushd


$RAISE_SUBPROC_ERROR = False
$XONSH_TRACE_SUBPROC = False
$PIP_NO_BUILD_ISOLATION = 1

def get_git_remotes(repo):
    """Given a path to a repository, get remotes
    """
    remotes = defaultdict(dict)

    with with_pushd(repo):
        for remote in !(git remote -v).itercheck():
            name, _, rest = remote.strip().partition('\t')
            url, _, direction = rest.partition(' (')
            direction = direction[:-1]
            remotes[name][direction] = url

    return dict(remotes)


with open('all_repos.yaml') as fin:
    checkouts = list(yaml.unsafe_load_all(fin))

local_checkouts = {co['name']: co for co in checkouts}
del checkouts

with open('extra_remotes.yaml') as fin:
    extra_remotes = list(yaml.unsafe_load_all(fin))

for project in extra_remotes:
    lc = local_checkouts[project['proj_name']]
    wd = lc['local_checkout']
    remotes = get_git_remotes(wd)
    if project['remote_name'] not in remotes:
        with with_pushd(wd):
            git remote add @(project['remote_name']) @(project['remote']['url'])

    with with_pushd(wd):
        git fetch @(project['remote_name'])
        if $(git branch --list @(project['branch'])):
            git reset --hard @(project['remote_name'])/@(project['branch'])
        else:
            git switch -c @(project['branch']) -t @(project['remote_name'])/@(project['branch'])
