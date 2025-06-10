# Dotfiles for quick new machine set up

to test with a docker container, run:

```bash
docker run --rm -it --privileged \
  -v "$PWD:/git/dotfiles:ro" \
  -e TEST_MODE=true \
  -e CONTAINER_MODE=true \
  ubuntu:latest \
  bash /git/dotfiles/setup.sh
```

on a clean machine, git clone this whole repo and run `setup.sh` normally
