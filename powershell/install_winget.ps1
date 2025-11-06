
#  CodeFestival language toolchain installer - winget bootstrap (deps-included)
#  목적: Windows 10에서 winget(App Installer) 설치에 필요한
#        1) VCLibs 14.00 UWP Desktop (x64)
#        2) Windows App Runtime 1.8(x64)
#        3) App Installer(msixbundle)
#      를 순서대로 설치하고 검증.

[CmdletBinding()]
param(
  [string]$DownloadDir = "$env:TEMP\winget-bootstrap",
  [switch]$Quiet
)

$ErrorActionPreference = 'Stop'
function log([string]$m){ if(-not $Quiet){ Write-Host "[winget-bootstrap] $m" -ForegroundColor Cyan } }
function warn([string]$m){ if(-not $Quiet){ Write-Host "[winget-bootstrap] $m" -ForegroundColor Yellow } }
function die ([string]$m){ Write-Host "[winget-bootstrap] ERROR: $m" -ForegroundColor Red; exit 1 }

# 0) 이미 winget이 있으면 끝
if (Get-Command winget -ErrorAction SilentlyContinue) {
  log "winget already installed: $((winget --version) 2>&1)"
  exit 0
}

# 1) 폴더 준비 & TLS
New-Item -ItemType Directory -Force -Path $DownloadDir | Out-Null
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# 2) URL (공식 aka.ms 단축 링크 사용)
#    - VCLibs 14.00 Desktop (x64) appx
#    - Windows App Runtime 1.8 (x64) 인스톨러 EXE (WinAppSDK Downloads의 "Installer (x64)")
#    - App Installer(msixbundle) (aka.ms/getwinget)
$VCLibsUrl  = "https://aka.ms/Microsoft.VCLibs.x64.14.00.Desktop.appx"
$WinAppRtUrl = "https://aka.ms/windowsappsdk/1.8/installer-x64"   # 최신 1.8.x x64 인스톨러로 리다이렉트
$AppInstallerUrl = "https://aka.ms/getwinget"

# 3) 경로 설정
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$LocalWinAppRt = Join-Path $ScriptDir "WindowsAppRuntimeInstall-x64.exe"   # ✅ 수정: 로컬 위치
$VCLibsPath   = Join-Path $DownloadDir "Microsoft.VCLibs.x64.14.00.Desktop.appx"
$WinAppRtPath = Join-Path $DownloadDir "WindowsAppRuntimeInstall-x64.exe"
$AppInstaller = Join-Path $DownloadDir "AppInstaller.msixbundle"

function Get-File($url,$dst){
  log "download: $url"
  Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $dst -TimeoutSec 1800
  if(-not (Test-Path $dst) -or ((Get-Item $dst).Length -le 0)){ die "downloaded file empty: $dst" }
}

# 4) VCLibs
if(-not (Get-AppxPackage Microsoft.VCLibs.140.00.UWPDesktop -ErrorAction SilentlyContinue)){
  if(-not (Test-Path $VCLibsPath)){ Get-File $VCLibsUrl $VCLibsPath }
  log "install VCLibs..."
  Add-AppxPackage -Path $VCLibsPath
} else { log "VCLibs already installed." }

# 5) Windows App Runtime 1.8
if(-not (Get-AppxPackage Microsoft.WindowsAppRuntime.1.8* -ErrorAction SilentlyContinue)){
  # ✅ 로컬 파일 우선 사용
  if(Test-Path $LocalWinAppRt){
    log "using local WindowsAppRuntimeInstall-x64.exe"
    $exe = $LocalWinAppRt
  } else {
    log "local installer not found → downloading"
    if(-not (Test-Path $WinAppRtPath)){ Get-File $WinAppRtUrl $WinAppRtPath }
    $exe = $WinAppRtPath
  }

  log "install Windows App Runtime 1.8 (quiet)..."
  $p = Start-Process -FilePath $exe -ArgumentList "/quiet","/norestart" -PassThru -Wait
  if($p.ExitCode -ne 0){ die "WinAppRuntime installer exit code $($p.ExitCode)" }
} else {
  log "Windows App Runtime 1.8 already present."
}

# 6) App Installer
if(-not (Get-AppxPackage Microsoft.DesktopAppInstaller -ErrorAction SilentlyContinue)){
  if(-not (Test-Path $AppInstaller)){ Get-File $AppInstallerUrl $AppInstaller }
  log "install App Installer..."
  Add-AppxPackage -Path $AppInstaller
}else{
  log "App Installer already installed."
}

# 7) 최종 확인
try{
  $ver = (winget --version) 2>&1
  log "SUCCESS: winget $ver"
}
catch{
  die "winget not detected after install"
}