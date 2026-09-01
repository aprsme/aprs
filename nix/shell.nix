{
  lib,
  stdenv,
  mkShell,
  # Elixir/Erlang
  erlang,
  elixir,
  # Development tools
  git,
  # LSPs and formatters
  elixir-ls,
  nixfmt,
  # File watching for `mix test.watch`
  inotify-tools,
}:

mkShell {
  name = "aprs-dev";

  buildInputs = [
    # Erlang is listed explicitly so `erl`, `epmd` and `dialyzer` land on PATH,
    # not just the `elixir`/`mix` wrappers that reference OTP internally.
    erlang
    elixir
    git
    elixir-ls
    nixfmt
  ]
  ++ lib.optionals stdenv.hostPlatform.isLinux [
    # mix_test_watch's file-system backend on Linux
    inotify-tools
  ];

  shellHook = ''
    # Keep Mix and Hex state inside the project instead of polluting $HOME,
    # so the toolchain here can never disagree with a system-wide install.
    export MIX_HOME="$PWD/.nix-mix"
    export HEX_HOME="$PWD/.nix-hex"
    export PATH="$MIX_HOME/bin:$HEX_HOME/bin:$PATH"
    mkdir -p "$MIX_HOME" "$HEX_HOME"

    export ERL_AFLAGS="-kernel shell_history enabled"

    # Everything above is pure environment: free, and all direnv needs.
    #
    # Everything below boots the BEAM, so it is charged to every `cd` if left
    # ungated. direnv sets DIRENV_IN_ENVRC while evaluating .envrc, so use it
    # to run first-time setup only for an explicit `nix develop`. (DIRENV_DIR
    # is NOT a valid discriminator -- direnv strips it from the environment
    # .envrc is evaluated in.)
    if [ -f mix.exs ] && [ -z "''${DIRENV_IN_ENVRC:-}" ]; then
      mix local.hex --force --if-missing > /dev/null 2>&1
      mix local.rebar --force --if-missing > /dev/null 2>&1
    fi
  '';
}
