# DezerX Install / Update Script

One-liner to install or update DezerX:

```bash
curl -fsSL https://raw.githubusercontent.com/Dezer-Host/script/main/script.sh -o /tmp/dx.sh && bash /tmp/dx.sh
```

---

## Features

- **Easy Installation:** Installs all required dependencies, configures Nginx, MariaDB, PHP, Redis, and more.
- **Update Support:** Seamlessly update existing DezerX installations.
- **Automatic SSL:** Optionally sets up Let's Encrypt SSL certificates for HTTPS.
- **Backup & Restore:** Backs up your files and database before updating, with optional automatic restore on failure.
- **Interactive Prompts:** Guides you through license, domain, and configuration steps.
- **Colorful Output:** Clear, color-coded progress and error messages.

---

## Requirements

- Ubuntu 20.04, 22.04, or newer (Debian-based systems)
- Root privileges (`sudo` or run as root)
- A valid DezerX license key
- A domain name pointed to your server's IP

---

## Usage

1. **Run the one-liner above on your server.**
2. **Follow the interactive prompts:**
   - Enter your license key
   - Enter your domain (without `http://` or `https://`)
   - Choose HTTP or HTTPS
   - Confirm or set the installation directory
3. **Wait for the script to finish.**
4. **Access your DezerX instance at your domain!**

---

## Troubleshooting

- **Check the log:**  
  All actions and errors are logged to `/tmp/dezerx-install.log`.
- **Nginx errors:**  
  If you see a warning about conflicting server names, remove duplicate configs from `/etc/nginx/sites-enabled/`.
- **Dependency issues:**  
  Make sure your system is up to date and not running other package managers in the background.
- **SSL issues:**  
  Ensure your domain points to your server and ports 80/443 are open.

---

## Uninstall

To remove DezerX and its dependencies, you can manually delete the installation directory and remove related Nginx, MariaDB, and PHP packages.

---

## Support

- [DezerX Documentation](https://docs.dezerx.com) (Outdated)
- [DezerX Support](https://discord.gg/kNK8297Hjh)

