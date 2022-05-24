{
  inputs.nixpkgs.url = "nixpkgs";

  outputs = { self, ... }@inputs: {
    lib = import ./.;
  };
}
