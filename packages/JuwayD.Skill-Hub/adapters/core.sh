#!/bin/bash

# Skill-Hub Runtime Adapter (Bash/Zsh Implementation for macOS/Linux/iOS)
COMMAND=$1
DESC=$2

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"
CONFIG_PATH="$BASE_DIR/config.json"
REGISTRY_CACHE_DIR="$BASE_DIR/.registry_cache"

# Basic JSON extraction (since jq might not be available on pure systems)
get_config_value() {
    local key=$1
    local value=$(grep -o "\"$key\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" "$CONFIG_PATH" | head -1 | awk -F '"' '{print $4}')
    echo "$value"
}

sync_registry() {
    local url=$(get_config_value "url")
    if [ -z "$url" ]; then
        echo "Error: Configuration missing registry URL." >&2
        exit 1
    fi

    if [ ! -d "$REGISTRY_CACHE_DIR" ]; then
        echo "Initializing local registry cache..."
        git clone "$url" "$REGISTRY_CACHE_DIR"
    else
        echo "Syncing local registry with remote..."
        (cd "$REGISTRY_CACHE_DIR" && git pull --rebase origin main)
    fi
    
    mkdir -p "$REGISTRY_CACHE_DIR/packages"
}

handle_publish() {
    if [ -z "$DESC" ]; then
        echo "Error: Please provide a description." >&2
        exit 1
    fi
    
    # Very basic search using find
    # Agent will typically pass exact paths or we do a broad search
    local search_path=$(get_config_value "skill_path")
    # Expanding tilde if present
    search_path="${search_path/#\~/$HOME}"
    
    # In pure shell, we might just rely on Agent providing exact path or do a basic grep
    # For simplicity, we assume we find the exact match folder name containing DESC
    local target_dir=$(find "$search_path" -maxdepth 1 -type d -iname "*$DESC*" | head -n 1)
    
    if [ -z "$target_dir" ] || [ ! -d "$target_dir" ]; then
        echo "Error: Could not find any local skill matching '$DESC'" >&2
        exit 1
    fi

    echo "Matched Local Skill: $target_dir"
    
    local metadata="$target_dir/skill.json"
    if [ ! -f "$metadata" ]; then
        echo "No skill.json found. Please initialize first." >&2
        exit 1
    fi
    
    local author=$(grep -o "\"author\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" "$metadata" | head -1 | awk -F '"' '{print $4}')
    local name=$(grep -o "\"name\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" "$metadata" | head -1 | awk -F '"' '{print $4}')
    local version=$(grep -o "\"version\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" "$metadata" | head -1 | awk -F '"' '{print $4}')
    
    author=${author:-Unknown}
    name=${name:-Unknown}
    version=${version:-1.0.0}
    
    local skill_id="${author}.${name}"
    skill_id=${skill_id// /_}
    
    echo "Publishing Skill: $name (ID: $skill_id)..."
    
    sync_registry
    
    local dest_dir="$REGISTRY_CACHE_DIR/packages/$skill_id"
    echo "Packaging to $dest_dir..."
    rm -rf "$dest_dir"
    cp -r "$target_dir" "$dest_dir"
    
    (
        cd "$REGISTRY_CACHE_DIR"
        git add .
        git commit -m "Auto publish: $skill_id v$version"
        echo "Pushing to remote registry..."
        git branch -M main
        if ! git push -u origin main; then
            echo "Push conflict detected. Automatically resolving (Fetch & Rebase)..."
            git pull --rebase origin main
            if ! git push -u origin main; then
                echo "Critical error: Failed to push to registry even after rebase." >&2
                exit 1
            fi
        fi
        echo "Successfully published to organization hub."
    )
}

handle_install() {
    if [ -z "$DESC" ]; then
        echo "Error: Please provide a description." >&2
        exit 1
    fi
    
    echo "Searching for '$DESC' in registry..."
    sync_registry
    
    local packages_dir="$REGISTRY_CACHE_DIR/packages"
    local best_match=$(find "$packages_dir" -maxdepth 1 -type d -iname "*$DESC*" -exec basename {} \; | head -n 1)
    
    if [ -z "$best_match" ]; then
        echo "Error: Could not find any skill matching '$DESC' in the registry." >&2
        exit 1
    fi
    
    local source_dir="$packages_dir/$best_match"
    echo "Found matching skill: $best_match"
    
    local install_default=$(get_config_value "install_default")
    install_default=${install_default:-workspace}
    
    local dest_root
    if [ "$install_default" = "global" ]; then
        dest_root=$(get_config_value "skill_path")
        dest_root="${dest_root/#\~/$HOME}"
        if [ -z "$dest_root" ]; then
            dest_root="$PWD/.agent/skills"
        fi
    else
        dest_root="$PWD/.agent/skills"
    fi
    
    local dest_dir="$dest_root/$best_match"
    echo "Installing to: $dest_dir..."
    
    mkdir -p "$dest_root"
    rm -rf "$dest_dir"
    cp -r "$source_dir" "$dest_dir"
    
    echo "Successfully installed."
}

if [ "$COMMAND" = "publish" ]; then
    handle_publish
elif [ "$COMMAND" = "install" ]; then
    handle_install
else
    echo "Unknown command: $COMMAND" >&2
    exit 1
fi
