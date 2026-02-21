import os
import sys
import json
import subprocess
import shutil

ARGS = sys.argv[1:]
if not ARGS:
    print("Usage: core.py <command> [args]")
    sys.exit(1)

COMMAND = ARGS[0]
BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CONFIG_PATH = os.path.join(BASE_DIR, 'config.json')
REGISTRY_CACHE_DIR = os.path.join(BASE_DIR, '.registry_cache')

def run_shell(cmd, cwd=None):
    try:
        result = subprocess.run(cmd, shell=True, text=True, capture_output=True, cwd=cwd or os.getcwd())
        if result.returncode != 0:
            return None
        return result.stdout.strip()
    except Exception:
        return None

def get_search_paths():
    try:
        with open(CONFIG_PATH, 'r', encoding='utf-8') as f:
            config = json.load(f)
        return [config.get('local', {}).get('skill_path', '')]
    except Exception:
        return []

def scan_for_skills(description):
    paths = get_search_paths()
    matches = []
    
    for p in paths:
        if not os.path.exists(p):
            continue
        for item in os.listdir(p):
            item_path = os.path.join(p, item)
            if os.path.isdir(item_path):
                if description.lower() in item.lower():
                    matches.append(item_path)
    return matches

def sync_registry():
    try:
        with open(CONFIG_PATH, 'r', encoding='utf-8') as f:
            config = json.load(f)
        registry_url = config['registry']['url']
    except Exception as e:
        print(f"Error reading config: {e}")
        sys.exit(1)
        
    if not os.path.exists(REGISTRY_CACHE_DIR):
        print("Initializing local registry cache...")
        run_shell(f'git clone "{registry_url}" "{REGISTRY_CACHE_DIR}"')
    else:
        print("Syncing local registry with remote...")
        run_shell(f'git pull --rebase origin main', cwd=REGISTRY_CACHE_DIR)
        
    packages_dir = os.path.join(REGISTRY_CACHE_DIR, 'packages')
    if not os.path.exists(packages_dir):
        os.makedirs(packages_dir, exist_ok=True)

def handle_publish(description):
    matches = scan_for_skills(description)
    if not matches:
        print(f"Error: Could not find any local skill matching \"{description}\"", file=sys.stderr)
        sys.exit(1)
    if len(matches) > 1:
        error_msg = f"AMBIGUITY_ERROR: Found multiple local skills matching \"{description}\":\n" + "\n".join([f" - {m}" for m in matches])
        error_msg += "\nAgent Notification: Please read this list to the user and ask them to specify exactly which one they meant."
        print(error_msg, file=sys.stderr)
        sys.exit(1)
        
    target_dir = matches[0]
    print(f"Matched Local Skill: {target_dir}")
    
    skill_json_path = os.path.join(target_dir, 'skill.json')
    if not os.path.exists(skill_json_path):
        print("No skill.json found. Please initialize first.")
        sys.exit(1)
        
    try:
        with open(skill_json_path, 'r', encoding='utf-8') as f:
            metadata = json.load(f)
    except Exception as e:
        print(f"Error parsing JSON: {e}")
        sys.exit(1)
        
    skill_id = f"{metadata.get('author', 'Unknown')}.{metadata.get('name', 'Unknown')}".replace(" ", "_")
    version = metadata.get('version', '1.0.0')
    print(f"Publishing Skill: {metadata.get('name')} (ID: {skill_id})...")
    
    sync_registry()
    
    dest_dir = os.path.join(REGISTRY_CACHE_DIR, 'packages', skill_id)
    print(f"Packaging to {dest_dir}...")
    if os.path.exists(dest_dir):
        shutil.rmtree(dest_dir)
    shutil.copytree(target_dir, dest_dir)
    
    run_shell('git add .', cwd=REGISTRY_CACHE_DIR)
    commit_msg = f"Auto publish: {skill_id} v{version}"
    run_shell(f'git commit -m "{commit_msg}"', cwd=REGISTRY_CACHE_DIR)
    
    print("Pushing to remote registry...")
    run_shell('git branch -M main', cwd=REGISTRY_CACHE_DIR)
    push_success = run_shell('git push -u origin main', cwd=REGISTRY_CACHE_DIR)
    
    if push_success is None:
        print("Push conflict detected. Automatically resolving (Fetch & Rebase)...")
        run_shell('git pull --rebase origin main', cwd=REGISTRY_CACHE_DIR)
        push_success_retry = run_shell('git push -u origin main', cwd=REGISTRY_CACHE_DIR)
        if push_success_retry is None:
            print("Critical error: Failed to push to registry even after rebase.", file=sys.stderr)
            sys.exit(1)
            
    print("Successfully published to organization hub.")

def handle_install(description):
    if not description:
        print("Error: Please provide a description or name of the skill to install.", file=sys.stderr)
        sys.exit(1)
        
    print(f"Searching for \"{description}\" in registry...")
    sync_registry()
    
    packages_dir = os.path.join(REGISTRY_CACHE_DIR, 'packages')
    matches = []
    if os.path.exists(packages_dir):
        for item in os.listdir(packages_dir):
            if description.lower() in item.lower():
                matches.append(item)
                
    if not matches:
        print(f"Error: Could not find any skill matching \"{description}\" in the registry.", file=sys.stderr)
        sys.exit(1)
        
    if len(matches) > 1:
        error_msg = f"AMBIGUITY_ERROR: Found multiple registry skills matching \"{description}\":\n" + "\n".join([f" - {m}" for m in matches])
        error_msg += "\nAgent Notification: Please read this list to the user and ask them to specify exactly which one they meant."
        print(error_msg, file=sys.stderr)
        sys.exit(1)
        
    best_match = matches[0]
    source_dir = os.path.join(packages_dir, best_match)
    print(f"Found matching skill: {best_match}")
    
    try:
        with open(CONFIG_PATH, 'r', encoding='utf-8') as f:
            config = json.load(f)
        install_default = config.get('local', {}).get('install_default', 'workspace')
    except Exception:
        install_default = 'workspace'
        
    if install_default == 'global':
        dest_root = config.get('local', {}).get('skill_path', os.path.join(os.getcwd(), '.agent', 'skills'))
    else:
        dest_root = os.path.join(os.getcwd(), '.agent', 'skills')
        
    dest_dir = os.path.join(dest_root, best_match)
    print(f"Installing to: {dest_dir}...")
    
    if os.path.exists(dest_dir):
        shutil.rmtree(dest_dir)
    shutil.copytree(source_dir, dest_dir)
    
    print("Successfully installed.")

if COMMAND == 'publish' and len(ARGS) > 1:
    handle_publish(ARGS[1])
elif COMMAND == 'install' and len(ARGS) > 1:
    handle_install(ARGS[1])
else:
    print(f"Unknown command or missing arguments: {COMMAND}")
    sys.exit(1)
