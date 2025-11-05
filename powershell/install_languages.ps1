<#
    CodeFestival language toolchain installer
    ---------------------------------------------------------------
    목적: Windows 11에서 대회용 언어 툴체인 자동 설치 및 검증
    대상:
      - Java (OpenJDK 21.0.4)
      - C (gcc 13.2.0) / C++ (g++ 13.2.0)  [WinLibs standalone]
      - Python 3 (PyPy3 v7.3.15 / Python 3.9.18)
    편의 래퍼 생성:
      - cf-javac.bat / cf-java-run.cmd
      - cf-gcc.bat / cf-g++.bat
      - python3.bat (pypy3 에일리어스)
    CodeFestival 규정 플래그(래퍼에 반영):
      - Java 컴파일:   javac -encoding UTF-8 -sourcepath . -d . {files}
      - Java 런타임:   java  -Dfile.encoding=UTF-8 -XX:+UseSerialGC -Xss64m -Xms{mem}m -Xmx{mem}m
      - C 컴파일:      gcc  -x c   -g -O2 -std=gnu11  -static {files} -lm
      - C++ 컴파일:    g++  -x c++ -g -O2 -std=gnu++20 -static {files}

    사용 예:
      .\install-codefestival.ps1 -InstallDir "C:\CodeFestival\tools" -SystemPath
      cf-gcc   main.c               # 정적 링크 gnu11, -O2, -g
      cf-g++   main.cpp             # 정적 링크 gnu++20, -O2, -g
      cf-javac Main.java            # UTF-8 컴파일
      cf-java-run 1024 Main         # 메모리 1024MB로 Main 실행

    주의:
      - PATH 적용은 새 터미널에서 반영됨.
      - 관리자 권한 없이도 사용자 PATH에 설치 가능(기본).
      - 네트워크 차단/프록시 환경에선 직접 파일 제공 필요.

    (c) CodeFestival language toolchain installer
#>

[CmdletBinding()]
param(
  # 설치 루트
  [string]$InstallDir = "C:\CodeFestival\tools",

  # 정확 버전이 없을 때 동일 메이저/호환 버전 허용
  [switch]$AllowNewer,

  # 시스템 PATH에 추가(관리자 필요). 기본: 사용자 PATH.
  [switch]$SystemPath,

  # MSYS2로 GCC 대체 설치 시도(기본은 WinLibs standalone)
  [switch]$UseMSYS2Fallback,

  # 개별 컴포넌트 스킵
  [switch]$SkipJava,
  [switch]$SkipGCC,
  [switch]$SkipPyPy,

  # 편의 래퍼 생성을 생략
  [switch]$NoWrappers
)

# ----------------- 공통 유틸 -----------------

$ErrorActionPreference = 'Stop'

function Write-Info([string]$msg){ Write-Host "[INFO] $msg" -ForegroundColor Cyan }
function Write-Warn([string]$msg){ Write-Host "[WARN] $msg" -ForegroundColor Yellow }
function Write-Err ([string]$msg){ Write-Host "[ERROR] $msg" -ForegroundColor Red }

function Ensure-Dir([string]$path){
  if(-not (Test-Path $path)){ New-Item -ItemType Directory -Path $path | Out-Null }
}

function Add-ToPath([string]$path, [switch]$SystemLevel){
  $path = [System.IO.Path]::GetFullPath($path)
  if(-not (Test-Path $path)){ throw "경로가 존재하지 않습니다: $path" }

  if($SystemLevel){
    if(-not ([bool](New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))){
      throw "시스템 PATH 수정에는 관리자 권한이 필요합니다. -SystemPath 없이 실행하거나 관리자 PowerShell로 실행하세요."
    }
    $reg = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Environment"
  }else{
    $reg = "HKCU:\Environment"
  }

  $current = (Get-ItemProperty -Path $reg -Name Path -ErrorAction SilentlyContinue).Path
  if([string]::IsNullOrEmpty($current)){ $current = "" }

  # 이미 포함되어 있으면 스킵
  $already = $current.Split(';') | Where-Object { $_ -ieq $path }
  if(-not $already){
    $newPath = ($current.TrimEnd(';') + ';' + $path).Trim(';')
    Set-ItemProperty -Path $reg -Name Path -Value $newPath
    # 현재 세션에도 반영
    $env:Path = $newPath
    Write-Info "PATH에 추가됨: $path  (새 터미널에서 확실히 반영)"
  }else{
    Write-Info "PATH에 이미 포함: $path"
  }
}

function Download-File([string]$url, [string]$dst){
  Write-Info "다운로드: $url"
  try{
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $dst -TimeoutSec 1800
  }catch{
    throw "다운로드 실패: $url`n$($_.Exception.Message)"
  }
  if(-not (Test-Path $dst) -or ((Get-Item $dst).Length -le 0)){
    throw "다운로드된 파일이 비정상입니다: $dst"
  }
}

function Expand-AnyArchive([string]$archivePath, [string]$destDir){
  Ensure-Dir $destDir
  $ext = [IO.Path]::GetExtension($archivePath).ToLowerInvariant()
  if($ext -eq ".zip"){
    Expand-Archive -Path $archivePath -DestinationPath $destDir -Force
  }elseif($ext -eq ".7z"){
    # 7-Zip 필요. 없으면 예외
    $sevenZip = (Get-Command 7z -ErrorAction SilentlyContinue)?.Source
    if(-not $sevenZip){ throw "7z 명령을 찾을 수 없습니다. zip 아카이브를 사용하거나 7-Zip을 설치하세요." }
    & $sevenZip x "-o$destDir" -y $archivePath | Out-Null
  }else{
    throw "지원되지 않는 압축 형식: $ext"
  }
}

function Get-CommandPath([string]$name){
  return (Get-Command $name -ErrorAction SilentlyContinue).Source
}

function Verify-Version([scriptblock]$cmd, [string]$pattern, [string]$human){
  try{
    $out = & $cmd 2>&1 | Out-String
  }catch{
    throw "$human 실행 실패: $($_.Exception.Message)"
  }
  if($out -notmatch $pattern){
    throw "$human 버전 검증 실패. 출력: `n$out"
  }
  Write-Info "$human 버전 확인: $($matches[0])"
  return $out
}

Ensure-Dir $InstallDir
$dl = Join-Path $InstallDir "downloads"
Ensure-Dir $dl

# ----------------- Java (OpenJDK 21.0.4) -----------------
if(-not $SkipJava){
  Write-Host "`n===== Java (OpenJDK 21.0.4) 설치 =====" -ForegroundColor Green
  $temurinId = "EclipseAdoptium.Temurin.21.JDK"
  $required = '21\.0\.4'
  $installed = $false

  function Get-JavaHome {
    $candidates = @(
      "HKLM:\SOFTWARE\Adoptium\JDK\21",
      "HKLM:\SOFTWARE\JavaSoft\JDK\21",
      "HKLM:\SOFTWARE\Eclipse Adoptium\JDK\21"
    )
    foreach($k in $candidates){
      try{
        $val = (Get-ItemProperty -Path $k -ErrorAction Stop)
        foreach($prop in @("JavaHome","Path","InstallLocation")){
          if($val.$prop){ return $val.$prop }
        }
      }catch{}
    }
    # 폴더 탐색
    $glob = Get-ChildItem "C:\Program Files" -Filter "jdk-21*" -Directory -ErrorAction SilentlyContinue
    if($glob){ return $glob[0].FullName }
    return $null
  }

  try{
    # 우선 정확 버전 시도
    Write-Info "winget으로 Temurin 21.0.4 시도"
    $argsExact = @("install","--id",$temurinId,"--version","21.0.4","--accept-package-agreements","--accept-source-agreements","-e","-h")
    winget @argsExact | Out-Null
    $installed = $true
  }catch{
    if($AllowNewer){
      Write-Warn "정확 버전(21.0.4) 설치 실패. -AllowNewer로 최신 21 설치 시도"
      try{
        $argsAny = @("install","--id",$temurinId,"--accept-package-agreements","--accept-source-agreements","-e","-h")
        winget @argsAny | Out-Null
        $installed = $true
      }catch{
        Write-Err "Temurin 설치 실패: $($_.Exception.Message)"
      }
    }else{
      Write-Err "Temurin 21.0.4 설치 실패. -AllowNewer를 주면 최신 21로 대체 설치합니다."
    }
  }

  # 검증 및 JAVA_HOME/PATH 설정
  $javaBin = Get-CommandPath "java"
  if(-not $javaBin){
    $home = Get-JavaHome
    if($home){
      Add-ToPath (Join-Path $home "bin") -SystemLevel:$SystemPath
      $javaBin = Get-CommandPath "java"
    }
  }
  if(-not $javaBin){ throw "java 실행 파일을 찾을 수 없습니다. 설치/경로를 확인하세요." }

  $verOut = Verify-Version { java -version } $required "Java(OpenJDK)"
  if($verOut -notmatch $required){
    if($AllowNewer){
      Write-Warn "요구 버전(21.0.4)과 다릅니다. 출력:`n$verOut"
    }else{
      throw "요구 버전(21.0.4) 불일치. -AllowNewer를 사용해 최신 21 허용 가능."
    }
  }

  $javaHome = Get-JavaHome
  if($javaHome){
    [System.Environment]::SetEnvironmentVariable("JAVA_HOME",$javaHome, [System.EnvironmentVariableTarget]::User)
    if($SystemPath){
      [System.Environment]::SetEnvironmentVariable("JAVA_HOME",$javaHome, [System.EnvironmentVariableTarget]::Machine)
    }
    Write-Info "JAVA_HOME=$javaHome"
  }else{
    Write-Warn "JAVA_HOME을 찾지 못했습니다. 필요시 수동 지정하세요."
  }
}else{
  Write-Info "Java 설치 스킵"
}

# ----------------- GCC/G++ 13.2.0 (WinLibs) -----------------
if(-not $SkipGCC){
  Write-Host "`n===== GCC/G++ 13.2.0 설치 =====" -ForegroundColor Green
  $gccRequired = '13\.2\.0'
  $gccRoot = Join-Path $InstallDir "winlibs-gcc-13.2.0"
  $gccBin = Join-Path $gccRoot "bin"

  function Find-WinLibsZipUrl {
    # winlibs.com 페이지에서 gcc-13.2.0이 포함된 zip 링크(우선 msvcrt, 실패 시 ucrt) 파싱
    $pageUrl = "https://winlibs.com/"
    $html = ""
    try{
      [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
      $html = (Invoke-WebRequest -UseBasicParsing -Uri $pageUrl -TimeoutSec 180).Content
    }catch{
      throw "winlibs.com 접근 실패: $($_.Exception.Message)"
    }
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
          # 상대링크면 보정
          if($href.StartsWith("/")){ return "https://winlibs.com$href" }
          else{ return "https://winlibs.com/$href" }
        }
        return $href
      }
    }
    throw "GCC 13.2.0 zip 링크를 페이지에서 찾지 못했습니다."
  }

  try{
    if(-not (Test-Path $gccBin)){
      $zipUrl = Find-WinLibsZipUrl
      $zipName = Split-Path $zipUrl -Leaf
      $zipPath = Join-Path $dl $zipName
      Download-File $zipUrl $zipPath
      Expand-AnyArchive $zipPath $gccRoot

      # WinLibs 압축엔 루트폴더가 하나 더 있을 수 있으니 bin 위치 정규화
      $bins = Get-ChildItem -Recurse -Directory $gccRoot -Filter "bin" -ErrorAction SilentlyContinue
      if($bins.Count -gt 0){ $gccBin = $bins[0].FullName }
    }

    Add-ToPath $gccBin -SystemLevel:$SystemPath

    $gccOut = Verify-Version { gcc --version } $gccRequired "gcc"
    $gppOut = Verify-Version { g++ --version } $gccRequired "g++"
  }catch{
    Write-Err "WinLibs 설치 실패: $($_.Exception.Message)"
    if($UseMSYS2Fallback){
      Write-Warn "MSYS2 대체 설치 시도(정적 링크 -static은 제한될 수 있음)"
      try{
        winget install --id MSYS2.MSYS2 -e --accept-package-agreements --accept-source-agreements -h | Out-Null
        $msysRoot = "C:\msys64"
        $msysExe  = Join-Path $msysRoot "usr\bin\bash.exe"
        if(-not (Test-Path $msysExe)){ throw "MSYS2 bash를 찾을 수 없습니다: $msysExe" }
        & $msysExe -lc "pacman -Sy --noconfirm" | Out-Null
        & $msysExe -lc "pacman -S --noconfirm --needed mingw-w64-ucrt-x86_64-gcc mingw-w64-ucrt-x86_64-gdb" | Out-Null
        $mingwBin = Join-Path $msysRoot "mingw64\bin"
        Add-ToPath $mingwBin -SystemLevel:$SystemPath
        Verify-Version { & (Join-Path $mingwBin "gcc.exe") --version } $gccRequired "gcc(MSYS2)"
        Verify-Version { & (Join-Path $mingwBin "g++.exe") --version } $gccRequired "g++(MSYS2)"
        Write-Warn "주의: MSYS2 툴체인은 -static 링크에 제약이 있을 수 있습니다."
      }catch{
        if($AllowNewer){
          Write-Warn "정확 버전 설치 실패. -AllowNewer 허용 상태에서 gcc/g++ 최신 버전으로 대체 사용을 권장합니다."
        }else{
          throw
        }
      }
    }else{
      if($AllowNewer){
        Write-Warn "정확 버전 설치 실패. -AllowNewer 허용 상태에서 gcc/g++ 최신 버전으로 대체 사용을 권장합니다."
      }else{
        throw
      }
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
      $zipName = "pypy3.9-v7.3.15-win64.zip"
      $zipPath = Join-Path $dl $zipName
      try{
        Download-File $primaryUrl $zipPath
      }catch{
        Write-Warn "직접 URL 실패, pypy 다운로드 페이지를 탐색합니다."
        $dlPage = "https://www.pypy.org/download.html"
        $html = (Invoke-WebRequest -UseBasicParsing -Uri $dlPage -TimeoutSec 180).Content
        $m = [regex]::Match($html, 'https?://[^"]*/pypy3\.9-v7\.3\.15-win64\.zip', 'IgnoreCase')
        if(-not $m.Success){ throw "다운로드 링크를 페이지에서 찾지 못했습니다." }
        $resolved = $m.Value
        Download-File $resolved $zipPath
      }
      Expand-AnyArchive $zipPath $InstallDir
    }

    if(-not (Test-Path $pypyExe)){ throw "pypy3.exe를 찾을 수 없습니다: $pypyExe" }
    Add-ToPath $pypyDir -SystemLevel:$SystemPath

    # 버전 검증: PyPy 7.3.15 / Python 3.9
    $pypyOut = & $pypyExe --version 2>&1 | Out-String
    if($pypyOut -notmatch 'PyPy 7\.3\.15'){
      if($AllowNewer){
        Write-Warn "PyPy 요구 버전(7.3.15)과 다릅니다. 출력:`n$pypyOut"
      }else{
        throw "PyPy 7.3.15 버전 검증 실패. 출력:`n$pypyOut"
      }
    }
    if($pypyOut -notmatch 'Python 3\.9'){
      Write-Warn "파이썬 인터프리터 버전이 3.9가 아닙니다. 출력:`n$pypyOut"
    }

    # pip 보장
    try{
      & $pypyExe -m ensurepip --upgrade | Out-Null
    }catch{
      Write-Warn "ensurepip 실패: $($_.Exception.Message)"
    }

    # python3 에일리어스 배치
    $pythonAlias = Join-Path $pypyDir "python3.bat"
    if(-not (Test-Path $pythonAlias)){
      @"
@echo off
REM CodeFestival language toolchain installer - python3 alias
"%~dp0pypy3.exe" %*
"@ | Out-File -FilePath $pythonAlias -Encoding ascii -Force
    }
    Write-Info "PyPy 설치 및 검증 완료."
  }catch{
    if($AllowNewer){
      Write-Warn "PyPy 7.3.15 설치에 실패했습니다. -AllowNewer로 대체 버전을 수동 사용하세요. 오류: $($_.Exception.Message)"
    }else{
      throw
    }
  }
}else{
  Write-Info "PyPy 설치 스킵"
}

# ----------------- 래퍼 스크립트 생성 -----------------
if(-not $NoWrappers){
  Write-Host "`n===== CodeFestival 래퍼 생성 =====" -ForegroundColor Green
  $binDir = Join-Path $InstallDir "cf-bin"
  Ensure-Dir $binDir

  # C/C++
  @"
@echo off
REM CodeFestival language toolchain installer - cf-gcc
gcc -x c -g -O2 -std=gnu11 -static %* -lm
"@ | Out-File (Join-Path $binDir "cf-gcc.bat") -Encoding ascii -Force

  @"
@echo off
REM CodeFestival language toolchain installer - cf-g++
g++ -x c++ -g -O2 -std=gnu++20 -static %*
"@ | Out-File (Join-Path $binDir "cf-g++.bat") -Encoding ascii -Force

  # Java 컴파일
  @"
@echo off
REM CodeFestival language toolchain installer - cf-javac
javac -encoding UTF-8 -sourcepath . -d . %*
"@ | Out-File (Join-Path $binDir "cf-javac.bat") -Encoding ascii -Force

  # Java 실행 (첫 번째 인자: 메모리(MB). 두 번째 이후: main 클래스/args)
  @"
@echo off
REM CodeFestival language toolchain installer - cf-java-run
if "%~1"=="" (
  echo 사용법: cf-java-run ^<memMB^> ^<MainClass^> [args...]
  exit /b 2
)
set MEM=%~1
shift
java -Dfile.encoding=UTF-8 -XX:+UseSerialGC -Xss64m -Xms%MEM%m -Xmx%MEM%m %*
"@ | Out-File (Join-Path $binDir "cf-java-run.cmd") -Encoding ascii -Force

  Add-ToPath $binDir -SystemLevel:$SystemPath
}else{
  Write-Info "래퍼 생성 스킵"
}

# ----------------- 최종 리포트 -----------------
Write-Host "`n===== 설치 결과 요약 =====" -ForegroundColor Green
try{
  if(-not $SkipJava){ java -version 2>&1 | Select-Object -First 2 | ForEach-Object { Write-Host "Java: $_" } }
}catch{ Write-Warn "Java 버전 확인 실패: $($_.Exception.Message)" }

try{
  if(-not $SkipGCC){ (& gcc --version 2>&1 | Select-Object -First 1) | ForEach-Object { Write-Host "GCC: $_" } }
}catch{ Write-Warn "GCC 버전 확인 실패: $($_.Exception.Message)" }

try{
  if(-not $SkipPyPy){ (& pypy3 --version 2>&1) | ForEach-Object { Write-Host "PyPy: $_" } }
}catch{ Write-Warn "PyPy 버전 확인 실패: $($_.Exception.Message)" }

Write-Host "`n설치 완료. 새 PowerShell/터미널을 열어 PATH 반영을 확인하세요." -ForegroundColor Green
