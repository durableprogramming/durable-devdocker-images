# Building Durable Devdocker Images

This document explains how to use the template-based build system to generate Docker images.

## Quick Start

```bash
# Install dependencies (jq required)
apt-get install jq  # Debian/Ubuntu
brew install jq     # macOS

# Generate all images for versions from last 6 months
./build.sh

# Generate and build MySQL images
./build.sh --db mysql --build

# Generate, build, and push all images
./build.sh --push
```

## How It Works

The build system uses templates to generate Docker images:

1. **Templates** (`templates/{database}/`)
   - `Dockerfile.template` - Base Dockerfile with `{{VERSION}}` placeholder
   - `entrypoint.sh` - Dynamic configuration script

2. **Version Discovery**
   - Queries Docker Hub API for official images
   - Filters to versions released in the last 6 months
   - Supports fallback to latest N versions

3. **Image Generation** (`build/{database}/{version}/`)
   - Replaces `{{VERSION}}` in templates
   - Copies entrypoint script
   - Creates ready-to-build Docker contexts

4. **Optional Building**
   - Builds images with `--build` flag
   - Pushes to registry with `--push` flag

## Build Script Options

```bash
./build.sh [OPTIONS]

Options:
  --db <name>     Process specific database (mysql, postgres, redis, mongodb)
  --fallback      Use latest 5 versions instead of last 6 months
  --build         Build Docker images after generating
  --push          Build and push Docker images to registry
  --help          Show help message
```

## Examples

### Generate Without Building

Creates Dockerfiles in `build/` directory:

```bash
./build.sh
./build.sh --db postgres
```

### Build Locally

Generates and builds Docker images:

```bash
./build.sh --build
./build.sh --db mysql --build
```

### Release to Registry

Generates, builds, and pushes to `durabledevdocker/*`:

```bash
./build.sh --push
./build.sh --db postgres --push
```

### Using Fallback Mode

When Docker Hub API is slow or you want specific versions:

```bash
./build.sh --fallback --db mysql
```

## Version Selection Strategy

The build script uses this strategy for selecting versions:

1. **Primary**: Query Docker Hub for versions updated in the last 6 months
2. **Filter**: Only include semantic versions (e.g., `8.0.44`, `16-alpine`)
3. **Fallback**: If none found, use 5 most recent versions
4. **Deduplicate**: Remove duplicate versions
5. **Sort**: Order versions semantically

## Manual Building

You can manually build any generated image:

```bash
cd build/mysql/8.0.44-debian
docker build -t durabledevdocker/mysql:8.0.44-debian .
docker push durabledevdocker/mysql:8.0.44-debian
```

## Registry Configuration

By default, images are tagged with the `durabledevdocker` registry prefix.

To use a different registry, modify `REGISTRY` in `build.sh`:

```bash
REGISTRY="myregistry"  # Results in myregistry/mysql:8.0
```

## Continuous Integration

Example GitHub Actions workflow:

```yaml
name: Build and Push Images

on:
  schedule:
    - cron: '0 0 * * 0'  # Weekly on Sunday
  workflow_dispatch:

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3

      - name: Login to Docker Hub
        uses: docker/login-action@v2
        with:
          username: ${{ secrets.DOCKER_USERNAME }}
          password: ${{ secrets.DOCKER_PASSWORD }}

      - name: Install dependencies
        run: sudo apt-get update && sudo apt-get install -y jq

      - name: Build and push images
        run: ./build.sh --push
```

## Troubleshooting

### jq not found

```bash
# Install jq
apt-get install jq  # Debian/Ubuntu
brew install jq     # macOS
yum install jq      # RHEL/CentOS
```

### Docker Hub API rate limits

Use `--fallback` to reduce API calls:

```bash
./build.sh --fallback
```

### No versions found

Check if the database name matches Docker Hub:
- `mysql` ✓
- `postgres` ✓
- `redis` ✓
- `mongo` ✓ (MongoDB uses "mongo" on Docker Hub)

### Build failures

Ensure you have Docker installed and running:

```bash
docker --version
docker info
```

## Adding New Database Types

See `templates/README.md` for instructions on adding new databases to the build system.
