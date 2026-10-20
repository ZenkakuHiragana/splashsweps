# Written By Ficool originally, Modified by EthanTheGreat
# Resolves workaround for hotloading shaders.
#
# Compiles each given shader file in order, e.g. build.ps1 inkmesh_vs30.hlsl inkmesh_ps30.hlsl
# Run it from this directory; the files are looked up by their names in the current directory.
# While GMOD is running, the output also gets a new numbered name, and every VMT in materials/splashsweps/shaders
# that refers to the shader is rewritten to that name, as GMOD reads a shader file only once per name.
# Vertex and pixel shaders are built separately. Build both when the data passed between them changes.

[CmdletBinding()]
param (
    [Parameter(Mandatory=$true, Position=0, ValueFromRemainingArguments=$true)][System.IO.FileInfo[]]$Files,
    [Parameter(Mandatory=$false)][System.UInt32]$Threads
)

$materialPath = Join-Path $PSScriptRoot ".." ".." "materials" "splashsweps" "shaders"
$shaderPath = Join-Path $PSScriptRoot ".." "fxc" "splashsweps"
$refreshCountPath = Join-Path $PSScriptRoot ".." ".." ".vscode"

# Retrieve specification from file name, and check all files before compiling any of them
$specs = [System.Collections.Generic.List[PSCustomObject]]::new()
foreach ($File in $Files) {
    if ($File.Extension -ne ".hlsl") {
        Write-Host "[Abort] File is not HLSL: $File"
        return
    }

    $shaderName = $File.BaseName
    $shaderType = [regex]::Match($shaderName, "_(vs|ps|gs|hs|ds|cs|ms)?[23][x0]$").Groups[1].Value
    $Version = switch -Regex ($shaderName) {
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
    if ($shaderType -notin @("vs", "ps")) {
        Write-Host "[Abort] Shader Type = $shaderType"
        return
    }
    if (-not (Test-Path "$shaderName.hlsl")) {
        Write-Host "[Abort] Not found: $shaderName.hlsl"
        return
    }

    $specs.Add([PSCustomObject]@{ Name = $shaderName; Type = $shaderType; Version = $Version })
}

# Replaces every value of $paramKey that refers to the shader in the VMT text, numbered or not.
# Tokens are split as KeyValues::ReadToken does: whitespace and // comments are skipped,
# a quoted token ends at the next quote, and an unquoted one ends at whitespace, a quote, or a brace.
function Update-ShaderReference([string]$text, [string]$paramKey, [string]$shaderName, [string]$paramValue) {
    $tokens = [regex]::Matches($text, '(?<skip>\s+|//[^\n]*)|(?<quoted>"[^"]*"?)|(?<brace>[{}])|[^\s"{}]+') |
        Where-Object { -not $_.Groups["skip"].Success }
    $valuePattern = "^splashsweps/(\d+_)?$([regex]::Escape($shaderName))$"
    $isKey = $true
    $key = $null
    $replacements = @()
    foreach ($token in $tokens) {
        $isQuoted = $token.Groups["quoted"].Success
        $content = if ($isQuoted) { $token.Value.Trim('"') } else { $token.Value }
        if ($token.Groups["brace"].Success) {
            $isKey = $true # A block starts or ends, so a key follows
        }
        elseif (-not $isQuoted -and $content -match '^\[.*\]$') {
            continue # A conditional such as [$X360] follows a value
        }
        elseif ($isKey) {
            $key = $content
            $isKey = $false
        }
        else {
            if ($key -eq "`$$paramKey" -and $content -match $valuePattern) {
                $quote = if ($isQuoted) { '"' } else { '' }
                $replacements += , @($token.Index, $token.Length, "$quote$paramValue$quote")
            }
            $isKey = $true
        }
    }
    for ($i = $replacements.Count - 1; $i -ge 0; $i--) {
        $index, $length, $value = $replacements[$i]
        $text = $text.Remove($index, $length).Insert($index, $value)
    }
    return $text
}

function New-One() {
    param([PSCustomObject]$spec)

    $shaderName = $spec.Name
    $shaderType = $spec.Type
    Write-Output "Writing Shaders for $($spec.Version) as: $shaderName..."

    # Run ShaderCompile
    # https://github.com/SCell555/ShaderCompile
    if ($Threads -ne 0) {
        ShaderCompile `
            -threads $Threads `
            -ver $spec.Version `
            -optimize 3 `
            -shaderpath $PWD `
            "$shaderName.hlsl"
    }
    else {
        ShaderCompile `
            -ver $spec.Version `
            -optimize 3 `
            -shaderpath $PWD `
            "$shaderName.hlsl"
    }

    if ($LASTEXITCODE -ne 0) {
        Write-Host "[Abort] ShaderCompile failed with exit code $LASTEXITCODE"
        exit $LASTEXITCODE
    }

    # Define the file path for refresh count
    $countFilePath = Join-Path $refreshCountPath "refresh_count_$shaderType.txt"

    # Check if the file exists; if not, create it with a default value of 0
    if (-not (Test-Path $countFilePath)) {
        New-Item -ItemType Directory -Path $refreshCountPath -Force -ErrorAction SilentlyContinue | Out-Null
        "0" | Set-Content -LiteralPath $countFilePath
    }

    # Read the file and convert the content to an integer
    $count = Get-Content -LiteralPath $countFilePath | ForEach-Object { [int]$_ }

    # Remove old numbered files of this shader, whichever count they were written with
    $numberedPattern = "^\d+_$([regex]::Escape($shaderName))\.vcs$"
    Get-ChildItem -LiteralPath $shaderPath -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match $numberedPattern } |
        ForEach-Object {
            Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue
            Write-Host "Removed: $($_.Name)"
        }

    # Move the output
    New-Item -ItemType Directory -Path $shaderPath -Force -ErrorAction SilentlyContinue | Out-Null
    Move-Item -Force `
        -LiteralPath (Join-Path $PWD "shaders" "fxc" "$shaderName.vcs") `
        -Destination $shaderPath
    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue -LiteralPath (Join-Path $PWD "include")
    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue -LiteralPath (Join-Path $PWD "shaders")

    # Without GMOD running there is no need to rename so reset the count.
    $isGmodRunning = Get-Process -Name "gmod" -ErrorAction SilentlyContinue
    if ($isGmodRunning) {
        $count++
    } else {
        $count = 1
    }

    # Write the updated count back to the file
    $count | Set-Content -LiteralPath $countFilePath

    # Display the new count for debugging
    Write-Host "Update:  #$count"

    $count = $count.ToString()

    if ($isGmodRunning) {
        $paramValue = "splashsweps/${count}_$shaderName"
    }
    else {
        $paramValue = "splashsweps/$shaderName"
    }

    # Rewrite every VMT referring to this shader
    $paramKey = if ($shaderType -eq "vs") { "vertexshader" } else { "pixshader" }
    Get-ChildItem -LiteralPath $materialPath -Filter "*.vmt" -File -ErrorAction SilentlyContinue | ForEach-Object {
        $vmtContents = [string](Get-Content -LiteralPath $_.FullName -Raw)
        $newContents = Update-ShaderReference $vmtContents $paramKey $shaderName $paramValue
        if ($newContents -cne $vmtContents) {
            Set-Content -LiteralPath $_.FullName -Value $newContents -NoNewLine
            Write-Host "Updated: $($_.Name)"
        }
    }

    # Determine Output File (Shader) & Delete
    $vcsPath = Join-Path $shaderPath "$shaderName.vcs"

    # Copy the file and overwrite if it exists
    if (Test-Path $vcsPath) {
        $newFileName = "${count}_$shaderName.vcs"
        $newDestinationPath = Join-Path $shaderPath $newFileName
        Copy-Item -LiteralPath $vcsPath -Destination $newDestinationPath -Force
        Write-Host "Copied:  $shaderName.vcs  ->  $newFileName"
    }
}

foreach ($spec in $specs) {
    New-One $spec
}
