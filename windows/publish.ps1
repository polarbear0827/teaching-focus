param([string]$OutputDirectory = (Join-Path $PSScriptRoot 'dist\win-x64'))
$ErrorActionPreference = 'Stop'
$env:DOTNET_CLI_TELEMETRY_OPTOUT = '1'
$env:DOTNET_GENERATE_ASPNET_CERTIFICATE = 'false'
$project = Join-Path $PSScriptRoot 'TeachingFocus.Windows\TeachingFocus.Windows.csproj'
dotnet publish $project -c Release -r win-x64 --self-contained true -o $OutputDirectory
if ($LASTEXITCODE -ne 0) { throw 'Windows publish failed.' }
$exe = Join-Path $OutputDirectory 'TeachingFocus.exe'
if (-not (Test-Path $exe)) { throw 'TeachingFocus.exe was not produced.' }
Copy-Item (Join-Path $PSScriptRoot 'README.md') (Join-Path $OutputDirectory '使用說明.txt') -Force
$zip = Join-Path (Split-Path $OutputDirectory -Parent) 'TeachingFocus-v1.1.0-windows-beta.1-x64.zip'
Compress-Archive -Path $exe,(Join-Path $OutputDirectory '使用說明.txt') -DestinationPath $zip -Force
$hash = (Get-FileHash $zip -Algorithm SHA256).Hash.ToLowerInvariant()
"$hash  $(Split-Path $zip -Leaf)" | Set-Content (Join-Path (Split-Path $zip -Parent) 'SHA256SUMS.txt') -Encoding ascii
Write-Host "Created portable Windows preview: $zip"
Write-Host 'No Windows runtime tests were executed. This EXE is not Authenticode signed.'
