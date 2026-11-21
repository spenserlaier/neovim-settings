{
  lib,
  stdenvNoCC,
  fetchurl,
  installShellFiles,
  zstd,
}:
let
  version = "0.171.0";
  archives = {
    aarch64-darwin = {
      target = "aarch64-apple-darwin";
      hash = "sha256-zGNZD8u5f5/pXS8QqocIzlZ4NYRNOgo36H0X4AfXrKA=";
    };
    x86_64-linux = {
      target = "x86_64-unknown-linux-musl";
      hash = "sha256-hn4PY4oDu7+SLh93q9cNIuKD4qU/kygfygCayNDe5OA=";
    };
  };
  archive = archives.${stdenvNoCC.hostPlatform.system};
in
stdenvNoCC.mkDerivation {
  pname = "codex";
  inherit version;
  src = fetchurl {
    url = "https://github.com/openai/codex/releases/download/rust-v${version}/codex-package-${archive.target}.tar.zst";
    inherit (archive) hash;
  };
  nativeBuildInputs = [
    installShellFiles
    zstd
  ];
  dontUnpack = true;
  # Keep the upstream package layout and signed binaries intact for daemon mode.
  dontFixup = true;
  installPhase = ''
    runHook preInstall
    mkdir -p "$out"
    zstd -dc "$src" | tar -xf - -C "$out"
    installShellCompletion --cmd codex \
      --bash <("$out/bin/codex" completion bash) \
      --fish <("$out/bin/codex" completion fish) \
      --zsh <("$out/bin/codex" completion zsh)
    runHook postInstall
  '';
  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    test "$("$out/bin/codex" --version)" = "codex-cli ${version}"
    runHook postInstallCheck
  '';
  meta = {
    description = "OpenAI Codex CLI";
    homepage = "https://github.com/openai/codex";
    license = lib.licenses.asl20;
    mainProgram = "codex";
    platforms = builtins.attrNames archives;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}
