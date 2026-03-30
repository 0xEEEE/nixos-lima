# Lima performance and system configuration
# Kernel modules, sysctl, system packages
{ config, pkgs, lib, ... }:

let
    cfg = config.services.lima;
in {
    config = lib.mkIf cfg.enable {
        networking.nat.enable = true;

        environment.systemPackages = with pkgs; [
            bash
            sshfs
            fuse3
            git
        ];

        boot.kernel.sysctl = {
            "kernel.unprivileged_userns_clone" = 1;
            "net.ipv4.ping_group_range" = "0 2147483647";
            "net.ipv4.ip_unprivileged_port_start" = 0;
        };
    };
}
