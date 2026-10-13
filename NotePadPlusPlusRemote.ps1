#Requires -Version 5.1

[CmdletBinding()]
param (
    [Parameter(Mandatory)]
    [string]$ComputerName,

    [Parameter(Mandatory)]
    [ValidateScript({
        if (-not (Test-Path -LiteralPath $_ -PathType Leaf)) {
            throw "Installer not found: $_"
        }
        $true
    })]
    [string]$InstallerPath,

    [PSCredential]$Credential
)

$ErrorActionPreference = 'Stop'
$session = $null
$deploymentExitCode = 1

$InstallerPath = (Resolve-Path -LiteralPath $InstallerPath).Path
$installerName = Split-Path -Path $InstallerPath -Leaf
$stagingDirectory = "C:\Windows\Temp\NotepadPlusPlus-$([guid]::NewGuid().ToString('N'))"
$remoteInstaller = Join-Path -Path $stagingDirectory -ChildPath $installerName

try {
    $sessionParameters = @{
        ComputerName = $ComputerName
        ErrorAction = 'Stop'
    }

    if ($PSBoundParameters.ContainsKey('Credential')) {
        $sessionParameters.Credential = $Credential
    }

    Write-Host "Connecting to $ComputerName..."
    $session = New-PSSession @sessionParameters

    Invoke-Command -Session $session -ScriptBlock {
        param($Directory)

        New-Item -Path $Directory -ItemType Directory -Force | Out-Null
    } -ArgumentList $stagingDirectory

    Write-Host "Copying installer to $ComputerName..."
    Copy-Item `
        -LiteralPath $InstallerPath `
        -Destination $remoteInstaller `
        -ToSession $session `
        -Force

    Write-Host "Installing Notepad++ silently..."

    $result = Invoke-Command -Session $session -ScriptBlock {
        param($Installer)

        # Notepad++ uses the NSIS silent-install switch. It is case-sensitive.
        $process = Start-Process `
            -FilePath $Installer `
            -ArgumentList '/S' `
            -Wait `
            -PassThru

        [PSCustomObject]@{
            ComputerName = $env:COMPUTERNAME
            ExitCode     = [int]$process.ExitCode
        }
    } -ArgumentList $remoteInstaller

    $deploymentExitCode = [int]$result.ExitCode

    if ($deploymentExitCode -eq 0) {
        Write-Host "Notepad++ was installed successfully on $($result.ComputerName)."
    }
    elseif ($deploymentExitCode -eq 3010) {
        Write-Warning "Installation completed successfully, but a restart is required."
    }
    else {
        Write-Warning "The installer returned exit code $deploymentExitCode."
    }
}
catch {
    Write-Error "Deployment failed: $($_.Exception.Message)" -ErrorAction Continue
    $deploymentExitCode = 1
}
finally {
    if ($session) {
        Invoke-Command -Session $session -ScriptBlock {
            param($Directory)

            Remove-Item -LiteralPath $Directory `
                -Recurse `
                -Force `
                -ErrorAction SilentlyContinue
        } -ArgumentList $stagingDirectory -ErrorAction SilentlyContinue

        Remove-PSSession -Session $session -ErrorAction SilentlyContinue
    }
}

Write-Host "Deployment exit code: $deploymentExitCode"
exit $deploymentExitCode