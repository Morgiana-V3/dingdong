$ErrorActionPreference = 'Stop'
Set-Location -LiteralPath $PSScriptRoot
if (-not (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'node_modules'))) {
    npm ci
    if ($LASTEXITCODE -ne 0) { throw '依赖安装失败' }
}
$dingdongReady = $false
try {
    $dingdongHealth = Invoke-RestMethod -Uri 'http://127.0.0.1:18890/health' -TimeoutSec 2
    $dingdongReady = $dingdongHealth.service -eq 'dingdong-node'
} catch {}
if (-not $dingdongReady) {
    npm run build
    if ($LASTEXITCODE -ne 0) { throw '订阅服务构建失败' }
    $dingdongData = Join-Path $PSScriptRoot 'data'
    New-Item -ItemType Directory -Force -Path $dingdongData | Out-Null
    Start-Process -FilePath (Get-Command node).Source -ArgumentList 'src/server.mjs' -WorkingDirectory $PSScriptRoot -WindowStyle Hidden -RedirectStandardOutput (Join-Path $dingdongData 'service.log') -RedirectStandardError (Join-Path $dingdongData 'service-error.log') | Out-Null
    for ($dingdongAttempt = 0; $dingdongAttempt -lt 20; $dingdongAttempt++) {
        Start-Sleep -Milliseconds 300
        try {
            $dingdongHealth = Invoke-RestMethod -Uri 'http://127.0.0.1:18890/health' -TimeoutSec 1
            if ($dingdongHealth.service -eq 'dingdong-node') { $dingdongReady = $true; break }
        } catch {}
    }
}
if (-not $dingdongReady) { throw '服务未启动，请检查 data/service-error.log 或端口占用' }
Write-Host '管理密钥位于 data/admin.key，请在登录页输入。'
Start-Process 'http://127.0.0.1:18890'
