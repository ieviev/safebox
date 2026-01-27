## security-hardened container for running [Claude Code](https://github.com/anthropics/claude-code)

i was going to originally call this claudebox, but that name is taken,
and there are many solutions out there, but most have something wrong with them. so this is safebox.

### highlights:
- this takes security seriously
- lines of code is not a metric to be proud of and we're not supposed to push 30 folders and 20 000 lines of slop here, it should be as small as possible
- reduced attack surface: 
  - builds from a flake on top of a distroless base
  - sudo, package managers, etc. are not even installed, (see [flake.nix](flake.nix#29-49))
- podman container to be run as non-root user inside
  - shares uid with current user but creates /home/claude home directory as user 'claude' inside container
  - only mounts current path, claude config, npm cache. (see [run.sh](run.sh))

### included tools

see [flake.nix](flake.nix#28-50) for the list of tools and how the container is built.

### usage

**prerequisites**:
- [nix](https://nixos.org/download/) package manager
- [podman](https://podman.io/docs/installation) container runtime
- existing claude code authentication (`~/.claude.json` and `~/.claude/` must exist from a previous `claude` login)

```sh
# build the container (or use aarch64-linux for ARM)
nix build .#packages.x86_64-linux.dockerImage
# load the image into podman:
podman load -i result
# execute from folder where you want to use it:
./run.sh claude
```

to allow all commands:
```sh
./run.sh claude --dangerously-skip-permissions
```

### volume mounts

run.sh mounts the following:
- `~/.claude.json` → claude authentication config
- `~/.claude/` → claude settings directory
- `~/.npm/` → npm cache for packages
- `$PWD` → current working directory (mounted at same path inside container)

### troubleshooting

strace is included for debugging. if something isn't working inside the container:
```sh
# start an interactive bash shell
./run.sh bash
# inside the container, run:
strace 2>trace.txt claude
```

### license

MIT

