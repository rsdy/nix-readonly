{
  inputs.nixpkgs.url = "nixpkgs";
  inputs.vm.url = "path:../.";

  outputs = { self, nixpkgs, vm, ... }@inputs:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
      lib = nixpkgs.lib // pkgs.lib // { vm = vm.lib; };

      minio = import ./vms/minio { inherit nixpkgs lib system; };
    in
    {
      nixosConfigurations = {
        inherit minio;
      };

      packages."${system}" = {
        allVms =
          pkgs.writeScriptBin "startVms" ''
            ${lib.vm.runner pkgs "minio1" minio}
          '';
      };
    };
}
