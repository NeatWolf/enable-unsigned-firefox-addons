param(
    [Parameter(Mandatory = $true)]
    [string]$LogFile,

    [string]$Message = "",

    [string]$InputFile = ""
)

try {
    $directory = Split-Path -Parent $LogFile
    if ($directory) {
        [System.IO.Directory]::CreateDirectory($directory) | Out-Null
    }

    $encoding = New-Object System.Text.UTF8Encoding($false)

    function Append-Text {
        param([string]$Text)
        [System.IO.File]::AppendAllText($LogFile, $Text, $encoding)
    }

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

    if ($Message -ne "") {
        Append-Text "[$timestamp] $Message`r`n"
    }

    if ($InputFile -ne "" -and [System.IO.File]::Exists($InputFile)) {
        Append-Text "----- output start -----`r`n"
        $content = [System.IO.File]::ReadAllText($InputFile)
        if ($content.Length -gt 0) {
            Append-Text $content
            if (-not $content.EndsWith("`n")) {
                Append-Text "`r`n"
            }
        }
        Append-Text "----- output end -----`r`n"
    }
} catch {
    # Logging must never block the Firefox action.
}

exit 0
