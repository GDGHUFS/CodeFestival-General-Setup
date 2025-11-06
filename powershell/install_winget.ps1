<#
  CodeFestival language toolchain installer - winget bootstrap
  목적: Windows 10(1809+)에서 winget(App Installer) 오프라인/스크립트 설치
  참고: https://learn.microsoft.com/windows/package-manager/winget/
#>

[CmdletBinding()]
param(
  [string]$DownloadDir = "$env:TEMP\winget-bootstrap",
  [switch]$Quiet
)

$ErrorActionPreference = 'Stop'
function say([string]$m){ if(-not $Quiet){ Write-Host "[winget-bootstrap] $m" -ForegroundColor Cyan } }
function warn([string]$m){ if(-not $Quiet){ Write-Host "[winget-bootstrap] $m" -ForegroundColor Yellow } }
function die ([string]$m){ Write-Host "[winget-bootstrap] ERROR: $m" -ForegroundColor Red; exit 1 }

# 0) 이미 설치되어 있으면 끝
if (Get-Command winget -ErrorAction SilentlyContinue) {
  say "winget 이미 존재: $((winget --version) 2>&1)"
  exit 0
}

# 1) OS 요건 간단체크 (Windows 10 1809 이상 권장)
$build = [Environment]::OSVersion.Version.Build
if ($build -lt 17763) { warn "Windows 빌드($build)가 낮습니다. winget은 Windows 10 1809(17763)+ 권장." }

# 2) 다운로드 폴더
New-Item -ItemType Directory -Force -Path $DownloadDir | Out-Null
$bundle = Join-Path $DownloadDir "AppInstaller.msixbundle"
$vclibs = Join-Path $DownloadDir "Microsoft.VCLibs.x64.14.00.Desktop.appx"

# 3) 네트워크 보안프로토콜
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# 4) App Installer 번들 다운로드 (공식 aka.ms 단축)
# 문서/커뮤니티에서 안내되는 표준 경로: https://aka.ms/getwinget
# ref: MS Docs + winget-cli GitHub releases
try {
  say "App Installer(msixbundle) 다운로드"
  Invoke-WebRequest -UseBasicParsing -Uri "https://aka.ms/getwinget" -OutFile $bundle -TimeoutSec 1800
} catch {
  die "App Installer 다운로드 실패: $($_.Exception.Message)`n네트워크/프록시를 확인하세요."
}

# 5) 의존성(VCLibs) 확보 시도 (일부 환경에서 필요)
# 참고: 수동 설치 시 VCLibs 등을 먼저 깔아야 하는 케이스가 있습니다.
# ref: 여러 가이드에서 VCLibs 14.00 Desktop 패키지 권장
$needVCLibs = $false
try {
  say "App Installer 설치 시도"
  Add-AppxPackage -Path $bundle
} catch {
  warn "App Installer 설치 실패, 의존성 보완을 시도: $($_.Exception.Message)"
  $needVCLibs = $true
}

if ($needVCLibs) {
  try {
    if (!(Test-Path $vclibs)) {
      say "VCLibs 패키지 다운로드"
      Invoke-WebRequest -UseBasicParsing -Uri "https://aka.ms/Microsoft.VCLibs.x64.14.00.Desktop.appx" -OutFile $vclibs -TimeoutSec 1200
    }
    say "VCLibs 설치"
    Add-AppxPackage -Path $vclibs

    say "App Installer 재설치 시도"
    Add-AppxPackage -Path $bundle
  } catch {
    die "의존성 설치/재시도 실패: $($_.Exception.Message)`nWindows App Runtime 등 추가 의존성이 필요할 수 있습니다. (조직 정책/에디션에 따라 다름)"
  }
}

# 6) 설치 검증
try {
  $ver = (winget --version) 2>&1
  say "설치 완료: winget $ver"
  exit 0
} catch {
  die "winget 실행 확인 실패: $($_.Exception.Message)"
}
