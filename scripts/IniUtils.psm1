<#
.SYNOPSIS
    Returns a map of INI sections and their values:
    "section name" -> ("key" -> "value")

.PARAMETER Path
    The path to the ini file to read

.OUTPUTS
    System.Collections.Hashtable
#>
function LoadIni {
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw [System.IO.FileNotFoundException]::new("Ini file not found: $Path", $Path)
    }
    $resolved = (Resolve-Path -LiteralPath $Path).ProviderPath

    $ini = @{}
    $section = ''

    switch -Regex -File $resolved {
        '^\s*([;#]|$)' { continue }
        '^\s*\[(.+)\]\s*$' {
            $section = $matches[1].Trim()
            if (-not $ini.ContainsKey($section)) { $ini[$section] = @{} }
            continue
        }
        '^\s*([^=]+?)\s*=\s*(.*?)\s*$' {
            if ($section -eq '') { continue }
            $ini[$section][$matches[1]] = [Environment]::ExpandEnvironmentVariables($matches[2])
            continue
        }
    }

    return $ini
}

Export-ModuleMember -Function LoadIni
