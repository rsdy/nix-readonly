{ nixpkgs, lib, system } @ args:
let
  vmName = "minio";
  vm =
    (lib.nixosSystem {
      inherit system;
      modules = [
        (
          lib.vm.createSystem
            {
              inherit lib;
              hostName = "minio";
              domain = "example.com";
              memorySize = 2048;
              cores = 2;
              hostMTU = 9000;
              zfsVolumeRoot = "tank/vms";

              mountPoints = {
                "/var/lib/minio" = lib.vm.mkMount "minio";
                "/var/lib/acme" = lib.vm.mkMount "acme";
              };
            })

        ./configuration.nix
      ];
    });

in
vm
