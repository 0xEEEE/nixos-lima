# Lima NixOS module — guest-side support for Lima VMs
# Provides services.lima.* options for initialization, SSH, mounts,
# provisioning, and guest agent management.
{ ... }: {
    imports = [
        ./options.nix
        ./init.nix
        ./guestagent.nix
        ./ssh.nix
        ./mounts.nix
        ./provision.nix
        ./performance.nix
    ];
}
