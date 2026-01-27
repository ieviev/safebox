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
          lib,
          system,
          ...
        }:
        let
          ipRangesRaw = builtins.readFile ./ip-ranges.txt;
          ipRangesList = builtins.filter (x: x != "") (lib.splitString "\n" ipRangesRaw);

          isIPv6 = addr: builtins.match ".*:.*" addr != null;
          ipv4Ranges = builtins.filter (addr: !(isIPv6 addr)) ipRangesList;
          ipv6Ranges = builtins.filter isIPv6 ipRangesList;

          entrypoint = pkgs.writeShellScript "entrypoint.sh" ''
            if ${pkgs.nftables}/bin/nft list ruleset >/dev/null 2>&1; then
              ${pkgs.nftables}/bin/nft -f /etc/nftables/safebox.conf
              echo "CAP_NET_ADMIN: firewall rules applied"
            fi
            exec "$@"
          '';

          nftablesConfig = pkgs.writeText "nftables.conf" ''
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
        in
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
              # to debug why something isnt working in the sandbox
              pkgs.strace
              # network filtering
              pkgs.nftables
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
              mkdir -p /etc/nftables
              cp ${nftablesConfig} /etc/nftables/safebox.conf
              chmod 644 /etc/nftables/safebox.conf
            '';
            config = {
              Entrypoint = [ "${entrypoint}" ];
              # nixos ssl certs are in a nonstandard location
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
