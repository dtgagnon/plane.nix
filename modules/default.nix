{ lib, pkgs, planePackage ? null, ... }:

# Import all submodules to build a complete configuration
{
  imports = [
    # Pass the package, lib and pkgs to options.nix
    (import ./options.nix { inherit lib pkgs planePackage; })
    ./system.nix
    ./services.nix
    ./networking.nix
  ];
}
