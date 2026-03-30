# Lima initialization service — user creation and boot readiness signaling
{ config, pkgs, lib, ... }:

let
    cfg = config.services.lima;
in {
    config = lib.mkIf cfg.enable {
        # Declarative user baseline — defines the default Lima user with
        # correct group memberships. mutableUsers allows the init script
        # to adjust UID/username at runtime if cidata specifies differently.
        users.mutableUsers = true;
        users.users."${cfg.defaultUser}" = {
            isNormalUser = true;
            extraGroups = [ "wheel" "users" ];
            shell = pkgs.bash;
        };

        systemd.services.lima-init = {
            description = "Reconfigure the system from lima-init userdata on startup";
            after = [ "network-pre.target" ];
            restartIfChanged = true;
            unitConfig.X-StopOnRemoval = false;
            serviceConfig = {
                Type = "oneshot";
                RemainAfterExit = true;
            };
            script = ''
                echo "attempting to fetch configuration from LIMA user data..."

                if [ -f ${cfg.cidataDir}/lima.env ]; then
                    echo "storage exists";
                else
                    echo "storage not exists";
                    exit 2
                fi
                # Read Lima environment (can't source directly — values may have spaces)
                while read -r line; do export "$line"; done <"${cfg.cidataDir}"/lima.env

                export PATH=${pkgs.lib.makeBinPath [ pkgs.shadow ]}:$PATH

                # Create/adjust user — the default user is declared in NixOS config
                # (users.users), but cidata may specify a different name or UID.
                if ! id -u "$LIMA_CIDATA_USER" >/dev/null 2>&1; then
                    useradd --home-dir "$LIMA_CIDATA_HOME" --create-home \
                        --uid "$LIMA_CIDATA_UID" --groups wheel,users "$LIMA_CIDATA_USER"
                fi

                # Signal boot readiness (provisioning runs as separate services)
                # Lima >= 2.1.0 requires instance ID in signal files;
                # older versions expect meta-data content.
                if [ -n "$LIMA_CIDATA_IID" ]; then
                    echo "$LIMA_CIDATA_IID" > /run/lima-ssh-ready
                    echo "$LIMA_CIDATA_IID" > /run/lima-boot-done
                else
                    cp "${cfg.cidataDir}"/meta-data /run/lima-ssh-ready
                    cp "${cfg.cidataDir}"/meta-data /run/lima-boot-done
                fi
                exit 0
            '';
        };

        # cidata filesystem mount — read-only, root-only
        fileSystems."${cfg.cidataDir}" = {
            device = "${cfg.cidataDev}";
            fsType = "auto";
            options = [ "ro" "mode=0700" "dmode=0700" "overriderockperm" "exec" "uid=0" ];
        };

        # Conditionally link /etc/environment from cidata if available
        system.activationScripts.lima-environment = ''
            if [ -f "${cfg.cidataDir}/etc_environment" ]; then
                ln -sfn "${cfg.cidataDir}/etc_environment" /etc/environment
            fi
        '';
    };
}
