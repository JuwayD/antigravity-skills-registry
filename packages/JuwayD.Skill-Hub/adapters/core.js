#!/usr/bin/env node
/**
 * Skill-Hub Runtime Adapter (Node.js Implementation)
 * This script is the primary entry point for high-performance Node.js environments.
 */
const { execSync } = require('child_process');
const fs = require('fs');
const path = require('path');

const ARGS = process.argv.slice(2);
const COMMAND = ARGS[0];

const CONFIG_PATH = path.join(__dirname, '..', 'config.json');
const REGISTRY_CACHE_DIR = path.join(__dirname, '..', '.registry_cache');

// Get search paths (Workspace + Global)
function getSearchPaths() {
    const config = JSON.parse(fs.readFileSync(CONFIG_PATH, 'utf8'));
    const globalPath = config.local.skill_path;
    // For simplicity in this demo, we assume the agent provides workspace info.
    // In real execution, we scan parent directories or .agent folders.
    return [globalPath];
}

// Hierarchical scanner for skills
function scanForSkills(description) {
    const paths = getSearchPaths();
    let matches = [];

    paths.forEach(p => {
        if (!fs.existsSync(p)) return;
        const items = fs.readdirSync(p);
        items.forEach(item => {
            const itemPath = path.join(p, item);
            if (fs.statSync(itemPath).isDirectory()) {
                if (item.toLowerCase().includes(description.toLowerCase())) {
                    matches.push(itemPath);
                }
            }
        });
    });
    return matches;
}

// Helper to run shell commands
function runShell(cmd, cwd = process.cwd()) {
    try {
        return execSync(cmd, { encoding: 'utf8', stdio: 'pipe', cwd }).trim();
    } catch (e) {
        return null; // Return null on error to allow graceful handling
    }
}

// Sync Registry Cache (The "Hidden" Git wrapper)
function syncRegistry() {
    const config = JSON.parse(fs.readFileSync(CONFIG_PATH, 'utf8'));
    const registryUrl = config.registry.url;

    if (!fs.existsSync(REGISTRY_CACHE_DIR)) {
        console.log("Initializing local registry cache...");
        runShell(`git clone ${registryUrl} "${REGISTRY_CACHE_DIR}"`);
    } else {
        console.log("Syncing local registry with remote...");
        // Fetch and rebase to ensure we have the latest without ugly merge commits
        runShell(`git pull --rebase origin main`, REGISTRY_CACHE_DIR);
    }

    // Ensure packages directory exists
    const packagesDir = path.join(REGISTRY_CACHE_DIR, 'packages');
    if (!fs.existsSync(packagesDir)) {
        fs.mkdirSync(packagesDir, { recursive: true });
    }
}

// Helper to copy directory recursively
function copyDirRecursiveSync(source, target) {
    if (!fs.existsSync(target)) fs.mkdirSync(target, { recursive: true });
    const files = fs.readdirSync(source);
    for (const file of files) {
        // Skip registry cache and git metadata to prevent infinite recursion
        if (file === '.registry_cache' || file === '.git' || file === 'node_modules') continue;

        const curSource = path.join(source, file);
        const curTarget = path.join(target, file);
        if (fs.lstatSync(curSource).isDirectory()) {
            copyDirRecursiveSync(curSource, curTarget);
        } else {
            fs.copyFileSync(curSource, curTarget);
        }
    }
}

// Logic for Search / Install / Publish
const Handlers = {
    'detect': () => {
        const results = {
            node: process.version,
            python: runShell('python --version'),
            git: runShell('git --version'),
            p4: runShell('p4 -V')
        };
        console.log(JSON.stringify(results, null, 2));
    },
    'publish': (description) => {
        const matches = scanForSkills(description);
        if (matches.length === 0) {
            console.error(`Error: Could not find any local skill matching "${description}"`);
            process.exit(1);
        }
        if (matches.length > 1) {
            console.error(`AMBIGUITY_ERROR: Found multiple local skills matching "${description}":\n` +
                matches.map(m => ` - ${m}`).join('\n') +
                `\nAgent Notification: Please read this list to the user and ask them to specify exactly which one they meant.`);
            process.exit(1);
        }

        const targetDir = matches[0];

        console.log(`Matched Local Skill: ${targetDir}`);
        const skillMetadataPath = path.join(targetDir, 'skill.json');

        if (!fs.existsSync(skillMetadataPath)) {
            console.log("No skill.json found. Initializing automatically...");
            Handlers['init'](targetDir);
        }

        const metadata = JSON.parse(fs.readFileSync(path.join(targetDir, 'skill.json'), 'utf8'));
        const skillId = `${metadata.author}.${metadata.name}`.replace(/\s+/g, '_');
        console.log(`Publishing Skill: ${metadata.name} (ID: ${skillId})...`);

        // 1. Sync registry first
        syncRegistry();

        // 2. Copy files to registry cache
        const destDir = path.join(REGISTRY_CACHE_DIR, 'packages', skillId);
        console.log(`Packaging to ${destDir}...`);
        copyDirRecursiveSync(targetDir, destDir);

        // 3. Git Add & Commit
        runShell('git add .', REGISTRY_CACHE_DIR);
        const commitMsg = `Auto publish: ${skillId} v${metadata.version}`;
        runShell(`git commit -m "${commitMsg}"`, REGISTRY_CACHE_DIR);

        // 4. Git Push with Collision Retry Logic
        console.log(`Pushing to remote registry...`);
        // Ensure we are on main branch for first-time pushes
        runShell('git branch -M main', REGISTRY_CACHE_DIR);
        let pushSuccess = runShell('git push -u origin main', REGISTRY_CACHE_DIR);

        if (pushSuccess === null) {
            console.log("Push conflict detected. Automatically resolving (Fetch & Rebase)...");
            // Only pull if remote has a main branch tracking setup
            runShell('git pull --rebase origin main', REGISTRY_CACHE_DIR);
            pushSuccess = runShell('git push -u origin main', REGISTRY_CACHE_DIR);
            if (pushSuccess === null) {
                console.error("Critical error: Failed to push to registry even after rebase.");
                process.exit(1);
            }
        }

        console.log("Successfully published to organization hub.");
    },
    'install': (description) => {
        if (!description) {
            console.error("Error: Please provide a description or name of the skill to install.");
            process.exit(1);
        }

        console.log(`Searching for "${description}" in registry...`);
        // 1. Force sync to get latest remote updates
        syncRegistry();

        // 2. Look for match in packages dir
        const packagesDir = path.join(REGISTRY_CACHE_DIR, 'packages');
        let matches = [];

        if (fs.existsSync(packagesDir)) {
            const items = fs.readdirSync(packagesDir);
            items.forEach(item => {
                if (item.toLowerCase().includes(description.toLowerCase())) {
                    matches.push(item);
                }
            });
        }

        if (matches.length === 0) {
            console.error(`Error: Could not find any skill matching "${description}" in the registry.`);
            process.exit(1);
        }

        if (matches.length > 1) {
            console.error(`AMBIGUITY_ERROR: Found multiple registry skills matching "${description}":\n` +
                matches.map(m => ` - ${m}`).join('\n') +
                `\nAgent Notification: Please read this list to the user and ask them to specify exactly which one they meant.`);
            process.exit(1);
        }

        const bestMatch = matches[0];
        const sourceDir = path.join(packagesDir, bestMatch);
        console.log(`Found matching skill: ${bestMatch}`);

        // 3. Determine destination
        const config = JSON.parse(fs.readFileSync(CONFIG_PATH, 'utf8'));
        const installDefault = config.local.install_default || 'workspace';

        // Use process.cwd() as workspace
        let destRoot = installDefault === 'global' ? config.local.skill_path : path.join(process.cwd(), '.agent', 'skills');

        const destDir = path.join(destRoot, bestMatch);

        console.log(`Installing to: ${destDir}...`);
        copyDirRecursiveSync(sourceDir, destDir);

        console.log("Successfully installed.");
    },
    'init': (targetDir) => {
        const skillJson = {
            name: path.basename(targetDir),
            version: "1.0.0",
            description: "Replace with description",
            author: "Anonymous",
            keywords: []
        };
        fs.writeFileSync(path.join(targetDir, 'skill.json'), JSON.stringify(skillJson, null, 2));
        console.log("Created skill.json template.");
    },
    'config': (args) => {
        // Expected args format: "key value" or similar passed from ARGS
        // To keep it simple, we take ARGS[1] as key path and ARGS.slice(2).join(' ') as value
        const keyPath = process.argv[3];
        const value = process.argv.slice(4).join(' ');

        if (!keyPath || !value) {
            console.error("Usage: core.js config <key.subkey> <value>");
            return;
        }

        const config = JSON.parse(fs.readFileSync(CONFIG_PATH, 'utf8'));
        const keys = keyPath.split('.');
        if (keys.length === 2 && config[keys[0]]) {
            config[keys[0]][keys[1]] = value;
        } else {
            console.error(`Invalid config key: ${keyPath}`);
            return;
        }

        fs.writeFileSync(CONFIG_PATH, JSON.stringify(config, null, 4));
        console.log(`[Config Updated] ${keyPath} = ${value}`);
    }
};

if (Handlers[COMMAND]) {
    Handlers[COMMAND](ARGS[1]);
} else {
    console.error(`Unknown command: ${COMMAND}`);
}
