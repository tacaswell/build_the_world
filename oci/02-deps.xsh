from pathlib import Path

debug = False

try_continue = False

if try_continue:
    container=$(buildah from btw-deps)
# we do not have an image to start from, bootstram from btw-source
if not try_continue or not container:
    container=$(buildah from btw-source)

print(container)

scratchmnt=$(buildah mount @(container))

buildah config --workingdir=btw  @(container)

buildah run @(container) -- pacman -Syu --noconfirm
buildah run @(container) -- pacman -Sy ack --noconfirm
buildah run @(container) -- pacman -Sy base-devel libjpeg-turbo cmake ccache gcc-fortran  blas-openblas  openblas hdf5 libxml2 libxslt graphviz --noconfirm

with open(Path(scratchmnt) / 'root' / '.bashrc', 'a') as fout:
    fout.write(
        '''
PATH=$PATH:/usr/bin/vendor_perl/
export PATH
''')

buildah unmount @(container)
buildah commit @(container) btw-deps


if debug:
    buildah rm @(container)
