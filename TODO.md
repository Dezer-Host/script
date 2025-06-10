# TODO

- [ ] Add an interactive menu UI (TUI) for easier navigation (e.g., using `select`, `whiptail`, or `dialog`)
- [x] Prompt user to optionally configure UFW firewall for HTTP/HTTPS ports
- [x] Implement automatic SSL renewal cron job (`certbot renew --quiet --deploy-hook "systemctl restart nginx"`)
- [x] Add dependency version checks and warn if unsupported/outdated
- [x] Create an uninstall option/script for clean removal of DezerX and its configs