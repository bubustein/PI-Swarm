# Pi-Swarm User Authentication & Security

## 🔐 Authentication Requirements

Pi-Swarm is designed to run as a **regular user** and follows Linux security best practices by avoiding root access whenever possible.

### ✅ Recommended Setup

**Use a regular user account on your Raspberry Pis:**
- Standard usernames: `pi`, `ubuntu`, `admin`, or your custom username
- The user must have `sudo` privileges for system administration
- SSH must be enabled for this user account

**Example valid usernames:**
- `pi` (default Raspberry Pi OS user)
- `ubuntu` (Ubuntu user)
- `admin` (custom administrator)
- `yourusername` (personalized account)

### ⚠️ What to Avoid

**Do NOT use the root account:**
- Most Raspberry Pi distributions disable root login by default for security
- Root accounts often have no password or password authentication disabled
- Using root violates security best practices
- Pi-Swarm will warn you if you attempt to use root

## 🚀 How Pi-Swarm Handles Authentication

### 1. User Prompts
When you run `./swarm-cluster.sh`, you'll see:

```
🔐 SSH Authentication Setup
Enter the username for your Raspberry Pi accounts.
⚠️  Note: Do not use 'root' - use your regular Pi user account (e.g., 'pi', 'ubuntu', etc.)

Enter SSH username for Pis: pi
Enter SSH password for pi: [hidden]
```

### 2. Root User Protection
If you accidentally enter `root` as the username:

```
⚠️  WARNING: Using 'root' is not recommended and may fail!
   Most Pi setups disable root login for security.
   Consider using your regular user account instead.

Continue with root anyway? (y/N): 
```

### 3. Automatic SSH Key Setup
Pi-Swarm automatically:
- Sets up SSH key authentication for secure access
- Uses your password only for initial setup
- Switches to key-based authentication afterward
- Maintains security throughout the deployment process

## 🔧 Troubleshooting Authentication Issues

### "SSH authentication failed" errors

**For root users:**
```
SSH authentication failed for root@192.168.1.10
Root login is often disabled on Pi systems for security.
Try using your regular Pi user account (e.g., 'pi', 'ubuntu', etc.)
If root has no password, consider enabling SSH keys or using a regular user.
```

**For regular users:**
```
SSH authentication failed for pi@192.168.1.10
Please check your username and password.
Ensure SSH is enabled and the user account exists on the Pi.
```

### Common Solutions

1. **Verify SSH is enabled:**
   ```bash
   sudo systemctl status ssh
   sudo systemctl enable ssh
   sudo systemctl start ssh
   ```

2. **Check user account exists:**
   ```bash
   id pi  # Replace 'pi' with your username
   ```

3. **Verify sudo privileges:**
   ```bash
   sudo whoami  # Should return 'root'
   ```

4. **Test SSH manually:**
   ```bash
   ssh pi@192.168.1.10  # Replace with your user and IP
   ```

## 🛡️ Security Features

### Automatic Security Hardening
Pi-Swarm automatically implements security best practices:
- Disables root login via SSH
- Sets up fail2ban for intrusion prevention
- Configures firewall rules
- Enables automatic security updates
- Sets up SSH key authentication

### User Account Requirements
Your Pi user account needs:
- **SSH access** - Ability to log in remotely
- **Sudo privileges** - For system administration tasks
- **Valid password** - For initial authentication
- **Home directory** - For SSH key storage

## 📋 Pre-Deployment Checklist

Before running Pi-Swarm, ensure:

- [ ] SSH is enabled on all Pis (`sudo raspi-config`)
- [ ] Your user account exists on all Pis
- [ ] Your user has sudo privileges (`sudo visudo`)
- [ ] You can SSH to each Pi manually
- [ ] Static IP addresses are configured
- [ ] All Pis are reachable on the network

### Verify Setup Command
```bash
# Test SSH access to each Pi
ssh pi@192.168.1.10 'sudo whoami'  # Should return 'root'
ssh pi@192.168.1.11 'sudo whoami'
ssh pi@192.168.1.12 'sudo whoami'
```

## 🎯 Why This Approach?

1. **Security**: Regular users with sudo are more secure than root access
2. **Best Practices**: Follows Linux security guidelines
3. **Compatibility**: Works with default Pi configurations
4. **Auditability**: Better tracking of administrative actions
5. **Recovery**: Easier to recover from misconfigurations

## 🔗 Related Documentation

- [Main README](README.md) - Complete setup guide
- [Enterprise Features](ENTERPRISE_FEATURES.md) - Advanced security options
- [Deployment Guide](DEPLOYMENT_READY_FINAL.md) - Production deployment
