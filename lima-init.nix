{ config, modulesPath, pkgs, lib, ... }:

let
    LIMA_CIDATA_MNT = "/mnt/lima-cidata";
    LIMA_CIDATA_DEV = "/dev/disk/by-label/cidata";

    cfg = config.services.lima;

    script = ''
    echo "attempting to fetch configuration from LIMA user data..."

    if [ -f ${LIMA_CIDATA_MNT}/lima.env ]; then
        echo "storage exists";
    else
        echo "storage not exists";
        exit 2
    fi
    # ripped from https://github.com/lima-vm/alpine-lima/blob/main/lima-init.sh
    # We can't just source lima.env because values might have spaces in them
    while read -r line; do export "$line"; done <"${LIMA_CIDATA_MNT}"/lima.env

    export PATH=${pkgs.lib.makeBinPath [ pkgs.shadow pkgs.gawk pkgs.mount ]}:$PATH

    # Create/adjust user — the default user is declared in NixOS config
    # (users.users), but cidata may specify a different name or UID.
    # Only do imperative user creation if the cidata user doesn't exist.
    if ! id -u "$LIMA_CIDATA_USER" >/dev/null 2>&1; then
        useradd --home-dir "$LIMA_CIDATA_HOME" --create-home \
            --uid "$LIMA_CIDATA_UID" --groups wheel,users "$LIMA_CIDATA_USER"
    fi

    # Run system provisioning scripts
    echo "Running system provisioning scripts"
    if [ -d "${LIMA_CIDATA_MNT}"/provision.system ]; then
    	for f in "${LIMA_CIDATA_MNT}"/provision.system/*; do
    		echo "Executing $f"
    		if ! "$f"; then
    			echo "Failed to execute $f"
    		fi
    	done
    fi

    # Run user provisioning scripts
    echo "Running user provisioning scripts"
    USER_SCRIPT="$LIMA_CIDATA_HOME/.lima-user-script"
    if [ -d "${LIMA_CIDATA_MNT}"/provision.user ]; then
        if [ ! -f /sbin/openrc-run ]; then
            until [ -e "/run/user/$LIMA_CIDATA_UID/systemd/private" ]; do sleep 3; done
        fi
        params=$(grep -o '^PARAM_[^=]*' "${LIMA_CIDATA_MNT}"/param.env | paste -sd ,)
        for f in "${LIMA_CIDATA_MNT}"/provision.user/*; do
            echo "Executing $f (as user $LIMA_CIDATA_USER)"
            cp "$f" "$USER_SCRIPT"
            chown "$LIMA_CIDATA_USER" "$USER_SCRIPT"
            chmod 755 "$USER_SCRIPT"
            if ! /run/wrappers/bin/sudo -iu "$LIMA_CIDATA_USER" "--preserve-env=$params" "XDG_RUNTIME_DIR=/run/user/$LIMA_CIDATA_UID" "$USER_SCRIPT"; then
                echo "Failed to execute $f (as user $LIMA_CIDATA_USER)"
            fi
            rm "$USER_SCRIPT"
        done
    fi


    #echo "$LIMA_CIDATA_SLIRP_GATEWAY host.lima.internal" >> /etc/hosts

    cp "${LIMA_CIDATA_MNT}"/meta-data /run/lima-ssh-ready
    cp "${LIMA_CIDATA_MNT}"/meta-data /run/lima-boot-done
    exit 0
    '';
in {
    imports = [];

    options = {
        services.lima = {
            enable = lib.mkEnableOption "lima-init, lima-guestagent, other Lima support";

            defaultUser = lib.mkOption {
                type = lib.types.str;
                default = "lima";
                description = "Default Lima user name. Overridden at runtime if cidata specifies a different user.";
            };
        };
    };

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
            inherit script;
            description = "Reconfigure the system from lima-init userdata on startup";

            after = [ "network-pre.target" ];

            restartIfChanged = true;
            unitConfig.X-StopOnRemoval = false;

            serviceConfig = {
                Type = "oneshot";
                RemainAfterExit = true;
            };
        };

        # Generate systemd mount units from Lima user-data at boot.
        # Replaces the imperative sed/awk /etc/fstab editing that conflicted
        # with NixOS's declarative fstab management.
        systemd.services.lima-mounts = {
            description = "Create systemd mount units from Lima user-data";
            after = [ "lima-init.service" ];
            requires = [ "lima-init.service" ];
            before = [ "local-fs.target" ];
            wantedBy = [ "local-fs.target" ];
            serviceConfig = {
                Type = "oneshot";
                RemainAfterExit = true;
            };
            path = [ pkgs.gawk pkgs.systemd pkgs.util-linux ];
            script = ''
                CIDATA="${LIMA_CIDATA_MNT}"
                [ -f "$CIDATA/user-data" ] || exit 0
                awk '
                    /^mounts:/ { flag = 1; next }
                    /^[^:]*:/ { flag = 0 }
                    /^ *$/ { flag = 0 }
                    flag {
                        sub(/^ *- \[/, "")
                        sub(/"?\] *$/, "")
                        n = split($0, fields, /"?, "?/)
                        if (n >= 3) {
                            dev = fields[1]; mp = fields[2]; fstype = fields[3]
                            opts = (n >= 4) ? fields[4] : "defaults"
                            print dev "\t" mp "\t" fstype "\t" opts
                        }
                    }
                ' "$CIDATA/user-data" | while IFS=$'\t' read -r dev mp fstype opts; do
                    [ -z "$mp" ] && continue
                    mkdir -p "$mp"
                    unit_name=$(systemd-escape --path --suffix=mount "$mp")
                    cat > "/run/systemd/system/$unit_name" <<UNIT
[Unit]
Description=Lima mount $mp
After=lima-mounts.service

[Mount]
What=$dev
Where=$mp
Type=$fstype
Options=$opts
UNIT
                done
                systemctl daemon-reload
                # Start all lima mounts
                for unit in /run/systemd/system/*.mount; do
                    [ -f "$unit" ] && systemctl start "$(basename "$unit")" || true
                done
            '';
        };

        systemd.services.lima-guestagent =  {
            enable = true;
            description = "Forward ports to the lima-hostagent";
            wantedBy = [ "multi-user.target" ];
            after = [ "network.target" "lima-init.service" ];
            requires = [ "lima-init.service" ];
            script = ''
                # We can't just source lima.env because values might have spaces in them
                while read -r line; do export "$line"; done < "${LIMA_CIDATA_MNT}"/lima.env
                ${LIMA_CIDATA_MNT}/lima-guestagent daemon --vsock-port "$LIMA_CIDATA_VSOCK_PORT"
            '';
            serviceConfig = {
                Type = "simple";
                Restart = "on-failure";
            };
        };

        fileSystems."${LIMA_CIDATA_MNT}" = {
            device = "${LIMA_CIDATA_DEV}";
            fsType = "auto";
            options = [ "ro" "mode=0700" "dmode=0700" "overriderockperm" "exec" "uid=0" ];
        };

        # Conditionally link /etc/environment from cidata if available.
        # Using activation script instead of environment.etc.source to avoid
        # failures when cidata mount is not yet available during activation.
        system.activationScripts.lima-environment = ''
            if [ -f "${LIMA_CIDATA_MNT}/etc_environment" ]; then
                ln -sfn "${LIMA_CIDATA_MNT}/etc_environment" /etc/environment
            fi
        '';

        environment.etc = {

            # Declarative script for SSH AuthorizedKeysCommand — reads keys
            # from Lima cidata at connection time instead of imperatively
            # parsing YAML and managing files/permissions in the init script
            "ssh/lima-authorized-keys" = {
                mode = "0755";
                text = ''
                    #!/bin/sh
                    CIDATA="${LIMA_CIDATA_MNT}"
                    [ -f "$CIDATA/user-data" ] || exit 0
                    ${pkgs.gawk}/bin/awk '
                        match($0, /^([[:space:]]*)ssh-authorized-keys:/, m) { ident="^" m[1] "[[:space:]]+-[[:space:]]+"; flag=1; next }
                        flag && $0 !~ ident { flag=0; next }
                        flag && $0 ~ ident { sub(ident, ""); gsub("\"", ""); print $0 }
                    ' "$CIDATA/user-data"
                '';
            };
        };

        # Use AuthorizedKeysCommand to dynamically read SSH keys from cidata.
        # This replaces the imperative awk+mkdir+chown+chmod+cp chain that
        # was in the lima-init script. OpenSSH handles all permissions itself.
        services.openssh.settings = {
            AuthorizedKeysCommand = "/etc/ssh/lima-authorized-keys %u";
            AuthorizedKeysCommandUser = "nobody";
        };

        networking.nat.enable = true;

        environment.systemPackages = with pkgs; [
            bash
            sshfs
            fuse3
            git
        ];

        # Declarative /bin/bash symlink (replaces imperative ln in init script)
        systemd.tmpfiles.rules = [
            "L+ /bin/bash - - - - /run/current-system/sw/bin/bash"
        ];

        boot.kernel.sysctl = {
            "kernel.unprivileged_userns_clone" = 1;
            "net.ipv4.ping_group_range" = "0 2147483647";
            "net.ipv4.ip_unprivileged_port_start" = 0;
        };
    };
}

