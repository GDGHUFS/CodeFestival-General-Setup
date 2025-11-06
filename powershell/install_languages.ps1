<#
  CodeFestival language toolchain installer (no-here-string edition)
  대상:
    - Java (OpenJDK 21.0.4 via winget Temurin 21)
    - C/C++ (GCC/G++ 13.2.0 via WinLibs; MSYS2 대체 옵션)
    - PyPy3 7.3.15 (Python 3.9.18)
  비고:
    - 새 터미널에서 PATH 반영
    - Windows 10 / PowerShell 5.1 호환
#>

[CmdletBinding()]
param(
  [string]$InstallDir = "C:\CodeFestival\tools",
  [switch]$AllowNewer,
  [switch]$SystemPath,
  [switch]$UseMSYS2Fallback,
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
}

function Expand-AnyArchive([string]$archivePath, [string]$destDir){
  Ensure-Dir $destDir
  $ext = [IO.Path]::GetExtension($archivePath).ToLowerInvariant()
  if($ext -eq ".zip"){
    Expand-Archive -Path $archivePath -DestinationPath $destDir -Force
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
  if($out -notmatch $pattern){ throw "$human 버전 검증 실패. 출력:`n$out" }
  Write-Info "$human 확인: $($matches[0])"
  return $out
}

Ensure-Dir $InstallDir
$dl = Join-Path $InstallDir "downloads"
Ensure-Dir $dl

# ---------- Java (OpenJDK 21.0.4) ----------
if(-not $SkipJava){
  Write-Host "`n===== Java (OpenJDK 21.0.4) 설치 =====" -ForegroundColor Green
  $temurinId = "EclipseAdoptium.Temurin.21.JDK"
  $required = '21\.0\.4'

  $winget = Get-CommandPath "winget"
  if(-not $winget){
    Write-Err "winget을 찾지 못했습니다. Microsoft Store에서 App Installer(winget)를 설치하거나 -SkipJava로 건너뛰세요."
  } else {
    try{
      Write-Info "winget으로 Temurin 21.0.4 시도"
      $argsExact = @("install","--id",$temurinId,"--version","21.0.4","--accept-package-agreements","--accept-source-agreements","-e","-h")
      winget @argsExact | Out-Null
    }catch{
      if($AllowNewer){
        Write-Warn "정확 버전 실패. 최신 21 설치 시도"
        winget install --id $temurinId -e -h --accept-package-agreements --accept-source-agreements | Out-Null
      }else{
        throw "Temurin 21.0.4 설치 실패. -AllowNewer로 대체 허용 가능."
      }
    }
  }

  # PATH/JAVA_HOME
  function Get-JavaHome {
    $cands = @(
      "HKLM:\SOFTWARE\Adoptium\JDK\21",
      "HKLM:\SOFTWARE\JavaSoft\JDK\21",
      "HKLM:\SOFTWARE\Eclipse Adoptium\JDK\21"
    )
    foreach($k in $cands){
      try{
        $val = Get-ItemProperty -Path $k -ErrorAction Stop
        foreach($prop in @("JavaHome","Path","InstallLocation")){
          if($val.$prop){ return $val.$prop }
        }
      }catch{}
    }
    $glob = Get-ChildItem "C:\Program Files" -Filter "jdk-21*" -Directory -ErrorAction SilentlyContinue
    if($glob){ return $glob[0].FullName }
    return $null
  }

  $javaBin = Get-CommandPath "java"
  if(-not $javaBin){
    $home = Get-JavaHome
    if($home){ Add-ToPath (Join-Path $home "bin") -SystemLevel:$SystemPath; $javaBin = Get-CommandPath "java" }
  }
  if(-not $javaBin){ throw "java 실행 파일을 찾지 못했습니다." }

  $verOut = Verify-Version { java -version } $required "Java(OpenJDK)"
  if($verOut -notmatch $required){
    if($AllowNewer){ Write-Warn "요구 버전과 다릅니다. 출력:`n$verOut" } else { throw "요구 버전 불일치(21.0.4)." }
  }

  $javaHome = Get-JavaHome
  if($javaHome){
    [Environment]::SetEnvironmentVariable("JAVA_HOME",$javaHome,[EnvironmentVariableTarget]::User)
    if($SystemPath){ [Environment]::SetEnvironmentVariable("JAVA_HOME",$javaHome,[EnvironmentVariableTarget]::Machine) }
    Write-Info "JAVA_HOME=$javaHome"
  } else {
    Write-Warn "JAVA_HOME을 찾지 못했습니다."
  }
}else{ Write-Info "Java 설치 스킵" }

# ---------- GCC/G++ 13.2.0 (WinLibs) ----------
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
      Download-File $zipUrl $zipPath
      Expand-AnyArchive $zipPath $gccRoot
      $bins = Get-ChildItem -Recurse -Directory $gccRoot -Filter "bin" -ErrorAction SilentlyContinue
      if($bins.Count -gt 0){ $gccBin = $bins[0].FullName }
    }
    Add-ToPath $gccBin -SystemLevel:$SystemPath
    Verify-Version { gcc --version } $gccRequired "gcc"
    Verify-Version { g++ --version } $gccRequired "g++"
  }catch{
    Write-Err "WinLibs 설치 실패: $($_.Exception.Message)"
    if($UseMSYS2Fallback){
      Write-Warn "MSYS2 대체 설치 시도(정적 링크 -static 제약 가능)"
      $wingetMSYS2 = Get-CommandPath "winget"
      if(-not $wingetMSYS2){ throw "winget 필요(MSYS2 설치). winget이 없습니다." }
      winget install --id MSYS2.MSYS2 -e --accept-package-agreements --accept-source-agreements -h | Out-Null
      $msysRoot = "C:\msys64"
      $bashExe  = Join-Path $msysRoot "usr\bin\bash.exe"
      if(-not (Test-Path $bashExe)){ throw "MSYS2 bash를 찾을 수 없습니다: $bashExe" }
      & $bashExe -lc "pacman -Sy --noconfirm" | Out-Null
      & $bashExe -lc "pacman -S --noconfirm --needed mingw-w64-ucrt-x86_64-gcc mingw-w64-ucrt-x86_64-gdb" | Out-Null
      $mingwBin = Join-Path $msysRoot "mingw64\bin"
      Add-ToPath $mingwBin -SystemLevel:$SystemPath
      Verify-Version { & (Join-Path $mingwBin "gcc.exe") --version } $gccRequired "gcc(MSYS2)"
      Verify-Version { & (Join-Path $mingwBin "g++.exe") --version } $gccRequired "g++(MSYS2)"
      Write-Warn "알림: MSYS2는 -static 링크에 제약이 있을 수 있습니다."
    } else {
      if($AllowNewer){ Write-Warn "정확 버전 실패. -AllowNewer로 최신 버전 사용 허용 가능." } else { throw }
    }
  }
}else{ Write-Info "GCC/G++ 설치 스킵" }

# ---------- PyPy3 7.3.15 ----------
if(-not $SkipPyPy){
  Write-Host "`n===== PyPy3 7.3.15 (Python 3.9.18) 설치 =====" -ForegroundColor Green
  $pypyDir = Join-Path $InstallDir "pypy3.9-v7.3.15-win64"
  $pypyExe = Join-Path $pypyDir "pypy3.exe"

  try{
    if(-not (Test-Path $pypyExe)){
      $primaryUrl = "https://downloads.python.org/pypy/pypy3.9-v7.3.15-win64.zip"
      $zipPath = Join-Path $dl "pypy3.9-v7.3.15-win64.zip"
      try{ Download-File $primaryUrl $zipPath }
      catch{
        Write-Warn "직접 URL 실패, pypy 다운로드 페이지에서 검색"
        $dlPage = "https://www.pypy.org/download.html"
        $html = (Invoke-WebRequest -UseBasicParsing -Uri $dlPage -TimeoutSec 180).Content
        $m = [regex]::Match($html, 'https?://[^"]*/pypy3\.9-v7\.3\.15-win64\.zip', 'IgnoreCase')
        if(-not $m.Success){ throw "다운로드 링크를 찾지 못했습니다." }
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

    # python3.bat (PyPy alias)
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
}else{ Write-Info "PyPy 설치 스킵" }

# ---------- 래퍼 생성 ----------
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

# ---------- 요약 ----------
Write-Host "`n===== 설치 결과 요약 =====" -ForegroundColor Green
try{ if(-not $SkipJava){ java -version 2>&1 | Select-Object -First 2 | % { Write-Host "Java: $_" } } }catch{ Write-Warn "Java 확인 실패: $($_.Exception.Message)" }
try{ if(-not $SkipGCC){ (& gcc --version 2>&1 | Select-Object -First 1) | % { Write-Host "GCC: $_" } } }catch{ Write-Warn "GCC 확인 실패: $($_.Exception.Message)" }
try{ if(-not $SkipPyPy){ (& pypy3 --version 2>&1) | % { Write-Host "PyPy: $_" } } }catch{ Write-Warn "PyPy 확인 실패: $($_.Exception.Message)" }

Write-Host "`n설치 완료. 새 PowerShell/터미널을 열어 PATH 반영을 확인하세요." -ForegroundColor Green
