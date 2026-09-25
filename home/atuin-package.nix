{ pkgs }:

let
  version = "18.23.0";
  release =
    if pkgs.stdenv.hostPlatform.isDarwin then
      {
        target = "aarch64-apple-darwin";
        hash = "sha256-yYi+HN4ZzXKVzmS8i5VdQvsYVeUifLZAyH/AnIQIw/w=";
      }
    else
      {
        target = "x86_64-unknown-linux-musl";
        hash = "sha256-0bQN1ufNPYI4Z//iKzmgJbxCD3h1kmrpypdBVTeNoU0=";
      };
in
pkgs.stdenvNoCC.mkDerivation {
  pname = "atuin";
  inherit version;

  src = pkgs.fetchurl {
    url = "https://github.com/atuinsh/atuin/releases/download/v${version}/atuin-${release.target}.tar.gz";
    inherit (release) hash;
  };

  dontUnpack = true;
  nativeBuildInputs = [ pkgs.gnutar ];
  installPhase = ''
    runHook preInstall
    mkdir -p "$out/bin"
    tar -xzf "$src" -C "$out/bin" --strip-components=1 "atuin-${release.target}/atuin"
    chmod +x "$out/bin/atuin"
    runHook postInstall
  '';

  meta.mainProgram = "atuin";
}
