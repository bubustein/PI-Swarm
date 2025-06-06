# Post-Deployment Hardening

After deploying Pi-Swarm, complete these steps to secure your cluster.

## 1. Change Service Passwords

- **Portainer**: Log in with the initial admin password and immediately change it in the user settings.
- **Grafana**: Change the default `admin` password in the first login prompt.
- **Other Services**: Update any credentials configured during deployment.

## 2. Enforce SSH Key Authentication

1. Generate an SSH key pair on your control machine (if you haven't already):
   ```bash
   ssh-keygen -t ed25519 -C "pi-swarm"
   ```
2. Copy your public key to each Pi node:
   ```bash
   ssh-copy-id pi@NODE_IP
   ```
3. Edit `/etc/ssh/sshd_config` on each node and set:
   ```
   PasswordAuthentication no
   ```
   Restart the SSH service to apply the change:
   ```bash
   sudo systemctl restart ssh
   ```

## 3. Review Firewall Settings

- Use `ufw` or `iptables` to allow only required ports (22, 2377, 7946, 4789, 3000, 9000, etc.).
- Deny all unexpected inbound traffic and restrict management interfaces to trusted networks.
- Test connectivity after applying firewall rules to ensure cluster communication is unaffected.

---

For additional security recommendations, see [Security Improvements](SECURITY_IMPROVEMENTS.md).
