# Changelog

## [3.0.0] - 2025-06-10

### Added

- Automatic OS detection: The main script now detects Debian or Ubuntu and redirects to the correct installer script automatically.
- GUI installation option: Users can now choose a graphical (dialog-based) installer (ALPHA).
- Uninstall option: Added a script option for clean removal of DezerX, its configs, and database.
- Automatic SSL renewal: Added a cron job for `certbot renew` with Nginx reload.
- nftables firewall configuration: Added prompt and logic to configure nftables for HTTP/HTTPS/SSH ports on Debian.
- Backup and restore: Automatic backup of files and database before updates, with restore on failure.
- Interactive prompts: Improved user guidance for license, domain, and configuration steps.
- Colorful and modern output: Enhanced color-coded messages and animated loader.
- DNS verification: Checks if the domain points to the correct server IP before proceeding.
- Node.js LTS installation and asset build: Installs Node.js if missing and builds frontend assets.
- Composer auto-install: Installs Composer if missing.
- Secure random password generation for database.
- Info file: Generates `INSTALLATION_INFO.txt` with credentials and important details.

### Changed

- .env handling: Now ensures only one entry per key, preventing duplicates and improving reliability.
- Permissions: Improved file and directory permissions for security and compatibility.
- Nginx configuration: More robust and secure default config, with automatic SSL and HTTP/2.
- Database setup: Improved checks and error handling for MariaDB user/database creation.
- Improved uninstall process for more thorough cleanup.
- Firewall logic: Switched from UFW to nftables as the default firewall configuration on Debian.

### Fixed

- Debian install script reliability: Now works out-of-the-box on Debian 12+.
- .env update verification: Fixed issues where some keys (like `CACHE_DRIVER`) were not reliably updated.
- Node.js/npm permission errors: Ensures npm cache directory is owned by the correct user.
- Various minor bugs and edge cases in installation and update flows.

### Removed

- Manual intervention for most common install/update errors.
- UFW as default firewall configuration on Debian (now uses nftables).

---

**Note:**  
This release brings major improvements to automation, reliability, and user experience. If you encounter issues, please check the generated log file or reach out for support.
