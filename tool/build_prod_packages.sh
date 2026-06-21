#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"

ENV_FILE="${ROOT_DIR}/.env.dart.define.json"
OUTPUT_ROOT="${ROOT_DIR}/dist/prod_packages"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
OUTPUT_DIR="${OUTPUT_ROOT}/${TIMESTAMP}"
PLATFORMS="android,ios,macos,windows,linux"
RUN_CLEAN=true

print_help() {
  cat <<'EOF'
Usage: tool/build_prod_packages.sh [options]

Build production Flutter packages and copy them to a timestamped folder.

Options:
  --env-file <path>      Path to dart define json file
                         (default: .env.dart.define.json)
  --platforms <list>     Comma-separated list: android,android-playstore,ios,ios-appstore,macos,macos-appstore,windows,linux
                         (default: all)
  --no-clean             Skip flutter clean + flutter pub get
  --output-dir <path>    Output base directory (default: dist/prod_packages)
  -h, --help             Show this help

Examples:
  tool/build_prod_packages.sh
  tool/build_prod_packages.sh --platforms android,macos
  tool/build_prod_packages.sh --env-file .env.prod.json --output-dir dist/releases
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --env-file)
      ENV_FILE="$2"
      shift 2
      ;;
    --platforms)
      PLATFORMS="$2"
      shift 2
      ;;
    --no-clean)
      RUN_CLEAN=false
      shift
      ;;
    --output-dir)
      OUTPUT_ROOT="$2"
      OUTPUT_DIR="${OUTPUT_ROOT}/${TIMESTAMP}"
      shift 2
      ;;
    -h|--help)
      print_help
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      print_help
      exit 1
      ;;
  esac
done

if [[ "${ENV_FILE}" != /* ]]; then
  ENV_FILE="${ROOT_DIR}/${ENV_FILE}"
fi

if [[ "${OUTPUT_ROOT}" != /* ]]; then
  OUTPUT_ROOT="${ROOT_DIR}/${OUTPUT_ROOT}"
  OUTPUT_DIR="${OUTPUT_ROOT}/${TIMESTAMP}"
fi

if ! command -v flutter >/dev/null 2>&1; then
  echo "flutter command not found in PATH"
  exit 1
fi

if [[ ! -f "${ENV_FILE}" ]]; then
  echo "Env file not found: ${ENV_FILE}"
  exit 1
fi

mkdir -p "${OUTPUT_DIR}"

build_args=(--release --dart-define-from-file="${ENV_FILE}")

copy_if_exists() {
  local src="$1"
  local dest="$2"
  if [[ -e "${src}" ]]; then
    cp -R "${src}" "${dest}"
    echo "Saved: ${dest}"
  else
    echo "Artifact not found: ${src}"
    return 1
  fi
}

zip_dir() {
  local src_dir="$1"
  local zip_target="$2"
  if command -v zip >/dev/null 2>&1; then
    (
      cd "$(dirname -- "${src_dir}")"
      zip -r "${zip_target}" "$(basename -- "${src_dir}")" >/dev/null
    )
    echo "Saved: ${zip_target}"
  else
    echo "zip command not found, directory copied without zip: ${src_dir}"
  fi
}

run_xcodebuild_filtered() {
  local filter_regex="$1"
  shift

  local xcodebuild_status=0
  set +e
  "$@" 2>&1 | grep -E "${filter_regex}"
  xcodebuild_status=${PIPESTATUS[0]}
  set -e

  if [[ "${xcodebuild_status}" -ne 0 ]]; then
    echo "xcodebuild failed with exit code ${xcodebuild_status}"
  fi

  return "${xcodebuild_status}"
}

IFS=',' read -r -a selected_platforms <<<"${PLATFORMS}"

echo "Output folder: ${OUTPUT_DIR}"
echo "Using env file: ${ENV_FILE}"
echo "Platforms: ${PLATFORMS}"

if [[ "${RUN_CLEAN}" == true ]]; then
  echo "Running flutter clean and flutter pub get..."
  (cd "${ROOT_DIR}" && flutter clean && flutter pub get)
fi

for raw_platform in "${selected_platforms[@]}"; do
  platform="$(echo "${raw_platform}" | tr '[:upper:]' '[:lower:]' | xargs)"

  case "${platform}" in
    android)
      echo "Building Android app bundle..."
      (cd "${ROOT_DIR}" && flutter build appbundle "${build_args[@]}")
      copy_if_exists \
        "${ROOT_DIR}/build/app/outputs/bundle/release/app-release.aab" \
        "${OUTPUT_DIR}/password_manager-android-release.aab"

      echo "Building Android apk..."
      (cd "${ROOT_DIR}" && flutter build apk "${build_args[@]}")
      copy_if_exists \
        "${ROOT_DIR}/build/app/outputs/flutter-apk/app-release.apk" \
        "${OUTPUT_DIR}/password_manager-android-release.apk"
      ;;

    android-playstore)
      echo "Building Android app bundle for Play Store..."
      (cd "${ROOT_DIR}" && flutter build appbundle "${build_args[@]}")
      copy_if_exists \
        "${ROOT_DIR}/build/app/outputs/bundle/release/app-release.aab" \
        "${OUTPUT_DIR}/password_manager-android-release.aab"

      echo "Uploading to Google Play Store..."
      (cd "${ROOT_DIR}/android" && ./gradlew publishReleaseBundle)

      echo "Android Play Store upload complete."
      ;;

    ios)
      echo "Building iOS ipa..."
      (cd "${ROOT_DIR}" && flutter build ipa "${build_args[@]}")

      ipa_file="$(ls "${ROOT_DIR}"/build/ios/ipa/*.ipa 2>/dev/null | head -n 1 || true)"
      if [[ -n "${ipa_file}" ]]; then
        copy_if_exists "${ipa_file}" "${OUTPUT_DIR}/password_manager-ios-release.ipa"
      else
        echo "No .ipa found in build/ios/ipa"
      fi
      ;;

    ios-appstore)
      echo "Building iOS app for App Store..."
      ARCHIVE_PATH="${OUTPUT_DIR}/Runner-ios.xcarchive"
      EXPORT_PATH="${OUTPUT_DIR}/ios-appstore-export"
      EXPORT_OPTIONS="${ROOT_DIR}/ios/ExportOptions.plist"

      (cd "${ROOT_DIR}" && flutter build ios "${build_args[@]}" --no-codesign)

      echo "Archiving with xcodebuild..."
      run_xcodebuild_filtered "(error:|warning:|\*\* ARCHIVE (SUCCEEDED|FAILED) \*\*)" \
        xcodebuild archive \
        -workspace "${ROOT_DIR}/ios/Runner.xcworkspace" \
        -scheme Runner \
        -configuration Release \
        -destination "generic/platform=iOS" \
        -archivePath "${ARCHIVE_PATH}" \
        -allowProvisioningUpdates \
        CODE_SIGN_STYLE=Automatic \
        DEVELOPMENT_TEAM=A8QUU5F9G3

      echo "Exporting and uploading to App Store Connect..."
      run_xcodebuild_filtered "(error:|warning:|\*\* EXPORT (SUCCEEDED|FAILED) \*\*|Uploaded)" \
        xcodebuild -exportArchive \
        -archivePath "${ARCHIVE_PATH}" \
        -exportOptionsPlist "${EXPORT_OPTIONS}" \
        -exportPath "${EXPORT_PATH}" \
        -allowProvisioningUpdates

      echo "iOS App Store upload complete."
      ;;

    macos)
      echo "Building macOS app..."
      (cd "${ROOT_DIR}" && flutter build macos "${build_args[@]}")

      macos_app="${ROOT_DIR}/build/macos/Build/Products/Release/password_manager.app"
      copy_if_exists "${macos_app}" "${OUTPUT_DIR}/password_manager-macos-release.app"
      zip_dir "${OUTPUT_DIR}/password_manager-macos-release.app" "${OUTPUT_DIR}/password_manager-macos-release.zip"
      ;;

    macos-appstore)
      echo "Building macOS app for App Store..."
      ARCHIVE_PATH="${OUTPUT_DIR}/Runner.xcarchive"
      EXPORT_PATH="${OUTPUT_DIR}/macos-appstore-export"
      EXPORT_OPTIONS="${ROOT_DIR}/macos/ExportOptions.plist"

      # Generate Flutter/Xcode config without signing. The archive step below
      # owns App Store signing with provisioning updates enabled.
      (cd "${ROOT_DIR}" && flutter build macos "${build_args[@]}" --config-only)

      macos_appstore_signing_args=(
        -allowProvisioningUpdates
        CODE_SIGN_STYLE=Automatic
        DEVELOPMENT_TEAM=A8QUU5F9G3
        CODE_SIGN_IDENTITY="Apple Distribution"
      )

      echo "Archiving with xcodebuild..."
      run_xcodebuild_filtered "(error:|warning:|\*\* ARCHIVE (SUCCEEDED|FAILED) \*\*)" \
        xcodebuild archive \
        -workspace "${ROOT_DIR}/macos/Runner.xcworkspace" \
        -scheme Runner \
        -configuration Release \
        -destination "generic/platform=macOS" \
        -archivePath "${ARCHIVE_PATH}" \
        "${macos_appstore_signing_args[@]}"

      echo "Exporting and uploading to App Store Connect..."
      run_xcodebuild_filtered "(error:|warning:|\*\* EXPORT (SUCCEEDED|FAILED) \*\*|Uploaded)" \
        xcodebuild -exportArchive \
        -archivePath "${ARCHIVE_PATH}" \
        -exportOptionsPlist "${EXPORT_OPTIONS}" \
        -exportPath "${EXPORT_PATH}" \
        "${macos_appstore_signing_args[@]}"

      echo "macOS App Store upload complete."
      ;;

    windows)
      echo "Building Windows app..."
      (cd "${ROOT_DIR}" && flutter build windows "${build_args[@]}")

      windows_dir="${ROOT_DIR}/build/windows/x64/runner/Release"
      copy_if_exists "${windows_dir}" "${OUTPUT_DIR}/password_manager-windows-release"
      zip_dir "${OUTPUT_DIR}/password_manager-windows-release" "${OUTPUT_DIR}/password_manager-windows-release.zip"
      ;;

    linux)
      echo "Building Linux app..."
      (cd "${ROOT_DIR}" && flutter build linux "${build_args[@]}")

      linux_dir="${ROOT_DIR}/build/linux/x64/release/bundle"
      copy_if_exists "${linux_dir}" "${OUTPUT_DIR}/password_manager-linux-release"
      zip_dir "${OUTPUT_DIR}/password_manager-linux-release" "${OUTPUT_DIR}/password_manager-linux-release.zip"
      ;;

    "")
      ;;

    *)
      echo "Unsupported platform: ${platform}"
      echo "Supported: android, android-playstore, ios, ios-appstore, macos, macos-appstore, windows, linux"
      exit 1
      ;;
  esac
done

echo "Done. Production packages are in: ${OUTPUT_DIR}"
