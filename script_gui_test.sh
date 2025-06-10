#!/bin/bash
set -euo pipefail

readonly SCRIPT_VERSION="2.0"
LOG_FILE="/tmp/dezerx-install.log"
OPERATION_MODE=""
LICENSE_KEY=""
DOMAIN=""
INSTALL_DIR=""
DB_PASSWORD=""
DB_NAME_PREFIX=""
DB_FULL_NAME=""
DB_USER_FULL=""
RESTORE_ON_FAILURE=""
PROTOCOL="https"
BACKUP_DIR=""
DB_BACKUP_FILE=""

print_banner() {
    whiptail --title "DezerX Installer" --msgbox "██████╗ ███████╗███████╗███████╗██████╗ ██╗  ██╗
██╔══██╗██╔════╝╚══███╔╝██╔════╝██╔══██╗╚██╗██╔╝
██║  ██║█████╗    ███╔╝ █████╗  ██████╔╝ ╚███╔╝ 
██║  ██║██╔══╝   ███╔╝  ██╔══╝  ██╔══██╗ ██╔██╗ 
██████╔╝███████╗███████╗███████╗██║  ██║██╔╝ ██╗
╚═════╝ ╚══════╝╚══════╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝

INSTALLATION & UPDATE SCRIPT v${SCRIPT_VERSION}
Requires Root Access

This script can install or update DezerX.
Estimated time: 3-6 minutes (install) / 3-5 minutes (update)
Operation log: $LOG_FILE" 20 70
}

log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >>"$LOG_FILE"
}

show_loading() {
    local pid=$1
    local message=$2
    local i=0
    while kill -0 "$pid" 2>/dev/null; do
        case $((i % 4)) in
            0) echo -n " [|] $message" ;;
            1) echo -n " [/] $message" ;;
            2) echo -n " [-] $message" ;;
            3) echo -n " [\\] $message" ;;
        esac
        sleep 0.5
        echo -ne "\r"
        i=$((i+1))
    done
    echo " [✓] $message - Complete"
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
        whiptail --title "Error" --msgbox "Command failed: $command\nCheck log file: $LOG_FILE" 12 70
        exit $exit_code
    fi
    return $exit_code
}

check_required_commands() {
    local cmds=(curl awk grep sed whiptail)
    for cmd in "${cmds[@]}"; do
        if ! command -v "$cmd" &>/dev/null; then
            whiptail --title "Error" --msgbox "Required command '$cmd' not found. Please install it." 10 60
            exit 1
        fi
    done
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        whiptail --title "Error" --msgbox "This script must be run as root!\n\nPlease run: sudo $0" 10 60
        exit 1
    fi
}

choose_operation_mode() {
    local choice
    choice=$(whiptail --title "DezerX Installer" --menu "What would you like to do?" 18 70 10 \
        "1" "🆕 Fresh Installation - Install DezerX from scratch" \
        "2" "🔄 Update Existing - Update an existing DezerX installation" \
        "3" "⚠️  Delete Installation - Remove DezerX and all its data ⚠️" 3>&1 1>&2 2>&3)
    
    case $choice in
        1) 
            OPERATION_MODE="install"
            if whiptail --title "Backup Option" --yesno "Would you like to automatically restore the previous backup if an error occurs?\n\nThe non-automatic restore feature is intended for developers and testing environments only." 12 70; then
                RESTORE_ON_FAILURE="yes"
            else
                RESTORE_ON_FAILURE="no"
            fi
            ;;
        2) 
            OPERATION_MODE="update"
            if whiptail --title "Backup Option" --yesno "Would you like to automatically restore the previous backup if an error occurs?\n\nThe non-automatic restore feature is intended for developers and testing environments only." 12 70; then
                RESTORE_ON_FAILURE="yes"
            else
                RESTORE_ON_FAILURE="no"
            fi
            ;;
        3) 
            OPERATION_MODE="delete"
            handle_deletion
            ;;
        *)
            whiptail --title "Error" --msgbox "Invalid choice. Exiting." 10 60
            exit 1
            ;;
    esac
}

handle_deletion() {
    if ! whiptail --title "Delete Confirmation" --yesno "This will remove DezerX and all its data permanently!\n\nAre you absolutely sure you want to continue?" 12 70; then
        whiptail --title "Cancelled" --msgbox "Deletion cancelled by user." 10 60
        exit 0
    fi

    INSTALL_DIR=$(whiptail --title "Installation Directory" --inputbox "Enter the DezerX installation directory to delete:" 10 60 "/var/www/DezerX" 3>&1 1>&2 2>&3)
    if [[ -z "$INSTALL_DIR" ]]; then
        INSTALL_DIR="/var/www/DezerX"
    fi

    if [[ ! -d "$INSTALL_DIR" ]]; then
        whiptail --title "Error" --msgbox "Directory $INSTALL_DIR does not exist. Aborting deletion." 10 60
        exit 1
    fi

    local confirmation_text=$(whiptail --title "Final Confirmation" --inputbox "Type 'DELETE EVERYTHING' to confirm deletion of $INSTALL_DIR:" 10 70 "" 3>&1 1>&2 2>&3)
    if [[ "$confirmation_text" != "DELETE EVERYTHING" ]]; then
        whiptail --title "Cancelled" --msgbox "Deletion cancelled - confirmation text did not match." 10 60
        exit 0
    fi

    perform_deletion
}

perform_deletion() {
    whiptail --title "Deleting" --infobox "Removing DezerX installation..." 10 60
    
    # Load DB info from .env if available
    if [[ -f "$INSTALL_DIR/.env" ]]; then
        DB_FULL_NAME=$(grep '^DB_DATABASE=' "$INSTALL_DIR/.env" | cut -d '=' -f2- | tr -d '"' || echo "")
        DB_USER_FULL=$(grep '^DB_USERNAME=' "$INSTALL_DIR/.env" | cut -d '=' -f2- | tr -d '"' || echo "")
    fi

    # Remove Nginx config
    rm -f /etc/nginx/sites-enabled/dezerx.conf 2>>"$LOG_FILE" || true
    rm -f /etc/nginx/sites-available/dezerx.conf 2>>"$LOG_FILE" || true
    systemctl reload nginx 2>>"$LOG_FILE" || true

    # Remove installation directory
    if [[ -d "$INSTALL_DIR" ]]; then
        rm -rf "$INSTALL_DIR" 2>>"$LOG_FILE" || true
    fi

    # Remove database and user if possible
    if command -v mariadb &>/dev/null && [[ -n "$DB_FULL_NAME" ]]; then
        mariadb -e "DROP DATABASE IF EXISTS \`$DB_FULL_NAME\`;" 2>>"$LOG_FILE" || true
    fi
    if command -v mariadb &>/dev/null && [[ -n "$DB_USER_FULL" ]]; then
        mariadb -e "DROP USER IF EXISTS '$DB_USER_FULL'@'127.0.0.1';" 2>>"$LOG_FILE" || true
    fi

    # Stop and disable queue worker
    systemctl stop dezerx.service 2>>"$LOG_FILE" || true
    systemctl disable dezerx.service 2>>"$LOG_FILE" || true
    rm -f /etc/systemd/system/dezerx.service 2>>"$LOG_FILE" || true

    whiptail --title "Complete" --msgbox "DezerX and all related data have been deleted successfully." 10 60
    exit 0
}

check_system_requirements() {
    whiptail --title "System Check" --infobox "Checking system requirements..." 10 60

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

    if [[ "$os_name" != "Ubuntu" ]] && [[ "$os_name" != "Debian" ]]; then
        whiptail --title "Error" --msgbox "This script only supports Ubuntu and Debian\nDetected: $os_name $os_version" 10 60
        exit 1
    fi

    local available_space=$(df / | awk 'NR==2 {print $4}')
    local required_space=5242880
    if [[ "$OPERATION_MODE" == "update" ]]; then
        required_space=2097152
    fi

    if [[ $available_space -lt $required_space ]]; then
        whiptail --title "Error" --msgbox "Insufficient disk space.\nRequired: $((required_space / 1024 / 1024))GB\nAvailable: $((available_space / 1024 / 1024))GB" 10 60
        exit 1
    fi

    local total_mem=$(free -m | awk 'NR==2{print $2}')
    if [[ $total_mem -lt 1024 ]]; then
        whiptail --title "Warning" --msgbox "Low memory detected: ${total_mem}MB\nRecommended: 2GB+\n\nContinuing anyway..." 10 60
    fi

    # Check dependency versions
    local version_warnings=""
    if command -v php &>/dev/null; then
        local php_version=$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;')
        if [[ $(echo "$php_version < 8.1" | bc 2>/dev/null || echo 1) -eq 1 ]]; then
            version_warnings+="PHP $php_version (recommended: 8.1+)\n"
        fi
    fi

    if command -v mariadb &>/dev/null; then
        local mariadb_version=$(mariadb --version | grep -oP 'Ver \K[0-9]+\.[0-9]+' | head -1)
        if [[ -n "$mariadb_version" && $(echo "$mariadb_version < 10.5" | bc 2>/dev/null || echo 1) -eq 1 ]]; then
            version_warnings+="MariaDB $mariadb_version (recommended: 10.5+)\n"
        fi
    fi

    if [[ -n "$version_warnings" ]]; then
        whiptail --title "Version Warnings" --msgbox "Some dependencies may be outdated:\n\n$version_warnings\nInstallation will continue..." 12 70
    fi

    whiptail --title "System Check" --msgbox "System requirements check passed!\n\nOS: $os_name $os_version\nMemory: ${total_mem}MB\nDisk Space: $((available_space / 1024 / 1024))GB available" 12 60
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

get_install_input() {
    while true; do
        LICENSE_KEY=$(whiptail --title "License Key" --inputbox "Enter your DezerX license key:" 10 60 "" 3>&1 1>&2 2>&3)
        if [[ -n "$LICENSE_KEY" && ${#LICENSE_KEY} -ge 10 ]]; then
            break
        else
            whiptail --title "Error" --msgbox "License key must be at least 10 characters. Please try again." 10 60
        fi
    done

    while true; do
        DOMAIN=$(whiptail --title "Domain" --inputbox "Enter your domain or subdomain:\n(e.g., example.com or app.example.com)\n\nDo NOT include http:// or https://" 12 70 "" 3>&1 1>&2 2>&3)
        if [[ -z "$DOMAIN" ]]; then
            whiptail --title "Error" --msgbox "Domain cannot be empty." 10 60
            continue
        fi

        validate_domain "$DOMAIN"
        local validation_result=$?
        if [[ $validation_result -eq 2 ]]; then
            whiptail --title "Error" --msgbox "Please enter the domain WITHOUT http:// or https://\n\nExample: Use 'example.com' instead of 'https://example.com'" 10 70
            continue
        elif [[ $validation_result -eq 1 ]]; then
            whiptail --title "Error" --msgbox "Invalid domain format. Please try again." 10 60
            continue
        else
            break
        fi
    done

    PROTOCOL=$(whiptail --title "Protocol" --radiolist "Choose protocol:" 12 60 2 \
        "https" "HTTPS - Secure (recommended)" ON \
        "http" "HTTP - Insecure" OFF 3>&1 1>&2 2>&3)

    INSTALL_DIR=$(whiptail --title "Install Directory" --inputbox "Enter installation directory:" 10 60 "/var/www/DezerX" 3>&1 1>&2 2>&3)
    if [[ -z "$INSTALL_DIR" ]]; then
        INSTALL_DIR="/var/www/DezerX"
    fi

    DB_NAME_PREFIX=$(echo "$DOMAIN" | grep -o '^[a-zA-Z]*' | tr '[:upper:]' '[:lower:]' | cut -c1-4)
    if [[ -z "$DB_NAME_PREFIX" ]]; then
        DB_NAME_PREFIX="dzrx"
    fi

    DB_FULL_NAME=$(whiptail --title "Database Name" --inputbox "Database name:" 10 60 "${DB_NAME_PREFIX}_dezerx" 3>&1 1>&2 2>&3)
    if [[ -z "$DB_FULL_NAME" ]]; then
        DB_FULL_NAME="${DB_NAME_PREFIX}_dezerx"
    fi

    DB_USER_FULL=$(whiptail --title "Database User" --inputbox "Database user:" 10 60 "${DB_NAME_PREFIX}_dezer" 3>&1 1>&2 2>&3)
    if [[ -z "$DB_USER_FULL" ]]; then
        DB_USER_FULL="${DB_NAME_PREFIX}_dezer"
    fi

    DB_PASSWORD=$(whiptail --title "Database Password" --passwordbox "Database password (leave blank to auto-generate):" 10 60 "" 3>&1 1>&2 2>&3)
    if [[ -z "$DB_PASSWORD" ]]; then
        DB_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)
    fi

    whiptail --title "Installation Summary" --yesno "Please confirm your installation settings:\n\nLicense Key: ${LICENSE_KEY:0:8}***\nDomain: $DOMAIN\nProtocol: $PROTOCOL\nFull URL: ${PROTOCOL}://$DOMAIN\nInstall Directory: $INSTALL_DIR\nDatabase: $DB_FULL_NAME\nDB User: $DB_USER_FULL\n\nProceed with installation?" 18 70
    if [ $? -ne 0 ]; then
        whiptail --title "Cancelled" --msgbox "Installation cancelled by user." 10 60
        exit 0
    fi
}

get_update_input() {
    while true; do
        LICENSE_KEY=$(whiptail --title "License Key" --inputbox "Enter your DezerX license key:" 10 60 "" 3>&1 1>&2 2>&3)
        if [[ -n "$LICENSE_KEY" && ${#LICENSE_KEY} -ge 10 ]]; then
            break
        else
            whiptail --title "Error" --msgbox "License key must be at least 10 characters. Please try again." 10 60
        fi
    done

    while true; do
        DOMAIN=$(whiptail --title "Domain" --inputbox "Enter your domain:\n(e.g., example.com or app.example.com)\n\nDo NOT include http:// or https://" 12 70 "" 3>&1 1>&2 2>&3)
        if [[ -z "$DOMAIN" ]]; then
            whiptail --title "Error" --msgbox "Domain cannot be empty." 10 60
            continue
        fi

        validate_domain "$DOMAIN"
        local validation_result=$?
        if [[ $validation_result -eq 2 ]]; then
            whiptail --title "Error" --msgbox "Please enter the domain WITHOUT http:// or https://\n\nExample: Use 'example.com' instead of 'https://example.com'" 10 70
            continue
        elif [[ $validation_result -eq 1 ]]; then
            whiptail --title "Error" --msgbox "Invalid domain format. Please try again." 10 60
            continue
        else
            break
        fi
    done

    PROTOCOL=$(whiptail --title "Protocol" --radiolist "Choose protocol:" 12 60 2 \
        "https" "HTTPS - Secure (recommended)" ON \
        "http" "HTTP - Insecure" OFF 3>&1 1>&2 2>&3)

    while true; do
        INSTALL_DIR=$(whiptail --title "Installation Directory" --inputbox "Enter your existing DezerX directory:" 10 60 "/var/www/DezerX" 3>&1 1>&2 2>&3)
        if [[ -z "$INSTALL_DIR" ]]; then
            INSTALL_DIR="/var/www/DezerX"
        fi

        if [[ ! -d "$INSTALL_DIR" ]]; then
            whiptail --title "Error" --msgbox "Directory $INSTALL_DIR does not exist. Please check the path." 10 60
            continue
        fi

        if [[ ! -f "$INSTALL_DIR/.env" ]]; then
            whiptail --title "Error" --msgbox "No .env file found in $INSTALL_DIR.\nThis doesn't appear to be a DezerX installation." 10 70
            continue
        fi

        if [[ ! -f "$INSTALL_DIR/artisan" ]]; then
            whiptail --title "Error" --msgbox "No artisan file found in $INSTALL_DIR.\nThis doesn't appear to be a Laravel/DezerX installation." 10 70
            continue
        fi
        break
    done

    whiptail --title "Update Summary" --yesno "Please confirm your update settings:\n\nLicense Key: ${LICENSE_KEY:0:8}***\nDomain: $DOMAIN\nProtocol: $PROTOCOL\nExisting Directory: $INSTALL_DIR\n\nProceed with update?" 15 70
    if [ $? -ne 0 ]; then
        whiptail --title "Cancelled" --msgbox "Update cancelled by user." 10 60
        exit 0
    fi
}

verify_license() {
    whiptail --title "License Verification" --infobox "Contacting DezerX license server..." 10 60

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
        whiptail --title "Success" --msgbox "License verified successfully!" 10 60
        rm -f "$temp_file"
        return 0
    else
        local error_msg="Unknown error"
        if [[ -f "$temp_file" ]]; then
            error_msg=$(cat "$temp_file" 2>/dev/null || echo "Unknown error")
        fi
        whiptail --title "License Error" --msgbox "License verification failed (HTTP: $http_code)\n\nServer response: $error_msg\n\nPlease check your license key and domain." 15 70
        rm -f "$temp_file"
        exit 1
    fi
}

create_backup() {
    whiptail --title "Creating Backup" --infobox "Creating backup of existing installation..." 10 60

    BACKUP_DIR="/tmp/dezerx-backup-$(date +%Y%m%d-%H%M%S)"
    execute_with_loading "cp -r $INSTALL_DIR $BACKUP_DIR" "Creating backup"

    if [[ ! -f "$BACKUP_DIR/.env" ]]; then
        whiptail --title "Error" --msgbox "Backup verification failed - .env file not found in backup" 10 60
        exit 1
    fi

    whiptail --title "Backup Complete" --msgbox "Backup created successfully!\n\nLocation: $BACKUP_DIR" 10 70
}

backup_database() {
    whiptail --title "Database Backup" --infobox "Backing up database..." 10 60

    local env_file="$INSTALL_DIR/.env"
    if [[ ! -f "$env_file" ]]; then
        whiptail --title "Warning" --msgbox ".env file not found. Skipping database backup." 10 60
        return 0
    fi

    local db_connection=$(grep '^DB_CONNECTION=' "$env_file" | cut -d '=' -f2- | tr -d '"' || echo "")
    local db_host=$(grep '^DB_HOST=' "$env_file" | cut -d '=' -f2- | tr -d '"' || echo "")
    local db_database=$(grep '^DB_DATABASE=' "$env_file" | cut -d '=' -f2- | tr -d '"' || echo "")
    local db_username=$(grep '^DB_USERNAME=' "$env_file" | cut -d '=' -f2- | tr -d '"' || echo "")
    local db_password=$(grep '^DB_PASSWORD=' "$env_file" | cut -d '=' -f2- | tr -d '"' || echo "")

    if [[ "$db_connection" != "mysql" ]]; then
        whiptail --title "Warning" --msgbox "Database connection is not 'mysql'. Skipping database backup." 10 60
        return 0
    fi

    if [[ -z "$db_host" || -z "$db_database" || -z "$db_username" ]]; then
        whiptail --title "Error" --msgbox "Missing database credentials in .env file. Cannot perform database backup." 10 60
        exit 1
    fi

    BACKUP_DIR="/tmp/dezerx-backup-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$BACKUP_DIR"
    DB_BACKUP_FILE="$BACKUP_DIR/database_$(date +%Y%m%d-%H%M%S).sql.gz"

    export MYSQL_PWD="$db_password"
    local mysqldump_cmd="mysqldump -h $db_host -u $db_username $db_database | gzip > \"$DB_BACKUP_FILE\""

    if ! command -v mysqldump &>/dev/null; then
        whiptail --title "Error" --msgbox "mysqldump command not found. Cannot perform database backup." 10 60
        unset MYSQL_PWD
        exit 1
    fi

    execute_with_loading "$mysqldump_cmd" "Creating database backup"
    unset MYSQL_PWD

    if [[ ! -s "$DB_BACKUP_FILE" ]]; then
        whiptail --title "Error" --msgbox "Database backup file is empty or not created!" 10 60
        return 1
    fi

    whiptail --title "Database Backup" --msgbox "Database backup completed successfully!\n\nLocation: $DB_BACKUP_FILE" 12 70
}

restore_backup() {
    whiptail --title "Restoring Backup" --infobox "Restoring from backup due to update failure..." 10 60

    if [[ -n "$BACKUP_DIR" && -d "$BACKUP_DIR" ]]; then
        rm -rf "$INSTALL_DIR"
        mv "$BACKUP_DIR" "$INSTALL_DIR"
        chown -R www-data:www-data "$INSTALL_DIR" 2>/dev/null || true
        chmod -R 755 "$INSTALL_DIR" 2>/dev/null || true
        chmod -R 775 "$INSTALL_DIR/storage" 2>/dev/null || true
        chmod -R 775 "$INSTALL_DIR/bootstrap/cache" 2>/dev/null || true
        whiptail --title "Backup Restored" --msgbox "Backup restored successfully!\nYour original installation has been restored." 10 60
    else
        whiptail --title "Error" --msgbox "No backup found to restore from!" 10 60
    fi
}

install_dependencies() {
    whiptail --title "Installing Dependencies" --infobox "Installing system dependencies..." 10 60

    execute_with_loading "apt-get update" "Updating package lists"
    execute_with_loading "DEBIAN_FRONTEND=noninteractive apt-get upgrade -y" "Upgrading system packages"
    execute_with_loading "apt-get install -y software-properties-common curl apt-transport-https ca-certificates gnupg lsb-release wget unzip git cron" "Installing basic dependencies"

    # Add repositories
    if ! LC_ALL=C.UTF-8 add-apt-repository -y ppa:ondrej/php >>"$LOG_FILE" 2>&1; then
        whiptail --title "Warning" --msgbox "Failed to add PHP PPA, trying alternative method..." 10 60
    fi

    curl -fsSL https://packages.redis.io/gpg | gpg --dearmor >/usr/share/keyrings/redis-archive-keyring.gpg 2>/dev/null
    echo "deb [signed-by=/usr/share/keyrings/redis-archive-keyring.gpg] https://packages.redis.io/deb $(lsb_release -cs) main" >/etc/apt/sources.list.d/redis.list

    curl -LsS https://r.mariadb.com/downloads/mariadb_repo_setup | bash >>"$LOG_FILE" 2>&1

    execute_with_loading "apt-get update" "Updating package lists with new repositories"

    local packages="nginx php8.3 php8.3-common php8.3-cli php8.3-gd php8.3-mysql php8.3-mbstring php8.3-bcmath php8.3-xml php8.3-fpm php8.3-curl php8.3-zip mariadb-server tar unzip git redis-server ufw"
    execute_with_loading "DEBIAN_FRONTEND=noninteractive apt-get install -y $packages" "Installing main packages"

    execute_with_loading "systemctl start nginx && systemctl enable nginx" "Starting Nginx"
    execute_with_loading "systemctl start php8.3-fpm && systemctl enable php8.3-fpm" "Starting PHP-FPM"
    execute_with_loading "systemctl start redis-server && systemctl enable redis-server" "Starting Redis"
    execute_with_loading "systemctl start cron && systemctl enable cron" "Starting Cron"
    execute_with_loading "systemctl stop ufw && systemctl disable ufw" "Stopping UFW for configuration"

    execute_with_loading "mkdir -p /var/www" "Creating web directory"

    whiptail --title "Dependencies" --msgbox "System dependencies installed successfully!" 10 60
}

install_composer() {
    whiptail --title "Installing Composer" --infobox "Installing Composer..." 10 60

    local composer_installer="/tmp/composer-installer.php"
    execute_with_loading "curl -sS https://getcomposer.org/installer -o $composer_installer" "Downloading Composer"
    execute_with_loading "php $composer_installer --install-dir=/usr/local/bin --filename=composer" "Installing Composer"

    rm -f "$composer_installer"

    if ! command -v composer &>/dev/null; then
        whiptail --title "Error" --msgbox "Composer installation failed" 10 60
        exit 1
    fi

    whiptail --title "Composer" --msgbox "Composer installed successfully!" 10 60
}

setup_database() {
    whiptail --title "Setting up Database" --infobox "Configuring MariaDB..." 10 60

    execute_with_loading "systemctl start mariadb && systemctl enable mariadb" "Starting MariaDB"

    # Secure MariaDB
    local sql_file=$(mktemp)
    cat >"$sql_file" <<'EOF'
DROP USER IF EXISTS ''@'%';
DROP USER IF EXISTS ''@'localhost';
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test_%';
FLUSH PRIVILEGES;
EOF

    if ! mariadb <"$sql_file" >>"$LOG_FILE" 2>&1; then
        whiptail --title "Error" --msgbox "Failed to secure MariaDB installation" 10 60
        rm -f "$sql_file"
        exit 1
    fi

    # Create database and user
    cat >"$sql_file" <<EOF
CREATE DATABASE IF NOT EXISTS \`$DB_FULL_NAME\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '$DB_USER_FULL'@'127.0.0.1' IDENTIFIED BY '$DB_PASSWORD';
GRANT ALL PRIVILEGES ON \`$DB_FULL_NAME\`.* TO '$DB_USER_FULL'@'127.0.0.1' WITH GRANT OPTION;
FLUSH PRIVILEGES;
EOF

    if ! mariadb <"$sql_file" >>"$LOG_FILE" 2>&1; then
        whiptail --title "Error" --msgbox "Failed to create database and user" 10 60
        rm -f "$sql_file"
        exit 1
    fi

    rm -f "$sql_file"
    whiptail --title "Database" --msgbox "Database setup completed successfully!\n\nDatabase: $DB_FULL_NAME\nUser: $DB_USER_FULL" 12 70
}

download_dezerx() {
    whiptail --title "Downloading DezerX" --infobox "Requesting download URL from DezerX servers..." 10 60

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
        local error_msg="Unknown error"
        if [[ -f "$temp_file" ]]; then
            error_msg=$(cat "$temp_file" 2>/dev/null || echo "Unknown error")
        fi
        whiptail --title "Download Error" --msgbox "Failed to get download URL (HTTP: $http_code)\n\nServer response: $error_msg" 12 70
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
        whiptail --title "Error" --msgbox "Failed to extract download URL from server response" 10 60
        if [[ "$OPERATION_MODE" == "update" ]]; then
            restore_backup
        fi
        exit 1
    fi

    if [[ "$OPERATION_MODE" == "install" ]]; then
        mkdir -p "$INSTALL_DIR"
    fi

    local download_file="/tmp/dezerx-$(date +%s).zip"
    whiptail --title "Downloading" --infobox "Downloading DezerX package..." 10 60

    if ! curl -L -o "$download_file" --progress-bar --connect-timeout 30 --max-time 300 "$download_url"; then
        whiptail --title "Error" --msgbox "Download failed" 10 60
        rm -f "$download_file"
        if [[ "$OPERATION_MODE" == "update" ]]; then
            restore_backup
        fi
        exit 1
    fi

    # Extract and install
    local temp_extract_dir=$(mktemp -d)
    if ! unzip -q "$download_file" -d "$temp_extract_dir"; then
        whiptail --title "Error" --msgbox "Failed to extract files" 10 60
        rm -f "$download_file"
        rm -rf "$temp_extract_dir"
        if [[ "$OPERATION_MODE" == "update" ]]; then
            restore_backup
        fi
        exit 1
    fi

    rm -f "$download_file"

    # Find DezerX directory
    local dezerx_source_dir=""
    local found_dirs=()
    while IFS= read -r -d '' dir; do
        found_dirs+=("$dir")
    done < <(find "$temp_extract_dir" -maxdepth 1 -type d -name "*DezerX*" -print0)

    if [[ ${#found_dirs[@]} -eq 0 ]]; then
        whiptail --title "Error" --msgbox "No DezerX directory found in the extracted archive" 10 60
        rm -rf "$temp_extract_dir"
        if [[ "$OPERATION_MODE" == "update" ]]; then
            restore_backup
        fi
        exit 1
    fi

    dezerx_source_dir="${found_dirs[0]}"
    if [[ ! -f "$dezerx_source_dir/.env.example" ]]; then
        whiptail --title "Error" --msgbox "Invalid DezerX package - .env.example not found" 10 60
        rm -rf "$temp_extract_dir"
        if [[ "$OPERATION_MODE" == "update" ]]; then
            restore_backup
        fi
        exit 1
    fi

    # Move files
    if [[ "$OPERATION_MODE" == "install" ]]; then
        rm -rf "$INSTALL_DIR"
        mkdir -p "$INSTALL_DIR"
        if ! mv "$dezerx_source_dir"/* "$INSTALL_DIR"/; then
            whiptail --title "Error" --msgbox "Failed to move DezerX files to installation directory" 10 60
            rm -rf "$temp_extract_dir"
            exit 1
        fi
        if ls "$dezerx_source_dir"/.[^.]* >/dev/null 2>&1; then
            for file in "$dezerx_source_dir"/.[^.]*; do
                mv "$file" "$INSTALL_DIR"/ 2>/dev/null || true
            done
        fi
    else
        if ! rsync -a --exclude='.env.example' --exclude='storage' "$dezerx_source_dir"/ "$INSTALL_DIR"/; then
            whiptail --title "Error" --msgbox "Failed to copy updated files to installation directory" 10 60
            rm -rf "$temp_extract_dir"
            restore_backup
            exit 1
        fi
    fi

    rm -rf "$temp_extract_dir"
    whiptail --title "Download Complete" --msgbox "DezerX files downloaded and extracted successfully!" 10 60
}

update_env_file() {
    local key="$1"
    local value="$2"
    local env_file="$3"

    if grep -q "^${key}=" "$env_file"; then
        if command -v perl >/dev/null 2>&1; then
            perl -i -pe "s|^${key}=.*|${key}=${value}|" "$env_file"
        else
            local temp_file=$(mktemp)
            grep -v "^${key}=" "$env_file" >"$temp_file"
            echo "${key}=${value}" >>"$temp_file"
            mv "$temp_file" "$env_file"
        fi
    else
        echo "${key}=${value}" >>"$env_file"
    fi
}

sync_env_files() {
    local install_dir="$1"
    local env_example_file="$install_dir/.env.example"
    local env_file="$install_dir/.env"

    if [[ ! -f "$env_example_file" ]] || [[ ! -f "$env_file" ]]; then
        return 0
    fi

    local env_example_lines
    mapfile -t env_example_lines <"$env_example_file"

    for line in "${env_example_lines[@]}"; do
        if [[ "$line" =~ ^[[:alnum:]_]+= ]]; then
            local key=$(echo "$line" | cut -d= -f1)
            if ! grep -q "^${key}=" "$env_file"; then
                printf "%s\n" "$line" >>"$env_file"
            fi
        fi
    done

    chown www-data:www-data "$env_file" 2>/dev/null || true
    chmod 644 "$env_file" 2>/dev/null || true
}

configure_laravel() {
    whiptail --title "Configuring Laravel" --infobox "Configuring Laravel application..." 10 60

    cd "$INSTALL_DIR"

    if [[ "$OPERATION_MODE" == "install" ]]; then
        if [[ ! -f ".env.example" ]]; then
            whiptail --title "Error" --msgbox ".env.example file not found in $INSTALL_DIR" 10 60
            exit 1
        fi
        execute_with_loading "cp .env.example .env" "Creating environment file"
    else
        if [[ ! -f ".env" ]]; then
            whiptail --title "Error" --msgbox ".env file not found in $INSTALL_DIR" 10 60
            restore_backup
            exit 1
        fi
        sync_env_files "$INSTALL_DIR"
    fi

    # Install composer dependencies
    whiptail --title "Composer" --infobox "Installing Composer dependencies..." 10 60
    echo "yes" | composer install --no-dev --optimize-autoloader >>"$LOG_FILE" 2>&1 &
    local composer_pid=$!
    show_loading $composer_pid "Installing Composer dependencies"
    wait $composer_pid
    if [ $? -ne 0 ]; then
        whiptail --title "Error" --msgbox "Composer installation failed\nCheck log file: $LOG_FILE" 10 60
        if [[ "$OPERATION_MODE" == "update" ]]; then
            restore_backup
        fi
        exit 1
    fi

    execute_with_loading "php artisan storage:link" "Linking storage"

    if [[ "$OPERATION_MODE" == "install" ]]; then
        execute_with_loading "php artisan key:generate --force" "Generating app key"

        update_env_file "DB_CONNECTION" "mysql" ".env"
        update_env_file "DB_HOST" "127.0.0.1" ".env"
        update_env_file "DB_PORT" "3306" ".env"
        update_env_file "DB_DATABASE" "$DB_FULL_NAME" ".env"
        update_env_file "DB_USERNAME" "$DB_USER_FULL" ".env"
        update_env_file "DB_PASSWORD" "$DB_PASSWORD" ".env"
        update_env_file "APP_URL" "${PROTOCOL}://$DOMAIN" ".env"
        update_env_file "KEY" "$LICENSE_KEY" ".env"
    else
        update_env_file "KEY" "$LICENSE_KEY" ".env"
    fi

    whiptail --title "Laravel" --msgbox "Laravel configuration completed successfully!" 10 60
}

check_dns() {
    local server_ip=$(curl -s --connect-timeout 10 ifconfig.me || curl -s --connect-timeout 10 ipinfo.io/ip || echo "Unable to detect")

    if ! whiptail --title "DNS Configuration" --yesno "Server IP Address: $server_ip\nDomain: $DOMAIN\n\nHave you pointed $DOMAIN to this server's IP address?\n\nSelect 'No' if you need instructions." 12 70; then
        whiptail --title "DNS Instructions" --msgbox "Please configure your DNS settings:\n\n1. Log into your domain registrar or DNS provider\n2. Create an A record pointing $DOMAIN to $server_ip\n3. Wait for DNS propagation (usually 5-30 minutes)\n\nPress OK when DNS is configured..." 15 70
    fi
}

prompt_ufw_firewall() {
    if ! command -v ufw &>/dev/null; then
        whiptail --title "Firewall" --msgbox "ufw (Uncomplicated Firewall) is not installed.\nSkipping firewall configuration." 10 60
        return
    fi

    if whiptail --title "Firewall Configuration" --yesno "Would you like to automatically configure the firewall (ufw) to allow HTTP/HTTPS traffic?" 10 60; then
        execute_with_loading "systemctl start ufw && systemctl enable ufw" "Starting UFW"
        ufw allow 80/tcp >>"$LOG_FILE" 2>&1
        ufw allow 443/tcp >>"$LOG_FILE" 2>&1
        ufw reload >>"$LOG_FILE" 2>&1
        whiptail --title "Firewall" --msgbox "UFW configured to allow HTTP/HTTPS traffic." 10 60
    else
        whiptail --title "Firewall" --msgbox "Skipped UFW firewall configuration.\nMake sure ports 80 and 443 are open." 10 60
        if whiptail --title "Firewall" --yesno "Do you want ufw to be started and enabled (without opening ports)?" 10 60; then
            execute_with_loading "systemctl start ufw && systemctl enable ufw" "Starting UFW"
            whiptail --title "Firewall" --msgbox "UFW started and enabled, but no ports were opened." 10 60
        fi
    fi
}

setup_ssl() {
    whiptail --title "SSL Certificate" --infobox "Setting up SSL certificate..." 10 60

    execute_with_loading "apt-get install -y certbot python3-certbot-nginx" "Installing Certbot"

    # Create temporary nginx config
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
        whiptail --title "SSL Error" --msgbox "Failed to obtain SSL certificate\n\nPlease ensure:\n1. Domain $DOMAIN points to this server\n2. Ports 80 and 443 are open\n3. No firewall is blocking the connection" 15 70
        exit 1
    fi

    rm -f /etc/nginx/sites-enabled/temp-dezerx
    rm -f /etc/nginx/sites-available/temp-dezerx

    whiptail --title "SSL" --msgbox "SSL certificate obtained successfully!" 10 60
}

setup_ssl_skip() {
    whiptail --title "SSL Certificate" --msgbox "You selected HTTP. Skipping SSL certificate setup." 10 60
}

configure_nginx() {
    whiptail --title "Configuring Nginx" --infobox "Setting up Nginx configuration..." 10 60

    rm -f /etc/nginx/sites-available/default
    rm -f /etc/nginx/sites-enabled/default

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

    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;

    client_max_body_size 100m;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php$ {
        fastcgi_pass unix:/run/php/php8.3-fpm.sock;
        fastcgi_index index.php;
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
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
    root $INSTALL_DIR/public;
    index index.php;

    client_max_body_size 100m;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php$ {
        fastcgi_pass unix:/run/php/php8.3-fpm.sock;
        fastcgi_index index.php;
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
    }

    location ~ /\.ht {
        deny all;
    }
}
EOF
    fi

    ln -sf /etc/nginx/sites-available/dezerx.conf /etc/nginx/sites-enabled/dezerx.conf

    if ! nginx -t >>"$LOG_FILE" 2>&1; then
        whiptail --title "Error" --msgbox "Nginx configuration test failed" 10 60
        exit 1
    fi

    execute_with_loading "systemctl restart nginx" "Restarting Nginx"
    whiptail --title "Nginx" --msgbox "Nginx configured successfully!" 10 60
}

install_nodejs_and_build() {
    whiptail --title "Building Assets" --infobox "Installing Node.js and building assets..." 10 60

    if [[ "$OPERATION_MODE" == "install" ]]; then
        execute_with_loading "curl -fsSL https://deb.nodesource.com/setup_20.x | bash -" "Adding Node.js repository"
        execute_with_loading "apt-get install -y nodejs" "Installing Node.js"
    fi

    cd "$INSTALL_DIR"

    if [[ -f "package.json" ]]; then
        execute_with_loading "npm install" "Installing npm dependencies"
        execute_with_loading "npm run build" "Building assets"
    fi

    whiptail --title "Assets" --msgbox "Assets built successfully!" 10 60
}

set_permissions() {
    whiptail --title "Setting Permissions" --infobox "Setting file permissions..." 10 60

    execute_with_loading "chown -R www-data:www-data $INSTALL_DIR" "Setting ownership"
    execute_with_loading "chmod -R 755 $INSTALL_DIR" "Setting base permissions"
    execute_with_loading "chmod -R 775 $INSTALL_DIR/storage" "Setting storage permissions"
    execute_with_loading "chmod -R 775 $INSTALL_DIR/bootstrap/cache" "Setting cache permissions"

    if [[ "$OPERATION_MODE" == "update" ]]; then
        execute_with_loading "chown -R www-data:www-data $INSTALL_DIR/*" "Additional ownership fixes"
        execute_with_loading "chown -R www-data:www-data $INSTALL_DIR/.[^.]*" "Hidden files ownership"
    fi

    whiptail --title "Permissions" --msgbox "File permissions set successfully!" 10 60
}

run_migrations() {
    whiptail --title "Database Migrations" --infobox "Running database migrations..." 10 60

    cd "$INSTALL_DIR"

    if ! sudo -u www-data php artisan migrate --force >>"$LOG_FILE" 2>&1; then
        whiptail --title "Migration Error" --msgbox "Database migration failed!\n\nCheck the log file: $LOG_FILE" 12 70
        if [[ "$OPERATION_MODE" == "update" ]]; then
            if [[ "$RESTORE_ON_FAILURE" == "yes" ]]; then
                restore_backup
            fi
        fi
        exit 1
    fi

    if ! sudo -u www-data php artisan db:seed --force >>"$LOG_FILE" 2>&1; then
        whiptail --title "Seeding Error" --msgbox "Database seeding failed!\n\nCheck the log file: $LOG_FILE" 12 70
        if [[ "$OPERATION_MODE" == "update" ]]; then
            if [[ "$RESTORE_ON_FAILURE" == "yes" ]]; then
                restore_backup
            fi
        fi
        exit 1
    fi

    chown -R www-data:www-data "$INSTALL_DIR" 2>/dev/null || true
    whiptail --title "Migrations" --msgbox "Database migrations completed successfully!" 10 60
}

setup_cron() {
    whiptail --title "Setting up Cron" --infobox "Configuring cron jobs..." 10 60

    local temp_cron_file=$(mktemp)

    if crontab -u www-data -l >"$temp_cron_file" 2>/dev/null; then
        # Existing crontab
        true
    else
        # No existing crontab
        >"$temp_cron_file"
    fi

    if ! grep -q "artisan schedule:run" "$temp_cron_file"; then
        echo "* * * * * cd $INSTALL_DIR && php artisan schedule:run >> /dev/null 2>&1" >>"$temp_cron_file"
        crontab -u www-data "$temp_cron_file"
    fi

    rm -f "$temp_cron_file"

    # Add SSL renewal cronjob if HTTPS is selected
    if [[ "$PROTOCOL" == "https" ]] && command -v certbot &>/dev/null; then
        if ! crontab -l 2>/dev/null | grep -q 'certbot renew --quiet --deploy-hook "systemctl restart nginx"'; then
            (crontab -l 2>/dev/null; echo '0 23 * * * certbot renew --quiet --deploy-hook "systemctl restart nginx"') | crontab -
        fi
    fi

    systemctl start cron 2>/dev/null || true
    whiptail --title "Cron" --msgbox "Cron jobs configured successfully!" 10 60
}

setup_queue_worker() {
    whiptail --title "Queue Worker" --infobox "Setting up queue worker service..." 10 60

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

[Install]
WantedBy=multi-user.target
EOF

    execute_with_loading "systemctl daemon-reload" "Reloading systemd"
    execute_with_loading "systemctl enable dezerx.service" "Enabling DezerX service"
    execute_with_loading "systemctl start dezerx.service" "Starting DezerX service"

    whiptail --title "Queue Worker" --msgbox "Queue worker service configured successfully!" 10 60
}

cleanup_backup() {
    if [[ "$OPERATION_MODE" == "update" && -n "$BACKUP_DIR" && -d "$BACKUP_DIR" ]]; then
        chown -R www-data:www-data "$INSTALL_DIR" 2>/dev/null || true
        chmod -R 755 "$INSTALL_DIR" 2>/dev/null || true
        chmod -R 775 "$INSTALL_DIR/storage" 2>/dev/null || true
        chmod -R 775 "$INSTALL_DIR/bootstrap/cache" 2>/dev/null || true
        rm -rf "$BACKUP_DIR"
    fi
}

print_summary() {
    local operation_text="Installation"
    local emoji="🎉"
    if [[ "$OPERATION_MODE" == "update" ]]; then
        operation_text="Update"
    fi

    local summary_text="$emoji $operation_text completed successfully!\n\nDezerX Details:\n"
    summary_text+="• URL: ${PROTOCOL}://$DOMAIN\n"
    summary_text+="• Directory: $INSTALL_DIR\n"
    
    if [[ "$OPERATION_MODE" == "install" ]]; then
        summary_text+="• Database: $DB_FULL_NAME\n"
        summary_text+="• DB User: $DB_USER_FULL\n"
        summary_text+="• DB Password: $DB_PASSWORD\n"
    fi
    
    summary_text+="• License: ${LICENSE_KEY:0:8}***\n\n"
    summary_text+="Next Steps:\n"
    summary_text+="1. Visit ${PROTOCOL}://$DOMAIN\n"
    summary_text+="2. Complete setup wizard\n"
    summary_text+="3. Configure your application"

    whiptail --title "$operation_text Complete" --msgbox "$summary_text" 20 70

    # Save installation info
    local info_file="$INSTALL_DIR/${operation_text^^}_INFO.txt"
    cat >"$info_file" <<EOF
DezerX $operation_text Information
==============================
Date: $(date)
Domain: $DOMAIN
URL: ${PROTOCOL}://$DOMAIN
Directory: $INSTALL_DIR
License: $LICENSE_KEY
Log: $LOG_FILE

Useful Commands:
- Check queue worker: systemctl status dezerx
- Restart queue worker: systemctl restart dezerx
- View logs: tail -f $INSTALL_DIR/storage/logs/laravel.log
- Restart Nginx: systemctl restart nginx
EOF

    if [[ "$OPERATION_MODE" == "install" ]]; then
        cat >>"$info_file" <<EOF
- Database: $DB_FULL_NAME
- DB User: $DB_USER_FULL
- DB Password: $DB_PASSWORD
EOF
    fi
}

cleanup_on_error() {
    whiptail --title "Error" --msgbox "Operation failed at line $1\n\nCheck the log file: $LOG_FILE" 12 70
    
    if [[ "$OPERATION_MODE" == "update" && "$RESTORE_ON_FAILURE" == "yes" ]]; then
        restore_backup
    fi
    exit 1
}

main() {
    echo "DezerX $(if [[ "$OPERATION_MODE" == "install" ]]; then echo "Installation"; else echo "Update"; fi) Log - $(date)" >"$LOG_FILE"

    print_banner
    trap 'cleanup_on_error $LINENO' ERR

    check_required_commands
    check_root
    choose_operation_mode

    if [[ "$OPERATION_MODE" == "delete" ]]; then
        exit 0
    fi

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
        get_update_input
        verify_license
        create_backup
        backup_database
        download_dezerx
        configure_laravel
        install_nodejs_and_build
        set_permissions
        run_migrations
        cleanup_backup
    fi

    print_summary
    log_message "Operation completed successfully"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi