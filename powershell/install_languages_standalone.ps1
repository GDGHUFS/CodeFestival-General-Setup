
#  CodeFestival language toolchain installer (no-winget / no-here-string)
#  대상:
#    - Java (OpenJDK 21.0.4)     : Adoptium API/페이지에서 ZIP 직접 다운로드
#    - C / C++ (GCC/G++ 13.2.0)  : WinLibs ZIP 직접 다운로드
#    - PyPy3 7.3.15 (Python 3.9) : 공식 ZIP 직접 다운로드
#  비고:
#    - PowerShell 5.1 호환. here-string 미사용.
#    - 새 터미널에서 PATH 반영 확인 필요.

[CmdletBinding()]
param(
  [string]$InstallDir = "C:\CodeFestival\tools",
  [switch]$AllowNewer,
  [switch]$SystemPath,
  [switch]$SkipJava,
  [switch]$SkipGCC,
  [switch]$SkipPyPy,
  [switch]$NoWrappers
)

$ErrorActionPreference = 'Stop'

function Write-Info([string]$m){ Write-Host "[INFO] $m" -ForegroundColor Cyan }
function Write-Warn([string]$m){ Write-Host "[WARN] $m" -ForegroundColor Yellow }
function Write-Err ([string]$m){ Write-Host "[ERROR] $m" -ForegroundColor Red }

function Ensure-Dir([string]$p){ if(-not (Test-Path $p)){ New-Item -ItemType Directory -Path $p | Out-Null } }

function Add-ToPath([string]$p, [switch]$SystemLevel){
  $p = [IO.Path]::GetFullPath($p)
  if(-not (Test-Path $p)){ throw "경로가 존재하지 않습니다: $p" }

  if($SystemLevel){
    $admin = (New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if(-not $admin){ throw "시스템 PATH 수정에는 관리자 권한이 필요합니다." }
    $reg = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Environment"
  } else {
    $reg = "HKCU:\Environment"
  }

  $current = (Get-ItemProperty -Path $reg -Name Path -ErrorAction SilentlyContinue).Path
  if([string]::IsNullOrEmpty($current)){ $current = "" }

  $exists = $false
  foreach($seg in $current.Split(';')){ if($seg -ieq $p){ $exists = $true; break } }
  if(-not $exists){
    $newPath = ($current.TrimEnd(';') + ';' + $p).Trim(';')
    Set-ItemProperty -Path $reg -Name Path -Value $newPath
    $env:Path = $newPath
    Write-Info "PATH에 추가됨: $p"
  } else {
    Write-Info "PATH에 이미 존재: $p"
  }
}

function Download-File([string]$url, [string]$dst){
  Write-Info "다운로드: $url"
  try{
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $dst -TimeoutSec 1800
  }catch{ throw "다운로드 실패: $url`n$($_.Exception.Message)" }
  if(-not (Test-Path $dst) -or ((Get-Item $dst).Length -le 0)){ throw "다운로드된 파일이 비정상입니다: $dst" }
  try{ Unblock-File -Path $dst -ErrorAction SilentlyContinue }catch{}
}

function Expand-AnyArchive([string]$archivePath, [string]$destDir){
  Ensure-Dir $destDir
  $ext = [IO.Path]::GetExtension($archivePath).ToLowerInvariant()
  if($ext -eq ".zip"){
    try{
      Expand-Archive -Path $archivePath -DestinationPath $destDir -Force
    }catch{
      throw "ZIP 해제 실패: $($_.Exception.Message)"
    }
  } elseif($ext -eq ".7z"){
    $gc = Get-Command 7z -ErrorAction SilentlyContinue
    $sevenZip = $null; if($gc){ $sevenZip = $gc.Source }
    if(-not $sevenZip){ throw "7z 명령을 찾을 수 없습니다. zip 또는 7-Zip 설치 필요." }
    & $sevenZip x "-o$destDir" -y $archivePath | Out-Null
  } else {
    throw "지원되지 않는 압축 형식: $ext"
  }
}

function Get-CommandPath([string]$name){
  $gc = Get-Command $name -ErrorAction SilentlyContinue
  if($gc){ return $gc.Source }
  return $null
}

function Verify-Version([scriptblock]$cmd, [string]$pattern, [string]$human){
  try{ $out = & $cmd 2>&1 | Out-String }catch{ throw "$human 실행 실패: $($_.Exception.Message)" }
  if($out -notmatch $pattern){
    throw "$human 버전 검증 실패. 출력:`n$out"
  }
  Write-Info "$human 확인: $($matches[0])"
  return $out
}

# 작업 디렉토리
Ensure-Dir $InstallDir
$dl = Join-Path $InstallDir "downloads"
Ensure-Dir $dl

# ----------------- Java (OpenJDK 21.0.4) -----------------
if(-not $SkipJava){
  Write-Host "`n===== Java (OpenJDK 21.0.9+10) 설치 =====" -ForegroundColor Green

  # 고정 다운로드 URL (요청사항)
  $jdkUrl = "https://adoptium.net/download?link=https%3A%2F%2Fgithub.com%2Fadoptium%2Ftemurin21-binaries%2Freleases%2Fdownload%2Fjdk-21.0.9%252B10%2FOpenJDK21U-jdk_x64_windows_hotspot_21.0.9_10.zip&vendor=Adoptium"
  $requiredRegex = '21\.0\.9'   # 검증: java -version 출력에 21.0.9 포함

  # 다운로드 고정: 실패 시 즉시 오류(다른 대체 루트 없음)
  $zipName = "OpenJDK21U-jdk_x64_windows_hotspot_21.0.9_10.zip"
  $zipPath = Join-Path $dl $zipName
  if(Test-Path $zipPath){ Remove-Item $zipPath -Force -ErrorAction SilentlyContinue }
  Write-Info "OpenJDK ZIP 다운로드 (고정 URL만 사용)"
  Download-File $jdkUrl $zipPath  # Download-File 내부에서 실패 시 throw

  # 압축 해제 (내용물 루트 폴더명은 릴리스에 따라 다를 수 있으므로 재귀로 bin 탐색)
  $javaRoot = Join-Path $InstallDir "jdk-21.0.9"
  if(Test-Path $javaRoot){ Remove-Item $javaRoot -Recurse -Force -ErrorAction SilentlyContinue }
  Ensure-Dir $javaRoot
  Expand-AnyArchive $zipPath $javaRoot

  # bin 디렉터리 탐색
  $javabins = Get-ChildItem -Recurse -Directory $javaRoot -Filter "bin" -ErrorAction SilentlyContinue
  if(-not $javabins -or $javabins.Count -eq 0){
    throw "JDK bin 디렉터리를 찾지 못했습니다. 압축 구조를 확인하세요."
  }
  $javaBinDir = $javabins[0].FullName
  Add-ToPath $javaBinDir -SystemLevel:$SystemPath

  # 버전 검증 (반드시 21.0.9 포함)
  $verOut = Verify-Version { java -version } $requiredRegex "Java(OpenJDK 21.0.9+10)"

  # JAVA_HOME 설정(bin 상위)
  $javaHome = [IO.Directory]::GetParent($javaBinDir).FullName
  [Environment]::SetEnvironmentVariable("JAVA_HOME",$javaHome,[EnvironmentVariableTarget]::User)
  if($SystemPath){ [Environment]::SetEnvironmentVariable("JAVA_HOME",$javaHome,[EnvironmentVariableTarget]::Machine) }
  Write-Info "JAVA_HOME=$javaHome"
}else{
  Write-Info "Java 설치 스킵"
}

# ----------------- GCC/G++ 13.2.0 (WinLibs) -----------------
if(-not $SkipGCC){
  Write-Host "`n===== GCC/G++ 13.2.0 설치 =====" -ForegroundColor Green
  $gccRequired = '13\.2\.0'
  $gccRoot = Join-Path $InstallDir "winlibs-gcc-13.2.0"
  $gccBin  = Join-Path $gccRoot "bin"

  function Find-WinLibsZipUrl {
    $pageUrl = "https://winlibs.com/"
    try{
      [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
      $html = (Invoke-WebRequest -UseBasicParsing -Uri $pageUrl -TimeoutSec 180).Content
    }catch{ throw "winlibs.com 접근 실패: $($_.Exception.Message)" }
    $regexes = @(
      'href="([^"]*winlibs-[^"]*gcc-13\.2\.0[^"]*msvcrt[^"]*\.zip)"',
      'href="([^"]*winlibs-[^"]*gcc-13\.2\.0[^"]*ucrt[^"]*\.zip)"',
      'href="([^"]*winlibs-[^"]*gcc-13\.2\.0[^"]*\.zip)"'
    )
    foreach($rx in $regexes){
      $m = [regex]::Match($html, $rx, 'IgnoreCase')
      if($m.Success){
        $href = $m.Groups[1].Value
        if($href -notmatch '^https?://'){
          if($href.StartsWith("/")){ return "https://winlibs.com$href" }
          else{ return "https://winlibs.com/$href" }
        }
        return $href
      }
    }
    throw "GCC 13.2.0 zip 링크를 찾지 못했습니다."
  }

  try{
    if(-not (Test-Path $gccBin)){
      $zipUrl  = Find-WinLibsZipUrl
      $zipName = Split-Path $zipUrl -Leaf
      $zipPath = Join-Path $dl $zipName
      if(-not (Test-Path $zipPath)){ Download-File $zipUrl $zipPath }
      Expand-AnyArchive $zipPath $gccRoot
      $bins = Get-ChildItem -Recurse -Directory $gccRoot -Filter "bin" -ErrorAction SilentlyContinue
      if($bins.Count -gt 0){ $gccBin = $bins[0].FullName }
    }
    Add-ToPath $gccBin -SystemLevel:$SystemPath
    Verify-Version { gcc --version } $gccRequired "gcc"
    Verify-Version { g++ --version } $gccRequired "g++"
  }catch{
    if($AllowNewer){
      Write-Warn "정확 버전 설치 실패. -AllowNewer 허용 상태에서 gcc/g++ 최신 버전 사용을 권장합니다. 오류: $($_.Exception.Message)"
    }else{
      throw
    }
  }
}else{
  Write-Info "GCC/G++ 설치 스킵"
}

# ----------------- PyPy3 7.3.15 (Python 3.9.18) -----------------
if(-not $SkipPyPy){
  Write-Host "`n===== PyPy3 7.3.15 (Python 3.9.18) 설치 =====" -ForegroundColor Green
  $pypyDir = Join-Path $InstallDir "pypy3.9-v7.3.15-win64"
  $pypyExe = Join-Path $pypyDir "pypy3.exe"

  try{
    if(-not (Test-Path $pypyExe)){
      $primaryUrl = "https://downloads.python.org/pypy/pypy3.9-v7.3.15-win64.zip"
      $zipPath = Join-Path $dl "pypy3.9-v7.3.15-win64.zip"
      try{ if(-not (Test-Path $zipPath)){ Download-File $primaryUrl $zipPath } }
      catch{
        Write-Warn "직접 URL 실패, pypy 다운로드 페이지에서 검색"
        $dlPage = "https://www.pypy.org/download.html"
        $html = (Invoke-WebRequest -UseBasicParsing -Uri $dlPage -TimeoutSec 180).Content
        $m = [regex]::Match($html, 'https?://[^"]*/pypy3\.9-v7\.3\.15-win64\.zip', 'IgnoreCase')
        if(-not $m.Success){ throw "다운로드 링크를 찾지 못했습니다." }
        $zipPath = Join-Path $dl "pypy3.9-v7.3.15-win64.zip"
        Download-File $m.Value $zipPath
      }
      Expand-AnyArchive $zipPath $InstallDir
    }

    if(-not (Test-Path $pypyExe)){ throw "pypy3.exe가 없습니다: $pypyExe" }
    Add-ToPath $pypyDir -SystemLevel:$SystemPath

    $pypyOut = & $pypyExe --version 2>&1 | Out-String
    if($pypyOut -notmatch 'PyPy 7\.3\.15'){
      if($AllowNewer){ Write-Warn "요구 PyPy와 다름. 출력:`n$pypyOut" } else { throw "PyPy 7.3.15 검증 실패.`n$pypyOut" }
    }
    if($pypyOut -notmatch 'Python 3\.9'){ Write-Warn "파이썬 인터프리터가 3.9가 아닙니다. 출력:`n$pypyOut" }

    try{ & $pypyExe -m ensurepip --upgrade | Out-Null } catch { Write-Warn "ensurepip 실패: $($_.Exception.Message)" }

    # python3.bat alias
    $pythonAlias = Join-Path $pypyDir "python3.bat"
    if(-not (Test-Path $pythonAlias)){
      Set-Content -LiteralPath $pythonAlias -Encoding ascii -Value @(
        '@echo off',
        'REM CodeFestival language toolchain installer - python3 alias',
        '"%~dp0pypy3.exe" %*'
      )
    }

    Write-Info "PyPy 설치 및 검증 완료"
  }catch{
    if($AllowNewer){ Write-Warn "PyPy 7.3.15 설치 실패. -AllowNewer로 대체 버전 허용 가능. 오류: $($_.Exception.Message)" } else { throw }
  }
}else{
  Write-Info "PyPy 설치 스킵"
}

# ----------------- CodeFestival 래퍼 생성 -----------------
if(-not $NoWrappers){
  Write-Host "`n===== CodeFestival 래퍼 생성 =====" -ForegroundColor Green
  $binDir = Join-Path $InstallDir "cf-bin"
  if(-not (Test-Path $binDir)){ New-Item -ItemType Directory -Path $binDir | Out-Null }

  # cf-gcc.bat
  Set-Content -LiteralPath (Join-Path $binDir "cf-gcc.bat") -Encoding ascii -Value @(
    '@echo off',
    'REM CodeFestival language toolchain installer - cf-gcc',
    'gcc -x c -g -O2 -std=gnu11 -static %* -lm'
  )

  # cf-g++.bat
  Set-Content -LiteralPath (Join-Path $binDir "cf-g++.bat") -Encoding ascii -Value @(
    '@echo off',
    'REM CodeFestival language toolchain installer - cf-g++',
    'g++ -x c++ -g -O2 -std=gnu++20 -static %*'
  )

  # cf-javac.bat
  Set-Content -LiteralPath (Join-Path $binDir "cf-javac.bat") -Encoding ascii -Value @(
    '@echo off',
    'REM CodeFestival language toolchain installer - cf-javac',
    'javac -encoding UTF-8 -sourcepath . -d . %*'
  )

  # cf-java-run.cmd
  Set-Content -LiteralPath (Join-Path $binDir "cf-java-run.cmd") -Encoding ascii -Value @(
    '@echo off',
    'REM CodeFestival language toolchain installer - cf-java-run',
    'REM usage: cf-java-run <memMB> <MainClass> [args...]',
    'IF "%~1"=="" (',
    '  ECHO usage: cf-java-run ^<memMB^> ^<MainClass^> [args...]',
    '  EXIT /B 2',
    ')',
    'SET MEM=%~1',
    'SHIFT',
    'java -Dfile.encoding=UTF-8 -XX:+UseSerialGC -Xss64m -Xms%MEM%m -Xmx%MEM%m %*'
  )

  Add-ToPath $binDir -SystemLevel:$SystemPath
}else{
  Write-Info "래퍼 생성 스킵"
}

# ----------------- 요약 -----------------
Write-Host "`n===== 설치 결과 요약 =====" -ForegroundColor Green
try{ if(-not $SkipJava){ java -version 2>&1 | Select-Object -First 2 | % { Write-Host "Java: $_" } } }catch{ Write-Warn "Java 확인 실패: $($_.Exception.Message)" }
try{ if(-not $SkipGCC){ (& gcc --version 2>&1 | Select-Object -First 1) | % { Write-Host "GCC: $_" } } }catch{ Write-Warn "GCC 확인 실패: $($_.Exception.Message)" }
try{ if(-not $SkipPyPy){ (& pypy3 --version 2>&1) | % { Write-Host "PyPy: $_" } } }catch{ Write-Warn "PyPy 확인 실패: $($_.Exception.Message)" }

Write-Host "`n설치 완료. 새 PowerShell/터미널을 열어 PATH 반영을 확인하세요." -ForegroundColor Green
