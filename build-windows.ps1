[CmdletBinding()]
param(
    [string]$LazarusDir = $env:LAZARUS_DIR,
    [string]$FpcPath = $env:FPC_EXE,
    [string]$OpenSslInstaller = $env:OPENSSL_INSTALLER,
    [string]$BuildCommit = $env:BUILD_COMMIT,
    [switch]$SkipTests
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RepositoryRoot = $PSScriptRoot
$OutputDir = Join-Path $RepositoryRoot 'dist\windows-x64'
$OpenSslVersion = '3.5.8'
$OpenSslUrl = 'https://slproweb.com/download/Win64OpenSSL_Light-3_5_8.exe'
$OpenSslSha256 = '86A34BBC39269D9F40EB02E1B19AE61CF6316518844F45C153B0A7D86DB9CDFC'
$OpenSslRuntimeNames = @('libcrypto-3-x64.dll', 'libssl-3-x64.dll')

function Require-File {
    param([string]$Path, [string]$Description)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "$Description not found: $Path"
    }
}

function Get-BuildCommit {
    $commit = $BuildCommit
    if ([string]::IsNullOrWhiteSpace($commit)) {
        $commit = $env:GITHUB_SHA
    }
    if ([string]::IsNullOrWhiteSpace($commit)) {
        return 'local'
    }
    if ($commit -notmatch '^[0-9a-fA-F]{7,64}$') {
        throw "Build commit must be a Git SHA, got: $commit"
    }
    return $commit.Substring(0, [Math]::Min(12, $commit.Length)).ToLowerInvariant()
}

function Set-BuildInfoCommit {
    param([string]$Path, [string]$Commit)

    $original = [System.IO.File]::ReadAllBytes($Path)
    $content = [System.Text.Encoding]::UTF8.GetString($original)
    $assignments = [regex]::Matches($content, "(?m)^\s*GIT_COMMIT\s*=\s*'[^']*';\s*$")
    if ($assignments.Count -ne 1) {
        throw "Could not set GIT_COMMIT in $Path"
    }
    $assignment = $assignments[0]
    $updated = $content.Substring(0, $assignment.Index) +
        "GIT_COMMIT = '$Commit';" +
        $content.Substring($assignment.Index + $assignment.Length)
    [System.IO.File]::WriteAllText($Path, $updated, [System.Text.UTF8Encoding]::new($false))
    return ,$original
}

function Assert-X64PortableExecutable {
    param([string]$Path)

    $stream = [System.IO.File]::OpenRead($Path)
    try {
        $reader = [System.IO.BinaryReader]::new($stream)
        if ($reader.ReadUInt16() -ne 0x5A4D) {
            throw "Not a PE file: $Path"
        }
        $stream.Position = 0x3C
        $peOffset = $reader.ReadInt32()
        $stream.Position = $peOffset
        if ($reader.ReadUInt32() -ne 0x00004550) {
            throw "Invalid PE header: $Path"
        }
        if ($reader.ReadUInt16() -ne 0x8664) {
            throw "Expected an x86-64 PE file: $Path"
        }
    }
    finally {
        $stream.Dispose()
    }
}

function Assert-OpenSslLoadable {
    param([string]$RuntimeDirectory)

    if (-not ('TransGuiOpenSslLoader' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public static class TransGuiOpenSslLoader {
    [DllImport("kernel32", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern IntPtr LoadLibrary(string fileName);

    [DllImport("kernel32", SetLastError = true)]
    public static extern bool FreeLibrary(IntPtr module);

    [DllImport("kernel32", CharSet = CharSet.Ansi, SetLastError = true)]
    public static extern IntPtr GetProcAddress(IntPtr module, string procName);
}
'@
    }

    $cryptoHandle = [IntPtr]::Zero
    $sslHandle = [IntPtr]::Zero
    try {
        $cryptoHandle = [TransGuiOpenSslLoader]::LoadLibrary((Join-Path $RuntimeDirectory 'libcrypto-3-x64.dll'))
        if ($cryptoHandle -eq [IntPtr]::Zero) {
            throw "Windows could not load libcrypto-3-x64.dll (error $([Runtime.InteropServices.Marshal]::GetLastWin32Error()))."
        }
        $sslHandle = [TransGuiOpenSslLoader]::LoadLibrary((Join-Path $RuntimeDirectory 'libssl-3-x64.dll'))
        if ($sslHandle -eq [IntPtr]::Zero) {
            throw "Windows could not load libssl-3-x64.dll (error $([Runtime.InteropServices.Marshal]::GetLastWin32Error()))."
        }
        if ([TransGuiOpenSslLoader]::GetProcAddress($cryptoHandle, 'OpenSSL_version') -eq [IntPtr]::Zero -or
            [TransGuiOpenSslLoader]::GetProcAddress($cryptoHandle, 'X509_VERIFY_PARAM_set1_ip_asc') -eq [IntPtr]::Zero -or
            [TransGuiOpenSslLoader]::GetProcAddress($sslHandle, 'TLS_method') -eq [IntPtr]::Zero -or
            [TransGuiOpenSslLoader]::GetProcAddress($sslHandle, 'SSL_set1_host') -eq [IntPtr]::Zero -or
            [TransGuiOpenSslLoader]::GetProcAddress($sslHandle, 'SSL_get0_param') -eq [IntPtr]::Zero) {
            throw 'The OpenSSL runtime is missing symbols required by Synapse ssl_openssl3.'
        }
    }
    finally {
        if ($sslHandle -ne [IntPtr]::Zero) { [void][TransGuiOpenSslLoader]::FreeLibrary($sslHandle) }
        if ($cryptoHandle -ne [IntPtr]::Zero) { [void][TransGuiOpenSslLoader]::FreeLibrary($cryptoHandle) }
    }
}

function Get-OpenSslRuntimeDirectory {
    $cacheDirectory = Join-Path $RepositoryRoot 'build\openssl\cache'
    $installDirectory = Join-Path $RepositoryRoot "build\openssl\win64\$OpenSslVersion"
    $installerPath = $OpenSslInstaller

    if ([string]::IsNullOrWhiteSpace($installerPath)) {
        $installerPath = Join-Path $cacheDirectory 'Win64OpenSSL_Light-3_5_8.exe'
        New-Item -ItemType Directory -Path $cacheDirectory -Force | Out-Null
        if (-not (Test-Path -LiteralPath $installerPath -PathType Leaf)) {
            Invoke-WebRequest -Uri $OpenSslUrl -OutFile $installerPath
        }
    }

    $installerPath = [System.IO.Path]::GetFullPath($installerPath)
    Require-File $installerPath 'OpenSSL installer'
    $installerHash = (Get-FileHash -LiteralPath $installerPath -Algorithm SHA256).Hash
    if ($installerHash -ne $OpenSslSha256) {
        throw "Unexpected OpenSSL installer SHA-256: $installerHash"
    }
$signature = Get-AuthenticodeSignature -FilePath $installerPath

if ($signature.Status -eq 'Valid') {
    Write-Host "OpenSSL installer Authenticode signature is valid."
}
elseif ($signature.Status -eq 'NotSigned') {
    Write-Warning "OpenSSL installer is not Authenticode-signed. Continuing because its SHA-256 matches the pinned expected hash."
}
else {
    throw "Invalid OpenSSL installer signature: $($signature.Status)"
}

    if (Test-Path -LiteralPath $installDirectory) {
        Remove-Item -LiteralPath $installDirectory -Recurse -Force
    }
    New-Item -ItemType Directory -Path $installDirectory -Force | Out-Null
    $installerProcess = Start-Process -FilePath $installerPath -ArgumentList @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', "/DIR=`"$installDirectory`"") -Wait -NoNewWindow -PassThru
    if ($installerProcess.ExitCode -ne 0) {
        throw "OpenSSL installer failed with exit code $($installerProcess.ExitCode)."
    }

    $runtimeDirectory = Join-Path $installDirectory 'bin'
    foreach ($runtimeName in $OpenSslRuntimeNames) {
        Require-File (Join-Path $runtimeDirectory $runtimeName) "OpenSSL $OpenSslVersion runtime DLL"
    }
    return $runtimeDirectory
}

if (-not [Environment]::Is64BitOperatingSystem -or -not [Environment]::Is64BitProcess) {
    throw 'This build must run in 64-bit Windows PowerShell on a 64-bit Windows host.'
}

if ([string]::IsNullOrWhiteSpace($LazarusDir)) {
    throw 'Set LAZARUS_DIR or pass -LazarusDir (for example C:\lazarus).'
}

$LazarusDir = [System.IO.Path]::GetFullPath($LazarusDir)
$LazBuild = Join-Path $LazarusDir 'lazbuild.exe'
Require-File $LazBuild 'Lazarus build tool'

if ([string]::IsNullOrWhiteSpace($FpcPath)) {
    $FpcPath = Join-Path $LazarusDir 'fpc\3.2.2\bin\x86_64-win64\fpc.exe'
}
$FpcPath = [System.IO.Path]::GetFullPath($FpcPath)
Require-File $FpcPath 'Free Pascal x86-64 compiler'

$fpcVersion = (& $FpcPath -iV).Trim()
if ($fpcVersion -ne '3.2.2') {
    throw "Unsupported FPC version '$fpcVersion'. This build is pinned to FPC 3.2.2."
}

$lazbuildVersion = (& $LazBuild --version | Out-String).Trim()
if ($lazbuildVersion -ne '4.8') {
    throw "Unsupported Lazarus installation. Expected Lazarus 4.8, got: $lazbuildVersion"
}

Require-File (Join-Path $RepositoryRoot 'transgui.lpi') 'Project file'
Require-File (Join-Path $RepositoryRoot 'synapse\source\lib\httpsend.pas') 'Synapse submodule'
Require-File (Join-Path $RepositoryRoot 'flags\flag_es.png') 'Embedded resource'
Require-File (Join-Path $RepositoryRoot 'lang\transgui.es') 'Translation resource'
$BuildInfoPath = Join-Path $RepositoryRoot 'buildinfo.pas'
Require-File $BuildInfoPath 'Build metadata source'
$ResolvedBuildCommit = Get-BuildCommit
$BuildInfoOriginal = Set-BuildInfoCommit $BuildInfoPath $ResolvedBuildCommit
Write-Host "Build commit: $ResolvedBuildCommit"

$LazBuildArguments = @(
    "--lazarusdir=$LazarusDir",
    "--compiler=$FpcPath",
    '--cpu=x86_64',
    '--os=win64'
)

try {
    $OpenSslRuntimeDirectory = Get-OpenSslRuntimeDirectory

    if (-not $SkipTests) {
        Push-Location (Join-Path $RepositoryRoot 'test')
        try {
            & $LazBuild @LazBuildArguments '-B' 'transguitest.lpi'
            if ($LASTEXITCODE -ne 0) {
                throw "Test compilation failed with exit code $LASTEXITCODE."
            }
            & (Join-Path $RepositoryRoot 'test\units\transguitest.exe') '-a'
            if ($LASTEXITCODE -ne 0) {
                throw "Tests failed with exit code $LASTEXITCODE."
            }
        }
        finally {
            Pop-Location
        }
    }

    Push-Location $RepositoryRoot
    try {
        & $LazBuild @LazBuildArguments '-B' '--build-mode=Release' 'transgui.lpi'
        if ($LASTEXITCODE -ne 0) {
            throw "Release compilation failed with exit code $LASTEXITCODE."
        }
    }
    finally {
        Pop-Location
    }

    $Executable = Join-Path $RepositoryRoot 'units\transgui.exe'
    Require-File $Executable 'Compiled application'
    Assert-X64PortableExecutable $Executable

    if (Test-Path -LiteralPath $OutputDir) {
        Remove-Item -LiteralPath $OutputDir -Recurse -Force
    }
    New-Item -ItemType Directory -Path $OutputDir | Out-Null
    Copy-Item -LiteralPath $Executable -Destination (Join-Path $OutputDir 'transgui.exe')

    $LanguageDir = Join-Path $OutputDir 'lang'
    New-Item -ItemType Directory -Path $LanguageDir | Out-Null
    Get-ChildItem -LiteralPath (Join-Path $RepositoryRoot 'lang') -File -Filter 'transgui.*' |
        Where-Object { $_.Extension -ne '.template' } |
        Copy-Item -Destination $LanguageDir

    foreach ($runtimeName in $OpenSslRuntimeNames) {
        $runtimeDll = Join-Path $OpenSslRuntimeDirectory $runtimeName
        Assert-X64PortableExecutable $runtimeDll
        Copy-Item -LiteralPath $runtimeDll -Destination $OutputDir
    }
    Assert-OpenSslLoadable $OutputDir

    Get-ChildItem -LiteralPath $OutputDir -File -Recurse |
        Get-FileHash -Algorithm SHA256 |
        ForEach-Object { "{0} *{1}" -f $_.Hash, $_.Path.Substring($OutputDir.Length + 1) } |
        Set-Content -LiteralPath (Join-Path $OutputDir 'SHA256SUMS.txt') -Encoding ascii

    Write-Host "Windows x64 build created in $OutputDir"
}
finally {
    [System.IO.File]::WriteAllBytes($BuildInfoPath, $BuildInfoOriginal)
}
