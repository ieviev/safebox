{
  description = "safebox";
  inputs = {
    flake-parts.url = "github:hercules-ci/flake-parts";
    openspec.url = "github:Fission-AI/OpenSpec";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/52d84bdcc3ca52d5356308fa1433a12a6dcc785a";
    fenix = {
      url = "github:nix-community/fenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };
  outputs =
    inputs@{ nixpkgs, flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      perSystem =
        {
          pkgs,
          lib,
          system,
          ...
        }:
        let
          pkgsUnstable = import inputs.nixpkgs-unstable {
            inherit system;
            config.allowUnfree = true;
          };
          ipRangesRaw = builtins.readFile ./ip-ranges.txt;
          ipRangesList = builtins.filter (x: x != "") (lib.splitString "\n" ipRangesRaw);

          isIPv6 = addr: builtins.match ".*:.*" addr != null;
          ipv4Ranges = builtins.filter (addr: !(isIPv6 addr)) ipRangesList;
          ipv6Ranges = builtins.filter isIPv6 ipRangesList;

          mkEntrypoint =
            pkgs:
            pkgs.writeShellScript "entrypoint.sh" ''
              if ${pkgs.nftables}/bin/nft list ruleset >/dev/null 2>&1; then
                ${pkgs.nftables}/bin/nft -f /etc/nftables/safebox.conf
                echo "CAP_NET_ADMIN: firewall rules applied"
              fi
              # initialize nix store db if needed
              if [ ! -f /nix/var/nix/db/db.sqlite ]; then
                ${pkgs.nix}/bin/nix-store --init
              fi
              exec "$@"
            '';

          mkNftablesConfig =
            pkgs:
            pkgs.writeText "nftables.conf" ''
              #!/usr/sbin/nft -f
              flush ruleset
              table inet nat {
                set allowed_v4 {
                  type ipv4_addr
                  flags interval
                  elements = {
                    ${lib.concatStringsSep ",\n                  " ipv4Ranges}
                  }
                }

                set allowed_v6 {
                  type ipv6_addr
                  flags interval
                  elements = {
                    ${lib.concatStringsSep ",\n                  " ipv6Ranges}
                  }
                }

                chain output {
                  type nat hook output priority -100; policy accept;
                  # Skip loopback
                  oif lo accept
                  # Allow DNS
                  meta l4proto { tcp, udp } th dport 53 accept
                  # Reroute non-whitelisted HTTP/HTTPS to zero IP
                  tcp dport { 80, 443 } ip daddr != @allowed_v4 dnat to 0.0.0.0
                  tcp dport { 80, 443 } ip6 daddr != @allowed_v6 dnat to ::
                }
              }
            '';

          mkDockerImage =
            pkgs: name:
            let
              passwdFile = pkgs.writeTextDir "etc/passwd" "claude:x:1000:1000:claude:/home/claude:/bin/sh";
              npmrc = pkgs.writeTextDir "home/claude/.npmrc" "prefix=~/.npm-global";
              nftablesDir = pkgs.runCommand "nftables-config" { } ''
                mkdir -p $out/etc/nftables
                cp ${mkNftablesConfig pkgs} $out/etc/nftables/safebox.conf
              '';
              nixConfDir = pkgs.writeTextDir "etc/nix/nix.conf" ''
                sandbox = false
                experimental-features = nix-command flakes
                build-users-group =
              '';
              notInstalled =
                name:
                pkgs.writeShellScriptBin name ''
                  echo "this binary exists only to hide a claude code warning about missing a program, it does not actually do anything and should not be used,"
                  exit 1
                '';

              # using rust toolchains is pretty nasty without this since it's spread all over the place
              rust_toolchain = inputs.fenix.packages.${system}.combine [
                (inputs.fenix.packages.${system}.latest.withComponents [
                  "cargo"
                  "rustc"
                  "rustfmt"
                  "rust-src"
                  "rust-analyzer"
                ])
                inputs.fenix.packages.${system}.targets.x86_64-unknown-linux-musl.latest.rust-std
                inputs.fenix.packages.${system}.targets.aarch64-unknown-linux-musl.latest.rust-std
              ];
              runtimeLibs = with pkgs; [
                libx11
                libxi
                libxcursor
                libxrandr
                libxkbcommon
                libGL
                alsa-lib
              ];
            in
            pkgs.dockerTools.buildImage {
              name = name;
              tag = "latest";
              extraCommands = ''
                mkdir -p tmp/claude/
                mkdir -p usr/bin/
                mkdir -p home/claude/
                chmod 1777 tmp/
                chmod -R 777 home/claude/
                ln -s /bin/env usr/bin/env
                # nix support
                mkdir -p nix/var/nix/{db,gcroots,profiles,temproots,userpool,daemon-socket}
                mkdir -p nix/store
                chmod -R 777 nix/var/
                chmod -R 777 nix/store/
              '';
              copyToRoot = 
                runtimeLibs ++
                [
                # filesystem structure
                passwdFile
                npmrc
                nftablesDir
                nixConfDir
                # openspec from their own repository
                inputs.openspec.packages.${system}.default
                # not installed, just to get rid of startup warnings
                pkgs.gitMinimal
                # (notInstalled "git")
                (notInstalled "vi")
                (notInstalled "code")
                # network filtering
                pkgs.bash
                pkgs.nftables
                # pkgs.nix-ld
                # minimum for claude code
                pkgsUnstable.claude-code
                pkgs.nodejs_25
                pkgs.which
                pkgs.openssl
                pkgs.cacert
                # useful utilities
                pkgs.nano
                pkgs.coreutils
                pkgs.fd
                pkgs.ripgrep
                pkgs.file
                pkgs.gnugrep
                pkgs.gnused
                pkgs.curl
                pkgs.gzip
                pkgs.gawk
                pkgs.brotli
                pkgs.jq
                pkgs.findutils
                # binary utils
                pkgs.hexdump
                pkgs.xxd
                pkgs.gnuplot
                # to debug why something isnt working in the sandbox
                pkgs.strace
                # tools you might need
                pkgs.glibc
                pkgs.clang
                # rust toolchain
                rust_toolchain
                # pkgs.cargo
                # pkgs.rustc
                # pkgs.rustfmt
                pkgs.wasm-pack
                pkgs.dotnet-sdk_10
                pkgs.pnpm
                # nix itself (for nix-shell inside container)
                pkgs.nix
              ];

              config = {
                Entrypoint = [ "${mkEntrypoint pkgs}" ];
                # nixos ssl certs are in a nonstandard location
                Env = [
                  # increase the output token limit, this happens sometimes
                  "CLAUDE_CODE_MAX_OUTPUT_TOKENS=64000" 
                  "OPENSPEC_TELEMETRY=0"
                  "SSL_CERT_FILE=/etc/ssl/certs/ca-bundle.crt"
                  "SSL_CERT_DIR=/etc/ssl/certs"
                  "NODE_EXTRA_CA_CERTS=/etc/ssl/certs/ca-bundle.crt"
                ];
              };
            };
        in
        {
          _module.args.pkgs = import nixpkgs {
            inherit system;
            config.allowUnfree = true; # because claude-code is unfree
          };
          packages.dockerImage = mkDockerImage pkgs "safebox";
          # possible, but not recommended, better use binfmt and nix build .#packages.aarch64-linux.dockerImage for cross compiling
          # packages.dockerImage-aarch64 = mkDockerImage pkgs.pkgsCross.aarch64-multiplatform "safebox";
        };
    };
}
