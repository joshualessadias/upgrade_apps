#!/usr/bin/env zsh
#
# Script to upgrade Homebrew cask-managed applications in ~/Applications
# Created: $(date)
# Updated: $(date)
#
# This script should be placed inside the folder containing the applications you want to upgrade.
#
# Usage: ./upgrade_apps.sh [options]
#   Options:
#     --skip-sudo     Skip applications that typically require sudo permissions
#     --help          Show this help message
#

# --- Helper Functions ---

# Print section header
print_header() {
  echo "\n\033[1;34m==== $1 ====\033[0m\n"
}

# Print success message
print_success() {
  echo "\033[1;32m✓ $1\033[0m"
}

# Print error message
print_error() {
  echo "\033[1;31m✗ $1\033[0m"
}

# Print info message
print_info() {
  echo "\033[1;36mℹ $1\033[0m"
}

# Print warning message
print_warning() {
  echo "\033[1;33m⚠ $1\033[0m"
}

# Check if Homebrew is installed
check_brew() {
  if ! command -v brew &> /dev/null; then
    print_error "Homebrew is not installed or not in PATH."
    echo "Please install Homebrew first: https://brew.sh/"
    exit 1
  fi
}

# Check for running brew processes
check_running_brew() {
  local running_brew=$(ps aux | grep -v grep | grep -c "brew")
  if [[ $running_brew -gt 1 ]]; then
    print_warning "Other brew processes are currently running."
    print_warning "This may cause conflicts. Consider trying again later."
    if [[ "$SKIP_WARNING" != "true" ]]; then
      read -q "REPLY?Continue anyway? (y/n) "
      echo
      if [[ "$REPLY" != "y" ]]; then
        print_info "Exiting."
        exit 0
      fi
    fi
  fi
}

# Check if an app exists at the expected path
check_app_path() {
  local app_name="$1"
  local app_path="$2"

  if [[ ! -d "$app_path" ]]; then
    print_warning "App not found at expected path: $app_path"
    # Check if it exists elsewhere
    local found_path=$(find ~/Applications -maxdepth 1 -name "${app_name}*.app" 2>/dev/null)
    if [[ -n "$found_path" ]]; then
      print_info "Found app at alternative path: $found_path"
      echo "$found_path"
      return 0
    fi
    echo ""
    return 1
  fi

  echo "$app_path"
  return 0
}

# List of apps that typically require sudo
declare -A sudo_apps
sudo_apps=(
  ["spotify"]="true"
  ["jetbrains-toolbox"]="true"
  # Add more apps that typically require sudo
)

# Function to show help/usage
show_help() {
  cat << EOF
Usage: ./upgrade_apps.sh [options]

This script should be placed inside the folder containing the applications you want to upgrade.

Options:
  --skip-sudo     Skip applications that typically require sudo permissions
  --help          Show this help message

Examples:
  ./upgrade_apps.sh --skip-sudo
EOF
  exit 0
}

# --- Main Script ---
print_header "Homebrew Application Upgrade Script"

# Parse command line arguments
SKIP_SUDO=false
SKIP_WARNING=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-sudo)
      SKIP_SUDO=true
      shift
      ;;
    --help)
      show_help
      ;;
    *)
      print_error "Unknown option: $1"
      show_help
      ;;
  esac
done

# Check for Homebrew
check_brew

# Check for running brew processes
check_running_brew

# Initialize counters
total_apps=0
processed_apps=0
successful_upgrades=0
failed_upgrades=0
skipped_apps=0
sudo_skipped=0

# Arrays to track apps by status
successfully_upgraded_apps=()
failed_upgrade_apps=()
not_managed_apps=()
sudo_skipped_apps=()

# Get the list of installed Homebrew casks
print_info "Getting list of installed Homebrew casks..."
brew_casks=$(brew list --cask)
if [[ $? -ne 0 ]]; then
  print_error "Failed to retrieve Homebrew casks. Exiting."
  exit 1
fi

# Get applications in ~/Applications
print_info "Scanning ~/Applications directory..."
apps=()
for app in ~/Applications/*.app; do
  if [[ -d "$app" ]]; then
    app_name=$(basename "$app" .app)
    apps+=("$app_name")
    ((total_apps++))
  fi
done

if [[ ${#apps[@]} -eq 0 ]]; then
  print_warning "No applications found in ~/Applications."
  exit 0
fi

print_info "Found ${#apps[@]} applications in ~/Applications."

# Array to store failed apps and their error messages
failed_apps=()

# Process each application
print_header "Processing Applications"

for app in "${apps[@]}"; do
  ((processed_apps++))

  # Create potential cask names (common variations)
  # Lowercase, replace spaces with hyphens
  potential_cask="${app:l}"
  potential_cask="${potential_cask// /-}"

  # Some apps have specific cask names - handle common cases
  case "$app" in
    "Brave Browser")
      potential_cask="brave-browser"
      ;;
    "Notion Calendar")
      potential_cask="notion-calendar"
      ;;
    "JetBrains Toolbox")
      potential_cask="jetbrains-toolbox"
      ;;
    # Add more special cases as needed
  esac

  # Always print the processing header first
  print_info "Processing $app ($potential_cask)..."

  # Check if the app is managed by Homebrew
  if echo "$brew_casks" | grep -q "$potential_cask"; then

    # Check if this app typically requires sudo and if we should skip it
    if [[ "$SKIP_SUDO" == "true" && "${sudo_apps[$potential_cask]}" == "true" ]]; then
      print_warning "Skipping $app as it typically requires sudo (--skip-sudo option enabled)."
      sudo_skipped_apps+=("$app")
      ((sudo_skipped++))
      ((skipped_apps++))
      echo "----------------------------------------"
      continue
    fi

    # Check if the app exists at the expected path
    app_path=$(check_app_path "$app" ~/Applications/"$app.app")
    if [[ -z "$app_path" ]]; then
      print_error "Cannot find $app in Applications directory. Skipping upgrade."
      failed_apps+=("$app: App not found at expected path")
      ((failed_upgrades++))
      echo "----------------------------------------"
      continue
    fi

    # Attempt to upgrade the cask
    echo "Attempting to upgrade $potential_cask..."

    # Run the brew upgrade command and capture its output
    upgrade_output=$(brew upgrade --cask "$potential_cask" 2>&1)
    upgrade_status=$?

    if [[ $upgrade_status -eq 0 ]]; then
      if [[ "$upgrade_output" == *"already installed"* || "$upgrade_output" == *"up-to-date"* ]]; then
        print_info "$app is already up-to-date."
      else
        print_success "$app upgraded successfully."
        successfully_upgraded_apps+=("$app")
        ((successful_upgrades++))
      fi
    else
      # Extract meaningful error message from upgrade output
      error_msg=$(echo "$upgrade_output" | grep -i "error:" | head -1)
      if [[ -z "$error_msg" ]]; then
        # If no specific error message found, use the last few lines
        error_msg=$(echo "$upgrade_output" | tail -3)
      fi

      print_error "Failed to upgrade $app."
      print_warning "Error message: $error_msg"

      # Check for common error patterns
      if [[ "$upgrade_output" == *"sudo"* || "$upgrade_output" == *"password"* ]]; then
        print_info "This app may require sudo privileges. Consider using --skip-sudo option."
        # Add to sudo apps list for future reference
        sudo_apps["$potential_cask"]="true"
      elif [[ "$upgrade_output" == *"already running"* ]]; then
        print_info "The app may be currently running. Close it and try again."
      elif [[ "$upgrade_output" == *"not there"* || "$upgrade_output" == *"not found"* ]]; then
        print_info "The app path may be incorrect. The app might have been moved or renamed."
      elif [[ "$upgrade_output" == *"no cask"* ]]; then
        print_info "The cask name might have changed. Check with 'brew info $potential_cask'."
      fi

      failed_apps+=("$app: $error_msg")
      failed_upgrade_apps+=("$app")
      ((failed_upgrades++))
    fi
  else
    print_warning "Skipping $app - not managed by Homebrew."
    not_managed_apps+=("$app")
    ((skipped_apps++))
  fi

  # Add a separator between apps
  echo "----------------------------------------"
done

# Print summary
print_header "Summary"
echo "Total applications found: $total_apps"
echo "Applications processed: $processed_apps"
echo "Successfully upgraded: $successful_upgrades"
echo "Failed upgrades: $failed_upgrades"
echo "Skipped (not managed by Homebrew): $((skipped_apps - sudo_skipped))"
if [[ $sudo_skipped -gt 0 ]]; then
  echo "Skipped (sudo required): $sudo_skipped"
fi
# Print details about failed upgrades if any
if [[ ${#failed_apps[@]} -gt 0 ]]; then
  print_header "Failed Upgrades"
  for failed_app in "${failed_apps[@]}"; do
    print_error "$failed_app"
  done

  print_info "You may want to upgrade these applications manually or check the error messages."
  print_info "For apps that require sudo, try running the script with admin privileges or upgrade manually."
fi

# Print app status details
print_header "Application Status Details"

# Always show Successfully Upgraded Apps category
print_success "Successfully Upgraded Apps:"
if [[ ${#successfully_upgraded_apps[@]} -gt 0 ]]; then
  for app in "${successfully_upgraded_apps[@]}"; do
    echo "  - $app"
  done
else
  echo "  (none)"
fi
echo

if [[ ${#failed_upgrade_apps[@]} -gt 0 ]]; then
  print_error "Failed Upgrade Apps:"
  for app in "${failed_upgrade_apps[@]}"; do
    echo "  - $app"
  done
  echo
fi

if [[ ${#not_managed_apps[@]} -gt 0 ]]; then
  print_warning "Apps Not Managed by Homebrew:"
  for app in "${not_managed_apps[@]}"; do
    echo "  - $app"
  done
  echo
fi

if [[ ${#sudo_skipped_apps[@]} -gt 0 ]]; then
  print_warning "Apps Skipped (Sudo Required):"
  for app in "${sudo_skipped_apps[@]}"; do
    echo "  - $app"
  done
  echo
fi

# Print details about failed upgrades if any
print_header "Recommendations"

if [[ $failed_upgrades -gt 0 ]]; then
  print_info "Some upgrades failed. You may want to:"
  echo "  - Run 'brew doctor' to check for Homebrew issues"
  echo "  - Check if apps are currently running before upgrading"
  echo "  - Try using 'brew upgrade --cask --force [app]' for specific apps"
  echo "  - You may need to run with sudo for some apps: 'sudo brew upgrade --cask [app]'"
fi

if [[ $sudo_skipped -gt 0 && "$SKIP_SUDO" == "true" ]]; then
  print_info "Some apps were skipped because they require sudo privileges."
  echo "  - Run without the --skip-sudo option to attempt upgrading these apps"
  echo "  - Or upgrade these apps manually using 'brew upgrade --cask [app]'"
fi

print_header "Done"

exit 0

