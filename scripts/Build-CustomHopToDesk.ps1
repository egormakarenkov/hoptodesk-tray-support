$ErrorActionPreference = 'Stop'
$taskRoot = $PSScriptRoot
$repoRoot = Join-Path $taskRoot 'hoptodesk'
$mappedHere = $false
$buildDrive = $null
foreach ($letter in @('H', 'J', 'K', 'L', 'M', 'N')) {
    $candidate = $letter + ':'
    if (!(Test-Path ($candidate + '\'))) {
        & subst $candidate $taskRoot
        if ($LASTEXITCODE -ne 0) { throw 'Could not map the build workspace.' }
        $buildDrive = $candidate
        $mappedHere = $true
        break
    }
}
if (!$buildDrive) { throw 'No free temporary build drive was available.' }

$savedEnvironment = @{}
$settings = @{
    VCPKG_ROOT = "$buildDrive\build-tools\vcpkg"
    LIBCLANG_PATH = "$buildDrive\build-tools\libclang\libclang-18.1.1.data\platlib\clang\native"
    CARGO_PROFILE_RELEASE_LTO = 'false'
    CARGO_PROFILE_RELEASE_CODEGEN_UNITS = '16'
    CARGO_PROFILE_RELEASE_OPT_LEVEL = '2'
}
try {
    foreach ($key in $settings.Keys) {
        $savedEnvironment[$key] = [Environment]::GetEnvironmentVariable($key, 'Process')
        [Environment]::SetEnvironmentVariable($key, $settings[$key], 'Process')
    }
    Push-Location $repoRoot
    try {
        & cargo +1.85.1 build --release --locked --features packui --jobs 4
        if ($LASTEXITCODE -ne 0) { throw 'HopToDesk build failed; no installed files were changed.' }
    } finally { Pop-Location }
} finally {
    foreach ($key in $savedEnvironment.Keys) {
        [Environment]::SetEnvironmentVariable($key, $savedEnvironment[$key], 'Process')
    }
    if ($mappedHere) { & subst $buildDrive /D }
}
