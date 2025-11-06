
<#
  CodeFestival language toolchain installer - winget bootstrap (deps-included)
  목적: Windows 10에서 winget(App Installer) 설치에 필요한
        1) VCLibs 14.00 UWP Desktop (x64)
        2) Windows App Runtime 1.8(x64)
        3) App Installer(msixbundle)
      를 순서대로 설치하고 검증.
#>

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

# 3) 다운로드 경로
$VCLibsPath   = Join-Path $DownloadDir "Microsoft.VCLibs.x64.14.00.Desktop.appx"
$WinAppRtPath = Join-Path $DownloadDir "WindowsAppRuntimeInstall-x64.exe"
$AppInstaller = Join-Path $DownloadDir "AppInstaller.msixbundle"

# 4) 다운로드 유틸
function Get-File($url,$dst){
  log "download: $url"
  try{
    Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $dst -TimeoutSec 1800
  }catch{ die "download failed: $url`n$($_.Exception.Message)" }
  if(-not (Test-Path $dst) -or ((Get-Item $dst).Length -le 0)){ die "empty file: $dst" }
}

# 5) VCLibs 설치
try{
  if(-not (Get-AppxPackage Microsoft.VCLibs.140.00.UWPDesktop -ErrorAction SilentlyContinue)){
    if(-not (Test-Path $VCLibsPath)){ Get-File $VCLibsUrl $VCLibsPath }
    log "install VCLibs..."
    Add-AppxPackage -Path $VCLibsPath
  } else { log "VCLibs already present." }
}catch{
  warn "VCLibs install failed: $($_.Exception.Message)"
  warn "조직 정책/스토어 서비스 비활성 등으로 막힐 수 있습니다."
}

# 6) Windows App Runtime 1.8 설치 (필수 의존성)
#    공식 문서의 'Installer (x64)'는 WindowsAppRuntimeInstall.exe 로, 프레임워크/메인 패키지를 한 번에 배포
#    /quiet /norestart 로 무인설치
if(-not (Get-AppxPackage Microsoft.WindowsAppRuntime.1.8* -ErrorAction SilentlyContinue)){
  if(-not (Test-Path $WinAppRtPath)){ Get-File $WinAppRtUrl $WinAppRtPath }
  log "install Windows App Runtime 1.8 (quiet)..."
  $p = Start-Process -FilePath $WinAppRtPath -ArgumentList "/quiet","/norestart" -PassThru -Wait
  if($p.ExitCode -ne 0){ die "Windows App Runtime installer exit code $($p.ExitCode)" }
} else {
  log "Windows App Runtime 1.8 already present."
}

# 7) App Installer(msixbundle) 설치
if(-not (Get-AppxPackage Microsoft.DesktopAppInstaller -ErrorAction SilentlyContinue)){
  if(-not (Test-Path $AppInstaller)){ Get-File $AppInstallerUrl $AppInstaller }
  log "install App Installer..."
  try{
    Add-AppxPackage -Path $AppInstaller
  }catch{
    # 흔한 실패: 사이드로딩 비활성, 의존성 누락
    warn "App Installer 설치 실패: $($_.Exception.Message)"
    warn "설정 > 업데이트 및 보안 > 개발자용 > '앱 사이드로드' 켜기 후 재시도하세요."
    die "App Installer installation failed."
  }
} else { log "App Installer already installed." }

# 8) 검증
try{
  $ver = (winget --version) 2>&1
  log "SUCCESS: winget $ver"
  exit 0
}catch{
  die "winget not found even after install: $($_.Exception.Message)"
}
