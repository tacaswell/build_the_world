
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

## History

The first version of this was a bash script that complied CPython and created a
virtual environment.  Very quickly the script started to automate installing
Python packages from source.  The number of projects that I was installing from
version control rapidly grew -- driven by needing to work around projects that
ship pre-cythonized c files in their sdists, needing un-released bug-fixes to
support the main branch of CPython, or just projects I was personally
contributing to.  Eventually a single `bash` script (without functions!) was refactored
to a `bash` script _with_ functions, to a `xonsh` script with all of checkout locations
hard-coded at the top of the file, to the current state which uses a handful of `xonsh` scripts
and a `yaml` file to track where the checkouts are.

## Code quality

This is 🚮 trash 🚮 code that as of the time of this writing has been used by 1
(one) person on 2 (two) computers (but one of those is now de-commissioned).
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
3. mongodb running on the local host (for logging and resuming the build)
   and pymongo available to xonsh
4. pyyaml
5. cmake
6. npm
7. git
8. hg
9. find
10. make + autotools
11. libhdf5 + headers
12. all of the image libraries + headers supported by imagecodecs
13. [gidgethub](https://gidgethub.readthedocs.io/en/latest/) (optional,
    can be in a venv, needed to refresh default branch names)
14. meson
15. openblas
16. patchelf

I use this on an up-to-date [Arch Linux](https://archlinux.org/) machine with a
fair number of AUR packages installed (mostly for imagecodecs).

## Usage

To use project is currently a multi step process.  The first step is to make
sure all of the relevant projects are cloned locally.  In principle there is
enough information in `all_repos.yaml` and `build_order.yaml` to identify and
clone any missing repositories.

```bash
xonsh ensure_clones.xonsh
```

will attempt clone most of the repositories (`sip` will need to be done by hand
because it is mecurial and hosted directly by riverbank) in an organization
that makes sense to my (and is related to which email address I use when
commiting to them).  Your mileage may vary.

The second step is locate all of the checkouts.

```bash
$ cd build_the_world
$ xonsh find_repos.xsh path/to/source/directory
```

will find all of the git and hg checkouts under the given directory and will
write out a file `all_repos.yaml` with information about all of the checkouts
it found.  While this is walking the repositories it will also change the url
on any `git://` urls to `https://` as github has stopped supporting the
unauthenticaed git protocol for fetching repostiory data.  Optionally, you can
sync the default branches via

```bash
python add_default_branch.py
xonsh update_build_order.xsh
```

Once all of the required repositories are checked out and found, run

```bash
$ xonsh make_bleeding.xsh
```

which will start from CPython try to build everything.  If something goes wrong
in the middle (which it often does), you can resolve the issue

```xonsh
$ vox activate bleeding  # or how ever you activate venvs in your shell
$ # fix the problem
$ xonsh build_py_env.xsh --continue
$ # repeat as needed
```

Eventually you will have a virtual environment with the development branch of
a large swath of the Scientific Python (and some web) ecosystem installed!

If you want to build a different branch of CPython than `main`, you can use the
`--branch` flag to select the branch:

```bash
$ xonsh make_bleeding.xsh --branch=aardvark_special
```


If you only want to install the development versions of the downstream
projects, but not CPython itself, you can do:

```xonsh
$ python -m venv /tmp/clean
$ vox activate /tmp/clean   # or how ever you activate venvs in your shell
$ xonsh build_py_env.xsh
$ # fix as needed
$ xonsh build_py_env.xsh --continue
```

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
5. **Does this work on \<platform\>?**: I have only ever run this on an up-to-date
   Arch Linux machine, so I have no idea!
6. **How long does this take to build?**: A while!  It is about 2 hours on a 4th
   gen I7.
7. **Could some of these build steps be done in parallel?**: Yes, but so far kicking
   this off and either doing other work or walking away has worked well enough for
   me.
8. **Doesn't this break all the time?**: Yes
9. **These answers all seem very selfish.**: That is more of a comment, but
   yes.  This project is currently all about solving _my_ problems (and my own
   amusement).
10. **Do you actually want anyone else to use this project?**: Yes! That is why
    this is now coming off of my computer and out into the world.  However, I
    am not sure if anyone else would _want_ to participate in this admittedly
    silly activity.  I am being honest about my current ambitions for it and
    the history.  If this seems interesting / fun / useful to you then lets be
    friends!
