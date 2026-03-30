# Lima provisioning — system and user provisioning as independent services
{ config, pkgs, lib, ... }:

let
    cfg = config.services.lima;
in {
    config = lib.mkIf cfg.enable {
        # System provisioning scripts from cidata (runs as root)
        systemd.services.lima-provision-system = {
            description = "Run Lima system provisioning scripts";
            after = [ "lima-init.service" "network.target" ];
            requires = [ "lima-init.service" ];
            wantedBy = [ "multi-user.target" ];
            serviceConfig = {
                Type = "oneshot";
                RemainAfterExit = true;
            };
            script = ''
                CIDATA="${cfg.cidataDir}"
                [ -d "$CIDATA/provision.system" ] || exit 0
                for f in "$CIDATA"/provision.system/*; do
                    echo "Executing $f"
                    "$f" || echo "Failed to execute $f"
                done
            '';
        };

        # User provisioning scripts from cidata (runs as Lima user via sudo)
        systemd.services.lima-provision-user = {
            description = "Run Lima user provisioning scripts";
            after = [ "lima-provision-system.service" ];
            requires = [ "lima-init.service" ];
            wantedBy = [ "multi-user.target" ];
            serviceConfig = {
                Type = "oneshot";
                RemainAfterExit = true;
            };
            path = [ pkgs.coreutils pkgs.gnugrep pkgs.util-linux ];
            script = ''
                CIDATA="${cfg.cidataDir}"
                [ -d "$CIDATA/provision.user" ] || exit 0
                # Read Lima environment
                while read -r line; do export "$line"; done < "$CIDATA/lima.env"
                # Wait for user systemd session
                until [ -e "/run/user/$LIMA_CIDATA_UID/systemd/private" ]; do sleep 3; done
                params=$(grep -o '^PARAM_[^=]*' "$CIDATA/param.env" 2>/dev/null | paste -sd , || true)
                USER_SCRIPT="$LIMA_CIDATA_HOME/.lima-user-script"
                for f in "$CIDATA"/provision.user/*; do
                    echo "Executing $f (as user $LIMA_CIDATA_USER)"
                    cp "$f" "$USER_SCRIPT"
                    chown "$LIMA_CIDATA_USER" "$USER_SCRIPT"
                    chmod 755 "$USER_SCRIPT"
                    if ! /run/wrappers/bin/sudo -iu "$LIMA_CIDATA_USER" \
                        "''${params:+--preserve-env=$params}" \
                        "XDG_RUNTIME_DIR=/run/user/$LIMA_CIDATA_UID" "$USER_SCRIPT"; then
                        echo "Failed to execute $f (as user $LIMA_CIDATA_USER)"
                    fi
                    rm "$USER_SCRIPT"
                done
            '';
        };
    };
}
