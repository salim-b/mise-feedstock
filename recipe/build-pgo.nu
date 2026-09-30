#!/usr/bin/env nu
# Builds mise using upstream's profile-guided optimization script (`scripts/pgo.bash`) and, when BOLT support is
# enabled via `$env.MISE_BOLT`, its post-link optimization script (`scripts/bolt.bash`) afterwards. Invoked from
# `recipe.yaml`'s build script on native (non-cross) Unix builds, i.e. when the `use_pgo` context var is `true`.
# Expects `$env.MISE_FEATURES` to already be set to the desired `cargo build --features` value.

let prefix = $env.LIBRARY_PREFIX? | default $env.PREFIX

# `pgo.bash` hard-codes the `llvm-profdata` location inside the rustc sysroot; provide it from `llvm-tools`
let sysroot = (^rustc --print sysroot | str trim)
let rhost = (^rustc -vV | lines | where {|l| $l starts-with "host: "} | first | str replace "host: " "")
let profdata_dir = ($sysroot | path join lib rustlib $rhost bin)
let profdata = ($profdata_dir | path join llvm-profdata)
# `mkdir` is idempotent (like `mkdir -p`): it creates missing parent dirs and doesn't error if `$profdata_dir`
# already exists, so this is safe to run unconditionally. Nu's `path exists` follows symlinks and reports `false`
# for a dangling one (verified empirically), so a stale/broken `$profdata` symlink from a prior build also enters
# this branch; `rm -f` removes that leftover directory entry first, since `ln -s` refuses to overwrite an existing
# path (even a dangling symlink)
if not ($profdata | path exists) {
  mkdir $profdata_dir
  rm -f $profdata
  ^ln -s ($env.BUILD_PREFIX | path join bin llvm-profdata) $profdata
}

# `pgo.bash` invokes `"$MISE_PGO_BUILD_TOOL" build ...`, so wrap `cargo auditable` in a single executable
let pgo_build_tool = ($env.SRC_DIR | path join mise-pgo-build-tool.sh)
cp ($env.RECIPE_DIR | path join mise-pgo-build-tool.sh) $pgo_build_tool
^chmod +x $pgo_build_tool
$env.MISE_PGO_BUILD_TOOL = $pgo_build_tool
$env.MISE_PGO_PROFILE = "release" # reuse the `CARGO_PROFILE_RELEASE_*` settings instead of upstream's `serious` profile
# the rust compiler activation always sets `CARGO_BUILD_TARGET`, even for native builds, so `pgo.bash` must be told
# the same target triple to compute the correct build output path
$env.MISE_PGO_TARGET = $env.CARGO_BUILD_TARGET

^bash scripts/pgo.bash --locked --no-default-features --features=($env.MISE_FEATURES)

let mise_bin = ($env.SRC_DIR | path join target $env.CARGO_BUILD_TARGET release mise)
if $env.MISE_BOLT? == "1" {
  ^bash scripts/bolt.bash $mise_bin
  # strip only now, since BOLT needed the symbols kept above
  ^($env.BUILD_PREFIX | path join bin ($env.CHOST + "-strip")) $mise_bin
}

mkdir ($prefix)/bin
cp $mise_bin ($prefix)/bin/mise
