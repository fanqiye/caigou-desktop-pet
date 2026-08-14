Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$scriptPath = Join-Path $root '菜狗现代桌宠.ps1'
$vbsPath = Join-Path $root '启动动态菜狗.vbs'
$manifestPath = Join-Path $root 'assets-hq\manifest.json'
$tokenPath = Join-Path $root 'design-tokens.json'
$errors = [System.Collections.Generic.List[string]]::new()

if (-not (Test-Path -LiteralPath $scriptPath)) { $errors.Add('缺少现代桌宠主脚本') }
if (-not (Test-Path -LiteralPath $vbsPath)) { $errors.Add('缺少隐藏启动器') }
if (-not (Test-Path -LiteralPath $manifestPath)) { $errors.Add('缺少高清 PNG 帧清单') }
if (-not (Test-Path -LiteralPath $tokenPath)) { $errors.Add('缺少现代设计令牌') }

$vbsText = Get-Content -Raw -LiteralPath $vbsPath
if ($vbsText -notmatch [regex]::Escape('菜狗现代桌宠.ps1')) { $errors.Add('隐藏启动器没有指向现代桌宠') }
$vbsBytes = [IO.File]::ReadAllBytes($vbsPath)
if ($vbsBytes.Length -lt 2 -or $vbsBytes[0] -ne 0xFF -or $vbsBytes[1] -ne 0xFE) { $errors.Add('隐藏启动器不是 WSH 兼容的 UTF-16LE 编码') }

if (Test-Path -LiteralPath $manifestPath) {
    $manifest = Get-Content -Raw -LiteralPath $manifestPath -Encoding UTF8 | ConvertFrom-Json
    $states = @($manifest.PSObject.Properties)
    if ($states.Count -ne 12) { $errors.Add("高清动画状态数量错误：$($states.Count)") }
    $frameCount = 0
    foreach ($state in $states) {
        $frames = @($state.Value.frames)
        $frameCount += $frames.Count
        if ($frames.Count -lt 2) { $errors.Add("高清动画帧数不足：$($state.Name)") }
        foreach ($relative in $frames) {
            $framePath = Join-Path (Join-Path $root 'assets-hq') $relative
            if (-not (Test-Path -LiteralPath $framePath)) { $errors.Add("缺少高清帧：$relative") }
        }
    }
    if ($frameCount -lt 70) { $errors.Add("高清 PNG 帧总数不足：$frameCount") }
}

if (Test-Path -LiteralPath $scriptPath) {
    $scriptText = Get-Content -Raw -LiteralPath $scriptPath
    foreach ($feature in 'state.json','petting','feeding','sleeping','feedbackCard','nextNudgeAt','ignoredNudges','petCooldownUntil','lastBondDecay','affectionCanDecrease','BitmapScalingMode','assets-hq','ambientRoutineNames','ambientTimer','activityPhase','cursor-curious','dream-twitch','wake-stretch','holdState','health','stamina','petStatus','departureReason','controlWindow','quickWindow','followMode','stopFollowing','returnHomeMode') {
        if ($scriptText -notmatch [regex]::Escape($feature)) { $errors.Add("缺少成熟互动机制：$feature") }
    }
}

if ($errors.Count -gt 0) {
    $errors | ForEach-Object { Write-Error $_ }
    exit 1
}

$output = & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -STA -File $scriptPath -SelfTest 2>&1 | Out-String
$requiredMarkers = @(
    'SELF_TEST_OK','renderer=WPF','hqFrames=True','modernFeedback=True','modernPanel=True',
    'ambientRoutines=33','ambientVariety=True','naturalSchedule=True','naturalStart=True',
    'staticRest=True','interactions=3','interactionLogic=True','affectionCanDecrease=True',
    'lifeSystem=True','departureReachable=True','followMode=True','nudgeWindow=True','persistence=True'
)
foreach ($marker in $requiredMarkers) {
    if ($output -notmatch [regex]::Escape($marker)) { $errors.Add("自检缺少标记：$marker") }
}
if ($LASTEXITCODE -ne 0 -or $errors.Count -gt 0) {
    $errors | ForEach-Object { Write-Error $_ }
    Write-Error "动态桌宠自检失败：$output"
    exit 1
}

Write-Output 'CAIGOU_DYNAMIC_TEST_OK'

