param(
  [switch]$Native,
  [switch]$Wasm
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$siblingEngine = Join-Path (Split-Path -Parent $root) 'estandarte-engine'
$localEngine = Join-Path $root 'engine'
$engineDir = if (Test-Path (Join-Path $siblingEngine 'go.mod')) {
  $siblingEngine
} elseif (Test-Path (Join-Path $localEngine 'go.mod')) {
  $localEngine
} else {
  throw "Motor Go nao encontrado em '$siblingEngine' nem em '$localEngine'."
}

Push-Location $engineDir
try {
  if ($Wasm -or -not $Native) {
    $env:GOOS = 'js'
    $env:GOARCH = 'wasm'
    go build -ldflags="-s -w" -o (Join-Path $root 'web\engine\estandarte.wasm') ./cmd/wasm
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    $goroot = go env GOROOT
    $wasmExec = Join-Path $goroot 'lib\wasm\wasm_exec.js'
    if (-not (Test-Path $wasmExec)) { $wasmExec = Join-Path $goroot 'misc\wasm\wasm_exec.js' }
    Copy-Item $wasmExec (Join-Path $root 'web\engine\wasm_exec.js') -Force
    Write-Host "Built web/engine/estandarte.wasm and copied wasm_exec.js"
  }

  if ($Native) {
    Remove-Item Env:GOOS -ErrorAction SilentlyContinue
    Remove-Item Env:GOARCH -ErrorAction SilentlyContinue
    $nativeDir = Join-Path $root 'native'
    New-Item -ItemType Directory -Path $nativeDir -Force | Out-Null

    $env:CGO_ENABLED = '0'
    $outRpc = Join-Path $nativeDir 'estandarte_engine_rpc.exe'
    go build -ldflags="-s -w -H=windowsgui" -o $outRpc ./cmd/rpc
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    Write-Host "Built native/estandarte_engine_rpc.exe"

    if (Get-Command gcc -ErrorAction SilentlyContinue) {
      $env:CGO_ENABLED = '1'
      $outDll = Join-Path $nativeDir 'estandarte_engine.dll'
      go build -buildmode=c-shared -o $outDll ./cmd/ffi
      if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
      Write-Host "Built native/estandarte_engine.dll"
    }
  }
} finally {
  Remove-Item Env:GOOS -ErrorAction SilentlyContinue
  Remove-Item Env:GOARCH -ErrorAction SilentlyContinue
  Remove-Item Env:CGO_ENABLED -ErrorAction SilentlyContinue
  Pop-Location
}
