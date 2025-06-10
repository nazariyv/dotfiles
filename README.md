# Dotfiles for quick new machine set up

to test with a docker container, run:

```bash
docker run --rm -it \
  -v "$PWD:/git/dotfiles:ro" \
  -e TEST_MODE=true \
  -e SUDO_USER=testuser \
  ubuntu:latest \
  bash -c "useradd -m testuser && bash /git/dotfiles/setup.sh"
```
