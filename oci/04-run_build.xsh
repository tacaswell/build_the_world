import sys
from pathlib import Path

debug = False

container=$(buildah from btw-deps)
if not container:
    sys.exit(1)

buildah run @(container) -- git pull
buildah copy @(container) extra_remotes.yaml extra_remotes.yaml
buildah copy @(container) setup_extra_remotes.xsh setup_extra_remotes.xsh

buildah run @(container) -- xonsh setup_extra_remotes.xsh

# TODO control the args via cli input
buildah run @(container) -- xonsh make_bleeding.xsh --target py313 --branch 3.13
# TODO control the container name via cli input
buildah commit @(container) btw-built
