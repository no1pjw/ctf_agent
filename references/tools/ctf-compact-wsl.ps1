[CmdletBinding()]
param(
    [string]$Distribution = 'Ubuntu'
)

$ErrorActionPreference = 'Stop'
$principal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw '관리자 PowerShell에서 실행해야 합니다.'
}

$lxss = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Lxss'
$distributionKey = Get-ChildItem -LiteralPath $lxss |
    ForEach-Object { Get-ItemProperty -LiteralPath $_.PSPath } |
    Where-Object { $_.DistributionName -eq $Distribution -and $_.BasePath } |
    Select-Object -First 1

if (-not $distributionKey) {
    throw "WSL 배포판을 찾을 수 없습니다: $Distribution"
}

$vhd = Join-Path $distributionKey.BasePath 'ext4.vhdx'
if (-not (Test-Path -LiteralPath $vhd -PathType Leaf)) {
    throw "VHDX를 찾을 수 없습니다: $vhd"
}

$resolved = (Resolve-Path -LiteralPath $vhd).Path
$localAppData = (Resolve-Path -LiteralPath $env:LOCALAPPDATA).Path
if (-not $resolved.StartsWith($localAppData, [StringComparison]::OrdinalIgnoreCase) -or
    [IO.Path]::GetFileName($resolved) -ne 'ext4.vhdx') {
    throw "안전 경계 밖 VHDX는 처리하지 않습니다: $resolved"
}

if (-not (Get-Command Optimize-VHD -ErrorAction SilentlyContinue)) {
    throw 'Optimize-VHD 명령을 찾을 수 없습니다. Hyper-V PowerShell 기능이 필요합니다.'
}

$before = (Get-Item -LiteralPath $resolved).Length
Write-Host "배포판: $Distribution"
Write-Host "대상: $resolved"
Write-Host ('압축 전: {0:N2} GiB' -f ($before / 1GB))
Write-Host '모든 WSL 배포판을 정상 종료합니다.'

wsl.exe --shutdown
Start-Sleep -Seconds 3
Optimize-VHD -Path $resolved -Mode Full

$after = (Get-Item -LiteralPath $resolved).Length
Write-Host ('압축 후: {0:N2} GiB' -f ($after / 1GB))
Write-Host ('회수: {0:N2} GiB' -f (($before - $after) / 1GB))
