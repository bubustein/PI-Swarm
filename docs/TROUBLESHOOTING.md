# Pi-Swarm Troubleshooting Guide

## Common Issues

### SSH Authentication Fails
- Ensure SSH is enabled on all Pis.
- Use the correct username and password.
- Try manual SSH to each Pi to verify access.

### Docker or Swarm Errors
- Make sure Docker is installed on all Pis.
- Check for port conflicts (2377, 7946, 4789).
- Use `docker info` and `docker service ls` for diagnostics.

### Monitoring Not Working
- Ensure all monitoring containers are running (`docker ps`).
- Check `config/docker-compose.monitoring.yml` for errors.

### General Debugging
- Check logs in `data/logs/`.
- Run `bash scripts/testing/comprehensive-test.sh` for a full check.

## Still Stuck?
- Open an issue on GitHub with logs and error details.
