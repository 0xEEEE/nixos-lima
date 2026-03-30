# Lima module options
{ lib, ... }:

let
    LIMA_CIDATA_MNT = "/mnt/lima-cidata";
    LIMA_CIDATA_DEV = "/dev/disk/by-label/cidata";
in {
    options.services.lima = {
        enable = lib.mkEnableOption "lima-init, lima-guestagent, other Lima support";

        defaultUser = lib.mkOption {
            type = lib.types.str;
            default = "lima";
            description = "Default Lima user name. Overridden at runtime if cidata specifies a different user.";
        };

        cidataDir = lib.mkOption {
            type = lib.types.str;
            default = LIMA_CIDATA_MNT;
            description = "Mount point for the Lima cidata disk.";
            readOnly = true;
        };

        cidataDev = lib.mkOption {
            type = lib.types.str;
            default = LIMA_CIDATA_DEV;
            description = "Device path for the Lima cidata disk.";
            readOnly = true;
        };
    };
}
