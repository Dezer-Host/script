#!/bin/bash

# --- EARLY SYSTEM CHECK: Redirect Debian users to the Debian script ---
if [ -f /etc/debian_version ] && ! grep -qi ubuntu /etc/os-release; then
    echo "Detected Debian system. Redirecting to the DezerX Debian installer..."
    curl -fsSL https://raw.githubusercontent.com/Dezer-Host/script/main/script_debian.sh -o /tmp/dx.sh && bash /tmp/dx.sh
    exit 0
fi

set -euo pipefail

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

LICENSE_KEY=""
DOMAIN=""
INSTALL_DIR=""
DB_PASSWORD=""
DB_NAME_PREFIX=""
DB_FULL_NAME=""
DB_USER_FULL=""
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/tmp/dezerx-install.log"
OPERATION_MODE=""
BACKUP_DIR=""
DB_BACKUP_FILE=""
RESTORE_ON_FAILURE=""
PROTOCOL="https"

print_color() {
    printf "${1}${2}${NC}\n"
}

check_required_commands() {
    local cmds=(curl awk grep sed)
    for cmd in "${cmds[@]}"; do
        if ! command -v "$cmd" &>/dev/null; then
            print_error "Required command '$cmd' not found. Please install it."
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
    local frame_count=${#spin_frames[@]}
    local i=0

    # Hide cursor
    tput civis 2>/dev/null || true

    while kill -0 "$pid" 2>/dev/null; do
        printf "\r${BLUE}%s %s${NC} " "$message" "${spin_frames[$i]}"
        i=$(((i + 1) % frame_count))
        sleep 0.08
    done

    # Show checkmark and restore cursor
    printf "\r${BLUE}%s ${GREEN}✔${NC}\n" "$message"
    tput cnorm 2>/dev/null || true
}

execute_with_loading() {
    local command="$1"
    local message="$2"

    log_message "Executing: $command"
    eval "$command" >>"$LOG_FILE" 2>&1 &
    local pid=$!
    show_loading $pid "$message"
    wait $pid
    local exit_code=$?

    if [ $exit_code -ne 0 ]; then
        print_error "Command failed: $command"
        print_error "Check log file: $LOG_FILE"
        exit $exit_code
    fi

    return $exit_code
}

print_banner() {
    clear
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
║               ${BOLD}${YELLOW}INSTALLATION & UPDATE SCRIPT v${SCRIPT_VERSION}${NC}${CYAN}              ║
║                  🚀 Requires Root Access 🚀                  ║
╚══════════════════════════════════════════════════════════════╝
"
    print_color $YELLOW "📋 This script can install or update DezerX"
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
    print_color $WHITE "2) 🖥️  GUI (with a graphical interface) (ALPHA)"
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
        print_color $WHITE "Please choose an option (1 or 2 or 3):"
        read -r choice
        case $choice in
        1)
            OPERATION_MODE="install"
            print_success "Selected: Fresh Installation"
            print_warning "The non automatic restore feature is intended for developers and testing environments only."
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
            print_warning "The non automatic restore feature is intended for developers and testing environments only."
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
            print_error "Invalid choice. Please enter 1 or 2 or 3."
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

    if [[ "$os_name" != "Ubuntu" ]] && [[ "$os_name" != "Debian" ]]; then
        print_error "This script only supports Ubuntu and Debian"
        exit 1
    fi

    local available_space=$(df / | awk 'NR==2 {print $4}')
    local required_space
    if [[ "$OPERATION_MODE" == "install" ]]; then
        required_space=5242880
    else
        required_space=2097152
    fi

    if [[ $available_space -lt $required_space ]]; then
        print_error "Insufficient disk space. Required: $((required_space / 1024 / 1024))GB, Available: $((available_space / 1024 / 1024))GB"
        exit 1
    fi

    local total_mem=$(free -m | awk 'NR==2{print $2}')
    if [[ $total_mem -lt 1024 ]]; then
        print_warning "Low memory detected: ${total_mem}MB. Recommended: 2GB+"
    fi

    print_success "System requirements check passed"
}

validate_domain() {
    local domain=$1

    if [[ $domain =~ ^https?:// ]]; then
        return 2
    fi

    if [[ ! $domain =~ ^[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?)*$ ]]; then
        return 1
    fi
    return 0
}

validate_directory() {
    local dir=$1
    if [[ ! $dir =~ ^/[a-zA-Z0-9/_-]+$ ]]; then
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
            print_error "Invalid directory path. Please try again."
        fi
    done

    while true; do
        print_color $CYAN "🗄️  DATABASE CONFIGURATION:"
        print_color $WHITE "Leave blank to use defaults."

        if [[ -z "$DB_NAME_PREFIX" ]]; then
            DB_NAME_PREFIX=$(echo "$DOMAIN" | grep -o '^[a-zA-Z]*' | tr '[:upper:]' '[:lower:]' | cut -c1-4)
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
        read -r -s user_db_pass
        echo
        if [[ -n "$user_db_pass" ]]; then
            DB_PASSWORD="$user_db_pass"
        else
            if [[ -z "$DB_PASSWORD" ]]; then
                DB_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)
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

        # --- NEU: DB-Infos aus .env lesen ---
        DB_FULL_NAME=$(get_env_variable "DB_DATABASE" "$INSTALL_DIR/.env")
        DB_USER_FULL=$(get_env_variable "DB_USERNAME" "$INSTALL_DIR/.env")
        DB_PASSWORD=$(get_env_variable "DB_PASSWORD" "$INSTALL_DIR/.env")
        # Fallback, falls leer:
        if [[ -z "$DB_FULL_NAME" ]]; then DB_FULL_NAME="dezerx"; fi
        if [[ -z "$DB_USER_FULL" ]]; then DB_USER_FULL="dezer"; fi

        break
    done

    print_success "Found existing DezerX installation at: $INSTALL_DIR"

    echo ""
    print_color $CYAN "📋 UPDATE SUMMARY:"
    print_info "License Key: ${LICENSE_KEY:0:8}***"
    print_info "Domain: $DOMAIN"
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
        print_step "4" "VERIFYING LICENSE"
    fi

    print_info "Contacting DezerX license server..."

    local temp_file=$(mktemp)
    local http_code

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
        print_error "License verification failed (HTTP: $http_code)"
        if [[ -f "$temp_file" ]]; then
            local error_msg=$(cat "$temp_file" 2>/dev/null || echo "Unknown error")
            print_error "Server response: $error_msg"
            rm -f "$temp_file"
        fi
        print_error "Please check your license key and domain."
        exit 1
    fi
}

create_backup() {
    print_step "5" "CREATING BACKUP"

    BACKUP_DIR="/tmp/dezerx-backup-$(date +%Y%m%d-%H%M%S)"

    print_info "Creating full backup of existing installation..."
    print_info "Backup location: $BACKUP_DIR"

    execute_with_loading "cp -r $INSTALL_DIR $BACKUP_DIR" "Creating backup of $INSTALL_DIR"

    if [[ ! -f "$BACKUP_DIR/.env" ]]; then
        print_error "Backup verification failed - .env file not found in backup"
        exit 1
    fi

    print_success "Backup created successfully!"
    print_info "💾 Backup saved to: $BACKUP_DIR"
}

get_env_variable() {
    local var_name="$1"
    local env_file="$2"
    if [[ -f "$env_file" ]]; then

        grep "^${var_name}=" "$env_file" | cut -d '=' -f 2- | sed 's/\r$//' | sed 's/"//g' | sed "s/'//g"
    else
        echo ""
    fi
}

backup_database() {
    print_step "5.1" "BACKING UP DATABASE"

    local env_file="$INSTALL_DIR/.env"

    if [[ ! -f "$env_file" ]]; then
        print_warning ".env file not found at $env_file. Skipping database backup."
        return 0 # This should return, not exit
    fi

    local db_connection=$(get_env_variable "DB_CONNECTION" "$env_file")
    local db_host=$(get_env_variable "DB_HOST" "$env_file")
    local db_port=$(get_env_variable "DB_PORT" "$env_file")
    local db_database=$(get_env_variable "DB_DATABASE" "$env_file")
    local db_username=$(get_env_variable "DB_USERNAME" "$env_file")
    local db_password=$(get_env_variable "DB_PASSWORD" "$env_file")

    if [[ "$db_connection" != "mysql" ]]; then
        print_warning "Database connection is not 'mysql' in .env. Skipping database backup."
        return 0 # This should return, not exit
    fi

    if [[ -z "$db_host" || -z "$db_database" || -z "$db_username" ]]; then
        print_error "Missing database credentials in .env file. Cannot perform database backup."
        exit 1 # Only exit on critical errors
    fi

    # Use existing BACKUP_DIR from create_backup()
    if [[ -z "$BACKUP_DIR" ]]; then
        print_error "BACKUP_DIR not set. create_backup() should run first."
        exit 1
    fi

    DB_BACKUP_FILE="$BACKUP_DIR/database_$(date +%Y%m%d-%H%M%S).sql.gz"

    print_info "Backing up database '$db_database'..."
    print_info "Backup file: $DB_BACKUP_FILE"

    local port_arg=""
    if [[ -n "$db_port" ]]; then
        port_arg="-P $db_port"
    fi

    export MYSQL_PWD="$db_password"
    local mysqldump_cmd="mysqldump -h $db_host $port_arg -u $db_username $db_database | gzip > \"$DB_BACKUP_FILE\""

    if ! command -v mysqldump &>/dev/null; then
        print_error "mysqldump command not found. Cannot perform database backup."
        unset MYSQL_PWD
        exit 1
    fi

    execute_with_loading "$mysqldump_cmd" "Creating database backup"
    local exit_code=$?
    unset MYSQL_PWD

    if [ $exit_code -ne 0 ]; then
        print_error "Database backup failed!"
        return 1
    fi

    if [[ ! -s "$DB_BACKUP_FILE" ]]; then
        print_error "Database backup file is empty or not created!"
        return 1
    fi

    print_success "Database backup completed successfully!"
    print_info "Database backup saved to: $DB_BACKUP_FILE"

    # Add explicit continuation message
    print_info "Continuing with update process..."
    return 0
}

restore_backup() {
    print_error "Restoring from backup due to update failure..."

    if [[ -n "$BACKUP_DIR" && -d "$BACKUP_DIR" ]]; then
        print_info "Removing failed update files..."
        rm -rf "$INSTALL_DIR"

        print_info "Restoring from backup: $BACKUP_DIR"
        mv "$BACKUP_DIR" "$INSTALL_DIR"

        print_info "Setting proper permissions after restore..."
        chown -R www-data:www-data "$INSTALL_DIR"
        chmod -R 755 "$INSTALL_DIR"
        chmod -R 775 "$INSTALL_DIR/storage" 2>/dev/null || true
        chmod -R 775 "$INSTALL_DIR/bootstrap/cache" 2>/dev/null || true

        print_success "Backup restored successfully!"
        print_info "Your original installation has been restored"
    else
        print_error "No backup found to restore from!"
    fi
}

install_dependencies() {
    print_step "5" "INSTALLING SYSTEM DEPENDENCIES"

    execute_with_loading "apt-get update" "Updating package lists"
    execute_with_loading "DEBIAN_FRONTEND=noninteractive apt-get upgrade -y" "Upgrading system packages"

    execute_with_loading "apt-get install -y software-properties-common curl apt-transport-https ca-certificates gnupg lsb-release wget unzip git cron" "Installing basic dependencies"

    print_info "Adding PHP repository..."
    if ! LC_ALL=C.UTF-8 add-apt-repository -y ppa:ondrej/php >>"$LOG_FILE" 2>&1; then
        print_warning "Failed to add PHP PPA, trying alternative method..."
    fi

    print_info "Adding Redis repository..."
    curl -fsSL https://packages.redis.io/gpg | gpg --dearmor >/usr/share/keyrings/redis-archive-keyring.gpg 2>/dev/null
    echo "deb [signed-by=/usr/share/keyrings/redis-archive-keyring.gpg] https://packages.redis.io/deb $(lsb_release -cs) main" >/etc/apt/sources.list.d/redis.list

    print_info "Adding MariaDB repository..."
    curl -LsS https://r.mariadb.com/downloads/mariadb_repo_setup | bash >>"$LOG_FILE" 2>&1

    execute_with_loading "apt-get update" "Updating package lists with new repositories"

    local packages="nginx php8.3 php8.3-common php8.3-cli php8.3-gd php8.3-mysql php8.3-mbstring php8.3-bcmath php8.3-xml php8.3-fpm php8.3-curl php8.3-zip mariadb-server tar unzip git redis-server ufw"

    execute_with_loading "DEBIAN_FRONTEND=noninteractive apt-get install -y $packages" "Installing PHP, MariaDB, Nginx, and other dependencies"

    execute_with_loading "systemctl start nginx && systemctl enable nginx" "Starting and enabling Nginx"
    execute_with_loading "systemctl start php8.3-fpm && systemctl enable php8.3-fpm" "Starting and enabling PHP-FPM"
    execute_with_loading "systemctl start redis-server && systemctl enable redis-server" "Starting and enabling Redis"
    execute_with_loading "systemctl start cron && systemctl enable cron" "Starting and enabling Cron service"
    execute_with_loading "systemctl stop ufw && systemctl disable ufw" "Stoping and disabling UFW due to later configuration"

    execute_with_loading "mkdir -p /var/www" "Creating /var/www directory"

    print_success "System dependencies installed successfully!"
}

install_composer() {
    print_step "6" "INSTALLING COMPOSER"

    local composer_installer="/tmp/composer-installer.php"

    execute_with_loading "curl -sS https://getcomposer.org/installer -o $composer_installer" "Downloading Composer installer"
    execute_with_loading "php $composer_installer --install-dir=/usr/local/bin --filename=composer" "Installing Composer"

    rm -f "$composer_installer"

    if ! command -v composer &>/dev/null; then
        print_error "Composer installation failed"
        exit 1
    fi

    print_success "Composer installed successfully!"
}

setup_database() {
    print_step "7" "SETTING UP DATABASE"

    execute_with_loading "systemctl start mariadb && systemctl enable mariadb" "Starting MariaDB service"

    DB_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)

    print_info "Securing MariaDB installation and creating database/user..."

    local sql_file=$(mktemp)
    cat >"$sql_file" <<EOF
-- Create the dedicated database for the application
CREATE DATABASE IF NOT EXISTS \`$DB_FULL_NAME\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- Create the dedicated user for the application (both hosts!)
CREATE USER IF NOT EXISTS '$DB_USER_FULL'@'127.0.0.1' IDENTIFIED BY '$DB_PASSWORD';
CREATE USER IF NOT EXISTS '$DB_USER_FULL'@'localhost' IDENTIFIED BY '$DB_PASSWORD';

-- Grant all privileges on the application database to the user (both hosts!)
GRANT ALL PRIVILEGES ON \`$DB_FULL_NAME\`.* TO '$DB_USER_FULL'@'127.0.0.1' WITH GRANT OPTION;
GRANT ALL PRIVILEGES ON \`$DB_FULL_NAME\`.* TO '$DB_USER_FULL'@'localhost' WITH GRANT OPTION;

-- Apply all privilege changes
FLUSH PRIVILEGES;
EOF

    if ! mariadb <"$sql_file" >>"$LOG_FILE" 2>&1; then
        print_error "Failed to secure MariaDB installation"
        rm -f "$sql_file"
        exit 1
    fi

    cat >"$sql_file" <<EOF
-- Create the dedicated database for the application
CREATE DATABASE IF NOT EXISTS \`$DB_FULL_NAME\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- Create the dedicated user for the application
CREATE USER IF NOT EXISTS '$DB_USER_FULL'@'127.0.0.1' IDENTIFIED BY '$DB_PASSWORD';

-- Grant all privileges on the application database to the user
GRANT ALL PRIVILEGES ON \`$DB_FULL_NAME\`.* TO '$DB_USER_FULL'@'127.0.0.1' WITH GRANT OPTION;

-- Apply all privilege changes
FLUSH PRIVILEGES;
EOF

    if ! mariadb <"$sql_file" >>"$LOG_FILE" 2>&1; then
        print_error "Failed to create database and user"
        rm -f "$sql_file"
        exit 1
    fi

    rm -f "$sql_file"

    print_success "Database setup completed successfully!"
    print_info "Database: $DB_FULL_NAME"
    print_info "Username: $DB_USER_FULL"
    print_info "Password: [Generated securely]"
}

download_dezerx() {
    if [[ "$OPERATION_MODE" == "install" ]]; then
        print_step "8" "DOWNLOADING DEZERX"
    else
        print_step "6" "DOWNLOADING DEZERX UPDATE"
    fi

    print_info "Requesting download URL from DezerX servers..."

    local temp_file=$(mktemp)
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
        print_error "Failed to get download URL (HTTP: $http_code)"
        if [[ -f "$temp_file" ]]; then
            local error_msg=$(cat "$temp_file" 2>/dev/null || echo "Unknown error")
            print_error "Server response: $error_msg"
        fi
        rm -f "$temp_file"
        if [[ "$OPERATION_MODE" == "update" ]]; then
            restore_backup
        fi
        exit 1
    fi

    local download_url
    if command -v jq &>/dev/null; then
        download_url=$(jq -r '.download_url' "$temp_file" 2>/dev/null)
    else
        download_url=$(grep -o '"download_url":"[^"]*' "$temp_file" | cut -d'"' -f4 | sed 's/\\//g')
    fi

    rm -f "$temp_file"

    if [[ -z "$download_url" || "$download_url" == "null" ]]; then
        print_error "Failed to extract download URL from server response"
        if [[ "$OPERATION_MODE" == "update" ]]; then
            restore_backup
        fi
        exit 1
    fi

    if [[ "$OPERATION_MODE" == "install" ]]; then
        print_info "Creating installation directory: $INSTALL_DIR"
        mkdir -p "$INSTALL_DIR"
    fi

    print_info "Downloading DezerX package..."
    local download_file="/tmp/dezerx-$(date +%s).zip"

    if ! curl -L -o "$download_file" \
        --progress-bar \
        --connect-timeout 30 \
        --max-time 300 \
        "$download_url"; then
        print_error "Download failed"
        rm -f "$download_file"
        if [[ "$OPERATION_MODE" == "update" ]]; then
            restore_backup
        fi
        exit 1
    fi

    print_success "Download completed successfully!"

    print_info "Extracting files to temporary location..."
    local temp_extract_dir=$(mktemp -d)

    if ! unzip -q "$download_file" -d "$temp_extract_dir"; then
        print_error "Failed to extract files"
        rm -f "$download_file"
        rm -rf "$temp_extract_dir"
        if [[ "$OPERATION_MODE" == "update" ]]; then
            restore_backup
        fi
        exit 1
    fi

    rm -f "$download_file"

    print_info "Locating DezerX files in extracted archive..."

    local dezerx_source_dir=""
    local found_dirs=()

    while IFS= read -r -d '' dir; do
        found_dirs+=("$dir")
    done < <(find "$temp_extract_dir" -maxdepth 1 -type d -name "*DezerX*" -print0)

    if [[ ${#found_dirs[@]} -eq 0 ]]; then
        print_error "No DezerX directory found in the extracted archive"
        print_info "Contents of extracted archive:"
        ls -la "$temp_extract_dir" || true
        rm -rf "$temp_extract_dir"
        if [[ "$OPERATION_MODE" == "update" ]]; then
            restore_backup
        fi
        exit 1
    elif [[ ${#found_dirs[@]} -eq 1 ]]; then
        dezerx_source_dir="${found_dirs[0]}"
    else

        for dir in "${found_dirs[@]}"; do
            if [[ -f "$dir/.env.example" ]]; then
                dezerx_source_dir="$dir"
                break
            fi
        done

        if [[ -z "$dezerx_source_dir" ]]; then
            dezerx_source_dir="${found_dirs[0]}"
        fi
    fi

    print_info "Found DezerX files in: $(basename "$dezerx_source_dir")"

    if [[ ! -f "$dezerx_source_dir/.env.example" ]]; then
        print_error "Invalid DezerX package - .env.example not found in $(basename "$dezerx_source_dir")"
        print_info "Contents of $(basename "$dezerx_source_dir"):"
        ls -la "$dezerx_source_dir" || true
        rm -rf "$temp_extract_dir"
        if [[ "$OPERATION_MODE" == "update" ]]; then
            restore_backup
        fi
        exit 1
    fi

    print_info "Moving DezerX files to installation directory..."

    if [[ "$OPERATION_MODE" == "install" ]]; then

        rm -rf "$INSTALL_DIR"
        mkdir -p "$INSTALL_DIR"

        if ! mv "$dezerx_source_dir"/* "$INSTALL_DIR"/; then
            print_error "Failed to move DezerX files to installation directory"
            rm -rf "$temp_extract_dir"
            if [[ "$OPERATION_MODE" == "update" ]]; then
                restore_backup
            fi
            exit 1
        fi

        if ls "$dezerx_source_dir"/.[^.]* >/dev/null 2>&1; then
            for file in "$dezerx_source_dir"/.[^.]*; do
                mv "$file" "$INSTALL_DIR"/ 2>/dev/null || true
            done
        fi
    else

        print_info "Preserving .env file and storage directory..."

        print_info "Copying updated files to installation directory (excluding .env.example and storage)..."
        if ! rsync -a --exclude='.env.example' --exclude='storage' "$dezerx_source_dir"/ "$INSTALL_DIR"/; then
            print_error "Failed to copy updated files to installation directory"
            rm -rf "$temp_extract_dir"
            restore_backup
            exit 1
        fi

        if ls "$dezerx_source_dir"/.[^.]* >/dev/null 2>&1; then
            for file in "$dezerx_source_dir"/.[^.]*; do
                local filename=$(basename "$file")
                if [[ "$filename" == ".env" ]]; then

                    continue
                fi

                if ! rsync -a "$file" "$INSTALL_DIR"/; then
                    print_warning "Failed to copy hidden file $filename"
                fi
            done
        fi
    fi

    rm -rf "$temp_extract_dir"

    if [[ "$OPERATION_MODE" == "install" && ! -f "$INSTALL_DIR/.env.example" ]]; then
        print_error "DezerX files not properly moved - .env.example not found in $INSTALL_DIR"
        print_info "Contents of $INSTALL_DIR:"
        ls -la "$INSTALL_DIR" || true
        exit 1
    fi

    print_success "DezerX files extracted and organized successfully!"
    print_info "Installation directory: $INSTALL_DIR"
}

update_env_file() {
    local key="$1"
    local value="$2"
    local env_file="$3"

    cp "$env_file" "${env_file}.bak"

    if command -v perl >/dev/null 2>&1; then
        if grep -q "^${key}=" "$env_file"; then

            perl -i -pe "s|^${key}=.*|${key}=${value}|" "$env_file" &&
                print_info "Updated ${key} in .env file (perl method)" && return 0
        else

            echo "${key}=${value}" >>"$env_file" &&
                print_info "Added ${key} to .env file" && return 0
        fi
    fi

    if command -v awk >/dev/null 2>&1; then
        local temp_file=$(mktemp)
        if grep -q "^${key}=" "$env_file"; then

            awk -v key="$key" -v val="$value" '{
                if ($0 ~ "^"key"=") {
                    print key"="val
                } else {
                    print $0
                }
            }' "$env_file" >"$temp_file" &&
                mv "$temp_file" "$env_file" &&
                print_info "Updated ${key} in .env file (awk method)" && return 0
        else

            echo "${key}=${value}" >>"$env_file" &&
                print_info "Added ${key} to .env file" && return 0
        fi
    fi

    if grep -q "^${key}=" "$env_file"; then

        local temp_file=$(mktemp)
        grep -v "^${key}=" "$env_file" >"$temp_file"
        echo "${key}=${value}" >>"$temp_file"
        mv "$temp_file" "$env_file"
        print_info "Updated ${key} in .env file (grep method)" && return 0
    else

        echo "${key}=${value}" >>"$env_file" &&
            print_info "Added ${key} to .env file" && return 0
    fi

    print_error "Failed to update ${key} in .env file"

    mv "${env_file}.bak" "$env_file"
    return 1
}

sync_env_files() {
    local install_dir="$1"
    local env_example_file="$install_dir/.env.example"
    local env_file="$install_dir/.env"

    if [[ ! -f "$env_example_file" ]]; then
        print_warning ".env.example not found in $install_dir. Cannot sync .env."
        return 0
    fi

    if [[ ! -f "$env_file" ]]; then
        print_warning ".env not found in $install_dir. This should not happen during an update. Skipping .env sync."
        return 0
    fi

    print_info "Synchronizing .env with .env.example..."

    if [[ $(
        tail -c 1 "$env_file"
        echo x
    ) != $'
'x ]]; then
        print_info "Adding a trailing newline to .env file."
        echo "" >>"$env_file"
    fi

    local env_example_lines
    mapfile -t env_example_lines <"$env_example_file"

    local added_vars=0

    for line in "${env_example_lines[@]}"; do

        local key=""

        if [[ "$line" =~ ^[[:alnum:]_]+= ]]; then
            key="$(echo "$line" | cut -d= -f1)"
        fi

        if [[ -n "$key" ]]; then

            if ! grep -q "^${key}=" "$env_file"; then

                printf "%s\n" "$line" >>"$env_file"
                print_info "Added missing variable '$key' from .env.example to .env."
                added_vars=$((added_vars + 1))

            fi
        fi
    done

    if [[ $added_vars -gt 0 ]]; then
        print_success "Synchronization complete. $added_vars new variables added to .env."
    else
        print_info ".env is already up-to-date with .env.example (no new variables to add)."
    fi

    chown www-data:www-data "$env_file" 2>/dev/null || true
    chmod 644 "$env_file" 2>/dev/null || true

    print_success ".env synchronization check finished."
}

configure_laravel() {
    if [[ "$OPERATION_MODE" == "install" ]]; then
        print_step "9" "CONFIGURING LARAVEL APPLICATION"
    else
        print_step "7" "UPDATING LARAVEL CONFIGURATION"
    fi

    cd "$INSTALL_DIR"

    if [[ "$OPERATION_MODE" == "install" ]]; then
        if [[ ! -f ".env.example" ]]; then
            print_error ".env.example file not found in $INSTALL_DIR"
            print_info "Directory contents:"
            ls -la "$INSTALL_DIR" || true
            exit 1
        fi

        execute_with_loading "cp .env.example .env" "Copying environment configuration"
    else
        if [[ ! -f ".env" ]]; then
            print_error ".env file not found in $INSTALL_DIR"
            restore_backup
            exit 1
        fi
        print_info "Using existing .env configuration"

        # Move sync_env_files to BEFORE composer install
        print_step "7.1" "SYNCHRONIZING .ENV FILE"
        sync_env_files "$INSTALL_DIR"
    fi

    print_info "Installing Composer dependencies..."
    if [[ "$OPERATION_MODE" == "install" ]]; then
        echo "yes" | composer install --no-dev --optimize-autoloader >>"$LOG_FILE" 2>&1 &
    else
        # Remove the duplicate sync_env_files call that was here
        echo "yes" | composer install --no-dev --optimize-autoloader >>"$LOG_FILE" 2>&1 &
    fi

    local composer_pid=$!
    show_loading $composer_pid "Installing Composer dependencies"
    wait $composer_pid
    local composer_exit_code=$?

    if [ $composer_exit_code -ne 0 ]; then
        print_error "Composer installation failed"
        print_error "Check log file: $LOG_FILE"
        if [[ "$OPERATION_MODE" == "update" ]]; then
            restore_backup
        fi
        exit $composer_exit_code
    fi

    # Add explicit success message and continuation
    print_success "Composer dependencies installed successfully!"
    print_info "Continuing with Laravel configuration..."

    execute_with_loading "php artisan storage:link" "Linking storage directory"

    if [[ "$OPERATION_MODE" == "install" ]]; then
        execute_with_loading "php artisan key:generate --force" "Generating application key"

        print_info "Updating environment configuration..."

        update_env_file "DB_CONNECTION" "mysql" ".env"
        update_env_file "DB_HOST" "127.0.0.1" ".env"
        update_env_file "DB_PORT" "3306" ".env"
        update_env_file "DB_DATABASE" "$DB_FULL_NAME" ".env"
        update_env_file "DB_USERNAME" "$DB_USER_FULL" ".env"
        update_env_file "DB_PASSWORD" "$DB_PASSWORD" ".env"

        update_env_file "APP_URL" "${PROTOCOL}://$DOMAIN" ".env"
        update_env_file "KEY" "$LICENSE_KEY" ".env"

        print_success "Laravel configuration completed!"
        print_success "Database configuration updated"
        print_success "APP_URL set to: ${PROTOCOL}://$DOMAIN"
        print_success "License key configured in KEY field"
    else
        update_env_file "KEY" "$LICENSE_KEY" ".env"
        print_success "Laravel configuration updated!"
        print_success "License key updated in KEY field"
    fi

    print_info "Verifying .env configuration..."
    if grep -q "^APP_KEY=" .env && grep -q "^KEY=" .env; then
        print_success "Both APP_KEY and KEY are properly configured"
        print_info "APP_KEY: $(grep '^APP_KEY=' .env | cut -d'=' -f2 | cut -c1-20)..."
        print_info "KEY: $(grep '^KEY=' .env | cut -d'=' -f2 | cut -c1-8)***"
    else
        print_warning "Could not verify all keys in .env file"
    fi

    # Add explicit completion message
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

prompt_ufw_firewall() {
    print_step "11" "FIREWALL CONFIGURATION"

    if ! command -v ufw &>/dev/null; then
        print_warning "ufw (Uncomplicated Firewall) is not installed. Skipping firewall configuration."
        return
    fi

    print_color $WHITE "Would you like to automatically configure the firewall (ufw) to allow HTTP/HTTPS traffic? (y/n):"
    read -r ufw_choice
    case "$ufw_choice" in
    [Yy] | [Yy][Ee][Ss])
        print_info "Configuring UFW to allow ports 80 (HTTP) and 443 (HTTPS)..."
        execute_with_loading "systemctl start ufw && systemctl enable ufw" "Starting & enabling UFW"
        ufw allow 80/tcp >>"$LOG_FILE" 2>&1
        ufw allow 443/tcp >>"$LOG_FILE" 2>&1
        ufw reload >>"$LOG_FILE" 2>&1
        print_success "UFW configured to allow HTTP/HTTPS traffic."
        ;;
    *)
        print_warning "Skipped UFW firewall configuration. Make sure ports 80 and 443 are open."
        print_color $WHITE "Do you want ufw to be started and enabled? (y/n):"
        read -r ufw_start_choice
        case "$ufw_start_choice" in
        [Yy] | [Yy][Ee][Ss])
            execute_with_loading "systemctl start ufw && systemctl enable ufw" "Starting & enabling UFW"
            print_success "UFW started and enabled, but no ports were opened."
            ;;
        *)
            print_info "UFW will not be started or enabled."
            ;;
        esac
        ;;
    esac
}

setup_ssl() {
    print_step "12" "SETTING UP SSL CERTIFICATE"

    execute_with_loading "apt-get install -y certbot python3-certbot-nginx" "Installing Certbot"

    print_info "Obtaining SSL certificate for $DOMAIN..."

    cat >/etc/nginx/sites-available/temp-dezerx <<EOF
server {
    listen 80;
    server_name $DOMAIN;
    root /var/www/html;
    index index.html;
    
    location / {
        try_files \$uri \$uri/ =404;
    }
}
EOF

    ln -sf /etc/nginx/sites-available/temp-dezerx /etc/nginx/sites-enabled/temp-dezerx
    systemctl reload nginx

    if ! certbot certonly --nginx -d "$DOMAIN" --non-interactive --agree-tos --email "admin@$DOMAIN" --no-eff-email; then
        print_error "Failed to obtain SSL certificate"
        print_info "Please ensure:"
        print_info "1. Domain $DOMAIN points to this server"
        print_info "2. Port 80 and 443 are open"
        print_info "3. No firewall is blocking the connection"
        exit 1
    fi

    rm -f /etc/nginx/sites-enabled/temp-dezerx
    rm -f /etc/nginx/sites-available/temp-dezerx

    print_success "SSL certificate obtained successfully!"
}

setup_ssl_skip() {
    print_step "12" "SETTING UP SSL CERTIFICATE"

    print_warning "You selected HTTP. Skipping SSL certificate setup."
}

configure_nginx() {
    print_step "13" "CONFIGURING NGINX"

    print_info "Removing default Nginx configuration..."
    rm -f /etc/nginx/sites-available/default
    rm -f /etc/nginx/sites-enabled/default

    print_info "Creating DezerX Nginx configuration..."
    if [[ "$PROTOCOL" == "https" ]]; then
        cat >/etc/nginx/sites-available/dezerx.conf <<EOF
server {
    listen 80;
    server_name $DOMAIN;
    return 301 https://\$server_name\$request_uri;
}

server {
    listen 443 ssl http2;
    server_name $DOMAIN;

    root $INSTALL_DIR/public;
    index index.php;

    access_log /var/log/nginx/dezerx.app-access.log;
    error_log  /var/log/nginx/dezerx.app-error.log error;


    client_max_body_size 100m;
    client_body_timeout 120s;

    sendfile off;


    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;
    ssl_session_cache shared:SSL:10m;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers "ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384";
    ssl_prefer_server_ciphers on;

    add_header X-Content-Type-Options nosniff;
    add_header X-XSS-Protection "1; mode=block";
    add_header X-Robots-Tag none;
    add_header Content-Security-Policy "frame-ancestors 'self'";
    add_header X-Frame-Options DENY;
    add_header Referrer-Policy same-origin;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php$ {
        fastcgi_split_path_info ^(.+\.php)(/.+)$;
        fastcgi_pass unix:/run/php/php8.3-fpm.sock;
        fastcgi_index index.php;
        include fastcgi_params;
        fastcgi_param PHP_VALUE "upload_max_filesize = 100M \n post_max_size=100M";
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_param HTTP_PROXY "";
        fastcgi_intercept_errors off;
        fastcgi_buffer_size 16k;
        fastcgi_buffers 4 16k;
        fastcgi_connect_timeout 300;
        fastcgi_send_timeout 300;
        fastcgi_read_timeout 300;
        include /etc/nginx/fastcgi_params;
    }

    location ~ /\.ht {
        deny all;
    }
}
EOF
    else
        cat >/etc/nginx/sites-available/dezerx.conf <<EOF
server {
    listen 80;
    server_name $DOMAIN;
    return 301 http://\$server_name\$request_uri;
    
    root $INSTALL_DIR/public;
    index index.php;

    access_log /var/log/nginx/dezerx.app-access.log;
    error_log  /var/log/nginx/dezerx.app-error.log error;

    client_max_body_size 100m;
    client_body_timeout 120s;

    sendfile off;

    add_header X-Content-Type-Options nosniff;
    add_header X-XSS-Protection "1; mode=block";
    add_header X-Robots-Tag none;
    add_header Content-Security-Policy "frame-ancestors 'self'";
    add_header X-Frame-Options DENY;
    add_header Referrer-Policy same-origin;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php$ {
        fastcgi_split_path_info ^(.+\.php)(/.+)$;
        fastcgi_pass unix:/run/php/php8.3-fpm.sock;
        fastcgi_index index.php;
        include fastcgi_params;
        fastcgi_param PHP_VALUE "upload_max_filesize = 100M \n post_max_size=100M";
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_param HTTP_PROXY "";
        fastcgi_intercept_errors off;
        fastcgi_buffer_size 16k;
        fastcgi_buffers 4 16k;
        fastcgi_connect_timeout 300;
        fastcgi_send_timeout 300;
        fastcgi_read_timeout 300;
        include /etc/nginx/fastcgi_params;
    }

    location ~ /\.ht {
        deny all;
    }
}
EOF
    fi

    ln -sf /etc/nginx/sites-available/dezerx.conf /etc/nginx/sites-enabled/dezerx.conf

    if ! nginx -t >>"$LOG_FILE" 2>&1; then
        print_error "Nginx configuration test failed"
        exit 1
    fi

    execute_with_loading "systemctl restart nginx" "Restarting Nginx"

    print_success "Nginx configured successfully!"
}

install_nodejs_and_build() {
    if [[ "$OPERATION_MODE" == "install" ]]; then
        print_step "14" "INSTALLING NODE.JS AND BUILDING ASSETS"
    else
        print_step "8" "BUILDING ASSETS"
    fi

    if [[ "$OPERATION_MODE" == "install" ]]; then
        execute_with_loading "curl -fsSL https://deb.nodesource.com/setup_20.x | bash -" "Adding Node.js repository"
        execute_with_loading "apt-get install -y nodejs" "Installing Node.js 20.x"
    fi

    cd "$INSTALL_DIR"

    if [[ -f "package.json" ]]; then
        execute_with_loading "npm install" "Installing npm dependencies"
        execute_with_loading "npm run build" "Building production assets"
    else
        print_warning "package.json not found, skipping npm build"
    fi

    print_success "Assets built successfully!"
}

set_permissions() {
    if [[ "$OPERATION_MODE" == "install" ]]; then
        print_step "15" "SETTING FILE PERMISSIONS"
    else
        print_step "9" "SETTING FILE PERMISSIONS"
    fi

    execute_with_loading "chown -R www-data:www-data $INSTALL_DIR" "Setting ownership to www-data"
    execute_with_loading "chmod -R 755 $INSTALL_DIR" "Setting base permissions"
    execute_with_loading "chmod -R 775 $INSTALL_DIR/storage" "Setting storage permissions"
    execute_with_loading "chmod -R 775 $INSTALL_DIR/bootstrap/cache" "Setting cache permissions"

    if [[ "$OPERATION_MODE" == "update" ]]; then
        print_info "Applying additional permission fixes for update..."
        execute_with_loading "chown -R www-data:www-data $INSTALL_DIR/*" "Setting ownership on all files"
        execute_with_loading "chown -R www-data:www-data $INSTALL_DIR/.[^.]*" "Setting ownership on hidden files"
    fi

    print_success "File permissions set successfully!"
}

run_migrations() {
    if [[ "$OPERATION_MODE" == "install" ]]; then
        print_step "16" "RUNNING DATABASE MIGRATIONS"
    else
        print_step "10" "RUNNING DATABASE MIGRATIONS"
    fi

    cd "$INSTALL_DIR"

    set +e

    print_info "Running database migrations..."
    sudo -u www-data php artisan migrate --force >>"$LOG_FILE" 2>&1
    local migrate_exit_code=$?

    if [ $migrate_exit_code -ne 0 ]; then
        print_error "Database migration failed!"
        print_error "Migration error details:"
        tail -20 "$LOG_FILE" | grep -A 10 -B 10 "migrate"

        if [[ "$OPERATION_MODE" == "update" ]]; then
            if [[ "$RESTORE_ON_FAILURE" == "yes" ]]; then
                print_error "Restoring backup due to migration failure..."
                restore_backup
            else
                print_warning "Restore on failure is disabled, skipping backup restore..."
            fi
        fi
        exit 1
    fi

    print_success "Database migrations completed successfully!"

    print_info "Running database seeders..."
    sudo -u www-data php artisan db:seed --force >>"$LOG_FILE" 2>&1
    local seed_exit_code=$?

    if [ $seed_exit_code -ne 0 ]; then
        print_error "Database seeding failed!"
        print_error "Seeding error details:"
        tail -20 "$LOG_FILE" | grep -A 10 -B 10 "seed"

        if [[ "$OPERATION_MODE" == "update" ]]; then
            if [[ "$RESTORE_ON_FAILURE" == "yes" ]]; then
                print_error "Restoring backup due to seeding failure..."
                restore_backup
            else
                print_error "Restore on failure is disabled, skipping backup restore..."
            fi
        fi
        exit 1
    fi

    print_success "Database seeders completed successfully!"

    print_info "Verifying file permissions after database operations..."
    chown -R www-data:www-data "$INSTALL_DIR" 2>/dev/null || true

    set -e
}

setup_cron() {
    print_step "17" "SETTING UP CRON JOBS"

    print_info "Adding Laravel scheduler to crontab..."

    local temp_cron_file=$(mktemp)

    if crontab -u www-data -l >"$temp_cron_file" 2>/dev/null; then
        print_info "Found existing crontab for www-data user"
    else
        print_info "No existing crontab for www-data user, creating new one"
        >"$temp_cron_file"
    fi

    if ! grep -q "artisan schedule:run" "$temp_cron_file"; then
        echo "* * * * * cd $INSTALL_DIR && php artisan schedule:run >> /dev/null 2>&1" >>"$temp_cron_file"
        if crontab -u www-data "$temp_cron_file"; then
            print_success "Laravel scheduler added to crontab successfully!"
        else
            print_error "Failed to install crontab for www-data user"
            rm -f "$temp_cron_file"
            exit 1
        fi
    else
        print_info "Laravel scheduler already exists in crontab"
    fi

    rm -f "$temp_cron_file"

    # Add certbot renewal cronjob only if https is selected and certbot is installed
    if [[ "$PROTOCOL" == "https" ]] && command -v certbot &>/dev/null; then
        if ! crontab -l 2>/dev/null | grep -q 'certbot renew --quiet --deploy-hook "systemctl restart nginx"'; then
            (
                crontab -l 2>/dev/null
                echo '0 23 * * * certbot renew --quiet --deploy-hook "systemctl restart nginx"'
            ) | crontab -
            print_success "Added SSL renewal cronjob for certbot."
        else
            print_info "SSL renewal cronjob for certbot already exists."
        fi
    fi

    if systemctl is-active --quiet cron; then
        print_success "Cron service is running"
    else
        print_warning "Cron service is not running, attempting to start..."
        if systemctl start cron; then
            print_success "Cron service started successfully"
        else
            print_error "Failed to start cron service"
            exit 1
        fi
    fi

    print_success "Cron job setup completed successfully!"
}

setup_queue_worker() {
    print_step "18" "SETTING UP QUEUE WORKER SERVICE"

    print_info "Creating systemd service for queue worker..."
    cat >/etc/systemd/system/dezerx.service <<EOF
[Unit]
Description=Laravel Queue Worker for DezerX
After=network.target

[Service]
User=www-data
Group=www-data
WorkingDirectory=$INSTALL_DIR
ExecStart=/usr/bin/php $INSTALL_DIR/artisan queue:work --queue=critical,virtfusion,high,medium,default,low --sleep=3 --tries=3 
Restart=always
RestartSec=5
StartLimitBurst=3
StartLimitIntervalSec=60
StandardOutput=syslog
StandardError=syslog
SyslogIdentifier=dezerx-worker

[Install]
WantedBy=multi-user.target
EOF

    execute_with_loading "systemctl daemon-reload" "Reloading systemd daemon"
    execute_with_loading "systemctl enable dezerx.service" "Enabling DezerX service"
    execute_with_loading "systemctl start dezerx.service" "Starting DezerX service"

    print_success "Queue worker service configured successfully!"
}

cleanup_backup() {
    if [[ "$OPERATION_MODE" == "update" && -n "$BACKUP_DIR" && -d "$BACKUP_DIR" ]]; then
        print_info "Final permission check after successful update..."
        chown -R www-data:www-data "$INSTALL_DIR" 2>/dev/null || true
        chmod -R 755 "$INSTALL_DIR" 2>/dev/null || true
        chmod -R 775 "$INSTALL_DIR/storage" 2>/dev/null || true
        chmod -R 775 "$INSTALL_DIR/bootstrap/cache" 2>/dev/null || true

        print_info "Cleaning up backup directory..."
        rm -rf "$BACKUP_DIR"
        print_success "Backup cleanup completed"
    fi
}

print_summary() {
    if [[ "$OPERATION_MODE" == "install" ]]; then
        print_step "19" "INSTALLATION COMPLETE"

        print_color $GREEN "╔══════════════════════════════════════════════════════════════╗"
        print_color $GREEN "║                                                              ║"
        print_color $GREEN "║                 🎉 INSTALLATION SUCCESSFUL! 🎉              ║"
        print_color $GREEN "║                                                              ║"
        print_color $GREEN "╚══════════════════════════════════════════════════════════════╝"

        print_success "DezerX has been successfully installed!"

        echo ""
        print_color $CYAN "📊 INSTALLATION DETAILS:"
        print_info "🌐 URL: ${BOLD}${PROTOCOL}//$DOMAIN${NC}"
        print_info "📁 Directory: ${BOLD}$INSTALL_DIR${NC}"
        print_info "🗄️  Database: ${BOLD}$DB_FULL_NAME${NC}"
        print_info "👤 DB User: ${BOLD}$DB_USER_FULL${NC}"
        print_info "🔐 DB Password: ${BOLD}$DB_PASSWORD${NC}"
        print_info "🔑 License Key: ${BOLD}${LICENSE_KEY:0:8}***${NC}"

        echo ""
        print_color $YELLOW "📋 NEXT STEPS:"
        print_info "1. Visit ${PROTOCOL}://$DOMAIN to access your DezerX installation"
        print_info "2. Complete the initial setup wizard"
        print_info "3. Configure your application settings"
    else
        print_step "11" "UPDATE COMPLETE"

        print_color $GREEN "╔══════════════════════════════════════════════════════════════╗"
        print_color $GREEN "║                                                              ║"
        print_color $GREEN "║                      🎉 UPDATE SUCCESSFUL! 🎉               ║"
        print_color $GREEN "║                                                              ║"
        print_color $GREEN "╚══════════════════════════════════════════════════════════════╝"

        print_success "DezerX has been successfully updated!"

        echo ""
        print_color $CYAN "📊 UPDATE DETAILS:"
        print_info "🌐 URL: ${BOLD}${PROTOCOL}://$DOMAIN${NC}"
        print_info "📁 Directory: ${BOLD}$INSTALL_DIR${NC}"
        print_info "🗄️  Database: ${BOLD}$DB_FULL_NAME${NC}"
        print_info "👤 DB User: ${BOLD}$DB_USER_FULL${NC}"
        print_info "🔑 License Key: ${BOLD}${LICENSE_KEY:0:8}***${NC}"

        echo ""
        print_color $YELLOW "📋 NEXT STEPS:"
        print_info "1. Visit ${PROTOCOL}://$DOMAIN to verify your updated installation"
        print_info "2. Check that all features are working correctly"
        print_info "3. Clear any browser cache if needed"
    fi

    echo ""
    print_color $YELLOW "🔧 USEFUL COMMANDS:"
    print_info "• Check queue worker: systemctl status dezerx"
    print_info "• Restart queue worker: systemctl restart dezerx"
    print_info "• View app logs: tail -f $INSTALL_DIR/storage/logs/laravel.log"
    print_info "• Restart Nginx: systemctl restart nginx"
    print_info "• View operation log: cat $LOG_FILE"
    print_info "• Check cron jobs: crontab -u www-data -l"
    print_info "• View .env file: cat $INSTALL_DIR/.env"

    echo ""
    print_color $CYAN "💡 SUPPORT:"
    print_info "📚 Documentation: https://docs.dezerx.com"
    print_info "🎫 Support: https://support.dezerx.com"

    echo ""
    print_color $GREEN "🚀 Thank you for choosing DezerX!"

    if [[ "$OPERATION_MODE" == "install" ]]; then
        cat >"$INSTALL_DIR/INSTALLATION_INFO.txt" <<EOF
DezerX Installation Information
==============================
Installation Date: $(date)
Domain: $DOMAIN
Full URL: ${PROTOCOL}://$DOMAIN
Installation Directory: $INSTALL_DIR
Database Name: $DB_FULL_NAME
Database User: $DB_USER_FULL
Database Password: $DB_PASSWORD
License Key: $LICENSE_KEY
Installation Log: $LOG_FILE

Access your installation at: ${PROTOCOL}://$DOMAIN

Useful Commands:
- Check queue worker: systemctl status dezerx
- Restart queue worker: systemctl restart dezerx
- View app logs: tail -f $INSTALL_DIR/storage/logs/laravel.log
- Restart Nginx: systemctl restart nginx
- Check cron jobs: crontab -u www-data -l
- View .env file: cat $INSTALL_DIR/.env
EOF
    else
        cat >"$INSTALL_DIR/UPDATE_INFO.txt" <<EOF
DezerX Update Information
========================
Update Date: $(date)
Domain: $DOMAIN
Full URL: ${PROTOCOL}://$DOMAIN
Installation Directory: $INSTALL_DIR
License Key: $LICENSE_KEY
Update Log: $LOG_FILE

Access your installation at: ${PROTOCOL}://$DOMAIN

Useful Commands:
- Check queue worker: systemctl status dezerx
- Restart queue worker: systemctl restart dezerx
- View app logs: tail -f $INSTALL_DIR/storage/logs/laravel.log
- Restart Nginx: systemctl restart nginx
- Check cron jobs: crontab -u www-data -l
- View .env file: cat $INSTALL_DIR/.env
EOF
    fi

    print_info "💾 Operation details saved to: $INSTALL_DIR/$(if [[ "$OPERATION_MODE" == "install" ]]; then echo "INSTALLATION_INFO.txt"; else echo "UPDATE_INFO.txt"; fi)"
}

show_contributors() {
    print_color $CYAN "=============================================================="
    print_color $CYAN "        DezerX Install / Update Script"
    print_color $CYAN "  Main script development and major contributions by:"
    print_color $YELLOW "  👑 Anthony S and 👑 KingIronMan2011"
    print_color $CYAN "=============================================================="
    echo ""
}

cleanup_on_error() {
    print_error "Operation failed at line $1"
    print_info "Check the operation log: $LOG_FILE"

    if [[ "$OPERATION_MODE" == "update" && "$RESTORE_ON_FAILURE" == "yes" ]]; then
        print_error "Attempting to restore from backup..."
        restore_backup
        restore_database
        print_info "Backup restore attempted."
    else
        print_info "You may need to clean up partially installed components manually."
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
        prompt_ufw_firewall
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
    show_contributors
    log_message "Operation completed successfully"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
