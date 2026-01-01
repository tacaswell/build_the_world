
# 🏗️ Build the world 🌐

This is a repository of Python and [xonsh](https://xon.sh) scripts that I
use to build a the section Python / pydata / scipy stack that I use (and help
maintain).

## Goals

I have frequently been caught out by changes to my upstream dependencies
breaking me.  Sometimes the changes are things I just have to adapt to.  But in
other cases I have been told the changes were unintentional and if the impact
had been known they would not have been released.  Thus, I set out to try and
find those issues as early as possible.

The goals of this project are:

1. Build and make available in a venv the main branch of CPython.
2. Install the main / default branch of most of the Scientific Python ecosystem.
3. Incremental builds / ability to resume after debugging a package's install.
4. Be able to easily switch any package to a source install for development.
5. Be easy to re-build everything from scratch.


## Code quality

This is 🚮 trash 🚮 code that as of the time of this writing has been used by 1
(one) person on 3 (three) computers (but one of those is now de-commissioned).
The unit testing is "can I rebuild the environment"; for a long while, the
"continue" functionality was implemented by commenting out the already built
projects...  These tools have been slowly moving towards being proper CLI
tools, but until then they get the job done.


This code is offered in the fullest sense of "AS IS".  However, I have been
slowly adding quality of life features and am open to any suggestions and
collaboration to improve it!

## Requirements

I have not been carefully tracking what system dependencies these scripts rely
on.  At a minimum running these scripts will require:

1. xonsh
2. c, c++, rust, and fortran compilers
4. pyyaml
5. cmake
6. npm
7. git
8. find
9. make + autotools
10. libhdf5 + headers
11. all of the image libraries + headers supported by imagecodecs
12. meson
13. openblas
14. patchelf
15. a development version of librdkafka
16. robin-map

This has been run (mostly successfully) on:

- an up-to-date [Arch Linux](https://archlinux.org/) machine with a fair number
  of AUR packages installed (mostly for imagecodecs).
- an OSX 12.4 M1 machine with a fair number of brew packages installed.  I have
  not gotten imagecodecs or cairocffi to build yet.
- an up-to-date Fedora 41 machine with a few non-standard repositories (kafka
  not building) with a lot of -devel packages for imagecodecs
- under Windows Subsystem for Linux (skipping all the kafka related packages and imagecodecs)


## Usage

### Set up source tree(s)

To use project is currently a multi step process.  The first step is to make
sure all of the relevant projects are cloned locally.  In principle there is
enough information in `all_repos.yaml` and `build_order.yaml` to identify and
clone any missing repositories.

```bash
xonsh ensure_clones.xsh
```

will attempt clone most of the repositories.

The second step is locate all of the checkouts.

```bash
$ cd build_the_world
$ xonsh find_repos.xsh path/to/source/directory
```

will find all of the git and hg checkouts under the given directory and will
write out a file `all_repos.yaml` with information about all of the checkouts
it found.  While this is walking the repositories it will also change the url
on any `git://` urls for fetch to `https://` as github has stopped supporting
the unauthenticated git protocol for fetching repostiory data.

A third step is move some projects to a particular tracking branch for bug-fixes or
compatibility with non-released versions of Python:

```bash
$ xonsh setup_extra_remotes.xsh                 # this will reset --hard to the tracking branch
$ xonsh find_repos.xsh path/to/source/directory # make repo metadata is up-to-date
```

The non-standard branches are tracked in `extra_remotes.yaml`.

### Build everything

Once all of the required repositories are checked out and found, run

```bash
$ xonsh make_bleeding.xsh
```

which will start from CPython try to move to the tip of the current default
branch and then build everything.  If something goes wrong in the middle (which
it often does), you can resolve the issue

```xonsh
$ vox activate bleeding  # or how ever you activate venvs in your shell
$ # fix the problem
$ xonsh build_py_env.xsh --continue
$ # repeat as needed
```

To update the metadata about any non-default branches required to make the build run
(or if any of the projects can move back to the default branch) run

```bash
$ xonsh repo_reort.xsh
```

and commit the updated `extra_remotes.yaml` to the repo.

Eventually you will have a virtual environment with the development branch of
a large swath of the Scientific Python (and some web) ecosystem installed!

### Control CPython branch and free-threading

If you want to build a different branch of CPython than `main`, you can use the
`--branch` flag to select the branch and `--target` flag to control the venv name

```bash
$ xonsh make_bleeding.xsh --branch=aardvark_special  --target burrow
```

To build CPython 3.13 with free threading enabled:

```bash
# xonsh make_bleeding.xsh --target py313t --branch 3.13 --freethread
```


To build CPython 3.13 with the jit enabled

```bash
# xonsh make_bleeding.xsh --target py313 --branch 3.13 --jit
```


### Start with existing CPython build

If you only want to install the development versions of the downstream
projects, but not CPython itself, you can do:

```xonsh
$ python -m venv /tmp/clean
$ vox activate /tmp/clean   # or how ever you activate venvs in your shell
$ xonsh build_py_env.xsh
$ # fix as needed
$ xonsh build_py_env.xsh --continue
```

## Add new projects

The build order is stored in the `build_order.d/*yaml` files which are run in
alphabetic order in the order the projects are listed in the files.

Each file is formatted as a list of dictionaries.

### Add new source install

To add a new install from a git checkout, add a section like:

```yaml
default_branch: main    # the default branch for the project
function: numpy_build   # the function in build_py_env.xsh used to build it
kind: source_install    # must be "source_install" to do a source install
name: numpy             # name that shows up in the log
proj_name: numpy        # the name top level folder when cloned, matched against all_repos.yaml
```

to the correct place in one of the files in `build_order.d`.  Most projects can
use the function `main_build`, but some projects require custom steps to build
(e.g. manually regenerating cython output, special steps to get the version
right).

### Add package from pypi

To add packages from pypi add an entry like:


```yaml
flags: --pre --upgrade --no-build-isolation    # flags to pass to the invocation of pip
kind: pip                                      # must be 'pip'
packages: beniget gast ply                     # list of packages to install
```

The custom version of `pip` that is used (assuming you are using my branch) will output
a copy-paste-able error message to add missing dependencies.

For the build flags `--pre --upgrade` are to stay in the spirit of being on the
bleeding edge without yet installing from git and are optional.

The `--no-build-isolation` is required for almost all packages to avoid errors
creating the captive virtual environment used when pip attempts isolated builds.

### Format yaml files

You can use [`yq`](https://github.com/mikefarah/yq) to format the yaml.  This
takes care of wrapping long lines, sorting the keys and adding the start/send
markup to the yaml.

```bash
yq -iYS --explicit-start --explicit-end -w 100 .  build_order.d/*.yaml
```

## Containers

There are scripts in `oci` to build [`buildah`](https://buildah.io) to build
OCI images that run this build.  It works up the first need for packages form
AUR.

This seemed like a good idea, but all of the checked out source results in a
9GB image.

Eventually the goal is to get a version of these on a container registry and
generate them on CI.  This is part of this project I very much would like help
with!

## FAQ

1. **Aren't you reinventing \<packaging system\>?**: Yes, well no.  While this
   code and packaging systems both build from source, a packaging system is
   trying to create distributable binary artifacts.  This code is only trying
   to making the installs work on the machine the script is run on.  I am
   solving a _much_ simpler problem than a packaging system.

   This code does implicitly rely on `pip`'s dependency resolution, but the
   build is ordered to be approximately right.


2. **What about [Spack](https://github.com/spack/spack)?** Spack has a
   "(re)build the world" approach, but keeps careful track of versions,
   provides tools to change versions and deterministically rebuild.  This
   code's goal is to get a working environment with the development branch of a
   majority of the Scientific Python stack installed and working.  Upgrading
   via this code is _very_ destructive: it deletes the old environment and
   replaces it!

   Again, I am solving a much simpler problem that Spack is trying to solve.
2. **Why xonsh?**: I wanted to learn xonsh and the shell/Python hybrid is
   really pleasant for this sort of work (even if I sometimes have to
   trial-and-error accessing variables between the two sides and with string escaping).
3. **Is this re-inventing pythonci?**:
   No. [pythonci](https://github.com/vstinner/pythonci/) is a Victor Stinner
   project with a more reasonable goal of building the stable release of
   projects against the default development branch of CPython.  I am trying to
   build the development branch of
   everything. [pythonperformance](https://github.com/python/pyperformance)
   also tries to rebuild stable versions of the ecosystem on top of the
   development branch of CPython.
4. **Do you run the tests for everything?**: No, that would be interesting.  I
   do regularly run the test suites of the projects I work on day-to-day
   (Matplotlib, h5py, and the [bluesky suite](https://blueskyproject.io)) which
   covers the parts of the upstream code _I_ care most about.
5. **Does this work on \<platform\>?**: I have only ever run this on an
   up-to-date Arch Linux machine and an up-to-date OSX M1 machine, so I have no
   idea!  Given the changes I had to make to get it to run on OSX, I would
   expect significant changes to work on Windows, but a fair chance of working
   on other *nix.
6. **Doesn't this break all the time?**: Yes.
7. **How long does this take to build?**: A while!  It is about 15min with
    ccache (and 40min without) when it does not break.
8. **Could some of these build steps be done in parallel?**: Yes, but so far
   kicking this off and either doing other work or walking away has worked well
   enough for me.
9. **These answers all seem very selfish.**: That is more of a comment, but
   yes.  This project is currently all about solving _my_ problems (and my own
   amusement).
10. **Do you actually want anyone else to use this project?**: Yes! That is why
    this is now coming off of my computer and out into the world.  However, I
    am not sure if anyone else would _want_ to participate in this admittedly
    silly activity.  I am being honest about my current ambitions for it and
    the history.  If this seems interesting / fun / useful to you then lets be
    friends!

## History

The first version of this was a bash script that complied CPython and created a
virtual environment.  Very quickly the script started to automate installing
Python packages from source.  The number of projects that I was installing from
version control rapidly grew -- driven by needing to work around projects that
ship pre-cythonized c files in their sdists, needing un-released bug-fixes to
support the main branch of CPython, or just projects I was personally
contributing to.  Eventually a single `bash` script (without functions!) was
refactored to a `bash` script _with_ functions, to a `xonsh` script with all of
checkout locations hard-coded at the top of the file, to a handful of `xonsh`
scripts and a `yaml` file to track where the checkouts are, to the current
state of a handful of `xonsh` scripts and a small fleet of `yaml` files to
track where the source is, what branches are being used, and the build order.

## Bugs found

- change to pybind11 exposed (known) gcc regression https://github.com/contourpy/contourpy/issues/512 / https://github.com/pybind/pybind11/pull/5908
- macro changes broke numpy build https://github.com/python/cpython/issues/142163 / https://github.com/python/cpython/pull/142164
- build broken due to argparse changes https://github.com/pypa/build/pull/960
- meson broke Panda's config https://github.com/pandas-dev/pandas/pull/63406
- use of deprecated functions in hiredis-py https://github.com/redis/hiredis-py/pull/218
