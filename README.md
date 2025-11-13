# Durable Devdocker Images

Development-focused Docker images with dynamic environment variable support and reduced mutability constraints.

Durable Devdocker Images provide Docker images specifically designed for development environments, where configuration changes need to take effect even after initial container creation. Unlike standard images that often apply environment variables only during first boot, these images respond to configuration changes throughout their lifecycle.

## Problem Statement

Standard Docker images for databases and services often have a critical limitation: environment variables like `MYSQL_USER` or `POSTGRES_DB` only take effect during initial container creation. Once the container has been initialized, changing these variables has no effect on the running system. This creates friction in development environments where:

- Developers need to frequently adjust configuration
- Testing requires different settings
- Multiple team members need different local setups
- Containers are repeatedly destroyed and recreated just to apply config changes

Durable Devdocker Images solve this by monitoring environment variables and applying changes dynamically, updating access controls, permissions, and configurations as needed.

## Features

- **Dynamic Configuration**: Environment variables are continuously monitored and applied, not just on first boot
- **Development-Optimized**: Designed for the fast iteration cycles of development environments
- **Reduced Friction**: Change configuration without destroying and recreating containers
- **Access Control Updates**: User permissions and access controls adapt to environment variable changes
- **UID/GID Control**: Easily set running user and group IDs to match host permissions and avoid file ownership conflicts
- **Standard Compatibility**: Drop-in replacements for standard images with enhanced behavior
- **Pragmatic Design**: Focused on solving real development workflow problems

## Design Philosophy

These images align with Durable Programming's core principles:

**Pragmatic Problem-Solving**: Addresses the real pain point of rigid container configuration in development environments.

**Developer Experience**: Eliminates the frustration of container recreation cycles and streamlines local development workflows.

**Modular and Composable**: Works with existing Docker and Docker Compose workflows without requiring major changes.

**Incremental Improvement**: Enhances standard images rather than requiring complete rewrites of development infrastructure.

**Sustainability**: Configuration is explicit through environment variables, making setups reproducible and maintainable over time.

## Use Cases

### Database Development
```yaml
# docker-compose.yml
services:
  mysql:
    image: durabledevdocker/mysql:latest
    environment:
      MYSQL_USER: developer
      MYSQL_PASSWORD: dev_password
      MYSQL_DATABASE: myapp_dev
    volumes:
      - mysql_data:/var/lib/mysql
```

Change `MYSQL_USER` to `new_developer` and restart the container - the user will be created and permissions updated automatically.

### Multi-Developer Environments
Different developers can use personalized environment variables without affecting shared image configuration:

```bash
# Developer A
export DB_USER=alice
docker-compose up

# Developer B
export DB_USER=bob
docker-compose up
```

### Testing Different Configurations
Rapidly iterate through different database configurations for integration testing without container recreation overhead.

## Available Images

Durable Devdocker Images are built for common development services:

- **MySQL/MariaDB**: Dynamic user and database management
- **PostgreSQL**: Dynamic role and schema configuration
- **Redis**: Dynamic configuration updates
- **MongoDB**: Dynamic user and authentication changes

Each image maintains full compatibility with its standard counterpart while adding dynamic configuration capabilities.

## Installation

### Using Docker Compose

Replace standard image references with Durable Devdocker equivalents:

```yaml
services:
  db:
    image: durabledevdocker/mysql:8.0
    environment:
      MYSQL_ROOT_PASSWORD: root
      MYSQL_USER: appuser
      MYSQL_PASSWORD: apppass
      MYSQL_DATABASE: appdb
```

### Using Docker CLI

```bash
docker run -d \
  -e MYSQL_ROOT_PASSWORD=root \
  -e MYSQL_USER=developer \
  -e MYSQL_PASSWORD=devpass \
  -e MYSQL_DATABASE=myapp \
  -v mysql_data:/var/lib/mysql \
  durabledevdocker/mysql:8.0
```

## Configuration

### Environment Variable Processing

Durable Devdocker Images check environment variables:

1. **On container start**: Initial setup identical to standard images
2. **On container restart**: Re-evaluate all environment variables and apply changes
3. **Configuration drift prevention**: Ensure running state matches declared environment

### Supported Environment Variables

Each image supports the same environment variables as its standard counterpart, plus:

#### Universal Variables (All Images)

- **`DEVDOCKER_UID`**: Set the user ID for the service process (default: image-specific)
- **`DEVDOCKER_GID`**: Set the group ID for the service process (default: image-specific)
- **`DEVDOCKER_SKIP_CONFIG_UPDATE`**: Set to `true` to disable dynamic configuration (reverts to standard image behavior)
- **`DEVDOCKER_VERBOSE`**: Set to `true` to enable detailed logging of configuration changes

### Image-Specific Configuration

#### MySQL/MariaDB
- `MYSQL_USER`: Dynamically created/updated
- `MYSQL_PASSWORD`: Updated when changed
- `MYSQL_DATABASE`: Created if missing
- User permissions automatically updated

#### PostgreSQL
- `POSTGRES_USER`: Dynamically managed
- `POSTGRES_PASSWORD`: Updated when changed
- `POSTGRES_DB`: Created if missing
- Role permissions automatically synchronized

### UID/GID Configuration

A common development pain point is file permission conflicts between containers and the host system. Durable Devdocker Images address this by allowing you to specify the exact UID and GID the service should run as.

#### Why This Matters

When containers write to mounted volumes, files are created with the container's user/group ownership. If this doesn't match your host user's UID/GID, you'll encounter permission denied errors or need to use sudo to access files.

#### Usage

**Match your host user:**
```bash
# Get your host UID and GID
id -u  # e.g., 1000
id -g  # e.g., 1000

# Use in docker-compose.yml
services:
  mysql:
    image: durabledevdocker/mysql:8.0
    environment:
      DEVDOCKER_UID: 1000
      DEVDOCKER_GID: 1000
      MYSQL_ROOT_PASSWORD: root
    volumes:
      - ./data:/var/lib/mysql
```

**Or use Docker Compose variable substitution:**
```yaml
services:
  mysql:
    image: durabledevdocker/mysql:8.0
    environment:
      DEVDOCKER_UID: ${UID:-1000}
      DEVDOCKER_GID: ${GID:-1000}
      MYSQL_ROOT_PASSWORD: root
```

Then run:
```bash
UID=$(id -u) GID=$(id -g) docker-compose up
```

**Or add to your .env file:**
```bash
# .env
DEVDOCKER_UID=1000
DEVDOCKER_GID=1000
```

#### How It Works

On container start/restart:
1. The service user's UID/GID is updated to match `DEVDOCKER_UID` and `DEVDOCKER_GID`
2. Ownership of service data directories is updated recursively (e.g., `/var/lib/mysql`)
3. The service starts with the specified UID/GID
4. All files created by the service match your host user's permissions

#### Best Practices

- **Always set UID/GID in development**: Prevents permission issues with mounted volumes
- **Use environment variables**: Keep UID/GID configurable per developer
- **Document in project README**: Ensure team members know to set these values
- **Check with `ls -l`**: Verify file ownership matches expectations after first run

## How It Works

Durable Devdocker Images use entrypoint scripts that:

1. **Detect environment changes**: Compare current environment variables with previous container state
2. **Apply configuration updates**: Execute appropriate commands to update running services
3. **Update access controls**: Modify users, permissions, and roles to match new configuration
4. **Maintain data integrity**: Ensure existing data remains accessible through configuration changes
5. **Log all changes**: Provide visibility into what configuration updates were applied

This approach maintains the declarative nature of environment variables while extending their applicability beyond initial container creation.

## Comparison with Standard Images

| Feature | Standard Images | Durable Devdocker Images |
|---------|----------------|-------------------------|
| Initial configuration | Environment variables applied | Environment variables applied |
| Configuration changes | Requires container recreation | Applied on restart |
| User management | Static after first boot | Dynamic throughout lifecycle |
| Access control updates | Manual intervention required | Automatic based on env vars |
| Development workflow | Destroy/recreate cycle | Restart to apply changes |
| Production suitability | Designed for production | Optimized for development |

## Best Practices

### Development Environments
- Use Durable Devdocker Images for local development and testing
- Leverage dynamic configuration to maintain consistent environments across team
- Store environment variables in `.env` files for reproducibility
- Document expected environment variables in project README

### Environment Variable Management
- Use clear, descriptive variable names
- Document all supported configuration options
- Avoid storing secrets in environment variables for production
- Use Docker secrets or external secret management for sensitive data

### Container Lifecycle
- Restart containers rather than recreating to apply configuration changes
- Use volumes to persist data across configuration updates
- Monitor logs when applying configuration changes to verify success
- Test configuration changes in isolation before applying broadly

### Production Deployment
Durable Devdocker Images are optimized for development. For production:
- Use standard images with immutable configuration
- Apply configuration changes through proper deployment pipelines
- Use container orchestration platforms (Kubernetes, Docker Swarm) for production workloads
- Separate development and production image choices

## Limitations

**Not for Production**: These images are designed for development environments where configuration flexibility is valuable. Production environments should use standard images with immutable infrastructure practices.

**Performance Overhead**: Configuration checking adds minimal overhead on container restart. For services requiring sub-second startup times, this may be noticeable.

**Security Considerations**: Dynamic user management is appropriate for development but not for production security models.

**State Complexity**: Tracking configuration changes across restarts adds complexity. In rare cases, manual intervention may be required to resolve configuration conflicts.

## Troubleshooting

### Configuration changes not applied
- Verify container was restarted (not just refreshed)
- Check `DEVDOCKER_SKIP_CONFIG_UPDATE` is not set to `true`
- Enable `DEVDOCKER_VERBOSE=true` and check logs for errors
- Ensure environment variables are properly passed to container

### Permission errors after user changes
- Existing files may have old ownership
- Ensure `DEVDOCKER_UID` and `DEVDOCKER_GID` are set correctly
- Verify the service user has been updated: `docker exec <container> id`
- Check file ownership: `docker exec <container> ls -la /var/lib/mysql`
- Run ownership update commands manually if needed
- Consider using Docker volumes with appropriate permissions

### File ownership problems on host
- Set `DEVDOCKER_UID` to your host user ID: `id -u`
- Set `DEVDOCKER_GID` to your host group ID: `id -g`
- Restart container to apply UID/GID changes
- Existing files will be updated to new ownership on restart

### Container fails to start after configuration change
- Check logs for specific error messages
- Verify environment variable values are valid
- Temporarily set `DEVDOCKER_SKIP_CONFIG_UPDATE=true` to boot with old config
- Restore previous environment variables to identify problematic change

## Contributing

We welcome contributions to Durable Devdocker Images. See [CONTRIBUTING.md](CONTRIBUTING.md) for:
- Development setup and testing procedures
- Adding support for new images
- Reporting issues and requesting features
- Code standards and review process

## Philosophy Alignment

These images embody Durable Programming principles:

**Pragmatic Problem-Solving**: Solve the real friction point of static container configuration in development workflows.

**Developer Experience**: Reduce time spent on environment management, increase time spent on actual development.

**Incremental Improvement**: Enhance existing Docker ecosystem rather than requiring new tools or complete infrastructure changes.

**Sustainability**: Explicit, reproducible configuration through environment variables ensures long-term maintainability.

**Modular Design**: Drop-in replacements for standard images maintain composability with existing Docker tooling.

**Quality and Testing**: Thoroughly tested against standard image behavior to ensure compatibility and reliability.

## License

[License information to be added]

## Support

- **Issues**: [GitHub Issues](https://github.com/durableprogramming/durable-devdocker-images/issues)
- **Email**: commercial@durableprogramming.com
- **Documentation**: [Full documentation](docs/)

---

Built with pragmatism and attention to developer experience by [Durable Programming LLC](https://durableprogramming.com)
