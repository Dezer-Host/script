#!/bin/bash

# Attempt to set pipefail, but don't error if not supported
if (set -o pipefail 2>/dev/null); then
    set -euo pipefail
    echo "DEBUG: pipefail is supported and set." >&2
else
    set -eu # Continue with error checking and unset variable checking
    # Use direct echo to LOG_FILE as log_message function may not be defined yet
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Warning: set -o pipefail is not supported by this shell. Pipeline behavior might differ." >>"$LOG_FILE"
    echo "DEBUG: pipefail is NOT supported. Using set -eu." >&2
fi

readonly RED='\033[0;31m'
readonly GREEN='\033[1;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly PURPLE='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly WHITE='\033[1;37m'
readonly BOLD='\033[1m'
readonly NC='\033[0m'
readonly SCRIPT_VERSION="3.0"

LOG_FILE="/tmp/dezerx-install.log"
LICENSE_KEY=""
DOMAIN=""
INSTALL_DIR=""
DB_PASSWORD=""
DB_NAME_PREFIX=""
DB_FULL_NAME=""
DB_USER_FULL=""
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# LOG_FILE already defined above
OPERATION_MODE=""
BACKUP_DIR=""
DB_BACKUP_FILE=""
RESTORE_ON_FAILURE=""
PROTOCOL="https"

# Initial Debug: Variables initialized.
echo "DEBUG: Global variables initialized." >&2

print_color() {
    printf "${1}${2}${NC}\n"
}

check_required_commands() {
    local cmds=(curl awk grep sed)
    for cmd in "${cmds[@]}"; do
        if ! command -v "$cmd" &>/dev/null; then
            print_error "Required command '$cmd' not found. Please install it." # print_error uses print_color
            exit 1
        fi
    done
}

log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >>"$LOG_FILE"
}

show_loading() {
    local pid=$1
    local message=$2
    local spin_frames=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
    # If colors are not defined yet or causing issues, remove them for debugging
    # local blue_color="$BLUE"
    # local green_color="$GREEN"
    # local nc_color="$NC"
    local blue_color='\033[0;34m' # Define locally if not sure about global scope yet
    local green_color='\033[1;32m'
    local nc_color='\033[0m'

    local frame_count=${#spin_frames[@]}
    local i=0

    # Hide cursor
    tput civis 2>/dev/null || true

    # Check if PID is valid and running
    while kill -0 "$pid" 2>/dev/null; do
        # Ensure message is not empty
        local display_message="${message:-Processing}"
        printf "\r${blue_color}%s %s${nc_color} " "$display_message" "${spin_frames[$i]}"
        i=$(((i + 1) % frame_count))
        sleep 0.08
    done

    # Show checkmark and restore cursor
    # Ensure message is not empty for the final display
    local final_display_message="${message:-Done}"
    printf "\r${blue_color}%s ${green_color}✔${nc_color}\n" "$final_display_message"
    tput cnorm 2>/dev/null || true
}

execute_with_loading() {
    local command="$1"
    local message="$2"

    log_message "Executing: $command"
    # Make eval safer by ensuring command is not empty
    if [[ -z "$command" ]]; then
        print_error "execute_with_loading received an empty command for message: $message"
        return 1 # Or exit, depending on desired strictness
    fi
    eval "$command" >>"$LOG_FILE" 2>&1 &
    local pid=$!
    show_loading $pid "$message"
    wait $pid
    local exit_code=$?

    if [ $exit_code -ne 0 ]; then
        print_error "Command failed (exit code $exit_code): $command" # Added exit code
        print_error "Check log file: $LOG_FILE"
        # Consider not exiting here directly but returning the error,
        # letting the caller decide, or rely on the ERR trap.
        return $exit_code # MODIFIED FROM exit $exit_code
    fi

    return $exit_code
}

execute_as_www_data() {
    local command_to_execute="$1"
    local loading_message="$2"
    local actual_command_string

    if id "www-data" &>/dev/null; then
        if command -v sudo &>/dev/null; then
            actual_command_string="sudo -u www-data $command_to_execute"
            execute_with_loading "$actual_command_string" "$loading_message (as www-data via sudo)"
        elif [[ $EUID -eq 0 ]]; then # Already root, use su
            # Ensure command_to_execute is properly quoted for su -c
            # Basic quoting for simple commands; complex commands might need more care
            local escaped_command_to_execute=$(printf "%q" "$command_to_execute")
            if [[ "$command_to_execute" == *\;* || "$command_to_execute" == *\|\|* || "$command_to_execute" == *\&\&* ]]; then
                # For complex commands, wrap in sh -c if not already
                if [[ ! ("$command_to_execute" == sh\ -c\ *) && ! ("$command_to_execute" == bash\ -c\ *) ]]; then
                    escaped_command_to_execute=$(printf "sh -c %q" "$command_to_execute")
                fi
            fi
            actual_command_string="su -s /bin/bash -c $escaped_command_to_execute www-data"
            execute_with_loading "$actual_command_string" "$loading_message (as www-data via su)"
        else
            print_warning "Cannot switch to www-data: sudo not found and not root. Running as current user."
            execute_with_loading "$command_to_execute" "$loading_message (as current user)"
        fi
    else
        print_warning "User www-data not found. Running as current user. Check permissions later."
        execute_with_loading "$command_to_execute" "$loading_message (as current user)"
    fi
    return $? # Return the exit code from execute_with_loading
}

print_banner() {
    # Make clear command more fault-tolerant
    command clear 2>/dev/null || printf '\033c' || echo "--- Attempted to clear screen ---"

    print_color $CYAN "
╔══════════════════════════════════════════════════════════════╗
║                                                              ║
║     ${BOLD}${WHITE}██████╗ ███████╗███████╗███████╗██████╗ ██╗  ██╗${NC}${CYAN}         ║
║     ${BOLD}${WHITE}██╔══██╗██╔════╝╚══███╔╝██╔════╝██╔══██╗╚██╗██╔╝${NC}${CYAN}         ║
║     ${BOLD}${WHITE}██║  ██║█████╗    ███╔╝ █████╗  ██████╔╝ ╚███╔╝ ${NC}${CYAN}         ║
║     ${BOLD}${WHITE}██║  ██║██╔══╝   ███╔╝  ██╔══╝  ██╔══██╗ ██╔██╗ ${NC}${CYAN}         ║
║     ${BOLD}${WHITE}██████╔╝███████╗███████╗███████╗██║  ██║██╔╝ ██╗${NC}${CYAN}         ║
║     ${BOLD}${WHITE}╚═════╝ ╚══════╝╚══════╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝${NC}${CYAN}         ║
║                                                              ║
║               ${BOLD}${YELLOW}INSTALLATION & UPDATE SCRIPT v${SCRIPT_VERSION}${NC}${CYAN}        ║
║                  🚀 Requires Root Access 🚀                  ║
╚══════════════════════════════════════════════════════════════╝
"
    print_color $YELLOW "📋 This script can install or update DezerX on Debian systems"
    print_color $YELLOW "⚡ Estimated time: 3-6 minutes (install) / 1-3 minutes (update)"
    print_color $YELLOW "📝 Operation log: $LOG_FILE"
    echo ""
}

print_step() {
    echo ""
    print_color $BOLD "${CYAN}┌─────────────────────────────────────────────────────────────┐"
    local step_line="│ Step $1: $2"
    local pad_length=$((62 - ${#step_line}))
    printf -v pad '%*s' "$pad_length" ''
    print_color $BOLD "${CYAN}${step_line}${pad}│"
    print_color $BOLD "${CYAN}└─────────────────────────────────────────────────────────────┘"
}

print_success() {
    printf "${GREEN}✔ %s${NC}\n" "$1"
}

print_error() {
    print_color $RED "❌ $1"
}

print_info() {
    print_color $BLUE "ℹ️  $1"
}

print_warning() {
    print_color $YELLOW "⚠️  $1"
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root!"
        print_info "Please run: sudo $0"
        exit 1
    fi
    print_success "Running with root privileges"
}

choose_install_variant() {
    print_step "0" "CHOOSE INSTALLATION VARIANT"
    print_color $CYAN "Please choose the installation variant:"
    print_color $WHITE "1) 🆕 Normal (without a GUI)"
    print_color $WHITE "2) 🖥️  GUI (with a graphical interface) (ALPHA) (not tested with Debian)"
    echo ""

    while true; do
        print_color $WHITE "Please choose an option (1 or 2):"
        read -r choice
        case $choice in
        1)
            print_success "Selected: Normal Installation (without GUI)"
            return 0
            ;;
        2)
            print_success "Selected: GUI Installation (ALPHA)"
            print_warning "This variant is still in ALPHA stage and may not work as expected."
            # Download and run the GUI script, then exit this script
            curl -fsSL https://raw.githubusercontent.com/Dezer-Host/script/main/script_gui.sh -o /tmp/dx.sh && bash /tmp/dx.sh
            exit 0
            ;;
        *)
            print_error "Invalid choice. Please enter 1 or 2."
            ;;
        esac
    done
}

choose_operation_mode() {
    print_step "1" "CHOOSE OPERATION"

    print_color $CYAN "What would you like to do?"
    print_color $WHITE "1) 🆕 Fresh Installation - Install DezerX from scratch"
    print_color $WHITE "2) 🔄 Update Existing - Update an existing DezerX installation"
    print_color $WHITE "3) ⚠️  Delete Installation - Remove DezerX and all its data ⚠️"
    echo ""

    while true; do
        print_color $WHITE "Please choose an option (1, 2, or 3):"
        read -r choice
        case $choice in
        1)
            OPERATION_MODE="install"
            print_success "Selected: Fresh Installation"
            print_warning "The non-automatic restore feature is intended for developers and testing environments only."
            print_color $WHITE "Would you like to automatically restore the previous backup if an error occurs? (y/n):"
            read -r restore_choice
            case $restore_choice in
            [Yy] | [Yy][Ee][Ss])
                print_info "Automatic restore enabled"
                RESTORE_ON_FAILURE="yes"
                ;;
            [Nn] | [Nn][Oo])
                print_info "Automatic restore disabled"
                RESTORE_ON_FAILURE="no"
                ;;
            *)
                print_error "Invalid choice. Defaulting to automatic restore."
                RESTORE_ON_FAILURE="yes"
                ;;
            esac
            break
            ;;
        2)
            OPERATION_MODE="update"
            print_success "Selected: Update Existing Installation"
            print_warning "The non-automatic restore feature is intended for developers and testing environments only."
            print_color $WHITE "Would you like to automatically restore the previous backup if an error occurs? (y/n):"
            read -r restore_choice
            case $restore_choice in
            [Yy] | [Yy][Ee][Ss])
                print_info "Automatic restore enabled"
                RESTORE_ON_FAILURE="yes"
                ;;
            [Nn] | [Nn][Oo])
                print_info "Automatic restore disabled"
                RESTORE_ON_FAILURE="no"
                ;;
            *)
                print_error "Invalid choice. Defaulting to automatic restore."
                RESTORE_ON_FAILURE="yes"
                ;;
            esac
            break
            ;;
        3)
            OPERATION_MODE="delete"
            print_success "Selected: Delete Installation"
            print_warning "This will remove DezerX and all its data permanently!"
            print_color $WHITE "Are you sure you want to delete the installation? Type 'DELETE EVERYTHING' to confirm:"
            read -r confirm_delete
            if [[ "$confirm_delete" == "DELETE EVERYTHING" ]]; then
                print_info "Proceeding with deletion..."
                local deletion_error=0

                # Ask for installation directory
                print_color $WHITE "Enter the DezerX installation directory to delete [default: /var/www/DezerX]:"
                read -r INSTALL_DIR_DELETE
                if [[ -z "$INSTALL_DIR_DELETE" ]]; then
                    INSTALL_DIR_DELETE="/var/www/DezerX"
                fi

                local env_file_path_delete="$INSTALL_DIR_DELETE/.env"
                local DB_FULL_NAME_DELETE=""
                local DB_USER_FULL_DELETE=""

                if [[ -f "$env_file_path_delete" ]]; then
                    DB_FULL_NAME_DELETE=$(get_env_variable "DB_DATABASE" "$env_file_path_delete")
                    DB_USER_FULL_DELETE=$(get_env_variable "DB_USERNAME" "$env_file_path_delete")
                else
                    print_warning ".env file not found at $env_file_path_delete. Will ask for DB details if cleanup is desired."
                    print_color $WHITE "Do you want to attempt to manually specify and delete database/user? (y/n)"
                    read -r manual_db_delete
                    if [[ "$manual_db_delete" =~ ^[Yy]$ ]]; then
                        print_color $WHITE "Enter database name to delete (leave blank if none):"
                        read -r DB_FULL_NAME_DELETE
                        print_color $WHITE "Enter database user to delete (leave blank if none):"
                        read -r DB_USER_FULL_DELETE
                    fi
                fi

                print_info "Removing Nginx configuration..."
                if [[ -f /etc/nginx/sites-enabled/dezerx.conf ]]; then
                    rm -f /etc/nginx/sites-enabled/dezerx.conf >>"$LOG_FILE" 2>&1 || deletion_error=1
                fi
                if [[ -f /etc/nginx/sites-available/dezerx.conf ]]; then
                    rm -f /etc/nginx/sites-available/dezerx.conf >>"$LOG_FILE" 2>&1 || deletion_error=1
                fi
                systemctl reload nginx >>"$LOG_FILE" 2>&1 || deletion_error=1
                print_success "Nginx configuration removed."

                print_info "Removing installation directory..."
                if [[ -d "$INSTALL_DIR_DELETE" ]]; then
                    rm -rf "$INSTALL_DIR_DELETE" >>"$LOG_FILE" 2>&1 || deletion_error=1
                    print_success "Installation directory removed: $INSTALL_DIR_DELETE"
                else
                    print_warning "Directory $INSTALL_DIR_DELETE does not exist. Skipping directory removal."
                fi

                if command -v mariadb &>/dev/null; then
                    if [[ -n "$DB_FULL_NAME_DELETE" ]]; then
                        print_info "Removing database '$DB_FULL_NAME_DELETE'..."
                        mariadb -e "DROP DATABASE IF EXISTS \`$DB_FULL_NAME_DELETE\`;" >>"$LOG_FILE" 2>&1 || deletion_error=1
                        print_success "Database '$DB_FULL_NAME_DELETE' removed (if it existed)."
                    fi
                    if [[ -n "$DB_USER_FULL_DELETE" ]]; then
                        print_info "Removing database user '$DB_USER_FULL_DELETE'..."
                        mariadb -e "DROP USER IF EXISTS '$DB_USER_FULL_DELETE'@'127.0.0.1';" >>"$LOG_FILE" 2>&1 || deletion_error=1
                        mariadb -e "DROP USER IF EXISTS '$DB_USER_FULL_DELETE'@'localhost';" >>"$LOG_FILE" 2>&1 || deletion_error=1
                        print_success "Database user '$DB_USER_FULL_DELETE' removed (if it existed)."
                    fi
                    if [[ -n "$DB_FULL_NAME_DELETE" || -n "$DB_USER_FULL_DELETE" ]]; then
                        mariadb -e "FLUSH PRIVILEGES;" >>"$LOG_FILE" 2>&1 || deletion_error=1
                    fi
                else
                    print_warning "mariadb command not found. Skipping database and user removal."
                fi

                print_info "Removing queue worker service..."
                if systemctl is-active --quiet dezerx.service; then
                    systemctl stop dezerx.service >>"$LOG_FILE" 2>&1 || deletion_error=1
                fi
                if systemctl is-enabled --quiet dezerx.service; then
                    systemctl disable dezerx.service >>"$LOG_FILE" 2>&1 || deletion_error=1
                fi
                if [[ -f /etc/systemd/system/dezerx.service ]]; then
                    rm -f /etc/systemd/system/dezerx.service >>"$LOG_FILE" 2>&1 || deletion_error=1
                fi
                systemctl daemon-reload >>"$LOG_FILE" 2>&1 || deletion_error=1
                print_success "Queue worker service removed."

                if [[ "$deletion_error" -ne 0 ]]; then
                    print_error "Some errors occurred during deletion. Please check the log: $LOG_FILE"
                else
                    print_success "DezerX and all related data have been deleted."
                fi
                exit 0
            else
                print_info "Deletion cancelled by user"
                exit 0
            fi
            break # Should not be reached if deletion proceeds or is cancelled
            ;;
        *)
            print_error "Invalid choice. Please enter 1, 2, or 3."
            ;;
        esac
    done
}

check_system_requirements() {
    if [[ "$OPERATION_MODE" == "install" ]]; then
        print_step "2" "CHECKING SYSTEM REQUIREMENTS"
    else
        print_step "2" "CHECKING SYSTEM STATUS"
    fi

    if ! command -v curl &>/dev/null; then
        execute_with_loading "apt-get update && apt-get install -y curl" "Installing curl"
    fi

    if ! command -v unzip &>/dev/null; then
        execute_with_loading "apt-get install -y unzip" "Installing unzip"
    fi

    if ! command -v lsb_release &>/dev/null; then
        execute_with_loading "apt-get install -y lsb-release" "Installing lsb-release"
    fi

    local os_name=$(lsb_release -si)
    local os_version=$(lsb_release -sr)

    print_info "Operating System: $os_name $os_version"

    if [[ "$os_name" != "Debian" ]]; then
        print_error "This script only supports Debian GNU/Linux."
        print_info "Your OS: $os_name $os_version"
        exit 1
    fi

    local available_space=$(df / | awk 'NR==2 {print $4}') # Space in 1K blocks
    local required_space_kb                                # Required space in 1K blocks
    if [[ "$OPERATION_MODE" == "install" ]]; then
        required_space_kb=$((5 * 1024 * 1024)) # 5GB in KB
    else
        required_space_kb=$((2 * 1024 * 1024)) # 2GB in KB
    fi

    if [[ $available_space -lt $required_space_kb ]]; then
        print_error "Insufficient disk space. Required: $((required_space_kb / 1024 / 1024))GB, Available: $((available_space / 1024 / 1024))GB"
        exit 1
    fi

    local total_mem_mb=$(free -m | awk 'NR==2{print $2}')
    if [[ $total_mem_mb -lt 1000 ]]; then # Check for ~1GB
        print_warning "Low memory detected: ${total_mem_mb}MB. Recommended: 2GB (2048MB) or more."
    fi

    print_success "System requirements check passed"
}

validate_domain() {
    local domain_to_validate=$1 # Renamed to avoid conflict with global DOMAIN

    if [[ $domain_to_validate =~ ^https?:// ]]; then
        return 2 # Indicates protocol included
    fi

    # Basic domain regex: starts with letter/number, can contain letters, numbers, hyphens (not at start/end of a part)
    # and must have at least one dot for TLD.
    if [[ ! $domain_to_validate =~ ^[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?)+$ ]]; then
        return 1 # Invalid format
    fi
    return 0 # Valid
}

validate_directory() {
    local dir_to_validate=$1 # Renamed to avoid conflict
    # Must be an absolute path, basic character set
    if [[ ! $dir_to_validate =~ ^/[a-zA-Z0-9/._-]+$ ]]; then
        return 1
    fi
    return 0
}

get_install_input() {
    print_step "3" "COLLECTING INSTALLATION DETAILS"

    while true; do
        print_color $BOLD$WHITE "🔑 Enter your DezerX license key:"
        read -r LICENSE_KEY
        if [[ -n "$LICENSE_KEY" && ${#LICENSE_KEY} -ge 10 ]]; then
            break
        else
            print_error "License key must be at least 10 characters. Please try again."
        fi
    done

    while true; do
        print_color $WHITE "🌐 Enter your domain or subdomain (e.g., example.com or app.example.com):"
        print_color $WHITE "   ⚠️  Do NOT include http:// or https:// - just the domain name"
        read -r DOMAIN

        local validation_result
        validate_domain "$DOMAIN"
        validation_result=$?

        if [[ $validation_result -eq 2 ]]; then
            print_error "Please enter the domain WITHOUT http:// or https://"
            print_error "Example: Use 'example.com' instead of 'https://example.com'"
            continue
        elif [[ $validation_result -eq 1 ]]; then
            print_error "Invalid domain format. Please try again."
            continue
        else
            break
        fi
    done

    while true; do
        print_color $WHITE "🌐 Use HTTPS (recommended) or HTTP? [https/http, default: https]:"
        read -r protocol_choice
        if [[ -z "$protocol_choice" || "$protocol_choice" =~ ^[Hh][Tt][Tt][Pp][Ss]$ ]]; then
            PROTOCOL="https"
            break
        elif [[ "$protocol_choice" =~ ^[Hh][Tt][Tt][Pp]$ ]]; then
            PROTOCOL="http"
            break
        else
            print_error "Please enter 'https' or 'http'."
        fi
    done

    while true; do
        print_color $WHITE "📁 Enter installation directory [default: /var/www/DezerX]:"
        read -r INSTALL_DIR
        if [[ -z "$INSTALL_DIR" ]]; then
            INSTALL_DIR="/var/www/DezerX"
        fi
        if validate_directory "$INSTALL_DIR"; then
            break
        else
            print_error "Invalid directory path. Path must be absolute (e.g., /var/www/myapp). Please try again."
        fi
    done

    while true; do
        print_color $CYAN "🗄️  DATABASE CONFIGURATION:"
        print_color $WHITE "Leave blank to use defaults."

        if [[ -z "$DB_NAME_PREFIX" ]]; then
            DB_NAME_PREFIX=$(echo "$DOMAIN" | grep -o '^[a-zA-Z0-9]*' | tr '[:upper:]' '[:lower:]' | cut -c1-4)
            if [[ -z "$DB_NAME_PREFIX" ]]; then
                DB_NAME_PREFIX="dzrx"
            fi
        fi

        print_color $WHITE "Database name [default: ${DB_NAME_PREFIX}_dezerx]:"
        read -r user_db_name
        if [[ -n "$user_db_name" ]]; then
            DB_FULL_NAME="$user_db_name"
        else
            DB_FULL_NAME="${DB_NAME_PREFIX}_dezerx"
        fi

        print_color $WHITE "Database user [default: ${DB_NAME_PREFIX}_dezer]:"
        read -r user_db_user
        if [[ -n "$user_db_user" ]]; then
            DB_USER_FULL="$user_db_user"
        else
            DB_USER_FULL="${DB_NAME_PREFIX}_dezer"
        fi

        print_color $WHITE "Database password [leave blank to auto-generate]:"
        read -r -s user_db_pass # -s for silent input
        echo                    # Newline after silent input
        if [[ -n "$user_db_pass" ]]; then
            DB_PASSWORD="$user_db_pass"
        else
            if [[ -z "$DB_PASSWORD" ]]; then # Generate only if not already set (e.g. by update)
                DB_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/\\\\" | cut -c1-25)
            fi
        fi
        break
    done

    echo ""
    print_color $CYAN "📋 INSTALLATION SUMMARY:"
    print_info "License Key: ${LICENSE_KEY:0:8}***"
    print_info "Domain: $DOMAIN"
    print_info "Full URL: ${PROTOCOL}://$DOMAIN"
    print_info "Install Directory: $INSTALL_DIR"
    print_info "Database Name: $DB_FULL_NAME"
    print_info "Database User: $DB_USER_FULL"
    print_info "Database Password: [${DB_PASSWORD:+Generated/Set}]"
    echo ""

    while true; do
        print_color $WHITE "Continue with installation? (y/n):"
        read -r confirm
        case $confirm in
        [Yy] | [Yy][Ee][Ss])
            break
            ;;
        [Nn] | [Nn][Oo])
            print_info "Installation cancelled by user"
            exit 0
            ;;
        *)
            print_error "Please answer with y/yes or n/no"
            ;;
        esac
    done

    print_success "Configuration confirmed!"
}

get_update_input() {
    print_step "3" "COLLECTING UPDATE DETAILS"

    while true; do
        print_color $BOLD$WHITE "🔑 Enter your DezerX license key:"
        read -r LICENSE_KEY
        if [[ -n "$LICENSE_KEY" && ${#LICENSE_KEY} -ge 10 ]]; then
            break
        else
            print_error "License key must be at least 10 characters. Please try again."
        fi
    done

    while true; do
        print_color $WHITE "🌐 Enter your domain (e.g., example.com or app.example.com):"
        print_color $WHITE "   ⚠️  Do NOT include http:// or https:// - just the domain name"
        read -r DOMAIN

        local validation_result
        validate_domain "$DOMAIN"
        validation_result=$?

        if [[ $validation_result -eq 2 ]]; then
            print_error "Please enter the domain WITHOUT http:// or https://"
            print_error "Example: Use 'example.com' instead of 'https://example.com'"
            continue
        elif [[ $validation_result -eq 1 ]]; then
            print_error "Invalid domain format. Please try again."
            continue
        else
            break
        fi
    done

    while true; do
        print_color $WHITE "🌐 Use HTTPS (recommended) or HTTP? [https/http, default: https]:"
        read -r protocol_choice
        if [[ -z "$protocol_choice" || "$protocol_choice" =~ ^[Hh][Tt][Tt][Pp][Ss]$ ]]; then
            PROTOCOL="https"
            break
        elif [[ "$protocol_choice" =~ ^[Hh][Tt][Tt][Pp]$ ]]; then
            PROTOCOL="http"
            break
        else
            print_error "Please enter 'https' or 'http'."
        fi
    done

    while true; do
        print_color $WHITE "📁 Enter your existing DezerX directory [default: /var/www/DezerX]:"
        read -r INSTALL_DIR
        if [[ -z "$INSTALL_DIR" ]]; then
            INSTALL_DIR="/var/www/DezerX"
        fi

        if [[ ! -d "$INSTALL_DIR" ]]; then
            print_error "Directory $INSTALL_DIR does not exist. Please check the path."
            continue
        fi

        if [[ ! -f "$INSTALL_DIR/.env" ]]; then
            print_error "No .env file found in $INSTALL_DIR. This doesn't appear to be a DezerX installation."
            continue
        fi

        if [[ ! -f "$INSTALL_DIR/artisan" ]]; then
            print_error "No artisan file found in $INSTALL_DIR. This doesn't appear to be a Laravel/DezerX installation."
            continue
        fi

        DB_FULL_NAME=$(get_env_variable "DB_DATABASE" "$INSTALL_DIR/.env")
        DB_USER_FULL=$(get_env_variable "DB_USERNAME" "$INSTALL_DIR/.env")
        DB_PASSWORD=$(get_env_variable "DB_PASSWORD" "$INSTALL_DIR/.env")

        if [[ -z "$DB_FULL_NAME" ]]; then
            DB_FULL_NAME="dezerx"
            print_warning "DB_DATABASE not found in .env, using default 'dezerx'"
        fi
        if [[ -z "$DB_USER_FULL" ]]; then
            DB_USER_FULL="dezer"
            print_warning "DB_USERNAME not found in .env, using default 'dezer'"
        fi
        # DB_PASSWORD can be empty if not set or if user wants to re-enter, handle accordingly

        break
    done

    print_success "Found existing DezerX installation at: $INSTALL_DIR"

    echo ""
    print_color $CYAN "📋 UPDATE SUMMARY:"
    print_info "License Key: ${LICENSE_KEY:0:8}***"
    print_info "Domain: $DOMAIN"
    print_info "Full URL: ${PROTOCOL}://$DOMAIN"
    print_info "Existing Directory: $INSTALL_DIR"
    echo ""

    while true; do
        print_color $WHITE "Continue with update? (y/n):"
        read -r confirm
        case $confirm in
        [Yy] | [Yy][Ee][Ss])
            break
            ;;
        [Nn] | [Nn][Oo])
            print_info "Update cancelled by user"
            exit 0
            ;;
        *)
            print_error "Please answer with y/yes or n/no"
            ;;
        esac
    done

    print_success "Update configuration confirmed!"
}

verify_license() {
    if [[ "$OPERATION_MODE" == "install" ]]; then
        print_step "4" "VERIFYING LICENSE"
    else
        print_step "4" "VERIFYING LICENSE" # Update also needs license verification
    fi

    print_info "Contacting DezerX license server..."

    local temp_file
    temp_file=$(mktemp)
    local http_code

    # Ensure curl uses a reasonable timeout
    http_code=$(curl -s -w "%{http_code}" -X POST \
        -H "Authorization: Bearer $LICENSE_KEY" \
        -H "domain: $DOMAIN" \
        -H "product: 1" \
        -H "Content-Type: application/json" \
        -o "$temp_file" \
        --connect-timeout 30 \
        --max-time 60 \
        https://market.dezerx.com/api/v1/verify)

    if [[ "$http_code" == "200" ]]; then
        print_success "License verified successfully!"
        rm -f "$temp_file"
        return 0
    else
        print_error "License verification failed (HTTP Code: $http_code)"
        if [[ -f "$temp_file" ]]; then
            local error_msg
            error_msg=$(cat "$temp_file" 2>/dev/null || echo "Unknown error from server")
            print_error "Server response: $error_msg"
            rm -f "$temp_file"
        fi
        print_error "Please check your license key and domain, then try again."
        exit 1
    fi
}

create_backup() {
    # This function is only relevant for update mode
    if [[ "$OPERATION_MODE" != "update" ]]; then
        return 0
    fi

    print_step "5" "CREATING BACKUP OF EXISTING INSTALLATION"

    BACKUP_DIR="/tmp/dezerx-backup-$(date +%Y%m%d-%H%M%S)"

    print_info "Backup location: $BACKUP_DIR"

    # Ensure INSTALL_DIR is set
    if [[ -z "$INSTALL_DIR" || ! -d "$INSTALL_DIR" ]]; then
        print_error "Installation directory '$INSTALL_DIR' not found or not set. Cannot create backup."
        exit 1
    fi

    execute_with_loading "cp -a \"$INSTALL_DIR\" \"$BACKUP_DIR\"" "Creating backup of $INSTALL_DIR"

    if [[ ! -f "$BACKUP_DIR/.env" ]]; then
        print_error "Backup verification failed - .env file not found in backup directory: $BACKUP_DIR"
        # Decide if this is fatal or a warning. For safety, let's make it fatal.
        exit 1
    fi

    print_success "Application files backup created successfully!"
    print_info "💾 Backup saved to: $BACKUP_DIR"
}

get_env_variable() {
    local var_name="$1"
    local env_file="$2"
    local value=""
    if [[ -f "$env_file" ]]; then
        # Read variable:
        # 1. Grep the line starting with VAR_NAME=
        # 2. Cut everything after the first '='
        # 3. Remove leading/trailing whitespace from the value.
        # 4. Remove surrounding quotes (single or double) if present.
        # 5. Remove inline comments (starting with a space then '#').
        # 6. Remove DOS carriage return.
        value=$(grep "^${var_name}=" "$env_file" | tail -n 1 | cut -d '=' -f 2- |
            sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' \
                -e 's/^"\(.*\)"$/\1/' -e "s/^'\(.*\)'$/\1/" \
                -e 's/[[:space:]]*#.*$//' -e 's/[[:space:]]*$//' \
                -e 's/\r$//')
    fi
    echo "$value"
}

backup_database() {
    if [[ "$OPERATION_MODE" != "update" ]]; then
        return 0
    fi

    print_step "5.1" "BACKING UP DATABASE"

    local env_file="$INSTALL_DIR/.env" # Use current INSTALL_DIR for .env

    if [[ ! -f "$env_file" ]]; then
        print_warning ".env file not found at $env_file. Skipping database backup."
        return 0
    fi

    local db_connection db_host db_port db_database db_username db_password_env
    db_connection=$(get_env_variable "DB_CONNECTION" "$env_file")
    db_host=$(get_env_variable "DB_HOST" "$env_file")
    db_port=$(get_env_variable "DB_PORT" "$env_file")
    db_database=$(get_env_variable "DB_DATABASE" "$env_file")     # This is DB_FULL_NAME
    db_username=$(get_env_variable "DB_USERNAME" "$env_file")     # This is DB_USER_FULL
    db_password_env=$(get_env_variable "DB_PASSWORD" "$env_file") # This is DB_PASSWORD

    if [[ "$db_connection" != "mysql" ]]; then
        print_warning "Database connection is not 'mysql' in .env (found: '$db_connection'). Skipping database backup."
        return 0
    fi

    if [[ -z "$db_host" || -z "$db_database" || -z "$db_username" ]]; then
        print_error "Missing critical database credentials (host, database, or username) in .env file. Cannot perform database backup."
        # This is critical, so we should probably exit or make it very clear.
        # For now, let's return 1 to indicate failure.
        return 1
    fi

    # Use existing BACKUP_DIR from create_backup()
    if [[ -z "$BACKUP_DIR" || ! -d "$BACKUP_DIR" ]]; then
        print_error "BACKUP_DIR '$BACKUP_DIR' not set or not a directory. create_backup() should run first."
        return 1
    fi

    DB_BACKUP_FILE="$BACKUP_DIR/database_$(date +%Y%m%d-%H%M%S).sql.gz"

    print_info "Backing up database '$db_database'..."
    print_info "Backup file: $DB_BACKUP_FILE"

    local port_arg=""
    if [[ -n "$db_port" ]]; then
        port_arg="--port=$db_port"
    fi

    # Temporarily set MYSQL_PWD for mysqldump
    export MYSQL_PWD="$db_password_env"
    local mysqldump_cmd="mysqldump --host=$db_host $port_arg --user=$db_username $db_database | gzip > \"$DB_BACKUP_FILE\""

    if ! command -v mysqldump &>/dev/null; then
        print_error "mysqldump command not found. Cannot perform database backup."
        unset MYSQL_PWD
        return 1
    fi

    # Use execute_with_loading for this potentially long operation
    execute_with_loading "$mysqldump_cmd" "Creating database backup"
    local dump_exit_code=$? # Get exit code from execute_with_loading's wait
    unset MYSQL_PWD         # Always unset password

    if [ $dump_exit_code -ne 0 ]; then
        print_error "Database backup failed! (mysqldump exit code: $dump_exit_code)"
        rm -f "$DB_BACKUP_FILE" # Clean up failed backup file
        return 1
    fi

    if [[ ! -s "$DB_BACKUP_FILE" ]]; then # Check if file exists and is not empty
        print_error "Database backup file is empty or was not created: $DB_BACKUP_FILE"
        return 1
    fi

    print_success "Database backup completed successfully!"
    print_info "Database backup saved to: $DB_BACKUP_FILE"
    return 0
}

restore_database() {
    if [[ "$OPERATION_MODE" != "update" || "$RESTORE_ON_FAILURE" != "yes" ]]; then
        return 0
    fi

    print_info "Attempting to restore database from backup..."

    if [[ -z "$DB_BACKUP_FILE" || ! -f "$DB_BACKUP_FILE" ]]; then
        print_warning "No database backup file found ($DB_BACKUP_FILE) or specified. Skipping database restore."
        return 1
    fi

    local env_file="$INSTALL_DIR/.env" # Use INSTALL_DIR which should now point to the restored app files
    if [[ ! -f "$env_file" ]]; then
        # If .env is not in restored app files, try backup dir .env
        env_file="$BACKUP_DIR/.env"
    fi

    if [[ ! -f "$env_file" ]]; then
        print_error ".env file not found in $INSTALL_DIR or $BACKUP_DIR. Cannot determine database credentials for restore."
        return 1
    fi

    local db_host db_port db_database db_username db_password_env
    db_host=$(get_env_variable "DB_HOST" "$env_file")
    db_port=$(get_env_variable "DB_PORT" "$env_file")
    db_database=$(get_env_variable "DB_DATABASE" "$env_file")
    db_username=$(get_env_variable "DB_USERNAME" "$env_file")
    db_password_env=$(get_env_variable "DB_PASSWORD" "$env_file")

    if [[ -z "$db_host" || -z "$db_database" || -z "$db_username" ]]; then
        print_error "Missing database credentials in .env. Cannot restore database."
        return 1
    fi

    print_info "Restoring database '$db_database' from $DB_BACKUP_FILE..."

    local port_arg=""
    if [[ -n "$db_port" ]]; then
        port_arg="--port=$db_port"
    fi

    export MYSQL_PWD="$db_password_env"
    # Drop and recreate database before import to ensure clean state
    mariadb --host="$db_host" $port_arg --user="$db_username" -e "DROP DATABASE IF EXISTS \`$db_database\`; CREATE DATABASE \`$db_database\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;" >>"$LOG_FILE" 2>&1

    local restore_cmd="gunzip < \"$DB_BACKUP_FILE\" | mariadb --host=$db_host $port_arg --user=$db_username $db_database"

    execute_with_loading "$restore_cmd" "Restoring database content"
    local restore_exit_code=$?
    unset MYSQL_PWD

    if [ $restore_exit_code -ne 0 ]; then
        print_error "Database restore failed! (Exit code: $restore_exit_code)"
        return 1
    fi

    print_success "Database restored successfully from $DB_BACKUP_FILE."
    return 0
}

restore_backup() {
    # This function is only relevant for update mode if RESTORE_ON_FAILURE is yes
    if [[ "$OPERATION_MODE" != "update" || "$RESTORE_ON_FAILURE" != "yes" ]]; then
        return 0
    fi

    print_error "Attempting to restore application files from backup due to failure..."

    if [[ -n "$BACKUP_DIR" && -d "$BACKUP_DIR" ]]; then
        print_info "Removing potentially failed/incomplete update files from $INSTALL_DIR..."
        rm -rf "$INSTALL_DIR"/* "$INSTALL_DIR"/.[^.]* 2>/dev/null || true # Clean target
        mkdir -p "$INSTALL_DIR"                                           # Ensure target dir exists

        print_info "Restoring application files from backup: $BACKUP_DIR to $INSTALL_DIR"
        # Use cp -a for preserving attributes, then rsync for safety if cp fails partially
        if cp -a "$BACKUP_DIR"/* "$INSTALL_DIR"/ && cp -a "$BACKUP_DIR"/.[^.]* "$INSTALL_DIR"/ 2>/dev/null; then
            : # cp successful
        else
            # Fallback to rsync if cp had issues (e.g. with hidden files)
            rsync -a --delete "$BACKUP_DIR/" "$INSTALL_DIR/" >>"$LOG_FILE" 2>&1
        fi

        print_info "Setting proper permissions after file restore..."
        # Ensure www-data exists or use a fallback if necessary (though www-data is standard on Debian for Nginx/Apache)
        if id "www-data" &>/dev/null; then
            chown -R www-data:www-data "$INSTALL_DIR" >>"$LOG_FILE" 2>&1
        else
            print_warning "User www-data not found. Skipping chown for restored files."
        fi
        chmod -R 755 "$INSTALL_DIR" >>"$LOG_FILE" 2>&1
        chmod -R 775 "$INSTALL_DIR/storage" 2>/dev/null || true
        chmod -R 775 "$INSTALL_DIR/bootstrap/cache" 2>/dev/null || true

        print_success "Application files backup restored successfully to $INSTALL_DIR!"
        print_info "Your original application files should be restored."
    else
        print_error "No backup directory found ($BACKUP_DIR) or it's not a directory. Cannot restore application files."
        return 1 # Indicate failure
    fi
    return 0
}

install_dependencies() {
    print_step "5" "INSTALLING SYSTEM DEPENDENCIES" # Step number consistent for install

    execute_with_loading "apt-get update -qq" "Updating package lists"
    execute_with_loading "DEBIAN_FRONTEND=noninteractive apt-get upgrade -y -qq" "Upgrading system packages"

    local base_packages="software-properties-common curl apt-transport-https ca-certificates gnupg lsb-release wget unzip git cron"
    execute_with_loading "DEBIAN_FRONTEND=noninteractive apt-get install -y -qq $base_packages" "Installing basic dependencies"

    print_info "Adding PHP repository (ppa:ondrej/php for up-to-date versions)..."
    # Ensure software-properties-common is installed before trying to add PPA
    if ! command -v add-apt-repository &>/dev/null; then
        execute_with_loading "DEBIAN_FRONTEND=noninteractive apt-get install -y -qq software-properties-common" "Installing software-properties-common"
    fi

    # LC_ALL=C.UTF-8 is good practice for locale issues with add-apt-repository
    if ! LC_ALL=C.UTF-8 add-apt-repository -y ppa:ondrej/php >>"$LOG_FILE" 2>&1; then
        print_warning "Failed to add PHP PPA (ppa:ondrej/php). PHP installation might use older versions from default Debian repos or fail."
        # Consider alternative: DEB.SURY.ORG direct method if PPA fails
        print_info "Attempting to add PHP repository using deb.sury.org direct method..."
        if ! (curl -sSLo /usr/share/keyrings/deb.sury.org-php.gpg https://packages.sury.org/php/apt.gpg &&
            echo "deb [signed-by=/usr/share/keyrings/deb.sury.org-php.gpg] https://packages.sury.org/php/ $(lsb_release -sc) main" >/etc/apt/sources.list.d/php.list &&
            apt-get update -qq); then
            print_error "Failed to add PHP repository using alternative method as well. PHP installation may fail."
        else
            print_success "Successfully added PHP repository using deb.sury.org direct method."
        fi
    else
        print_success "PHP PPA added successfully."
    fi

    print_info "Adding Redis repository..."
    # Add --yes to gpg to auto-overwrite if the key file exists
    curl -fsSL https://packages.redis.io/gpg | gpg --yes --dearmor -o /usr/share/keyrings/redis-archive-keyring.gpg >>"$LOG_FILE" 2>&1
    echo "deb [signed-by=/usr/share/keyrings/redis-archive-keyring.gpg] https://packages.redis.io/deb $(lsb_release -cs) main" >/etc/apt/sources.list.d/redis.list

    print_info "Adding MariaDB repository..."
    # The mariadb_repo_setup script is generally robust.
    if ! curl -LsS https://r.mariadb.com/downloads/mariadb_repo_setup | bash >>"$LOG_FILE" 2>&1; then
        print_warning "Failed to add MariaDB repository using script. MariaDB installation might use older versions or fail."
    else
        print_success "MariaDB repository added successfully."
    fi

    execute_with_loading "apt-get update -qq" "Updating package lists with new repositories"

    local php_version="8.3" # Define PHP version
    local app_packages="nginx php${php_version} php${php_version}-common php${php_version}-cli php${php_version}-gd php${php_version}-mysql php${php_version}-mbstring php${php_version}-bcmath php${php_version}-xml php${php_version}-fpm php${php_version}-curl php${php_version}-zip mariadb-server mariadb-client tar unzip git redis-server nftables"

    execute_with_loading "DEBIAN_FRONTEND=noninteractive apt-get install -y -qq $app_packages" "Installing PHP, MariaDB, Nginx, and other dependencies"

    execute_with_loading "systemctl start nginx && systemctl enable nginx" "Starting and enabling Nginx"
    execute_with_loading "systemctl start php${php_version}-fpm && systemctl enable php${php_version}-fpm" "Starting and enabling PHP-FPM service"
    execute_with_loading "systemctl start redis-server && systemctl enable redis-server" "Starting and enabling Redis service"
    execute_with_loading "systemctl start cron && systemctl enable cron" "Starting and enabling Cron service"
    execute_with_loading "systemctl stop nftables && systemctl disable nftables" "Stoping and Disableing nftables service"

    # UFW is handled later in prompt_ufw_firewall, ensure it's not prematurely blocking if already active.
    # If UFW is active and enabled, new rules for HTTP/S will be added. If not, user is prompted.
    # No need to stop/disable it here unless there's a specific reason.

    execute_with_loading "mkdir -p /var/www" "Creating /var/www directory if it doesn't exist"

    print_success "System dependencies installed successfully!"
}

install_composer() {
    print_step "6" "INSTALLING COMPOSER" # Step number consistent for install

    local composer_installer="/tmp/composer-installer.php"

    execute_with_loading "curl -sS https://getcomposer.org/installer -o $composer_installer" "Downloading Composer installer"
    # Install Composer globally
    execute_with_loading "php $composer_installer --install-dir=/usr/local/bin --filename=composer" "Installing Composer to /usr/local/bin"

    rm -f "$composer_installer" # Clean up installer script

    if ! command -v composer &>/dev/null; then
        print_error "Composer installation failed. 'composer' command not found."
        exit 1
    fi

    print_success "Composer installed successfully!"
}

setup_database() {
    print_step "7" "SETTING UP DATABASE" # Step number consistent for install

    execute_with_loading "systemctl start mariadb && systemctl enable mariadb" "Starting and enabling MariaDB service"

    # DB_PASSWORD should be set from get_install_input or generated if empty
    if [[ -z "$DB_PASSWORD" ]]; then
        DB_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/\\\\" | cut -c1-25)
        print_info "Generated a new secure password for the database user."
    fi

    # DB_FULL_NAME and DB_USER_FULL should be set from get_install_input
    if [[ -z "$DB_FULL_NAME" || -z "$DB_USER_FULL" ]]; then
        print_error "Database name or user is not set. Cannot proceed with database setup."
        exit 1
    fi

    print_info "Securing MariaDB installation and creating database/user..."
    print_info "Database: $DB_FULL_NAME, User: $DB_USER_FULL"

    # Use a heredoc for the SQL commands for clarity
    local sql_commands
    sql_commands=$(
        cat <<EOF
-- Secure installation (equivalent of parts of mysql_secure_installation)
-- Remove anonymous users
DELETE FROM mysql.global_priv WHERE User='';
-- Disallow root login remotely
DELETE FROM mysql.global_priv WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
-- Remove test database
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';

-- Create the dedicated database for the application
CREATE DATABASE IF NOT EXISTS \`$DB_FULL_NAME\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- Create the dedicated user for the application (for both localhost and 127.0.0.1)
CREATE USER IF NOT EXISTS '$DB_USER_FULL'@'127.0.0.1' IDENTIFIED BY '$DB_PASSWORD';
CREATE USER IF NOT EXISTS '$DB_USER_FULL'@'localhost' IDENTIFIED BY '$DB_PASSWORD';

-- Grant all privileges on the application database to the user
GRANT ALL PRIVILEGES ON \`$DB_FULL_NAME\`.* TO '$DB_USER_FULL'@'127.0.0.1';
GRANT ALL PRIVILEGES ON \`$DB_FULL_NAME\`.* TO '$DB_USER_FULL'@'localhost';

-- Apply all privilege changes
FLUSH PRIVILEGES;
EOF
    )
    # Execute SQL commands
    if ! echo "$sql_commands" | mariadb >>"$LOG_FILE" 2>&1; then
        print_error "Failed to execute MariaDB setup commands. Check $LOG_FILE for details."
        exit 1
    fi

    print_success "Database setup completed successfully!"
    print_info "Database: $DB_FULL_NAME"
    print_info "Username: $DB_USER_FULL"
    print_info "Password: [Set or Generated Securely]"
}

download_dezerx() {
    if [[ "$OPERATION_MODE" == "install" ]]; then
        print_step "8" "DOWNLOADING DEZERX APPLICATION FILES"
    else # update
        print_step "6" "DOWNLOADING DEZERX UPDATE FILES"
    fi

    print_info "Requesting download URL from DezerX servers..."

    local temp_file
    temp_file=$(mktemp)
    local http_code

    http_code=$(curl -s -w "%{http_code}" -X POST \
        -H "Authorization: Bearer $LICENSE_KEY" \
        -H "domain: $DOMAIN" \
        -H "product: 1" \
        -H "Content-Type: application/json" \
        -o "$temp_file" \
        --connect-timeout 30 \
        --max-time 60 \
        https://market.dezerx.com/api/v1/download)

    if [[ "$http_code" != "200" ]]; then
        print_error "Failed to get download URL (HTTP Code: $http_code)"
        if [[ -f "$temp_file" ]]; then
            local error_msg
            error_msg=$(cat "$temp_file" 2>/dev/null || echo "Unknown error from server")
            print_error "Server response: $error_msg"
        fi
        rm -f "$temp_file"
        if [[ "$OPERATION_MODE" == "update" && "$RESTORE_ON_FAILURE" == "yes" ]]; then
            restore_backup
            restore_database
        fi
        exit 1
    fi

    local download_url
    # Try jq first, then fallback to grep/cut for robustness
    if command -v jq &>/dev/null; then
        download_url=$(jq -r '.download_url' "$temp_file" 2>/dev/null)
    else
        download_url=$(grep -o '"download_url":"[^"]*' "$temp_file" | cut -d'"' -f4 | sed 's/\\//g') # Basic parsing
    fi
    rm -f "$temp_file"

    if [[ -z "$download_url" || "$download_url" == "null" ]]; then
        print_error "Failed to extract download URL from server response."
        if [[ "$OPERATION_MODE" == "update" && "$RESTORE_ON_FAILURE" == "yes" ]]; then
            restore_backup
            restore_database
        fi
        exit 1
    fi

    if [[ "$OPERATION_MODE" == "install" ]]; then
        print_info "Creating installation directory: $INSTALL_DIR"
        mkdir -p "$INSTALL_DIR" # Ensure directory exists
    fi

    print_info "Downloading DezerX package from secured URL..."
    local download_file="/tmp/dezerx-package-$(date +%s).zip"

    # Use curl with progress bar for better UX
    if ! curl -L -o "$download_file" --progress-bar --connect-timeout 30 --max-time 300 "$download_url"; then
        print_error "Download failed. Check network connection and URL."
        rm -f "$download_file"
        if [[ "$OPERATION_MODE" == "update" && "$RESTORE_ON_FAILURE" == "yes" ]]; then
            restore_backup
            restore_database
        fi
        exit 1
    fi
    echo # Newline after progress bar

    print_success "Download completed successfully: $download_file"

    print_info "Extracting files to a temporary location..."
    local temp_extract_dir
    temp_extract_dir=$(mktemp -d /tmp/dezerx-extract.XXXXXX)

    if ! unzip -q "$download_file" -d "$temp_extract_dir"; then
        print_error "Failed to extract files from $download_file to $temp_extract_dir."
        rm -f "$download_file"
        rm -rf "$temp_extract_dir"
        if [[ "$OPERATION_MODE" == "update" && "$RESTORE_ON_FAILURE" == "yes" ]]; then
            restore_backup
            restore_database
        fi
        exit 1
    fi
    rm -f "$download_file" # Clean up downloaded zip

    print_info "Locating DezerX application files within extracted archive..."
    # Common pattern: archive might contain a single root folder like 'DezerX-version' or 'dist'
    local dezerx_source_dir="$temp_extract_dir" # Default to root of extraction

    # Try to find a directory with .env.example or artisan to be more specific
    local found_artisan_dir
    found_artisan_dir=$(find "$temp_extract_dir" -maxdepth 2 -name "artisan" -printf "%h\n" | head -n 1)

    if [[ -n "$found_artisan_dir" && -d "$found_artisan_dir" ]]; then
        dezerx_source_dir="$found_artisan_dir"
        print_info "Found application files in subdirectory: $(basename "$dezerx_source_dir")"
    else
        print_info "Using root of extracted archive as source."
    fi

    if [[ ! -f "$dezerx_source_dir/.env.example" && ! -f "$dezerx_source_dir/artisan" ]]; then
        print_error "Invalid DezerX package - .env.example or artisan not found in '$dezerx_source_dir'."
        ls -la "$dezerx_source_dir" # List contents for debugging
        rm -rf "$temp_extract_dir"
        if [[ "$OPERATION_MODE" == "update" && "$RESTORE_ON_FAILURE" == "yes" ]]; then
            restore_backup
            restore_database
        fi
        exit 1
    fi

    print_info "Moving DezerX files to installation directory: $INSTALL_DIR"
    # For install, clear directory first. For update, rsync will overwrite.
    if [[ "$OPERATION_MODE" == "install" ]]; then
        rm -rf "$INSTALL_DIR"/* "$INSTALL_DIR"/.[^.]* 2>/dev/null # Clean existing content
        mkdir -p "$INSTALL_DIR"                                   # Ensure it exists
    fi

    # Use rsync for robust copy, handling existing files correctly for updates
    # Exclude .env for updates to preserve existing settings, it will be synced later
    local rsync_exclude_opts=""
    if [[ "$OPERATION_MODE" == "update" ]]; then
        rsync_exclude_opts="--exclude '.env'"
    fi

    if ! rsync -a $rsync_exclude_opts "$dezerx_source_dir/" "$INSTALL_DIR/"; then
        print_error "Failed to move/copy DezerX files to $INSTALL_DIR."
        rm -rf "$temp_extract_dir"
        if [[ "$OPERATION_MODE" == "update" && "$RESTORE_ON_FAILURE" == "yes" ]]; then
            restore_backup
            restore_database
        fi
        exit 1
    fi

    print_info "Setting initial ownership and permissions for $INSTALL_DIR to allow www-data operations..."
    if id "www-data" &>/dev/null; then
        # Change ownership of the entire installation directory to www-data
        chown -R www-data:www-data "$INSTALL_DIR" >>"$LOG_FILE" 2>&1
        # Ensure the www-data user (now owner) can write to the top-level $INSTALL_DIR
        # This allows composer to create the vendor/ directory inside $INSTALL_DIR.
        # set_permissions will refine permissions for subdirectories and files later.
        chmod u+rwx "$INSTALL_DIR" >>"$LOG_FILE" 2>&1
    else
        print_warning "User www-data not found. Skipping initial chown/chmod for $INSTALL_DIR. Composer may fail."
    fi

    rm -rf "$temp_extract_dir" # Clean up temporary extraction directory

    if [[ "$OPERATION_MODE" == "install" && ! -f "$INSTALL_DIR/.env.example" ]]; then
        print_error "DezerX files not properly moved - .env.example not found in $INSTALL_DIR."
        ls -la "$INSTALL_DIR" # List contents for debugging
        exit 1
    fi

    print_success "DezerX files extracted and organized successfully!"
    print_info "Application directory: $INSTALL_DIR"
}

update_env_file() {
    local key_to_update="$1"
    local value_to_set="$2"
    local target_env_file="$3"
    local backup_file_path

    if [[ ! -f "$target_env_file" ]]; then
        print_error "Cannot update .env: File not found at $target_env_file"
        return 1
    fi

    backup_file_path="${target_env_file}.bak-$(date +%s)-${key_to_update}"
    cp "$target_env_file" "$backup_file_path"

    # Ensure .env ends with a newline
    if [[ $(
        tail -c1 "$target_env_file"
        echo x
    ) != $'\nx' ]]; then
        echo >>"$target_env_file"
    fi

    # Remove all lines for the key, then add the new value
    sed -i -E "/^${key_to_update}=.*$/d" "$target_env_file"
    echo "${key_to_update}=${value_to_set}" >>"$target_env_file"
    log_message "Set ${key_to_update} in $target_env_file"

    # Verify change by reading the value back using get_env_variable
    local current_value
    current_value=$(get_env_variable "$key_to_update" "$target_env_file")

    log_message "DEBUG: update_env_file verification for key '$key_to_update'"
    log_message "DEBUG: value_to_set (raw): [$value_to_set]"
    log_message "DEBUG: current_value (from get_env_variable): [$current_value]"

    if [[ "$current_value" == "$value_to_set" ]]; then
        print_info "Successfully updated/added '$key_to_update' in $target_env_file."
        rm -f "$backup_file_path"
        return 0
    else
        print_error "Failed to verify update for '$key_to_update' in $target_env_file."
        print_error "Expected: '$value_to_set', Got: '$current_value'"
        if [[ "$RESTORE_ON_FAILURE" == "yes" ]]; then
            if [[ -f "$backup_file_path" ]]; then
                mv "$backup_file_path" "$target_env_file"
                print_info "Restored $target_env_file from local backup $backup_file_path (due to failed verification for '$key_to_update')."
            else
                print_error "Local backup file $backup_file_path not found. Cannot restore $target_env_file for this key."
            fi
        else
            print_warning "Local .env update verification failed for '$key_to_update'."
            print_warning "Automatic restore of this specific change is disabled by user preference (RESTORE_ON_FAILURE=no)."
            print_warning "The .env file may be in an inconsistent state for this key. The local backup is at $backup_file_path."
        fi
        return 1
    fi
}

sync_env_files() {
    local current_install_dir="$1" # Renamed
    local example_env="$current_install_dir/.env.example"
    local live_env="$current_install_dir/.env"

    if [[ ! -f "$example_env" ]]; then
        print_warning ".env.example not found in $current_install_dir. Cannot sync .env."
        return 0 # Not fatal, but a warning
    fi

    if [[ ! -f "$live_env" ]]; then
        print_warning ".env not found in $current_install_dir. This is unusual for an update. Skipping .env sync."
        # If it's an install, .env is copied from .env.example, so this sync is less critical.
        # If it's an update and .env is missing, that's a bigger problem.
        return 0
    fi

    print_info "Synchronizing $live_env with $example_env..."

    # Ensure .env ends with a newline for robust parsing/appending
    if [[ $(
        tail -c1 "$live_env"
        echo x
    ) != $'\nx' ]]; then
        echo >>"$live_env"
        print_info "Added trailing newline to $live_env."
    fi

    local added_vars_count=0
    # Read .env.example line by line
    # IFS= prevents stripping leading/trailing whitespace from lines
    # -r prevents backslash escapes from being interpreted
    while IFS= read -r line || [[ -n "$line" ]]; do
        # Skip comments and empty lines
        if [[ "$line" =~ ^\s*# || -z "$line" ]]; then
            continue
        fi

        # Extract key from "KEY=VALUE" format
        local key_from_example
        key_from_example=$(echo "$line" | cut -d'=' -f1)

        if [[ -n "$key_from_example" ]]; then
            # Check if key exists in the live .env file (match whole line beginning with KEY=)
            if ! grep -q "^${key_from_example}=" "$live_env"; then
                # Key does not exist in live .env, so append the whole line from .env.example
                printf "%s\n" "$line" >>"$live_env"
                print_info "Added missing variable '$key_from_example' from .env.example to .env."
                added_vars_count=$((added_vars_count + 1))
            fi
        fi
    done <"$example_env"

    if [[ $added_vars_count -gt 0 ]]; then
        print_success "Synchronization complete. $added_vars_count new variable(s) added to .env."
    else
        print_info ".env is already up-to-date with .env.example (no new variables found to add)."
    fi

    # Ensure correct permissions for .env
    if id "www-data" &>/dev/null; then
        chown www-data:www-data "$live_env" >>"$LOG_FILE" 2>&1
    fi
    chmod 640 "$live_env" >>"$LOG_FILE" 2>&1 # More secure permission

    print_success ".env synchronization check finished."
}

configure_laravel() {
    if [[ "$OPERATION_MODE" == "install" ]]; then
        print_step "9" "CONFIGURING LARAVEL APPLICATION"
    else # update
        print_step "7" "UPDATING LARAVEL CONFIGURATION"
    fi

    cd "$INSTALL_DIR" || {
        print_error "Failed to change directory to $INSTALL_DIR"
        exit 1
    }

    if [[ "$OPERATION_MODE" == "install" ]]; then
        if [[ ! -f ".env.example" ]]; then
            print_error ".env.example file not found in $INSTALL_DIR. Download might have failed."
            ls -la "$INSTALL_DIR" # List contents for debugging
            exit 1
        fi
        execute_with_loading "cp .env.example .env" "Copying .env.example to .env"
        # Ensure .env is writable by www-data before artisan commands modify it
        if id "www-data" &>/dev/null; then
            execute_with_loading "chown www-data:www-data .env" "Setting .env ownership to www-data"
            # Give www-data (owner) write permission. Group www-data also gets write. Others read.
            execute_with_loading "chmod 664 .env" "Setting .env permissions for www-data write"
        else
            print_warning "User www-data not found. .env permissions might be incorrect for artisan commands."
            # If www-data doesn't exist, execute_as_www_data might run commands as root if sudo isn't present.
            # In that case, root can write to the root-owned .env file.
        fi
    else # update
        if [[ ! -f ".env" ]]; then
            print_error ".env file not found in $INSTALL_DIR for update. This is critical."
            if [[ "$RESTORE_ON_FAILURE" == "yes" ]]; then
                restore_backup
                restore_database
            fi
            exit 1
        fi
        print_info "Using existing .env configuration for update. Will sync with .env.example."
        # Sync .env with .env.example *before* composer install for updates
        sync_env_files "$INSTALL_DIR" # This function also handles .env permissions
    fi

    print_info "Installing/Updating Composer dependencies (can take a few minutes)..."
    # --no-interaction for non-interactive, --no-dev for production, --prefer-dist for speed
    local composer_command="composer install --no-interaction --no-dev --optimize-autoloader --prefer-dist"

    execute_as_www_data "$composer_command" "Installing Composer dependencies"
    local composer_exit_code=$?
    if [ $composer_exit_code -ne 0 ]; then
        print_error "Composer dependencies installation failed with exit code $composer_exit_code."
        return $composer_exit_code # Propagate error
    fi

    print_success "Composer dependencies installed/updated successfully!"
    print_info "Continuing with Laravel configuration..."

    execute_as_www_data "php artisan storage:link" "Linking storage directory"
    # No need to check exit code for storage:link usually, but can be added if problematic.

    if [[ "$OPERATION_MODE" == "install" ]]; then
        execute_as_www_data "php artisan key:generate --force" "Generating application key"
        local key_gen_exit_code=$?
        if [ $key_gen_exit_code -ne 0 ]; then
            print_error "php artisan key:generate failed with exit code $key_gen_exit_code. Check .env permissions."
            # This is critical for an install.
            return $key_gen_exit_code
        fi

        print_info "Updating .env file with installation details..."
        update_env_file "APP_NAME" "DezerX" ".env"
        update_env_file "APP_ENV" "production" ".env"
        update_env_file "APP_DEBUG" "false" ".env"
        update_env_file "APP_URL" "${PROTOCOL}://$DOMAIN" ".env"

        update_env_file "LOG_CHANNEL" "stack" ".env"
        update_env_file "LOG_LEVEL" "error" ".env" # Production logging

        update_env_file "DB_CONNECTION" "mysql" ".env"
        update_env_file "DB_HOST" "127.0.0.1" ".env"
        update_env_file "DB_PORT" "3306" ".env"
        update_env_file "DB_DATABASE" "$DB_FULL_NAME" ".env"
        update_env_file "DB_USERNAME" "$DB_USER_FULL" ".env"
        update_env_file "DB_PASSWORD" "$DB_PASSWORD" ".env" # Ensure DB_PASSWORD is quoted if it contains special chars

        update_env_file "BROADCAST_DRIVER" "log" ".env"      # Default, can be changed to redis
        update_env_file "CACHE_DRIVER" "file" ".env"         # Default, can be changed to redis
        update_env_file "QUEUE_CONNECTION" "database" ".env" # Default, can be changed to redis
        update_env_file "SESSION_DRIVER" "file" ".env"       # Default, can be changed to redis
        update_env_file "SESSION_LIFETIME" "120" ".env"

        update_env_file "REDIS_HOST" "127.0.0.1" ".env"
        update_env_file "REDIS_PASSWORD" "null" ".env"
        update_env_file "REDIS_PORT" "6379" ".env"

        update_env_file "KEY" "$LICENSE_KEY" ".env" # Custom DezerX license key field

        print_success "Laravel .env configuration updated for installation."
    else # update
        # For updates, primarily ensure APP_URL and DezerX KEY are correct.
        # Other critical settings like DB connection should be preserved from existing .env
        update_env_file "APP_URL" "${PROTOCOL}://$DOMAIN" ".env"
        update_env_file "KEY" "$LICENSE_KEY" ".env"
        print_success "Laravel .env configuration checked/updated for update (APP_URL, KEY)."
    fi

    print_info "Optimizing Laravel application..."
    execute_as_www_data "php artisan config:cache" "Caching configuration"
    # execute_as_www_data "php artisan route:cache" "Caching routes"
    execute_as_www_data "php artisan view:cache" "Caching views"
    # execute_as_www_data "php artisan event:cache" "Caching events" # If using event discovery

    print_success "Laravel configuration phase completed successfully!"
}

check_dns() {
    print_step "10" "DNS VERIFICATION" # Step number consistent for install

    local server_ip
    # Try multiple methods to get public IP
    server_ip=$(curl -s --connect-timeout 5 https://ifconfig.me || curl -s --connect-timeout 5 https://api.ipify.org || curl -s --connect-timeout 5 https://ipinfo.io/ip || echo "Unable to detect server IP automatically")

    if [[ "$server_ip" == "Unable to detect server IP automatically" ]]; then
        print_warning "Could not automatically detect the server's public IP address."
        print_color $WHITE "Please manually enter this server's public IP address:"
        read -r server_ip
        if [[ -z "$server_ip" ]]; then
            print_error "No IP address entered. DNS check cannot proceed effectively."
            # Optionally, allow to skip or exit
            return 1 # Indicate failure or inability to check
        fi
    fi

    print_info "This Server's Public IP Address: $server_ip"
    print_info "Domain to configure: $DOMAIN"
    print_info "Attempting to resolve $DOMAIN..."

    local resolved_ip
    # Use `getent hosts` or `dig` if available, fallback to `nslookup`
    if command -v dig &>/dev/null; then
        resolved_ip=$(dig +short "$DOMAIN" A | tail -n1)
    elif command -v getent &>/dev/null; then
        resolved_ip=$(getent hosts "$DOMAIN" | awk '{print $1}' | head -n1)
    elif command -v nslookup &>/dev/null; then
        resolved_ip=$(nslookup "$DOMAIN" | awk '/^Address: / { print $2 }' | tail -n1)
    else
        print_warning "DNS lookup tools (dig, getent, nslookup) not found. Cannot automatically verify DNS."
        resolved_ip="unknown"
    fi

    if [[ "$resolved_ip" == "$server_ip" ]]; then
        print_success "DNS check successful! $DOMAIN resolves to $server_ip."
        return 0
    elif [[ "$resolved_ip" == "unknown" ]]; then
        print_warning "Could not automatically verify DNS."
    else
        print_warning "$DOMAIN currently resolves to $resolved_ip, which does not match this server's IP $server_ip."
    fi

    while true; do
        print_color $WHITE "🌐 Have you pointed an A record for '$DOMAIN' to this server's IP ($server_ip)? (y/n):"
        read -r dns_response
        case $dns_response in
        [Yy] | [Yy][Ee][Ss] | [Yy][Ee])
            print_success "DNS configuration acknowledged by user."
            break
            ;;
        [Nn] | [Nn][Oo])
            print_warning "Please configure your DNS settings:"
            print_info "1. Log into your domain registrar or DNS provider."
            print_info "2. Create or update an A record for '$DOMAIN' to point to '$server_ip'."
            print_info "3. Wait for DNS propagation (can take from minutes to hours)."
            print_color $WHITE "Press Enter to acknowledge and continue, or Ctrl+C to abort and fix DNS first."
            read -r
            break # Continue after user acknowledgement
            ;;
        *)
            print_error "Please answer with y/yes or n/no."
            ;;
        esac
    done
    return 0
}

configure_firewall() {
    print_step "11" "FIREWALL CONFIGURATION (nftables)"

    if ! command -v nft &>/dev/null; then
        print_warning "nftables is not installed. Skipping firewall configuration."
        print_info "You may need to configure your firewall manually if one is active."
        return
    fi

    print_color $WHITE "Would you like to configure the firewall (nftables) to allow HTTP (port 80) and HTTPS (port 443) traffic? (y/n):"
    read -r nft_choice
    case "$nft_choice" in
    [Yy] | [Yy][Ee][Ss])
        print_info "Configuring nftables..."

        # Create a basic filter table and input chain if not present
        nft list table inet filter >/dev/null 2>&1 || nft add table inet filter
        nft list chain inet filter input >/dev/null 2>&1 || nft add chain inet filter input { type filter hook input priority 0 \; policy accept \; }

        # Allow SSH, HTTP, and HTTPS
        nft add rule inet filter input tcp dport 22 accept 2>/dev/null || true
        nft add rule inet filter input tcp dport 80 accept 2>/dev/null || true
        nft add rule inet filter input tcp dport 443 accept 2>/dev/null || true

        print_success "nftables rules added for SSH (22), HTTP (80), and HTTPS (443)."

        # Ensure nftables is enabled and started
        execute_with_loading "systemctl enable nftables" "Enabling nftables service"
        execute_with_loading "systemctl start nftables" "Starting nftables service"

        print_info "Current nftables rules:"
        nft list ruleset
        ;;
    *)
        print_warning "Skipped automatic nftables configuration for HTTP/HTTPS ports."
        print_info "Ensure ports 80 and 443 (and 22 for SSH) are open in your firewall if nftables is active or if you use another firewall."
        print_color $WHITE "Would you like to enable and start nftables service anyway? (y/n):"
        read -r enable_choice
        case "$enable_choice" in
            [Yy] | [Yy][Ee][Ss])
                execute_with_loading "systemctl enable nftables" "Enabling nftables service"
                execute_with_loading "systemctl start nftables" "Starting nftables service"
                print_success "nftables service enabled and started."
                ;;
            *)
                print_info "nftables service was not enabled or started."
                ;;
        esac
        ;;
    esac
}

setup_ssl() {
    # This function is called only if PROTOCOL is "https"
    print_step "12" "SETTING UP SSL CERTIFICATE (Let's Encrypt with Certbot)" # Step consistent for install

    if ! command -v certbot &>/dev/null; then
        print_info "Certbot not found. Installing Certbot..."
        # Install certbot and the nginx plugin
        execute_with_loading "apt-get install -y -qq certbot python3-certbot-nginx" "Installing Certbot and Nginx plugin"
        if ! command -v certbot &>/dev/null; then
            print_error "Certbot installation failed. Cannot proceed with SSL setup."
            print_info "You may need to configure SSL manually or re-run the script after installing Certbot."
            return 1 # Indicate failure
        fi
    fi

    print_info "Obtaining SSL certificate for $DOMAIN using Certbot with Nginx plugin..."
    print_warning "Ensure your Nginx configuration for $DOMAIN (port 80) is temporarily active for the challenge."

    # Create a temporary Nginx config for HTTP challenge if no config exists or to ensure it's clean
    # This is safer than relying on an existing complex config during initial cert issuance.
    local temp_nginx_conf_path="/etc/nginx/sites-available/temp-certbot-$DOMAIN.conf"
    local temp_nginx_symlink="/etc/nginx/sites-enabled/temp-certbot-$DOMAIN.conf"

    cat >"$temp_nginx_conf_path" <<EOF
server {
    listen 80;
    server_name $DOMAIN;
    root /var/www/html; # A standard temporary root for challenges
    index index.html index.htm;

    location ~ /.well-known/acme-challenge/ {
        allow all;
        root /var/www/html; # Ensure certbot can write here or specify a different challenge path
    }
}
EOF
    mkdir -p /var/www/html # Ensure challenge directory root exists
    ln -sf "$temp_nginx_conf_path" "$temp_nginx_symlink"

    # Test and reload Nginx
    if ! nginx -t >>"$LOG_FILE" 2>&1; then
        print_error "Temporary Nginx configuration for Certbot failed test. Check $LOG_FILE."
        rm -f "$temp_nginx_conf_path" "$temp_nginx_symlink"
        return 1
    fi
    systemctl reload nginx >>"$LOG_FILE" 2>&1

    # Request certificate. --nginx plugin will modify the Nginx config.
    # --no-eff-email to avoid prompts if email is for recovery only.
    # --agree-tos is required.
    # --redirect will typically be handled by the main Nginx config later, but --nginx plugin might offer it.
    # For initial, just get the cert: certbot certonly --nginx -d "$DOMAIN" ...
    # Or let certbot handle the Nginx config: certbot --nginx -d "$DOMAIN" ...
    local certbot_email="admin@$DOMAIN" # Default email, user might want to change this
    print_info "Using email $certbot_email for SSL certificate registration."

    if ! certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos --email "$certbot_email" --redirect --hsts --uir >>"$LOG_FILE" 2>&1; then
        print_error "Failed to obtain SSL certificate for $DOMAIN."
        print_info "Please check the Certbot logs in /var/log/letsencrypt/letsencrypt.log for details."
        print_info "Common issues:"
        print_info "1. DNS for $DOMAIN not propagated to this server's IP."
        print_info "2. Port 80 not open or Nginx not correctly serving the challenge."
        print_info "3. Rate limits from Let's Encrypt (try again later or use --staging flag for testing)."
        rm -f "$temp_nginx_conf_path" "$temp_nginx_symlink" # Clean up temp config
        systemctl reload nginx >>"$LOG_FILE" 2>&1           # Reload Nginx to remove temp config
        return 1                                            # Indicate failure
    fi

    # Certbot --nginx should have updated the main Nginx config or created one.
    # We will overwrite/create dezerx.conf in configure_nginx, so the temp one can be removed.
    rm -f "$temp_nginx_conf_path" "$temp_nginx_symlink"
    # Reload Nginx after Certbot's changes and our cleanup
    execute_with_loading "systemctl reload nginx" "Reloading Nginx after SSL setup"

    print_success "SSL certificate obtained and configured successfully for $DOMAIN!"
    return 0
}

setup_ssl_skip() {
    print_step "12" "SSL CERTIFICATE SETUP" # Step number consistent for install
    print_warning "You selected HTTP protocol. Skipping SSL certificate setup."
    print_info "Your site will be served over HTTP, which is insecure. HTTPS is strongly recommended for production."
}

configure_nginx() {
    print_step "13" "CONFIGURING NGINX WEB SERVER" # Step number consistent for install

    print_info "Removing default Nginx site configuration (if it exists)..."
    rm -f /etc/nginx/sites-available/default
    rm -f /etc/nginx/sites-enabled/default

    local nginx_conf_file="/etc/nginx/sites-available/dezerx.conf"
    print_info "Creating DezerX Nginx configuration at $nginx_conf_file..."

    # Common Nginx settings
    local common_nginx_settings
    common_nginx_settings=$(
        cat <<EOF
    root $INSTALL_DIR/public;
    index index.php index.html index.htm;

    access_log /var/log/nginx/dezerx.app-access.log;
    error_log  /var/log/nginx/dezerx.app-error.log error;

    client_max_body_size 100m;      # Max upload size
    client_body_timeout 120s;       # Timeout for reading client body

    # Security headers (can be customized)
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
    # add_header Content-Security-Policy "default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline';" always; # Example CSP

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php$ {
        try_files \$uri =404;
        fastcgi_split_path_info ^(.+\.php)(/.+)$;
        fastcgi_pass unix:/run/php/php8.3-fpm.sock; # Ensure this matches your PHP-FPM version
        fastcgi_index index.php;
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_param PHP_VALUE "upload_max_filesize = 100M \n post_max_size=100M"; # PHP settings via Nginx
        fastcgi_param HTTP_PROXY ""; # Clear proxy header
        fastcgi_intercept_errors off;
        fastcgi_buffer_size 16k;
        fastcgi_buffers 4 16k;
        fastcgi_connect_timeout 300;
        fastcgi_send_timeout 300;
        fastcgi_read_timeout 300;
    }

    # Deny access to .htaccess files (though Nginx doesn't use them)
    location ~ /\.ht {
        deny all;
    }

    # Deny access to .env and other sensitive files
    location ~ /\.env\$ { deny all; }
    location ~ /\.git { deny all; }
    location ~ /composer\.lock\$ { deny all; }
    location ~ /composer\.json\$ { deny all; }
EOF
    )

    if [[ "$PROTOCOL" == "https" ]]; then
        # Ensure SSL certificate paths are correct (Certbot default)
        local ssl_cert_path="/etc/letsencrypt/live/$DOMAIN/fullchain.pem"
        local ssl_key_path="/etc/letsencrypt/live/$DOMAIN/privkey.pem"

        if [[ ! -f "$ssl_cert_path" || ! -f "$ssl_key_path" ]]; then
            print_error "SSL certificate files not found for $DOMAIN at $ssl_cert_path or $ssl_key_path."
            print_info "This might happen if SSL setup failed. Please check."
            # Decide if this is fatal. For now, proceed but Nginx will fail to start/reload.
        fi

        cat >"$nginx_conf_file" <<EOF
server {
    listen 80;
    server_name $DOMAIN;
    # Redirect HTTP to HTTPS
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl http2;
    server_name $DOMAIN;

    ssl_certificate $ssl_cert_path;
    ssl_certificate_key $ssl_key_path;
    
    # Recommended SSL/TLS settings (from Certbot or Mozilla SSL Config Generator)
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers on;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 1d;
    ssl_session_tickets off; # Consider security implications

    # HSTS (Strict Transport Security) - uncomment if you are sure about HTTPS only
    # add_header Strict-Transport-Security "max-age=63072000; includeSubDomains; preload" always;

$common_nginx_settings
}
EOF
    else # HTTP
        cat >"$nginx_conf_file" <<EOF
server {
    listen 80;
    server_name $DOMAIN;

$common_nginx_settings
}
EOF
    fi

    # Enable the site by creating a symlink
    ln -sf "$nginx_conf_file" "/etc/nginx/sites-enabled/$(basename "$nginx_conf_file")"

    print_info "Testing Nginx configuration..."
    if ! nginx -t >>"$LOG_FILE" 2>&1; then
        print_error "Nginx configuration test failed. Check $LOG_FILE for details."
        nginx -t # Print errors to console as well
        # Do not exit here, allow user to fix and re-run or debug.
        # Or, make it fatal:
        # if [[ "$OPERATION_MODE" == "update" && "$RESTORE_ON_FAILURE" == "yes" ]]; then restore_backup; restore_database; fi
        # exit 1
        print_warning "Nginx test failed. The web server might not start correctly."
    else
        print_success "Nginx configuration test passed."
    fi

    execute_with_loading "systemctl restart nginx" "Restarting Nginx service"

    print_success "Nginx configured successfully!"
}

install_nodejs_and_build() {
    if [[ "$OPERATION_MODE" == "install" ]]; then
        print_step "14" "INSTALLING NODE.JS AND BUILDING ASSETS"
    else # update
        print_step "8" "BUILDING FRONTEND ASSETS"
    fi

    # Check if Node.js and npm are installed, install if not (especially for fresh install)
    if ! command -v node &>/dev/null || ! command -v npm &>/dev/null; then
        print_info "Node.js or npm not found. Installing Node.js (LTS)..."
        # Using NodeSource for up-to-date LTS version (e.g., 20.x)
        execute_with_loading "curl -fsSL https://deb.nodesource.com/setup_lts.x | bash -" "Adding Node.js LTS repository"
        execute_with_loading "apt-get install -y -qq nodejs" "Installing Node.js"
        if ! command -v node &>/dev/null || ! command -v npm &>/dev/null; then
            print_error "Node.js/npm installation failed. Cannot build frontend assets."
            return 1 # Indicate failure
        fi
        print_success "Node.js and npm installed: $(node -v), npm $(npm -v)"
    else
        print_info "Node.js and npm found: $(node -v), npm $(npm -v)"
    fi

    cd "$INSTALL_DIR" || {
        print_error "Failed to change directory to $INSTALL_DIR"
        return 1
    }

    # Ensure npm cache directory exists and is owned by www-data
    if [[ ! -d "/var/www/.npm" ]]; then
        mkdir -p /var/www/.npm
    fi
    chown -R www-data:www-data /var/www/.npm

    # Clean up node_modules and package-lock.json before npm install
    if [[ -d "node_modules" ]]; then
        rm -rf node_modules
    fi
    if [[ -f "package-lock.json" ]]; then
        rm -f package-lock.json
    fi

    if [[ -f "package.json" ]]; then
        print_info "Installing npm dependencies (can take a few minutes)..."
        local npm_install_cmd="npm install"
        execute_as_www_data "$npm_install_cmd" "Installing npm dependencies"
        local npm_install_exit_code=$?
        if [ $npm_install_exit_code -ne 0 ]; then
            print_error "npm install failed with exit code $npm_install_exit_code."
            return $npm_install_exit_code
        fi

        print_info "Building production assets (can take a few minutes)..."
        local npm_build_cmd="npm run build"
        execute_as_www_data "$npm_build_cmd" "Building assets"
        local npm_build_exit_code=$?
        if [ $npm_build_exit_code -ne 0 ]; then
            print_error "npm run build failed with exit code $npm_build_exit_code."
            return $npm_build_exit_code
        fi
        print_success "Frontend assets built successfully!"
    else
        print_warning "package.json not found in $INSTALL_DIR. Skipping npm install and build."
    fi
    return 0
}

set_permissions() {
    local step_num
    if [[ "$OPERATION_MODE" == "install" ]]; then
        step_num="15"
    else # update
        step_num="9"
    fi
    print_step "$step_num" "SETTING FILE PERMISSIONS"

    cd "$INSTALL_DIR" || {
        print_error "Failed to change directory to $INSTALL_DIR"
        return 1
    }

    print_info "Setting ownership to www-data:www-data for $INSTALL_DIR..."
    if id "www-data" &>/dev/null; then
        execute_with_loading "chown -R www-data:www-data ." "Setting ownership (chown)" # Use . for current dir
    else
        print_warning "User www-data not found. Skipping chown. Manual permission adjustment might be needed."
    fi

    print_info "Setting directory permissions (typically 755 or 775 for storage/cache)..."
    execute_with_loading "find . -type d -exec chmod 755 {} \;" "Setting directory permissions to 755"

    print_info "Setting file permissions (typically 644 or 664 for storage/cache)..."
    execute_with_loading "find . -type f -exec chmod 644 {} \;" "Setting file permissions to 644"

    print_info "Setting specific writable permissions for storage and bootstrap/cache..."
    if [[ -d "storage" ]]; then
        execute_with_loading "chmod -R ug+rwx storage" "Setting storage permissions (u+rwx, g+rwx)"
    fi
    if [[ -d "bootstrap/cache" ]]; then
        execute_with_loading "chmod -R ug+rwx bootstrap/cache" "Setting bootstrap/cache permissions (u+rwx, g+rwx)"
    fi

    # Ensure .env has secure permissions
    if [[ -f ".env" ]]; then
        chmod 640 .env >>"$LOG_FILE" 2>&1 # Only owner and group read, owner write
        if id "www-data" &>/dev/null; then
            chown "$(id -u):www-data" .env >>"$LOG_FILE" 2>&1 # Owner: current user, Group: www-data
        fi
    fi

    print_success "File permissions set successfully!"
}

run_migrations() {
    local step_num
    if [[ "$OPERATION_MODE" == "install" ]]; then
        step_num="16"
    else # update
        step_num="10"
    fi
    print_step "$step_num" "RUNNING DATABASE MIGRATIONS AND SEEDERS"

    cd "$INSTALL_DIR" || {
        print_error "Failed to change directory to $INSTALL_DIR"
        return 1
    }

    # Temporarily disable exit on error for migrations/seeding to handle errors gracefully
    set +e
    print_info "Running database migrations..."
    # --force is needed for production environments
    execute_as_www_data "php artisan migrate --force" "Running database migrations"
    local migrate_exit_code=$?
    set -e # Re-enable exit on error

    if [ $migrate_exit_code -ne 0 ]; then
        print_error "Database migration failed! (Exit code: $migrate_exit_code)"
        print_error "Check $LOG_FILE for detailed migration errors."
        tail -n 20 "$LOG_FILE" # Show last few lines of log
        if [[ "$OPERATION_MODE" == "update" && "$RESTORE_ON_FAILURE" == "yes" ]]; then
            print_error "Attempting to restore backup due to migration failure..."
            restore_backup
            restore_database
        else
            print_warning "Automatic restore is disabled or not applicable. Manual intervention may be required."
        fi
        exit 1 # Critical failure
    fi
    print_success "Database migrations completed successfully!"

    if [[ "$OPERATION_MODE" == "install" ]]; then
        set +e
        print_info "Running database seeders (for initial setup)..."
        execute_as_www_data "php artisan db:seed --force" "Running database seeders"
        local seed_exit_code=$?
        set -e

        if [ $seed_exit_code -ne 0 ]; then
            print_warning "Database seeding failed or had issues (Exit code: $seed_exit_code)."
            print_warning "This might be normal if seeders are optional or environment-dependent. Check $LOG_FILE."
            tail -n 20 "$LOG_FILE"
            # Seeding failure is usually not as critical as migration failure for an update.
            # For install, it might mean incomplete setup.
        else
            print_success "Database seeders completed successfully!"
        fi
    else
        print_info "Skipping database seeders for update mode (usually run only on fresh install)."
    fi

    # Final permission check after artisan commands
    # set_permissions # Call set_permissions again to ensure everything is correct
    # Re-calling set_permissions here might be redundant if execute_as_www_data handles permissions correctly
    # or if the artisan commands themselves create files with correct ownership when run as www-data.
    # However, it can be a safety measure. For now, let's assume www-data execution handles it.
    # If specific files created by artisan need different permissions than default, adjust here or in set_permissions.

    print_success "Database operations phase completed."
}

setup_cron() {
    print_step "17" "SETTING UP CRON JOBS" # Step number consistent for install

    print_info "Adding Laravel scheduler to crontab for www-data user..."

    local cron_job_command="* * * * * cd $INSTALL_DIR && /usr/bin/php artisan schedule:run >> /dev/null 2>&1"
    local user_to_run_cron="www-data"

    if ! id "$user_to_run_cron" &>/dev/null; then
        print_warning "User '$user_to_run_cron' not found. Cannot set up user-specific cron job."
        print_info "You may need to set up the cron job manually: $cron_job_command"
        return 1
    fi

    # Since check_root ensures script is root, sudo is not needed for crontab -u www-data
    if ! (crontab -u "$user_to_run_cron" -l 2>/dev/null | grep -Fq "artisan schedule:run"); then
        # Add new cron job
        (
            crontab -u "$user_to_run_cron" -l 2>/dev/null
            echo "$cron_job_command"
        ) | crontab -u "$user_to_run_cron" -
        if crontab -u "$user_to_run_cron" -l 2>/dev/null | grep -Fq "artisan schedule:run"; then
            print_success "Laravel scheduler added to crontab for $user_to_run_cron."
        else
            print_error "Failed to add Laravel scheduler to crontab for $user_to_run_cron."
        fi
    else
        print_info "Laravel scheduler already exists in crontab for $user_to_run_cron."
    fi

    # Certbot renewal cron job (system-wide, usually handled by certbot package)
    if [[ "$PROTOCOL" == "https" ]] && command -v certbot &>/dev/null; then
        print_info "Ensuring Certbot auto-renewal cron job/timer is active..."
        # Certbot package usually sets up a systemd timer or cron job in /etc/cron.d/
        if systemctl list-timers | grep -q 'certbot.timer'; then
            print_success "Certbot systemd timer is active."
            execute_with_loading "systemctl start certbot.timer && systemctl enable certbot.timer" "Ensuring Certbot timer is started and enabled"
        elif [[ -f /etc/cron.d/certbot ]]; then
            print_success "Certbot cron job found in /etc/cron.d/certbot."
        else
            print_warning "Could not find standard Certbot renewal timer/cron. Adding a basic one."
            # Add a root cron job for certbot renewal if none found
            local certbot_renew_job="0 3 * * * /usr/bin/certbot renew --quiet --deploy-hook \"systemctl reload nginx\""
            if ! (crontab -l 2>/dev/null | grep -Fq "certbot renew"); then
                (
                    crontab -l 2>/dev/null
                    echo "$certbot_renew_job"
                ) | crontab -
                print_success "Added basic Certbot renewal cron job to root's crontab."
            else
                print_info "A Certbot renewal job seems to exist in root's crontab."
            fi
        fi
    fi

    if systemctl is-active --quiet cron; then
        print_success "Cron service (cronie/fcron) is running."
    else
        print_warning "Cron service is not running. Attempting to start..."
        if systemctl start cron >>"$LOG_FILE" 2>&1 && systemctl enable cron >>"$LOG_FILE" 2>&1; then
            print_success "Cron service started and enabled successfully."
        else
            print_error "Failed to start or enable cron service. Scheduled tasks may not run."
        fi
    fi
    print_success "Cron job setup phase completed."
}

setup_queue_worker() {
    print_step "18" "SETTING UP QUEUE WORKER SERVICE (Systemd)" # Step consistent for install

    local service_name="dezerx-worker" # Changed from dezerx.service to dezerx-worker.service
    local service_file="/etc/systemd/system/${service_name}.service"

    print_info "Creating systemd service file at $service_file..."
    # User and Group should be www-data
    # WorkingDirectory should be $INSTALL_DIR
    # ExecStart should point to php and artisan queue:work
    # Ensure --queue names match your application's needs
    cat >"$service_file" <<EOF
[Unit]
Description=DezerX Laravel Queue Worker
After=network.target mariadb.service redis-server.service # Ensure DB and Redis are up

[Service]
User=www-data
Group=www-data
WorkingDirectory=$INSTALL_DIR
ExecStart=/usr/bin/php $INSTALL_DIR/artisan queue:work --tries=3 --timeout=90 --sleep=3 --queue=default,notifications,emails
Restart=always
RestartSec=5s # Restart after 5 seconds if it fails

# Resource limits (optional, adjust as needed)
# MemoryMax=512M
# CPUWeight=100

StandardOutput=syslog
StandardError=syslog
SyslogIdentifier=$service_name

[Install]
WantedBy=multi-user.target
EOF

    execute_with_loading "systemctl daemon-reload" "Reloading systemd daemon"
    execute_with_loading "systemctl enable $service_name" "Enabling $service_name service"
    execute_with_loading "systemctl restart $service_name" "Starting/Restarting $service_name service" # Use restart to ensure it picks up changes

    if systemctl is-active --quiet "$service_name"; then
        print_success "$service_name service is active."
    else
        print_error "$service_name service failed to start. Check status with: systemctl status $service_name"
        print_error "Also check logs: journalctl -u $service_name -n 50 --no-pager"
        # This could be critical, consider if script should exit.
    fi
    print_success "Queue worker service configured successfully!"
}

cleanup_backup() {
    # Only run in update mode, and only if the update was successful (implied by reaching this step)
    if [[ "$OPERATION_MODE" == "update" ]]; then
        if [[ -n "$BACKUP_DIR" && -d "$BACKUP_DIR" ]]; then
            print_info "Update appears successful. Cleaning up backup directory..."
            rm -rf "$BACKUP_DIR"
            if [[ -n "$DB_BACKUP_FILE" && -f "$DB_BACKUP_FILE" ]]; then # This check is redundant if DB_BACKUP_FILE is inside BACKUP_DIR
                :                                                       # Already removed by rm -rf "$BACKUP_DIR"
            fi
            print_success "Backup directory $BACKUP_DIR (and its contents) cleaned up."
        else
            print_info "No backup directory to clean up or backup was not created."
        fi
    fi
}

print_summary() {
    local summary_step_num
    local info_file_name
    if [[ "$OPERATION_MODE" == "install" ]]; then
        summary_step_num="19"
        info_file_name="INSTALLATION_INFO.txt"
        print_step "$summary_step_num" "INSTALLATION COMPLETE"
        print_color $GREEN "╔══════════════════════════════════════════════════════════════╗"
        print_color $GREEN "║                                                              ║"
        print_color $GREEN "║                 🎉 INSTALLATION SUCCESSFUL! 🎉              ║"
        print_color $GREEN "║                                                              ║"
        print_color $GREEN "╚══════════════════════════════════════════════════════════════╝"
        print_success "DezerX has been successfully installed!"
    else                      # update
        summary_step_num="11" # Adjust update step numbers if needed
        info_file_name="UPDATE_INFO.txt"
        print_step "$summary_step_num" "UPDATE COMPLETE"
        print_color $GREEN "╔══════════════════════════════════════════════════════════════╗"
        print_color $GREEN "║                                                              ║"
        print_color $GREEN "║                      🎉 UPDATE SUCCESSFUL! 🎉               ║"
        print_color $GREEN "║                                                              ║"
        print_color $GREEN "╚══════════════════════════════════════════════════════════════╝"
        print_success "DezerX has been successfully updated!"
    fi

    echo ""
    print_color $CYAN "📊 DETAILS:"
    print_info "🌐 URL: ${BOLD}${PROTOCOL}://$DOMAIN${NC}"
    print_info "📁 Directory: ${BOLD}$INSTALL_DIR${NC}"
    if [[ "$OPERATION_MODE" == "install" ]]; then
        print_info "🗄️  Database Name: ${BOLD}$DB_FULL_NAME${NC}"
        print_info "👤 DB User: ${BOLD}$DB_USER_FULL${NC}"
        print_info "🔑 DB Password: ${BOLD}(Set during installation - check $INSTALL_DIR/$info_file_name or .env file)${NC}"
    fi
    print_info "🔑 License Key: ${BOLD}${LICENSE_KEY:0:8}***${NC}"

    echo ""
    print_color $YELLOW "📋 NEXT STEPS:"
    print_info "1. Visit ${PROTOCOL}://$DOMAIN in your browser."
    if [[ "$OPERATION_MODE" == "install" ]]; then
        print_info "2. Complete any on-screen setup wizards if applicable."
    else
        print_info "2. Verify all features are working as expected after the update."
    fi
    print_info "3. Clear your browser cache if you experience any display issues."

    echo ""
    print_color $YELLOW "🔧 USEFUL COMMANDS:"
    print_info "• Check queue worker: ${BOLD}systemctl status dezerx-worker${NC}"
    print_info "• Restart queue worker: ${BOLD}systemctl restart dezerx-worker${NC}"
    print_info "• View app logs: ${BOLD}tail -f $INSTALL_DIR/storage/logs/laravel.log${NC}"
    print_info "• View Nginx access log: ${BOLD}tail -f /var/log/nginx/dezerx.app-access.log${NC}"
    print_info "• View Nginx error log: ${BOLD}tail -f /var/log/nginx/dezerx.app-error.log${NC}"
    print_info "• Restart Nginx: ${BOLD}systemctl restart nginx${NC}"
    print_info "• View this script's operation log: ${BOLD}cat $LOG_FILE${NC}"
    print_info "• Check cron jobs for www-data: ${BOLD}sudo crontab -u www-data -l${NC}"
    print_info "• View .env file: ${BOLD}sudo cat $INSTALL_DIR/.env${NC} (handle with care)"

    echo ""
    print_color $CYAN "💡 SUPPORT & DOCUMENTATION:"
    print_info "📚 DezerX Documentation: https://docs.dezerx.com (replace with actual link)"
    print_info "🎫 DezerX Support: https://support.dezerx.com (replace with actual link)"

    echo ""
    print_color $GREEN "🚀 Thank you for using DezerX!"

    # Save installation/update details to a file
    local details_file_path="$INSTALL_DIR/$info_file_name"
    {
        echo "DezerX $([[ "$OPERATION_MODE" == "install" ]] && echo "Installation" || echo "Update") Information"
        echo "=================================================="
        echo "Date: $(date)"
        echo "Operation Mode: $OPERATION_MODE"
        echo "Domain: $DOMAIN"
        echo "Full URL: ${PROTOCOL}://$DOMAIN"
        echo "Installation Directory: $INSTALL_DIR"
        if [[ "$OPERATION_MODE" == "install" ]]; then
            echo "Database Name: $DB_FULL_NAME"
            echo "Database User: $DB_USER_FULL"
            echo "Database Password: $DB_PASSWORD" # Be cautious about logging passwords
        fi
        echo "License Key: $LICENSE_KEY" # Also sensitive
        echo "Script Log File: $LOG_FILE"
        echo ""
        echo "Access your installation at: ${PROTOCOL}://$DOMAIN"
        echo ""
        echo "Useful Commands (also listed above):"
        echo "- Check queue worker: systemctl status dezerx-worker"
        echo "- Restart queue worker: systemctl restart dezerx-worker"
        # ... (add more commands if desired)
    } >"$details_file_path"

    print_info "💾 Operation details saved to: $details_file_path"
    # Secure the info file if it contains sensitive data
    chmod 600 "$details_file_path"
    if id "www-data" &>/dev/null; then
        chown "$(id -u):www-data" "$details_file_path"
    fi
}

cleanup_on_error() {
    local lineno="$1"
    local command_that_failed="${BASH_COMMAND}" # Get the command that failed
    print_error "Operation failed at line $lineno: $command_that_failed"
    print_error "An error occurred. Please check the script output and the log file: $LOG_FILE"
    tail -n 30 "$LOG_FILE" # Show last 30 lines of log for quick diagnostics

    if [[ "$OPERATION_MODE" == "update" && "$RESTORE_ON_FAILURE" == "yes" ]]; then
        print_warning "Attempting to restore from backup due to script error..."
        restore_backup   # Restore application files
        restore_database # Restore database
        print_info "Backup restore attempt finished. Please verify your system."
    else
        print_warning "Automatic restore on failure was not enabled or not applicable."
        print_info "You may need to clean up partially installed/updated components manually."
    fi
    exit 1
}

main() {
    echo "DezerX $(if [[ "$OPERATION_MODE" == "install" ]]; then echo "Installation"; else echo "Update"; fi) Log - $(date)" >"$LOG_FILE"

    print_banner
    trap 'cleanup_on_error $LINENO' ERR

    check_required_commands
    check_root
    choose_install_variant
    choose_operation_mode
    check_system_requirements

    if [[ "$OPERATION_MODE" == "install" ]]; then
        get_install_input
        verify_license
        install_dependencies
        install_composer
        setup_database
        download_dezerx
        configure_laravel
        check_dns
        configure_firewall
        if [[ "$PROTOCOL" == "https" ]]; then
            setup_ssl
        else
            setup_ssl_skip
        fi
        configure_nginx
        install_nodejs_and_build
        set_permissions
        run_migrations
        setup_cron
        setup_queue_worker
    else
        if [[ "$OPERATION_MODE" == "update" ]]; then
            # UPDATE MODE
            get_update_input
            verify_license
            create_backup
            backup_database # <--- ADD THIS LINE
            download_dezerx
            configure_laravel
            print_info "DEBUG: configure_laravel completed, continuing..."
            install_nodejs_and_build
            set_permissions
            run_migrations
            cleanup_backup
        fi
    fi

    print_summary
    log_message "Operation completed successfully"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
