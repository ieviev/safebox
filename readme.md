## security-hardened container for running [Claude Code](https://github.com/anthropics/claude-code)

### highlights:
- podman bubblewrap does a good job of isolating the container, but we also take care to minimize the attack surface of the container itself.
- short and human-written
- minimal attack surface from the LLM: 
  - builds on top of a distroless base
  - see [flake.nix](flake.nix) for included tools
- podman container to be run as non-root user inside
  - shares uid with current user but creates /home/claude home directory as user 'claude' inside container
  - only mounts current path, claude config, npm cache. (see [run.sh](run.sh))
- no risk of data loss, assuming you at least use version control:
  - as an experiment, running `rm -rf --no-preserve-root /` inside the container (don't do this at home!) only wiped the writable mounts (current dir, claude configs, npm cache) and left the rest intact
- data exfiltration protections: 
  - claude cannot exfiltrate data outside the mounted folders
  - optional whitelisted firewall rules (see [data exfiltration protection](#data-exfiltration-protection))

### usage

**prerequisites**:
- [nix](https://nixos.org/download/) to build the container image
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


### data exfiltration protection

by default, the container allows outbound network access to any destination. to restrict outbound connections to only whitelisted IPs, use `run-firewall.sh`:

```sh
./run-firewall.sh claude
```

this applies nftables rules that reroute HTTP/HTTPS traffic to non-whitelisted destinations to `0.0.0.0`, causing immediate connection failure instead of allowing the request.

the allowed IP ranges in [ip-ranges.txt](ip-ranges.txt) are generated from `./gen-ip-ranges.sh` at build time similar to [anthropic's devcontainer](https://github.com/anthropics/claude-code/blob/main/.devcontainer/init-firewall.sh). DNS is allowed to any destination (necessary for resolution).

if firewall capability is available, it is applied automatically on container startup and a message is printed to indicate it was applied.

### troubleshooting

strace is included for debugging. if something isn't working inside the container:
```sh
# start an interactive bash shell
./run.sh bash
# inside the container, run:
strace 2>trace.txt claude
```

> `which: no code in...` / `which: no vi in...` on startup: 

you can ignore these warnings, claude looks for some applications on startup, but we don't want these installed in the container.

### license

MIT

