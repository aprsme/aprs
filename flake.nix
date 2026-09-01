{
  description = "aprs - local development environment for the APRS packet parser library";

  # Local-development tooling only. The library is published to Hex with
  # `mix hex.publish` and CI runs plain `mix` in the hexpm/elixir container,
  # so this flake exposes no package or release outputs -- just the dev shell
  # and the Nix formatter.

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };

    systems.url = "github:nix-systems/default";
  };

  outputs =
    inputs@{
      nixpkgs,
      flake-parts,
      systems,
      ...
    }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      # nixpkgs 26.11 dropped x86_64-darwin support
      systems = builtins.filter (s: s != "x86_64-darwin") (import systems);

      perSystem =
        { pkgs, system, ... }:
        {
          _module.args.pkgs = import nixpkgs {
            inherit system;
            overlays = [
              # Pin specific Elixir and Erlang versions to match .tool-versions:
              # Elixir 1.20.3-otp-29, Erlang 29.0.5.
              (
                final: prev:
                let
                  # nixpkgs ships OTP 29.0.5, so the interpreter comes straight
                  # from the binary cache rather than being rebuilt from a
                  # tarball. Elixir must resolve through this same OTP 29 set so
                  # the dev shell matches .tool-versions.
                  beam29 = prev.beam29Packages;
                in
                {
                  erlang = beam29.erlang;

                  # Elixir 1.20 built against Erlang 29 (1.20.3-otp-29)
                  elixir = beam29.elixir_1_20;

                  # Keep beamPackages on the same pins so any BEAM tool taken
                  # from pkgs (elixir-ls, rebar3) uses this Elixir and OTP.
                  beamPackages = beam29.overrideScope (
                    self: super: {
                      elixir = super.elixir_1_20;
                    }
                  );
                }
              )
            ];
          };

          # Development shell: Elixir/Erlang, LSP, formatters.
          devShells.default = pkgs.callPackage ./nix/shell.nix { };

          # Nix formatter for flake files
          formatter = pkgs.nixfmt;
        };
    };
}
