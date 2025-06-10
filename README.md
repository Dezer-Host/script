# DezerX Install / Update Script

One-liner to install or update DezerX for Ubuntu:

```bash
curl -fsSL https://raw.githubusercontent.com/Dezer-Host/script/main/script.sh -o /tmp/dx.sh && bash /tmp/dx.sh
```

One-liner to install or update DezerX with graphical interface (ALPHA) (this will later be integrated in the main script):

```bash
curl -fsSL https://raw.githubusercontent.com/Dezer-Host/script/main/script_gui.sh -o /tmp/dx.sh && bash /tmp/dx.sh
```

---

## Features

- **Easy Installation & Update:** Installs all required dependencies, configures Nginx, MariaDB, PHP, Redis, and more. Updates existing installations safely.
- **Automatic SSL:** Optionally sets up Let's Encrypt SSL certificates for HTTPS.
- **Backup & Restore:** Backs up your files and database before updating, with optional automatic restore on failure.
- **Interactive Prompts:** Guides you through license, domain, and configuration steps.
- **Custom Database Settings:** Choose your own database name, user, and password, or use secure defaults. Reads and preserves credentials from your `.env` during updates.
- **Colorful Output:** Clear, color-coded progress and error messages.
- **Modern Loader:** Animated spinner and clear success/error indicators.
- **Safe & Idempotent:** Designed to be re-run safely for updates or repairs.
- **Uninstall Option:** Clean removal of DezerX, Nginx configs, and database/user.
- **Server Friendly:** Works on Ubuntu Server (no GUI required), all dialogs are terminal-based.

---

## Requirements

- Ubuntu 20.04, 22.04, 24.04, or newer (Debian-based systems)
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
   - Choose your database name, user, and password (or accept defaults)
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
- **Database issues:**  
  Ensure the database credentials in your `.env` file match what was created during installation or update.  
  If you see "Access denied" errors, check that the user exists for both `localhost` and `127.0.0.1` and that the password is correct.

---

## Uninstall

DezerX provides an **uninstall/delete option directly in the script**.  
To uninstall, simply **run the script again and choose the delete option** from the interactive menu.

---

## Support

- [DezerX Documentation](https://docs.dezerx.com) (Outdated)
- [DezerX Support (Discord)](https://discord.gg/kNK8297Hjh)

---

## License

This script is **not open source** and is intended solely for installing or updating DezerX software.  
You may not copy, distribute, or modify this script for other purposes without explicit permission from the author.

**Contributions are welcome** for improving the installation experience, but usage is limited to DezerX customers and partners.

If you want to contribute but don't know where to start, check the [TODO](./TODO.md) file for ideas and open tasks.

All rights are reserved by the author.
