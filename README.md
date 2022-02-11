# 🏗️ Build the world 🌐

This is a repository of Python and [xonsh](https://xon.sh) scripts that I
use to build a the section Python / pydata / scipy stack that I use (and help
maintain).

I have frequently been caught out by changes to my upstream dependencies
breaking me.  Sometimes the changes are things I just have to adapt to, but in
other cases I have been told the changes were unintentional and if the impact
had been known they would not have been released.  Thus, I set out to try and
find those issues as early as possible.

The first version of this script only complied CPython and created a virtual
environment for me to work in.  However, due needing to install things from
source (mostly to deal with projects that ship pre-cythonized c files in their
sdists), to get bug fixes for the newest CPython that were not released yet, or
because I had to work from a development branch the number of projects being
built from git (or hg) checkouts kept growing.  Eventually I out-grew my bash
script without functions, to a bash script with functions, then a xonsh script
with all of the source locations hard-coded, to finally the current state

## Code quality

This is trash code that as of the time of this writing has been used by 1 (one)
person on 1 (one) computer.  The unit testing is "can I rebuild the
environment";  for a long while, the "continue" functionality was implemented by
commenting out the already built projects.

These tools have been slowly moving towards being proper CLI tools, but they
get the job done.  This code is offered in the fullest sense of "AS IS", but
I have been slowly adding quality of life features and am very open to any
suggestions of how to improve it.

## Requirements

I have not been carefully tracking what system dependencies these scripts rely
on.  At a minimum running these scripts will require:

1. xonsh
2. c, c++, and fortran compilers
3. mongodb running on the local host (for logging and resuming the build)
   and pymongo available to xonsh.
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


## Usage

To use project is currently a multi step process.  The first step is to use

```bash
$ cd build_the_world
$ xonsh find_repos.xsh path/to/source/directory
```

which will find all of the git and hg checkouts under the given directory and
will write out a file `all_repos.yaml` with information about all of the
checkouts it found.

In principle there is enough information in `all_repos.yaml` and
`build_order.yaml` to identify and clone any missing repositories.

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

1. **Aren't you reinventing \<packaging system\>?**: Yes, well no, while this
   code and packaging systems both build from source, a packaging system is
   trying to create distributively artifacts.  This code is only about making
   the installs work on the machine the script is run on.  It is also very
   important to be to be able to source install from a development branch any
   project in the environment.

   I am solving a _much_ simpler problem than a packaging system.
2. **Why xonsh?**: I wanted to learn xonsh and the shell/Python hybrid is really
   pleasant for this sort of work (even I sometimes have to trial-and-error moving
   variables between the two sides).
3. **Is this re-inventing pythonci?**:
   No. [pythonci](https://github.com/vstinner/pythonci/) is a Victor Stinner
   project with a more reasonable goal of building the stable branches of
   projects against the default development branch of CPython.   I am trying to
   build the development branch of everything.
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
    the history.  If this seems interesting / fun / useful to you lets be
    friends!
