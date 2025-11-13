# Release Process

This document describes how to create releases and publish Docker images to GitHub Container Registry (GHCR).

## Overview

The repository uses GitHub Actions to automatically build and push Docker images to GitHub Container Registry when a new release is published. Images are built for multiple platforms (amd64 and arm64) and tagged with version-specific tags.

## Release Workflow

### 1. Automatic Releases (Recommended)

When you create a new GitHub release, the workflow automatically:
- Generates Dockerfiles for all database types (MySQL, PostgreSQL, Percona Server, Valkey)
- Builds images for multiple architectures (amd64, arm64)
- Pushes images to `ghcr.io/<owner>/<database>:<version>`
- Tags the latest version as `latest`

**Steps:**
1. Go to the GitHub repository
2. Click "Releases" → "Create a new release"
3. Choose or create a tag (e.g., `v1.0.0`)
4. Write release notes
5. Click "Publish release"
6. The workflow will automatically build and push all images

### 2. Manual Workflow Dispatch

You can also trigger builds manually without creating a release:

1. Go to "Actions" tab in GitHub
2. Select "Build and Push Docker Images"
3. Click "Run workflow"
4. (Optional) Specify databases to build (comma-separated: `mysql,postgres` or `all`)
5. Click "Run workflow"

This is useful for testing or rebuilding specific database images.

## Image Naming Convention

Images are published to GitHub Container Registry with the following naming:

```
ghcr.io/<owner>/<database>:<version>
```

**Examples:**
- `ghcr.io/durableprogramming/mysql:8.0.44`
- `ghcr.io/durableprogramming/postgres:17.6`
- `ghcr.io/durableprogramming/percona-server:8.0.36`
- `ghcr.io/durableprogramming/valkey:8.0`

The most recent version for each database is also tagged as `latest`:
- `ghcr.io/durableprogramming/mysql:latest`

## Local Testing

Before creating a release, you can test the build process locally:

### Generate Dockerfiles

```bash
# Generate for all databases
./build.sh

# Generate for specific database
./build.sh --db mysql
```

### Build Images Locally

```bash
# Build all images
./build.sh --build

# Build specific database
./build.sh --db postgres --build
```

### Push to GitHub Container Registry

First, authenticate with GitHub Container Registry:

```bash
# Create a Personal Access Token (PAT) with packages:write scope
# Then login:
echo $GITHUB_TOKEN | docker login ghcr.io -u USERNAME --password-stdin
```

Build and push images:

```bash
# Set the registry to your GitHub organization/username
export DOCKER_REGISTRY=ghcr.io/durableprogramming

# Build and push all images
./build.sh --push

# Build and push specific database
./build.sh --db mysql --push
```

## Image Visibility

By default, images pushed to GHCR are private. To make them public:

1. Go to your GitHub profile
2. Click "Packages"
3. Select the package (e.g., `mysql`)
4. Click "Package settings"
5. Under "Danger Zone", click "Change visibility"
6. Select "Public" and confirm

## Workflow Configuration

The workflow is defined in `.github/workflows/release.yml` and includes:

- **Multi-platform builds**: Builds for both amd64 and arm64 architectures
- **Matrix strategy**: Builds each database type in parallel
- **Version tagging**: Automatically tags images with version numbers
- **Latest tagging**: The newest version for each database is tagged as `latest`
- **Build summaries**: Provides detailed output of built images

## Supported Databases

The following database types are built and published:
- **mysql**: MySQL database images
- **postgres**: PostgreSQL database images
- **percona-server**: Percona Server for MySQL images
- **valkey**: Valkey (Redis alternative) images

## Version Selection

The build script automatically fetches and builds versions that were released in the last 6 months. This ensures images stay current without manually maintaining version lists.

To override this behavior locally:

```bash
# Use latest N versions instead of date-based selection
./build.sh --fallback
```

## Troubleshooting

### Workflow Fails

Check the Actions tab for detailed error logs. Common issues:
- Missing dependencies (jq)
- Invalid Dockerfile templates
- Network issues fetching version information

### Images Not Appearing

- Ensure the workflow completed successfully
- Check package visibility settings in GitHub
- Verify you're looking in the correct namespace (`ghcr.io/<owner>/<database>`)

### Permission Denied

The workflow requires:
- `contents: read` permission (to checkout code)
- `packages: write` permission (to push images)

These are automatically provided via `GITHUB_TOKEN` in GitHub Actions.

## Best Practices

1. **Test locally first**: Run `./build.sh --build` to verify Dockerfiles generate correctly
2. **Use semantic versioning**: Tag releases with semantic versions (e.g., `v1.0.0`)
3. **Write release notes**: Document what changed in each release
4. **Monitor builds**: Check the Actions tab to ensure builds succeed
5. **Verify images**: Pull and test images after publishing

## Manual Build Without GitHub Actions

If you need to build and push manually:

```bash
# 1. Authenticate with GHCR
echo $GITHUB_TOKEN | docker login ghcr.io -u USERNAME --password-stdin

# 2. Set registry
export DOCKER_REGISTRY=ghcr.io/<your-org>

# 3. Generate, build, and push
./build.sh --push

# Or for a specific database:
./build.sh --db mysql --push
```

## Additional Resources

- [GitHub Container Registry Documentation](https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry)
- [GitHub Actions Documentation](https://docs.github.com/en/actions)
- [Docker Buildx Documentation](https://docs.docker.com/buildx/working-with-buildx/)
