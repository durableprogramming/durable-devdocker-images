#!/bin/bash
set -e

# Durable Devdocker Images Build Script
# Generates Docker images from templates for versions released in the last 6 months

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATES_DIR="$SCRIPT_DIR/templates"
BUILD_DIR="$SCRIPT_DIR/build"
REGISTRY="${DOCKER_REGISTRY:-durabledevdocker}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log() {
    echo -e "${BLUE}[build]${NC} $*" >&2
}

success() {
    echo -e "${GREEN}[build]${NC} $*" >&2
}

warn() {
    echo -e "${YELLOW}[build]${NC} $*" >&2
}

error() {
    echo -e "${RED}[build]${NC} $*" >&2
}

# Get versions from Docker Hub for the last 6 months
get_recent_versions() {
    local image=$1
    local months=${2:-6}

    log "Fetching versions for $image from the last $months months..."

    # Calculate the date 6 months ago
    local cutoff_date
    if date --version >/dev/null 2>&1; then
        # GNU date
        cutoff_date=$(date -d "$months months ago" +%s)
    else
        # BSD date (macOS)
        cutoff_date=$(date -v-${months}m +%s)
    fi

    # Fetch tags from Docker Hub API
    local page=1
    local versions=()

    while true; do
        local response=$(curl -s "https://registry.hub.docker.com/v2/repositories/library/$image/tags?page=$page&page_size=100")

        # Check if we got results
        if [ -z "$response" ] || [ "$response" = "null" ]; then
            break
        fi

        # Parse the response to get tags and their last updated dates (main tags only, no subtags)
        local page_versions=$(echo "$response" | jq -r '.results[] | select(.name | test("^[0-9]+\\.[0-9]+(\\.[0-9]+)?$")) | "\(.name)|\(.last_updated)"' 2>/dev/null || true)

        if [ -z "$page_versions" ]; then
            break
        fi

        # Filter versions by date
        while IFS='|' read -r version last_updated; do
            if [ -n "$last_updated" ]; then
                local version_date=$(date -d "$last_updated" +%s 2>/dev/null || date -j -f "%Y-%m-%dT%H:%M:%S" "${last_updated%.*}" +%s 2>/dev/null || echo "0")
                if [ "$version_date" -ge "$cutoff_date" ]; then
                    versions+=("$version")
                fi
            fi
        done <<< "$page_versions"

        # Check if there's a next page
        local next=$(echo "$response" | jq -r '.next' 2>/dev/null)
        if [ "$next" = "null" ] || [ -z "$next" ]; then
            break
        fi

        page=$((page + 1))
    done

    # Return unique versions, sorted
    printf '%s\n' "${versions[@]}" | sort -V | uniq
}

# Get latest N versions as fallback
get_latest_versions() {
    local image=$1
    local count=${2:-5}

    log "Fetching latest $count versions for $image..."

    curl -s "https://registry.hub.docker.com/v2/repositories/library/$image/tags?page_size=$count" | \
        jq -r '.results[] | select(.name | test("^[0-9]+\\.[0-9]+(\\.[0-9]+)?$")) | .name' | \
        head -n "$count"
}

# Check if a version has images for the current platform
check_platform_availability() {
    local image=$1
    local version=$2
    local platform=${3:-linux/amd64}

    # Query Docker Hub API for tag info
    local tag_info=$(curl -s "https://registry.hub.docker.com/v2/repositories/library/$image/tags/$version")

    # Check if the tag has images for our platform
    local has_platform=$(echo "$tag_info" | jq -r --arg platform "$platform" '.images[]? | select(.os + "/" + .architecture == $platform) | .architecture' 2>/dev/null)

    if [ -n "$has_platform" ]; then
        return 0
    else
        return 1
    fi
}

# Generate Dockerfile and entrypoint from template
generate_image() {
    local db_type=$1
    local version=$2

    local template_dir="$TEMPLATES_DIR/$db_type"
    local output_dir="$BUILD_DIR/$db_type/$version"

    if [ ! -d "$template_dir" ]; then
        error "Template directory not found: $template_dir"
        return 1
    fi

    log "Generating $db_type:$version"

    # Create output directory
    mkdir -p "$output_dir"

    # Process Dockerfile template
    if [ -f "$template_dir/Dockerfile.template" ]; then
        sed "s/{{VERSION}}/$version/g" "$template_dir/Dockerfile.template" > "$output_dir/Dockerfile"
    else
        error "Dockerfile.template not found in $template_dir"
        return 1
    fi

    # Copy entrypoint script
    if [ -f "$template_dir/entrypoint.sh" ]; then
        cp "$template_dir/entrypoint.sh" "$output_dir/entrypoint.sh"
        chmod +x "$output_dir/entrypoint.sh"
    else
        error "entrypoint.sh not found in $template_dir"
        return 1
    fi

    success "Generated $db_type:$version in $output_dir"
}

# Build Docker image
build_image() {
    local db_type=$1
    local version=$2
    local push=${3:-false}

    local build_dir="$BUILD_DIR/$db_type/$version"
    local image_tag="$REGISTRY/$db_type:$version"

    if [ ! -d "$build_dir" ]; then
        error "Build directory not found: $build_dir"
        return 1
    fi

    log "Building $image_tag"

    if docker build -t "$image_tag" "$build_dir"; then
        success "Built $image_tag"

        # Also tag as latest for the most recent version
        if [ "$push" = "true" ]; then
            log "Pushing $image_tag"
            docker push "$image_tag"
            success "Pushed $image_tag"
        fi
    else
        error "Failed to build $image_tag"
        return 1
    fi
}

# Process a database type
process_database() {
    local db_type=$1
    local use_fallback=${2:-false}
    local build_images=${3:-false}
    local push_images=${4:-false}

    log "Processing $db_type"

    # Get versions
    local versions
    if [ "$use_fallback" = "true" ]; then
        versions=$(get_latest_versions "$db_type" 5)
    else
        versions=$(get_recent_versions "$db_type" 6)

        # Fallback to latest versions if no recent versions found
        if [ -z "$versions" ]; then
            warn "No versions found in last 6 months for $db_type, using latest versions"
            versions=$(get_latest_versions "$db_type" 5)
        fi
    fi

    if [ -z "$versions" ]; then
        error "No versions found for $db_type"
        return 1
    fi

    log "Found versions for $db_type:"
    echo "$versions" | sed 's/^/  /'

    # Generate images
    local version_count=0
    local skipped_count=0
    local failed_count=0
    while IFS= read -r version; do
        if [ -n "$version" ]; then
            # Check platform availability before processing
            if [ "$build_images" = "true" ]; then
                if ! check_platform_availability "$db_type" "$version"; then
                    warn "Skipping $db_type:$version - not available for linux/amd64"
                    skipped_count=$((skipped_count + 1))
                    continue
                fi
            fi

            generate_image "$db_type" "$version" || {
                error "Failed to generate $db_type:$version"
                failed_count=$((failed_count + 1))
                continue
            }

            if [ "$build_images" = "true" ]; then
                build_image "$db_type" "$version" "$push_images" || {
                    error "Failed to build $db_type:$version, continuing..."
                    failed_count=$((failed_count + 1))
                    continue
                }
            fi

            version_count=$((version_count + 1))
        fi
    done <<< "$versions"

    success "Processed $version_count versions for $db_type"
    if [ $skipped_count -gt 0 ]; then
        warn "Skipped $skipped_count versions (platform unavailable)"
    fi
    if [ $failed_count -gt 0 ]; then
        warn "Failed $failed_count versions"
    fi
}

# Main function
main() {
    local databases=()
    local use_fallback=false
    local build_images=false
    local push_images=false

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --db)
                databases+=("$2")
                shift 2
                ;;
            --fallback)
                use_fallback=true
                shift
                ;;
            --build)
                build_images=true
                shift
                ;;
            --push)
                push_images=true
                build_images=true
                shift
                ;;
            --help)
                echo "Usage: $0 [OPTIONS]"
                echo ""
                echo "Options:"
                echo "  --db <name>     Process specific database (can be specified multiple times)"
                echo "  --fallback      Use latest N versions instead of versions from last 6 months"
                echo "  --build         Build Docker images after generating"
                echo "  --push          Push Docker images after building"
                echo "  --help          Show this help message"
                echo ""
                echo "Environment variables:"
                echo "  DOCKER_REGISTRY Override the default registry (default: durabledevdocker)"
                echo "                  Example: DOCKER_REGISTRY=ghcr.io/myorg ./build.sh"
                echo ""
                echo "Supported databases: mysql, postgres"
                echo ""
                echo "Examples:"
                echo "  $0                                    # Generate all images"
                echo "  $0 --db mysql                         # Generate only MySQL images"
                echo "  $0 --build                            # Generate and build all images"
                echo "  $0 --db postgres --build              # Generate and build PostgreSQL images"
                echo "  $0 --push                             # Generate, build, and push all images"
                echo "  DOCKER_REGISTRY=ghcr.io/owner $0 --push  # Push to GitHub Container Registry"
                exit 0
                ;;
            *)
                error "Unknown option: $1"
                exit 1
                ;;
        esac
    done

    # If no databases specified, process all
    if [ ${#databases[@]} -eq 0 ]; then
        databases=(mysql postgres)
    fi

    # Check dependencies
    if ! command -v jq &> /dev/null; then
        error "jq is required but not installed. Please install jq."
        exit 1
    fi

    if [ "$build_images" = "true" ] && ! command -v docker &> /dev/null; then
        error "docker is required for building images but not installed."
        exit 1
    fi

    # Create build directory
    mkdir -p "$BUILD_DIR"

    log "Starting image generation..."
    log "Templates directory: $TEMPLATES_DIR"
    log "Build directory: $BUILD_DIR"
    log "Registry: $REGISTRY"

    # Process each database
    for db in "${databases[@]}"; do
        if [ -d "$TEMPLATES_DIR/$db" ]; then
            process_database "$db" "$use_fallback" "$build_images" "$push_images"
        else
            warn "Template not found for $db, skipping"
        fi
    done

    success "Image generation complete!"
    log "Generated images are in: $BUILD_DIR"
}

main "$@"
