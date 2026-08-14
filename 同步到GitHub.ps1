param(
    [string]$Message = '更新菜狗桌宠'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectRoot = $PSScriptRoot
$testScript = Join-Path $projectRoot 'tests\test-caigou-dynamic.ps1'

Push-Location $projectRoot
try {
    if (-not (Test-Path -LiteralPath '.git')) {
        throw '当前目录还不是 Git 仓库。'
    }
    if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
        throw '未找到 GitHub CLI（gh）。'
    }
    & gh auth status *> $null
    if ($LASTEXITCODE -ne 0) {
        throw 'GitHub 尚未登录，请先运行 gh auth login。'
    }

    & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $testScript
    if ($LASTEXITCODE -ne 0) {
        throw '菜狗桌宠测试失败，已停止同步。'
    }

    $changes = @(& git status --porcelain)
    if ($changes.Count -eq 0) {
        Write-Output '没有需要同步的更新。'
        exit 0
    }

    & git add -A -- .
    if ($LASTEXITCODE -ne 0) { throw '暂存更新失败。' }

    $blocked = @(& git diff --cached --name-only | Where-Object {
        $_ -eq 'state.json' -or $_ -match '\.log$' -or $_ -match '(^|/)backup-before-' -or $_ -eq '菜狗动态桌宠.ps1' -or $_ -match '(^|/)assets/'
    })
    if ($blocked.Count -gt 0) {
        & git restore --staged -- $blocked
        throw "检测到不应上传的本地文件：$($blocked -join ', ')"
    }

    & git commit -m $Message
    if ($LASTEXITCODE -ne 0) { throw '创建 Git 提交失败。' }

    $branch = (& git branch --show-current).Trim()
    if ([string]::IsNullOrWhiteSpace($branch)) { throw '无法确定当前 Git 分支。' }

    & git pull --rebase origin $branch
    if ($LASTEXITCODE -ne 0) { throw '拉取远端更新失败，请先解决冲突。' }
    & git push origin $branch
    if ($LASTEXITCODE -ne 0) { throw '推送 GitHub 失败。' }

    $commit = (& git rev-parse --short HEAD).Trim()
    Write-Output "GITHUB_SYNC_OK branch=$branch commit=$commit"
}
finally {
    Pop-Location
}

