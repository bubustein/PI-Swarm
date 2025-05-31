# Pi-Swarm FAQ

**Q: Can I run Pi-Swarm as root?**
A: No, Pi-Swarm is designed for regular users with sudo privileges for security reasons.

**Q: How do I add more Pis to my cluster?**
A: Use the CLI tool (`./core/pi-swarm add-node <ip>`) or rerun the deployment script.

**Q: What if a Pi fails?**
A: The cluster will remain operational if you have 3+ managers. Replace the failed Pi and rejoin it.

**Q: How do I update Pi-Swarm?**
A: Pull the latest code and rerun the deployment script. Your config and data are preserved.

**Q: Where are logs and backups?**
A: See `data/logs/` and `data/backups/`.

**Q: How do I get help?**
A: Open an issue on GitHub or email the maintainers.
