param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('Install', 'Remove')]
    [string]$Action
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$rules = @(
    @{
        Name = 'H-Gallery Android Sync'
        Protocol = 'TCP'
        Port = '8000'
    },
    @{
        Name = 'H-Gallery Android Discovery'
        Protocol = 'UDP'
        Port = '47851'
    }
)

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Invoke-Netsh {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments,
        [switch]$IgnoreExitCode
    )

    $netsh = Join-Path $env:SystemRoot 'System32\netsh.exe'
    & $netsh @Arguments | Out-Null
    $exitCode = $LASTEXITCODE

    if (-not $IgnoreExitCode -and $exitCode -ne 0) {
        throw "netsh ha restituito il codice $exitCode per: $($Arguments -join ' ')"
    }
}

if (-not (Test-IsAdministrator)) {
    Write-Error 'La configurazione di Windows Firewall richiede privilegi amministrativi.'
    exit 5
}

try {
    # Rimuovere prima le regole con i nostri nomi rende l'operazione idempotente
    # e impedisce che aggiornamenti/reinstallazioni accumulino duplicati.
    foreach ($rule in $rules) {
        Invoke-Netsh -Arguments @(
            'advfirewall', 'firewall', 'delete', 'rule',
            "name=$($rule.Name)"
        ) -IgnoreExitCode
    }

    if ($Action -eq 'Install') {
        foreach ($rule in $rules) {
            Invoke-Netsh -Arguments @(
                'advfirewall', 'firewall', 'add', 'rule',
                "name=$($rule.Name)",
                'dir=in',
                'action=allow',
                'enable=yes',
                'profile=private',
                'remoteip=localsubnet',
                "protocol=$($rule.Protocol)",
                "localport=$($rule.Port)"
            )
        }
    }

    exit 0
}
catch {
    Write-Error $_
    exit 1
}
