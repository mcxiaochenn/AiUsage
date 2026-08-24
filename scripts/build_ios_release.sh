#!/usr/bin/env bash
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "iOS release builds require macOS." >&2
  exit 1
fi

project_root="$(cd "$(dirname "$0")/.." && pwd)"
app_root="$project_root/app"
output_root="$app_root/build/release"

if [[ "$(git -C "$project_root" rev-parse --is-shallow-repository)" != "false" ]]; then
  echo "Release builds require complete Git history; shallow clones are not supported." >&2
  exit 1
fi

build_number="$(git -C "$project_root" rev-list --count HEAD)"
if [[ ! "$build_number" =~ ^[1-9][0-9]*$ ]]; then
  echo "Invalid Git commit count: $build_number" >&2
  exit 1
fi

version_name="$(sed -nE 's/^version:[[:space:]]*([0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?)[[:space:]]*$/\1/p' "$app_root/pubspec.yaml")"
if [[ -z "$version_name" ]]; then
  echo "app/pubspec.yaml must contain a SemVer without a +buildNumber suffix." >&2
  exit 1
fi

pushd "$app_root" >/dev/null
flutter build ios --release --no-codesign --no-pub \
  --build-name "$version_name" --build-number "$build_number"
popd >/dev/null

runner_app="$app_root/build/ios/iphoneos/Runner.app"
info_plist="$runner_app/Info.plist"
if [[ ! -d "$runner_app" || ! -f "$info_plist" ]]; then
  echo "Runner.app was not produced at $runner_app" >&2
  exit 1
fi

plist_value() {
  /usr/libexec/PlistBuddy -c "Print :$1" "$info_plist"
}

bundle_id="$(plist_value CFBundleIdentifier)"
bundle_version="$(plist_value CFBundleShortVersionString)"
bundle_build="$(plist_value CFBundleVersion)"
executable_name="$(plist_value CFBundleExecutable)"
executable="$runner_app/$executable_name"

[[ "$bundle_id" == "dev.chendusk.aiusage" ]] || { echo "Unexpected bundle id: $bundle_id" >&2; exit 1; }
[[ "$bundle_version" == "$version_name" ]] || { echo "Version mismatch: $bundle_version" >&2; exit 1; }
[[ "$bundle_build" == "$build_number" ]] || { echo "Build number mismatch: $bundle_build" >&2; exit 1; }
[[ -x "$executable" ]] || { echo "Runner executable is missing: $executable" >&2; exit 1; }
file "$executable" | grep -q 'arm64' || { echo "Runner executable does not contain arm64." >&2; exit 1; }

rust_archive="$(find "$app_root/build/ios" -name 'libai_usage_core.a' -type f -print -quit)"
[[ -n "$rust_archive" ]] || { echo "libai_usage_core.a was not produced by Cargokit." >&2; exit 1; }
rust_strings="$(mktemp)"
strings "$executable" > "$rust_strings"
if ! grep -Fq 'begin_device_login' "$rust_strings" ||
   ! grep -Fq 'refresh_deepseek_usage' "$rust_strings"; then
  rm -f "$rust_strings"
  echo "Runner does not contain the expected flutter_rust_bridge API payload." >&2
  exit 1
fi
rm -f "$rust_strings"

if [[ -d "$runner_app/_CodeSignature" ]]; then
  echo "Runner.app unexpectedly contains a code signature." >&2
  exit 1
fi

mkdir -p "$output_root"
staging="$(mktemp -d)"
trap 'rm -rf "$staging"' EXIT
mkdir -p "$staging/Payload"
ditto "$runner_app" "$staging/Payload/Runner.app"

artifact="$output_root/AiUsage-ios-release-unsigned.ipa"
rm -f "$artifact"
pushd "$staging" >/dev/null
ditto -c -k --sequesterRsrc Payload "$artifact"
popd >/dev/null

unzip -l "$artifact" | grep -q 'Payload/Runner.app/Info.plist' || {
  echo "IPA Payload layout is invalid." >&2
  exit 1
}

printf 'Artifact: %s\nVersion: %s\nBuild: %s\nBundle: %s\n' \
  "$artifact" "$version_name" "$build_number" "$bundle_id"
