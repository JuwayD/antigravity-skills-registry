param (
    [string]$Command = "",
    [string]$Description = ""
)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$BaseDir = Split-Path -Parent $ScriptDir
$ConfigPath = Join-Path $BaseDir "config.json"
$RegistryCacheDir = Join-Path $BaseDir ".registry_cache"

# Helper to read config safely
function Get-Config {
    if (Test-Path $ConfigPath) {
        return Get-Content $ConfigPath | ConvertFrom-Json
    }
    return $null
}

function Sync-Registry {
    $config = Get-Config
    if (-not $config -or -not $config.registry.url) {
        Write-Error "Error: Configuration missing registry URL."
        exit 1
    }
    
    $url = $config.registry.url
    if (-not (Test-Path $RegistryCacheDir)) {
        Write-Host "Initializing local registry cache..."
        git clone $url $RegistryCacheDir
    } else {
        Write-Host "Syncing local registry with remote..."
        Set-Location $RegistryCacheDir
        git pull --rebase origin main
        Set-Location $ScriptDir
    }
}

function Setup-PackagesDir {
    $packagesDir = Join-Path $RegistryCacheDir "packages"
    if (-not (Test-Path $packagesDir)) {
        New-Item -ItemType Directory -Path $packagesDir | Out-Null
    }
    return $packagesDir
}

function Handle-Publish {
    param([string]$Desc)
    
    $config = Get-Config
    $searchPaths = @($config.local.skill_path)
    $matches = @()
    
    foreach ($p in $searchPaths) {
        if (Test-Path $p) {
            $dirs = Get-ChildItem -Path $p -Directory
            foreach ($dir in $dirs) {
                if ($dir.Name.ToLower().Contains($Desc.ToLower())) {
                    $matches += $dir.FullName
                }
            }
        }
    }
    
    if ($matches.Count -eq 0) {
        Write-Error "Error: Could not find any local skill matching '$Desc'"
        exit 1
    }
    if ($matches.Count -gt 1) {
        Write-Error "AMBIGUITY_ERROR: Found multiple local skills matching '$Desc':"
        $matches | ForEach-Object { Write-Error " - $_" }
        Write-Error "Agent Notification: Please read this list to the user and ask them to specify exactly which one they meant."
        exit 1
    }
    
    $targetDir = $matches[0]
    Write-Host "Matched Local Skill: $targetDir"
    
    $skillJsonPath = Join-Path $targetDir "skill.json"
    if (-not (Test-Path $skillJsonPath)) {
        Write-Error "No skill.json found. Please initialize first."
        exit 1
    }
    
    $metadata = Get-Content $skillJsonPath | ConvertFrom-Json
    $author = if ($metadata.author) { $metadata.author } else { "Unknown" }
    $name = if ($metadata.name) { $metadata.name } else { "Unknown" }
    $version = if ($metadata.version) { $metadata.version } else { "1.0.0" }
    $skillId = "$author.$name" -replace "\s+", "_"
    
    Write-Host "Publishing Skill: $name (ID: $skillId)..."
    
    Sync-Registry
    $packagesDir = Setup-PackagesDir
    $destDir = Join-Path $packagesDir $skillId
    
    Write-Host "Packaging to $destDir..."
    if (Test-Path $destDir) {
        Remove-Item -Path $destDir -Recurse -Force
    }
    Copy-Item -Path $targetDir -Destination $destDir -Recurse -Force
    
    Set-Location $RegistryCacheDir
    try {
        git add .
        $commitMsg = "Auto publish: $skillId v$version"
        git commit -m "$commitMsg"
        
        Write-Host "Pushing to remote registry..."
        git branch -M main
        git push -u origin main
        
        if ($LASTEXITCODE -ne 0) {
            Write-Host "Push conflict detected. Automatically resolving (Fetch & Rebase)..."
            git pull --rebase origin main
            git push -u origin main
            if ($LASTEXITCODE -ne 0) {
                Write-Error "Critical error: Failed to push to registry even after rebase."
                exit 1
            }
        }
        Write-Host "Successfully published to organization hub."
    } finally {
        Set-Location $ScriptDir
    }
}

function Handle-Install {
    param([string]$Desc)
    
    if ([string]::IsNullOrWhiteSpace($Desc)) {
        Write-Error "Error: Please provide a description or name of the skill to install."
        exit 1
    }
    
    Write-Host "Searching for '$Desc' in registry..."
    Sync-Registry
    $packagesDir = Setup-PackagesDir
    
    $matches = @()
    if (Test-Path $packagesDir) {
        $items = Get-ChildItem -Path $packagesDir -Directory
        foreach ($item in $items) {
            if ($item.Name.ToLower().Contains($Desc.ToLower())) {
                $matches += $item.Name
            }
        }
    }
    
    if ($matches.Count -eq 0) {
        Write-Error "Error: Could not find any skill matching '$Desc' in the registry."
        exit 1
    }
    if ($matches.Count -gt 1) {
        Write-Error "AMBIGUITY_ERROR: Found multiple registry skills matching '$Desc':"
        $matches | ForEach-Object { Write-Error " - $_" }
        Write-Error "Agent Notification: Please read this list to the user and ask them to specify exactly which one they meant."
        exit 1
    }
    
    $bestMatch = $matches[0]
    $sourceDir = Join-Path $packagesDir $bestMatch
    Write-Host "Found matching skill: $bestMatch"
    
    $config = Get-Config
    $installDefault = if ($config.local.install_default) { $config.local.install_default } else { "workspace" }
    
    if ($installDefault -eq "global") {
        $destRoot = if ($config.local.skill_path) { $config.local.skill_path } else { Join-Path (Get-Location).Path ".agent\skills" }
    } else {
        $destRoot = Join-Path (Get-Location).Path ".agent\skills"
    }
    
    $destDir = Join-Path $destRoot $bestMatch
    Write-Host "Installing to: $destDir..."
    
    if (Test-Path $destDir) {
        Remove-Item -Path $destDir -Recurse -Force
    }
    if (-not (Test-Path $destRoot)) {
        New-Item -ItemType Directory -Path $destRoot | Out-Null
    }
    Copy-Item -Path $sourceDir -Destination $destDir -Recurse -Force
    
    Write-Host "Successfully installed."
}

if ($Command -eq "publish" -and $Description) {
    Handle-Publish -Desc $Description
} elseif ($Command -eq "install" -and $Description) {
    Handle-Install -Desc $Description
} else {
    Write-Error "Unknown command or missing arguments: $Command"
    exit 1
}
