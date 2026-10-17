param(
  [string]$Flutter = 'flutter',
  [switch]$BuildWeb,
  [switch]$BackendOnly,
  [switch]$DatabaseTests
)
$ErrorActionPreference = 'Stop'
$awaazRoot = Split-Path $PSScriptRoot -Parent
if (-not $BackendOnly) {
  Push-Location (Join-Path $awaazRoot 'apps\mobile')
  try {
    & $Flutter pub get
    if ($LASTEXITCODE -ne 0) { throw 'Flutter dependency resolution failed' }
    & $Flutter analyze
    if ($LASTEXITCODE -ne 0) { throw 'Flutter analysis failed' }
    & $Flutter test
    if ($LASTEXITCODE -ne 0) { throw 'Flutter tests failed' }
    if ($BuildWeb) {
      & $Flutter build web --release
      if ($LASTEXITCODE -ne 0) { throw 'Web build failed' }
    }
  } finally { Pop-Location }
}
Push-Location (Join-Path $awaazRoot 'apps\api')
try {
  pnpm install --frozen-lockfile
  if ($LASTEXITCODE -ne 0) { throw 'API dependency resolution failed' }
  pnpm format:check
  if ($LASTEXITCODE -ne 0) { throw 'API formatting check failed' }
  pnpm check
  if ($LASTEXITCODE -ne 0) { throw 'API type check failed' }
  pnpm test
  if ($LASTEXITCODE -ne 0) { throw 'API tests failed' }
  if ($DatabaseTests) {
    pnpm test:db
    if ($LASTEXITCODE -ne 0) { throw 'API database tests failed' }
  }
  pnpm openapi
  if ($LASTEXITCODE -ne 0) { throw 'API schema export failed' }
} finally { Pop-Location }
