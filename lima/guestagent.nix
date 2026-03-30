# Lima guest agent — forwards ports to the host agent via VSOCK
{ config, lib, ... }:

let
    cfg = config.services.lima;
in {
    config = lib.mkIf cfg.enable {
        systemd.services.lima-guestagent = {
            enable = true;
            description = "Forward ports to the lima-hostagent";
            wantedBy = [ "multi-user.target" ];
            after = [ "network.target" "lima-init.service" ];
            requires = [ "lima-init.service" ];
            serviceConfig = {
                Type = "simple";
                Restart = "on-failure";
            };
            script = ''
                # Read Lima environment (can't source directly — values may have spaces)
                while read -r line; do export "$line"; done < "${cfg.cidataDir}"/lima.env
                ${cfg.cidataDir}/lima-guestagent daemon --vsock-port "$LIMA_CIDATA_VSOCK_PORT"
            '';
        };
    };
}
