# QCOW2 EFI image builder — replaces deprecated nixos-generators
# Uses nixpkgs built-in make-disk-image.nix (upstreamed since NixOS 25.05)
{ config, lib, pkgs, modulesPath, ... }: {
    system.build.qcow2 = import (modulesPath + "/../lib/make-disk-image.nix") {
        inherit config lib pkgs;
        format = "qcow2";
        partitionTableType = "efi";
        diskSize = "auto";
        additionalSpace = "2048M";
    };
}
