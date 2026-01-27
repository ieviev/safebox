{
  description = "safebox";
  inputs = {
    flake-parts.url = "github:hercules-ci/flake-parts";
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
          system,
          ...
        }:
        {
          _module.args.pkgs = import nixpkgs {
            inherit system;
            config.allowUnfree = true; # because claude-code is unfree
          };
          packages.dockerImage = pkgs.dockerTools.buildImage {
            name = "safebox";
            tag = "latest";
            compressor = "zstd";
            copyToRoot = [
              pkgs.claude-code
              pkgs.nodejs_25
              pkgs.which
              pkgs.openssl
              pkgs.cacert
              pkgs.nano
              # tools it loves to use
              pkgs.file
              pkgs.gnugrep
              pkgs.bash
              pkgs.coreutils
              pkgs.curl
              # tools it sometimes should use instead
              pkgs.fd
              pkgs.sd
              pkgs.ripgrep
              # to debug why something isnt working in the sandbox
              pkgs.strace
              # tools you might need
              # pkgs.libc
              # pkgs.git
            ];
            # at the very least we need a /tmp dir and a home dir for claude
            runAsRoot = ''
              #!${pkgs.runtimeShell}
              mkdir -p /tmp
              chmod 1777 /tmp
              echo "claude:x:1000:1000:claude:/home/claude:/bin/sh" > /etc/passwd
              mkdir -p /home/claude
              chown 1000:1000 /home/claude
            '';
            config = {
              Cmd = [ "claude" ];
              # nixos ssl certs for node ssl won't fail
              Env = [
                "SSL_CERT_FILE=/etc/ssl/certs/ca-bundle.crt"
                "SSL_CERT_DIR=/etc/ssl/certs"
                "NODE_EXTRA_CA_CERTS=/etc/ssl/certs/ca-bundle.crt"
              ];
            };
          };
        };
    };
}
