# Lima SSH key management — declarative AuthorizedKeysCommand
# Reads SSH public keys from cidata at connection time instead of
# imperatively parsing YAML and managing file permissions in init.
{ config, pkgs, lib, ... }:

let
    cfg = config.services.lima;
in {
    config = lib.mkIf cfg.enable {
        environment.etc."ssh/lima-authorized-keys" = {
            mode = "0755";
            text = ''
                #!/bin/sh
                CIDATA="${cfg.cidataDir}"
                [ -f "$CIDATA/user-data" ] || exit 0
                ${pkgs.gawk}/bin/awk '
                    match($0, /^([[:space:]]*)ssh-authorized-keys:/, m) { ident="^" m[1] "[[:space:]]+-[[:space:]]+"; flag=1; next }
                    flag && $0 !~ ident { flag=0; next }
                    flag && $0 ~ ident { sub(ident, ""); gsub("\"", ""); print $0 }
                ' "$CIDATA/user-data"
            '';
        };

        services.openssh.settings = {
            AuthorizedKeysCommand = "/etc/ssh/lima-authorized-keys %u";
            # Must run as root because cidata is mounted with mode=0700,uid=0
            AuthorizedKeysCommandUser = "root";
        };
    };
}
