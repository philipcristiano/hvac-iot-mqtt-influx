let
  sysPkg = import <nixpkgs> { };
  releasedPkgs = sysPkg.fetchFromGitHub {
    owner = "NixOS";
    repo = "nixpkgs";
    rev = "20.09";
    sha256 = "1wg61h4gndm3vcprdcg7rc4s1v3jkm5xd7lw8r2f67w502y94gcy";
  };
  stdenv = released_pkgs.stdenv;
  released_pkgs = import releasedPkgs {};

in stdenv.mkDerivation {
  name = "env";
  buildInputs = [ released_pkgs.gnumake
                  released_pkgs.erlangR23

                  released_pkgs.wget
                ];
  shellHook = ''
            set -e
            source .env

  '';

}
