# Lima mount management — generates systemd mount units from cidata
# Replaces imperative sed/awk /etc/fstab editing with ephemeral
# mount units in /run/systemd/system/
{ config, pkgs, lib, ... }:

let
    cfg = config.services.lima;
in {
    config = lib.mkIf cfg.enable {
        systemd.services.lima-mounts = {
            description = "Create systemd mount units from Lima user-data";
            after = [ "lima-init.service" ];
            requires = [ "lima-init.service" ];
            wantedBy = [ "multi-user.target" ];
            serviceConfig = {
                Type = "oneshot";
                RemainAfterExit = true;
            };
            path = [ pkgs.gawk pkgs.systemd pkgs.util-linux ];
            script = ''
                CIDATA="${cfg.cidataDir}"
                [ -f "$CIDATA/user-data" ] || exit 0
                awk '
                    /^mounts:/ { flag = 1; next }
                    /^[^:]*:/ { flag = 0 }
                    /^ *$/ { flag = 0 }
                    flag {
                        sub(/^ *- \[/, "")
                        sub(/\] *$/, "")
                        gsub(/"/, "")
                        n = split($0, fields, ", *")
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

[Mount]
What=$dev
Where=$mp
Type=$fstype
Options=$opts,nofail
TimeoutSec=10
UNIT
                done
                systemctl daemon-reload
                for unit in /run/systemd/system/*.mount; do
                    [ -f "$unit" ] || continue
                    mp=$(grep "^Where=" "$unit" | cut -d= -f2)
                    # Skip if already mounted (Lima vz handles virtiofs natively)
                    if [ -n "$mp" ] && ! mountpoint -q "$mp" 2>/dev/null; then
                        # Use --no-block to avoid one stuck mount blocking all others
                        systemctl start --no-block "$(basename "$unit")" || true
                    fi
                done
            '';
        };

        # Declarative /bin/bash symlink (Lima scripts expect /bin/bash)
        systemd.tmpfiles.rules = [
            "L+ /bin/bash - - - - /run/current-system/sw/bin/bash"
        ];
    };
}
