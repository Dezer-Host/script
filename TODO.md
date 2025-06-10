# TODO

- [ ] Add an interactive menu UI (TUI) for easier navigation (using `dialog`)
- [x] Prompt user to optionally configure UFW firewall for HTTP/HTTPS ports
- [x] Implement automatic SSL renewal cron job (`certbot renew --quiet --deploy-hook "systemctl restart nginx"`)
- [x] Create an uninstall option/script for clean removal of DezerX and its configs
- [x] Make the deletion better because its not working 100% yet
- [ ] Fix the Debian install script