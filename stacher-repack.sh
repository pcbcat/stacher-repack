#!/bin/bash

clear

# version
Version="v1.0.0"

# =================================================================
# stacher repackaging script
# see readme.md for info
# =================================================================

# exit on error
set -e
# exit on unset vars
set -u
# pipelines fail on first error
set -o pipefail


# --- Configuration & Globals ---

# constants
APP_NAME="Stacher7"
APPDIR_NAME="unpacked-stacher7"
APPIMAGE_TOOL="appimagetool-x86_64.AppImage"

# state variables
SCRIPT_DIR=$(pwd)
DEB_FILE=$(find . -maxdepth 1 -iname "stacher*.deb" -print -quit)
TEMP_DIR="" # set later

# colors
Blu='\e[0;34m';
Yel='\e[0;33m';
Gre='\e[0;32m';
Red='\e[0;31m';
NC='\e[0m';

# --- Helper Functions ---

# runs on exit to clean up temp files
cleanup() {
  local exit_code=$?
  # un-register trap to prevent loops
  trap - EXIT

  # clean up temp dir if it exists
  if [ -n "$TEMP_DIR" ] && [ -d "$TEMP_DIR" ]; then
    log_info "Cleaning up temporary files..."
    rm -rf "$TEMP_DIR"
  fi

  # handle unexpected errors
  case $exit_code in
    0|2|3|4|5|6)
      # known exit, do nothing
      ;;
    *)
      # unexpected error
      log_error "Script failed with an unexpected error (exit code: $exit_code)."
      log_info "Please file a bug report at: https://github.com/pcbcat/stacher-repack/issues"
      ;;
  esac

  # exit with original code
  exit $exit_code
}

# register cleanup func
trap cleanup EXIT # The EXIT trap is special, it runs on any script exit.

# logging functions to standardize output
log_info() { echo -e "${Blu}==>${NC} $1"; }
log_warn() { echo -e "${Yel}==> WARNING:${NC} $1"; }
log_error() { echo -e "${Red}==> ERROR:${NC} $1"; }
log_success() { echo -e "${Gre}==> SUCCESS:${NC} $1"; }


# --- Core Logic Functions ---

check_dependencies() {
  log_info "Checking for required tools..."
  local dependencies=(ar tar zstd uname grep mktemp sed curl cut)
  local missing_deps=()
  for cmd in "${dependencies[@]}"; do
    if ! command -v "$cmd" &> /dev/null; then
      missing_deps+=("$cmd")
    fi
  done

  if [ ${#missing_deps[@]} -ne 0 ]; then
    log_error "Missing required command(s): ${missing_deps[*]}"
    log_info "Please install them using your system's package manager."
    log_info "e.g. for Debian/Ubuntu: sudo apt install binutils tar zstd coreutils grep sed curl gawk"
    exit 5 
  fi
  log_info "All required tools are present."
}

setup_workspace() {
  echo "[1/7] Setting up temporary workspace..."
  TEMP_DIR=$(mktemp -d) # create a secure temporary directory
  cp "$DEB_FILE" "$TEMP_DIR/"
  cd "$TEMP_DIR" || exit
}

download_appimagetool() {
  log_warn "AppImageTool ('$APPIMAGE_TOOL') not found."
  local prompt
  printf -v prompt "Do you want to download the latest version automatically? (%b/%b) " "${Gre}y${NC}" "${Red}n${NC}"
  while true; do
      read -p "$prompt" yn
      case $yn in
          [Yy]* ) break;;
          [Nn]* ) log_info "Aborting. Please download the tool manually."; exit 2;;
          * ) log_error "Invalid input. Please answer yes (y) or no (n).";;
      esac
  done

  log_info "Finding latest AppImageTool release..."
  local DOWNLOAD_URL
  DOWNLOAD_URL=$(curl -s https://api.github.com/repos/AppImage/appimagetool/releases/latest | grep "browser_download_url.*x86_64.AppImage" | cut -d '"' -f 4)

  if [ -z "$DOWNLOAD_URL" ]; then
    log_error "Could not automatically find the download URL for AppImageTool."
    log_info "Please download it manually from https://github.com/AppImage/appimagetool/releases"
    exit 2
  fi

  log_info "Downloading from: $DOWNLOAD_URL"
  if ! curl -L --progress-bar -o "$APPIMAGE_TOOL" "$DOWNLOAD_URL"; then
    log_error "Download failed."
    rm -f "$APPIMAGE_TOOL" # clean up partially downloaded file
    exit 2
  fi
  log_success "Download complete."
}

unpack_deb_archive() {
  echo "[2/7] Unpacking Debian archive..."
  # extracts all from the .deb
  ar x ./*.deb
}

verify_architecture() {
  echo "[3/7] Verifying package architecture..."
  # unpack control files to a sub-dir to avoid conflicts
  mkdir control_files
  tar -I zstd -xf control.tar.zst -C control_files

  local DEB_ARCH MACHINE_ARCH UNAME_ARCH
  DEB_ARCH=$(grep -oP '^Architecture: \K.*' control_files/control)
  UNAME_ARCH=$(uname -m)

  # translate arch format for comparison
  case "$UNAME_ARCH" in
    "x86_64")
      MACHINE_ARCH="amd64"
      ;;
    "aarch64")
      MACHINE_ARCH="arm64"
      ;;
    *)
      log_error "Unsupported machine architecture '$UNAME_ARCH'."
      log_info "This script cannot verify compatibility for this architecture."
      exit 4
      ;;
  esac

  if [ "$DEB_ARCH" != "$MACHINE_ARCH" ]; then
    log_error "Architecture mismatch!"
    log_info "Package is for '$DEB_ARCH', but this machine is '$MACHINE_ARCH' ($UNAME_ARCH)."
    exit 4
  fi
  echo "Architecture check passed ($MACHINE_ARCH)."
}

unpack_data() {
  echo "[4/7] Unpacking application data..."
  tar -I zstd -xf data.tar.zst
}

assemble_appdir() {
  echo "[5/7] Assembling the AppDir..."
  mkdir "$APPDIR_NAME"
  cp -r usr/lib/stacher7/* "$APPDIR_NAME/"
  cp usr/share/applications/stacher7.desktop "$APPDIR_NAME/"
  cp usr/share/pixmaps/stacher7.png "$APPDIR_NAME/"
}

configure_appimage() {
  echo "[6/7] Configuring AppImage..."
  sed -i 's|^Exec=.*|Exec=Stacher7|' "$APPDIR_NAME/stacher7.desktop"
  sed -i 's|^Icon=.*|Icon=stacher7|' "$APPDIR_NAME/stacher7.desktop"

  cat <<EOF > "$APPDIR_NAME/AppRun"
#!/bin/bash
HERE="\$(dirname "\$(readlink -f "\${0}")")"
chmod +x "\$HERE/Stacher7"
chmod +x "\$HERE/chrome-sandbox"
exec "\$HERE/Stacher7" --no-sandbox "\$@"
EOF
  chmod +x "$APPDIR_NAME/AppRun"
}

build_appimage() {
  echo "[7/7] Building the AppImage..."
  local APPDIR_PATH
  # get absolute path to the appdir
  APPDIR_PATH=$(pwd -P)/$APPDIR_NAME

  # cd back to start dir
  cd "$SCRIPT_DIR" || exit

  # run appimagetool, this makes the final file
  if ! ./"$APPIMAGE_TOOL" "$APPDIR_PATH"; then
      log_error "appimagetool failed to build the AppImage."
      log_info "Please check the output from the tool above for details."
      exit 6
  fi

  # clean up appimagetool's leftover a.out file
  rm -f a.out
}

show_intro() {
  echo -e "${Blu}Stacher Repackager $Version by pcbcat${NC}"
  echo ""
  echo -e "${Yel}WARNING:${NC} In order for this script to run correctly, it requires the following:"
  echo "  - The packaged Stacher7 .deb file: https://stacher.io/"
  echo "  - Appimagetool (will be downloaded if missing)"
  echo "  - A compatible machine architecture (e.g., x86_64)"
  echo "  - AppImage support on your system"
  echo ""
  log_info "For more information, please read README.md in the github repository."

  # confirm user wants to continue
  local prompt
  printf -v prompt "Do you wish to continue? (%b/%b) " "${Gre}y${NC}" "${Red}n${NC}"
  while true; do
      read -p "$prompt" yn
      case $yn in
          [Yy]* ) echo ""; break;;
          [Nn]* ) log_info "Aborting script."; exit 0;;
          * ) log_error "Invalid input. Please answer yes (y) or no (n).";;
      esac
  done
}

run_preflight_checks() {
  log_info "Running pre-flight checks..."
  # 1. check for dependencies
  check_dependencies

  # 2. check for appimagetool, download if missing
  if [ ! -f "$APPIMAGE_TOOL" ]; then
      download_appimagetool
  fi
  chmod +x "$APPIMAGE_TOOL"

  # 3. check for .deb file
  if [ -z "$DEB_FILE" ]; then
    log_error "No 'stacher*.deb' file found in the current directory."
    log_info "Please place the Stacher .deb file here before running the script."
    log_info "You can get it at: https://stacher.io/"
    exit 3
  fi

  log_info "Source .deb file: $DEB_FILE"
  log_info "AppImage tool:    $APPIMAGE_TOOL"
}

# --- Main Execution ---

main() {
  show_intro
  run_preflight_checks

  log_info "Starting AppImage creation process for $APP_NAME..."

  # run main steps
  setup_workspace
  unpack_deb_archive
  verify_architecture
  unpack_data
  assemble_appdir
  configure_appimage
  build_appimage

  echo ""
  log_success "AppImage has been created in the current directory."
}

# run main
main
