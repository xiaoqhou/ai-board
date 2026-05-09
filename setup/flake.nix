{
  description = "Codespace nix flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
  };

  outputs = { self, nixpkgs }: 
  let
    system = "x86_64-linux";
    pkgs = nixpkgs.legacyPackages.${system};
    basePackages = with pkgs; [
      just
      opencode
    ];
  in
  {
    # run 'nix profile add .' to install base packages
    packages.${system}.default = pkgs.buildEnv {
      name = "codespace-base";
      paths = basePackages;
    };

    # This defines the shell environment
    devShells.${system}.default = pkgs.mkShell {
      buildInputs = basePackages;
      shellHook = ''
        echo "Nix dev env is ready.";
      '';
    };

  };
}