from pathlib import Path

debug = False

container=$(buildah from btw-source)
# we do not have an image to start from, bootstram from archlinux
if not container:
    container=$(buildah from archlinux)

print(container)

scratchmnt=$(buildah mount @(container))
print(scratchmnt)

print($(ls @(scratchmnt)))

btw = (Path(scratchmnt) / 'btw')

if not btw.exists():
    git clone https://github.com/tacaswell/build_the_world @(btw)
else:
    buildah run --workingdir=btw @(container)  -- git remote update
    buildah run --workingdir=btw @(container)  -- git reset --hard origin/main

xonsh ensure_clones.xsh --target @(scratchmnt)/src

buildah run @(container) -- pacman -Syu --noconfirm
buildah run @(container) -- pacman -Sy git xonsh python python-yaml --noconfirm

buildah run --workingdir=btw @(container)  -- xonsh find_repos.xsh ../src/
buildah run --workingdir=btw @(container) -- xonsh setup_extra_remotes.xsh
buildah run --workingdir=btw @(container)  -- xonsh find_repos.xsh ../src/

buildah unmount @(container)
buildah commit @(container) btw-source


if debug:
    buildah rm @(container)
