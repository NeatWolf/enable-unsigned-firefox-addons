param(
    [Parameter(Mandatory = $true)]
    [string]$Choices,

    [string]$Prompt = ""
)

$choicesUpper = $Choices.ToUpperInvariant()
[Console]::Write($Prompt)

if ([Console]::IsInputRedirected) {
    $stdin = [Console]::OpenStandardInput()
    while (($next = $stdin.ReadByte()) -ge 0) {
        $ch = [char]$next

        if ($ch -eq "`r" -or $ch -eq "`n") {
            continue
        }

        $idx = $choicesUpper.IndexOf([char]::ToUpperInvariant($ch))
        if ($idx -ge 0) {
            [Console]::WriteLine()
            exit ($idx + 1)
        }
    }

    [Console]::WriteLine()
    exit 255
}

while ($true) {
    $key = [Console]::ReadKey($true)
    $idx = $choicesUpper.IndexOf([char]::ToUpperInvariant($key.KeyChar))

    if ($idx -ge 0) {
        [Console]::WriteLine()
        exit ($idx + 1)
    }
}
