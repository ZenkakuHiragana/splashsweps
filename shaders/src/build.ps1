# Written By Ficool originally, Modified by EthanTheGreat
# Resolves workaround for hotloading shaders.

[CmdletBinding()]
param (
    [Parameter(Mandatory=$true)][System.IO.FileInfo]$File,
    [Parameter(Mandatory=$false)][System.UInt32]$Threads
)

# Sanity check
if ($File.Extension -ne ".hlsl") {
    Write-Host "[Abort] File is not HLSL: $File"
    return
}

$materialPath = Join-Path $PSScriptRoot ".." ".." "materials" "splashsweps" "shaders"
$shaderPath = Join-Path $PSScriptRoot ".." "fxc" "splashsweps"
$refreshCountPath = Join-Path $PSScriptRoot ".." ".." ".vscode"

# Retrieve specification from file name
$baseFileName = $File.BaseName
$baseName = $baseFileName -replace "_(vs|ps|gs|hs|ds|cs|ms)?[23][x0]$", ""
$baseShaderType = [regex]::Match($baseFileName, "_(vs|ps|gs|hs|ds|cs|ms)?[23][x0]$").Groups[1].Value
$vmtPath = Join-Path $materialPath "$baseName.vmt"
$Version = switch -Regex ($baseFileName) {
    "_vs2"  { "20b" }
    "_vs3"  { "30"  }
    "_ps2"  { "20b" }
    "_ps3"  { "30"  }
    default { "30"  }
}
if ($Version -notin @("20b", "30", "40", "41", "50", "51")) {
    Write-Host "[Abort] Version = $Version"
	return
}
if ($baseShaderType -notin @("vs", "ps")) {
    Write-Host "[Abort] Shader Type = $ShaderType"
    return
}

function New-One() {
    param([string]$shaderType)
    
    $isPixelShader = $shaderType -eq "ps"
    $isVertexShader = $shaderType -eq "vs"
    $shaderSuffix = "_$shaderType$Version"
    Write-Output "Writing Shaders for $Version as: $baseName$shaderSuffix..."
    if (-not (Test-Path "$baseName$shaderSuffix.hlsl")) {
        Write-Host "[Abort] Not found: $baseName$shaderSuffix.hlsl"
        return
    }

    # Run ShaderCompile
    # https://github.com/SCell555/ShaderCompile
    if ($Threads -ne 0) {
        ShaderCompile `
            -threads $Threads `
            -ver $Version `
            -optimize 3 `
            -shaderpath $PWD `
            "$baseName$shaderSuffix.hlsl"
    }
    else {
        ShaderCompile `
            -ver $Version `
            -optimize 3 `
            -shaderpath $PWD `
            "$baseName$shaderSuffix.hlsl"
    }

    # Move the output
    New-Item -ItemType Directory -Path $shaderPath -Force -ErrorAction SilentlyContinue | Out-Null
    Move-Item -Force `
        -LiteralPath (Join-Path $PWD "shaders" "fxc" "$baseName$shaderSuffix.vcs") `
        -Destination $shaderPath
    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue -LiteralPath (Join-Path $PWD "include")
    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue -LiteralPath (Join-Path $PWD "shaders")

    # Define the file path for refresh count
    $countFilePath = Join-Path $refreshCountPath "refresh_count_$shaderType.txt"

    # Check if the file exists; if not, create it with a default value of 0
    if (-not (Test-Path $countFilePath)) {
        New-Item -ItemType Directory -Path $refreshCountPath -Force -ErrorAction SilentlyContinue | Out-Null
        "0" | Set-Content -LiteralPath $countFilePath
    }

    # Read the file and convert the content to an integer
    $count = Get-Content -LiteralPath $countFilePath | ForEach-Object { [int]$_ }
    $oldCount = $count

    # Write the updated count back to the file
    ++$count | Set-Content -LiteralPath $countFilePath

    # Display the new count for debugging
    Write-Host "Update:  #$count"

    $oldCount = $oldCount.ToString()
    $count = $count.ToString()

    $paramValue = "${count}_$baseName$shaderSuffix"
    if (Test-Path $vmtPath) {
        $vmtPixelShaderValue = ""
        $vmtVertexShaderValue = ""
        $vmtContents = Get-Content $vmtPath -Raw
        $vertexShaderMatch = [regex]::Match($vmtContents, '"\$vertexshader"\s+"([^"]*)"')
        if ($vertexShaderMatch.Success) {
            $vmtVertexShaderValue = $vertexShaderMatch.Groups[1].Value
            Write-Host "Found existing vertex shader value: $vmtVertexShaderValue"
        }
        $pixelShaderMatch = [regex]::Match($vmtContents, '"\$pixshader"\s+"([^"]*)"')
        if ($pixelShaderMatch.Success) {
            $vmtPixelShaderValue = $pixelShaderMatch.Groups[1].Value
            Write-Host "Found existing pixel shader value: $vmtPixelShaderValue"
        }
        if ($isVertexShader) {
            $content = $content -replace '"\$vertexshader"\s+"[^"]*"', "`"`$vertexshader`" `"$paramValue`""
        }
        if ($isPixelShader) { 
            $content = $content -replace '"\$pixshader"\s+"[^"]*"', "`"`$pixshader`" `"$paramValue`""
        }
        New-Item -ItemType Directory -Path $materialPath -Force -ErrorAction SilentlyContinue | Out-Null
        Set-Content -LiteralPath $vmtPath -Value $content
    }

    # Determine Output File (Shader) & Delete 
    $vcsPath = Join-Path $shaderPath "$baseName$shaderSuffix.vcs"

    # Copy the file and overwrite if it exists
    if (Test-Path $vcsPath) {
        $newFileName = "${count}_$baseName$shaderSuffix.vcs"
        $newDestinationPath = Join-Path $shaderPath $newFileName
        Copy-Item -LiteralPath $vcsPath -Destination $newDestinationPath -Force
        Write-Host "Copied:  $baseName$shaderSuffix.vcs  ->  $newFileName"
    }

    # Remove old files
    $oldName = "${oldCount}_$baseName$shaderSuffix.vcs"
    $destructionPath = Join-Path $shaderPath $oldName

    # Check if the file exists and remove it
    if (Test-Path $destructionPath) {
        Remove-Item -LiteralPath $destructionPath -Force -ErrorAction SilentlyContinue
        Write-Host "Removed: $oldName"
    }
}

New-One("vs")
New-One("ps")
