let
  sysPkg = import <nixpkgs> { };
  releasedPkgs = sysPkg.fetchFromGitHub {
    owner = "NixOS";
    repo = "nixpkgs";
    rev = "22.11";
    sha256 = "sha256-/HEZNyGbnQecrgJnfE8d0WC5c1xuPSD2LUpB6YXlg4c=";
  };
  pkgs = import releasedPkgs {};
  stdenv = pkgs.stdenv;
  extraInputs = sysPkg.lib.optionals stdenv.isDarwin (with sysPkg.darwin.apple_sdk.frameworks; [
    Cocoa
    CoreServices]);


in stdenv.mkDerivation {
  name = "env";
  buildInputs = [ pkgs.gnumake
                  pkgs.erlangR24
                  pkgs.rebar3
                  pkgs.wget

                  pkgs.rebar

                # UI
                  pkgs.foreman

                ] ++ extraInputs;
  shellHook = ''
        source .env
  '';

}
