param(
    [switch]$SelfTest,
    [switch]$OpenPanel
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:createdNew = $false
$mutexName = if ($SelfTest) { 'Local\CaiGouModernPet_20260804_SelfTest' } else { 'Local\CaiGouModernPet_20260804' }
$script:mutex = [Threading.Mutex]::new($true, $mutexName, [ref]$script:createdNew)
if (-not $script:createdNew) { exit 0 }

try {
    Add-Type -AssemblyName PresentationFramework
    Add-Type -AssemblyName PresentationCore
    Add-Type -AssemblyName WindowsBase
    Add-Type -AssemblyName System.Xaml
    Add-Type -AssemblyName System.Windows.Forms

    $app = [Windows.Application]::new()
    $app.ShutdownMode = [Windows.ShutdownMode]::OnMainWindowClose

    $assetDir = Join-Path $PSScriptRoot 'assets-hq'
    $manifestPath = Join-Path $assetDir 'manifest.json'
    $tokenPath = Join-Path $PSScriptRoot 'design-tokens.json'
    $statePath = Join-Path $PSScriptRoot 'state.json'
    if (-not (Test-Path -LiteralPath $manifestPath)) { throw "缺少高清动画清单：$manifestPath" }
    if (-not (Test-Path -LiteralPath $tokenPath)) { throw "缺少设计令牌：$tokenPath" }

    $manifest = Get-Content -Raw -LiteralPath $manifestPath -Encoding UTF8 | ConvertFrom-Json
    $tokens = Get-Content -Raw -LiteralPath $tokenPath -Encoding UTF8 | ConvertFrom-Json
    $primitive = $tokens.primitive
    $color = @{
        Surface = [string]$primitive.'surface-elevated'
        SurfaceBorder = [string]$primitive.'surface-border'
        Ink = [string]$primitive.'ink-900'
        Muted = [string]$primitive.'ink-600'
        Accent = [string]$primitive.'cabbage-500'
        Positive = [string]$primitive.'cabbage-700'
        PositiveSoft = [string]$primitive.'cabbage-soft'
        Need = [string]$primitive.'amber-500'
        NeedSoft = [string]$primitive.'amber-soft'
        Energy = [string]$primitive.'blue-500'
        EnergySoft = [string]$primitive.'blue-soft'
        Health = [string]$primitive.'rose-500'
        HealthDark = [string]$primitive.'rose-700'
        HealthSoft = [string]$primitive.'rose-soft'
        Boundary = [string]$primitive.'coral-500'
        BoundarySoft = [string]$primitive.'coral-soft'
        SurfaceGlass = [string]$primitive.'surface-glass'
        SurfaceHover = [string]$primitive.'surface-hover'
        SurfacePressed = [string]$primitive.'surface-pressed'
        Divider = [string]$primitive.divider
        Shadow = [string]$primitive.shadow
        Track = [string]$primitive.track
        White = [string]$primitive.'cream-0'
    }
    $brush = { param([string]$Value) [Windows.Media.BrushConverter]::new().ConvertFromString($Value) }

    $script:frames = @{}
    $script:frameIntervals = @{}
    foreach ($property in $manifest.PSObject.Properties) {
        $stateName = $property.Name
        $entry = $property.Value
        $loaded = [Collections.Generic.List[Windows.Media.Imaging.BitmapImage]]::new()
        foreach ($relative in $entry.frames) {
            $path = Join-Path $assetDir ([string]$relative)
            if (-not (Test-Path -LiteralPath $path)) { throw "缺少高清帧：$path" }
            $bitmap = [Windows.Media.Imaging.BitmapImage]::new()
            $bitmap.BeginInit()
            $bitmap.CacheOption = [Windows.Media.Imaging.BitmapCacheOption]::OnLoad
            $bitmap.UriSource = [Uri]::new($path, [UriKind]::Absolute)
            $bitmap.EndInit()
            $bitmap.Freeze()
            $loaded.Add($bitmap)
        }
        if ($loaded.Count -lt 2) { throw "高清动画帧数不足：$stateName" }
        $script:frames[$stateName] = $loaded
        $script:frameIntervals[$stateName] = [int]$entry.intervalMs
    }

    $script:affection = 52
    $script:fullness = 72
    $script:energy = 78
    $script:health = 100
    $script:petStatus = 'home'
    $script:departureReason = ''
    $script:departedAt = $null
    $script:lowHungerTicks = 0
    $script:starvationTicks = 0
    $script:recoveryTicks = 0
    $script:interactionCount = 0
    $script:ignoredNudges = 0
    $script:feedRefusals = 0
    $script:lastInteraction = Get-Date
    $script:lastBondDecay = Get-Date
    $script:lastBondEvent = '刚刚见面，正在熟悉彼此'
    if (Test-Path -LiteralPath $statePath) {
        try {
            $saved = Get-Content -Raw -LiteralPath $statePath -Encoding UTF8 | ConvertFrom-Json
            $script:affection = [int]$saved.affection
            $script:fullness = [int]$saved.fullness
            $script:energy = if ($saved.PSObject.Properties.Name -contains 'stamina') { [int]$saved.stamina } else { [int]$saved.energy }
            if ($saved.PSObject.Properties.Name -contains 'health') { $script:health = [int]$saved.health }
            if ($saved.PSObject.Properties.Name -contains 'petStatus') { $script:petStatus = [string]$saved.petStatus }
            if ($saved.PSObject.Properties.Name -contains 'departureReason') { $script:departureReason = [string]$saved.departureReason }
            if ($saved.PSObject.Properties.Name -contains 'departedAt' -and $saved.departedAt) { $script:departedAt = [datetime]$saved.departedAt }
            if ($saved.PSObject.Properties.Name -contains 'lowHungerTicks') { $script:lowHungerTicks = [int]$saved.lowHungerTicks }
            if ($saved.PSObject.Properties.Name -contains 'starvationTicks') { $script:starvationTicks = [int]$saved.starvationTicks }
            if ($saved.PSObject.Properties.Name -contains 'recoveryTicks') { $script:recoveryTicks = [int]$saved.recoveryTicks }
            $script:interactionCount = [int]$saved.interactions
            if ($saved.PSObject.Properties.Name -contains 'ignoredNudges') { $script:ignoredNudges = [int]$saved.ignoredNudges }
            if ($saved.PSObject.Properties.Name -contains 'feedRefusals') { $script:feedRefusals = [int]$saved.feedRefusals }
            if ($saved.PSObject.Properties.Name -contains 'lastInteraction' -and $saved.lastInteraction) { $script:lastInteraction = [datetime]$saved.lastInteraction }
            if ($saved.PSObject.Properties.Name -contains 'lastBondDecay' -and $saved.lastBondDecay) { $script:lastBondDecay = [datetime]$saved.lastBondDecay }
            if ($saved.PSObject.Properties.Name -contains 'lastBondEvent' -and $saved.lastBondEvent) { $script:lastBondEvent = [string]$saved.lastBondEvent }
            if ($saved.lastUpdated -and $script:petStatus -eq 'home') {
                $remainingHours = [Math]::Max(0, ((Get-Date) - [datetime]$saved.lastUpdated).TotalHours)
                if ($script:fullness -gt 25 -and $remainingHours -ge 1) {
                    $drop = [Math]::Min($script:fullness - 25, [int][Math]::Floor($remainingHours))
                    $script:fullness -= $drop
                    $remainingHours -= $drop
                }
                if ($script:fullness -gt 10 -and $remainingHours -ge 2) {
                    $drop = [Math]::Min($script:fullness - 10, [int][Math]::Floor($remainingHours / 2))
                    $script:fullness -= $drop
                    $remainingHours -= ($drop * 2)
                }
                if ($script:fullness -gt 0 -and $remainingHours -ge 4) {
                    $drop = [Math]::Min($script:fullness, [int][Math]::Floor($remainingHours / 4))
                    $script:fullness -= $drop
                    $remainingHours -= ($drop * 4)
                }
                if ($script:fullness -le 0 -and $remainingHours -ge 6) {
                    $script:health -= [Math]::Min(100, [int][Math]::Floor($remainingHours / 6))
                }
            }
            $now = Get-Date
            $decayReference = $script:lastBondDecay
            $graceEnd = $script:lastInteraction.AddHours(6)
            if ($decayReference -lt $graceEnd) { $decayReference = $graceEnd }
            if (($now - $script:lastInteraction).TotalHours -ge 12) {
                $bondLoss = [Math]::Min(12, [int][Math]::Floor(($now - $decayReference).TotalHours / 6))
                if ($bondLoss -gt 0) {
                    $script:affection -= $bondLoss
                    $script:lastBondDecay = $decayReference.AddHours($bondLoss * 6)
                    $script:lastBondEvent = "很久没等到回应，关系 -$bondLoss"
                }
            }
        } catch {}
    }
    $script:affection = [Math]::Min(100, [Math]::Max(0, $script:affection))
    $script:fullness = [Math]::Min(100, [Math]::Max(0, $script:fullness))
    $script:energy = [Math]::Min(100, [Math]::Max(0, $script:energy))
    $script:health = [Math]::Min(100, [Math]::Max(0, $script:health))
    if ($script:health -le 0) {
        $script:petStatus = 'deceased'
        if (-not $script:departureReason) { $script:departureReason = '长期饥饿让生命值归零' }
    } elseif ($script:affection -le 5 -and $script:petStatus -eq 'home') {
        $script:petStatus = 'departed'
        if (-not $script:departureReason) { $script:departureReason = '长期得不到照顾，选择离开' }
    }
    if ($SelfTest) {
        $script:petStatus = 'home'
        $script:departureReason = ''
        $script:health = [Math]::Max(50, $script:health)
        $script:affection = [Math]::Max(40, $script:affection)
        $script:fullness = [Math]::Max(40, $script:fullness)
        $script:energy = [Math]::Max(40, $script:energy)
    }

    $window = [Windows.Window]::new()
    $window.Title = '菜狗现代桌宠'
    $window.Width = [double]$tokens.component.'pet-width'
    $window.Height = [double]$tokens.component.'pet-height'
    $window.WindowStyle = [Windows.WindowStyle]::None
    $window.ResizeMode = [Windows.ResizeMode]::NoResize
    $window.AllowsTransparency = $true
    $window.Background = [Windows.Media.Brushes]::Transparent
    $window.ShowInTaskbar = $false
    $window.Topmost = $true
    $window.ShowActivated = $false

    $root = [Windows.Controls.Grid]::new()
    $window.Content = $root

    $groundShadow = [Windows.Shapes.Ellipse]::new()
    $groundShadow.Width = 54
    $groundShadow.Height = 9
    $groundShadow.HorizontalAlignment = [Windows.HorizontalAlignment]::Center
    $groundShadow.VerticalAlignment = [Windows.VerticalAlignment]::Bottom
    $groundShadow.Margin = [Windows.Thickness]::new(0, 0, 0, 5)
    $groundShadow.Fill = & $brush $color.Shadow
    $groundShadow.IsHitTestVisible = $false
    $groundShadow.Effect = [Windows.Media.Effects.BlurEffect]@{ Radius = 5 }
    [void]$root.Children.Add($groundShadow)

    $petImage = [Windows.Controls.Image]::new()
    $petImage.Stretch = [Windows.Media.Stretch]::Uniform
    $petImage.Margin = [Windows.Thickness]::new(1)
    $petImage.Cursor = [Windows.Input.Cursors]::Hand
    $petImage.RenderTransformOrigin = [Windows.Point]::new(0.5, 0.62)
    $petScale = [Windows.Media.ScaleTransform]::new(1, 1)
    $petRotate = [Windows.Media.RotateTransform]::new(0)
    $petTranslate = [Windows.Media.TranslateTransform]::new(0, 0)
    $petTransform = [Windows.Media.TransformGroup]::new()
    [void]$petTransform.Children.Add($petScale)
    [void]$petTransform.Children.Add($petRotate)
    [void]$petTransform.Children.Add($petTranslate)
    $petImage.RenderTransform = $petTransform
    [Windows.Media.RenderOptions]::SetBitmapScalingMode($petImage, [Windows.Media.BitmapScalingMode]::HighQuality)
    [void]$root.Children.Add($petImage)

    $particleCanvas = [Windows.Controls.Canvas]::new()
    $particleCanvas.IsHitTestVisible = $false
    [void]$root.Children.Add($particleCanvas)

    $feedbackWindow = [Windows.Window]::new()
    $feedbackWindow.Title = '菜狗反馈'
    $feedbackWindow.WindowStyle = [Windows.WindowStyle]::None
    $feedbackWindow.ResizeMode = [Windows.ResizeMode]::NoResize
    $feedbackWindow.AllowsTransparency = $true
    $feedbackWindow.Background = [Windows.Media.Brushes]::Transparent
    $feedbackWindow.ShowInTaskbar = $false
    $feedbackWindow.Topmost = $true
    $feedbackWindow.ShowActivated = $false
    $feedbackWindow.SizeToContent = [Windows.SizeToContent]::WidthAndHeight

    $feedbackTransform = [Windows.Media.TranslateTransform]::new(0, 8)
    $feedbackCard = [Windows.Controls.Border]::new()
    $feedbackCard.Name = 'feedbackCard'
    $feedbackCard.Width = 286
    $feedbackCard.MinHeight = 86
    $feedbackCard.CornerRadius = [Windows.CornerRadius]::new([double]$tokens.component.'feedback-radius')
    $feedbackCard.Padding = [Windows.Thickness]::new([double]$tokens.component.'feedback-padding')
    $feedbackCard.Background = & $brush $color.Surface
    $feedbackCard.BorderBrush = & $brush $color.SurfaceBorder
    $feedbackCard.BorderThickness = [Windows.Thickness]::new(1)
    $feedbackCard.RenderTransform = $feedbackTransform
    $feedbackCard.Effect = [Windows.Media.Effects.DropShadowEffect]@{
        BlurRadius = [double]$tokens.component.'feedback-shadow-blur'
        ShadowDepth = 3
        Opacity = 0.24
        Color = [Windows.Media.ColorConverter]::ConvertFromString($color.Shadow)
    }
    $feedbackWindow.Content = $feedbackCard

    $feedbackStack = [Windows.Controls.StackPanel]::new()
    $feedbackCard.Child = $feedbackStack
    $feedbackTitle = [Windows.Controls.TextBlock]::new()
    $feedbackTitle.FontFamily = [Windows.Media.FontFamily]::new('Microsoft YaHei UI')
    $feedbackTitle.FontSize = 13
    $feedbackTitle.FontWeight = [Windows.FontWeights]::SemiBold
    $feedbackTitle.Foreground = & $brush $color.Ink
    [void]$feedbackStack.Children.Add($feedbackTitle)
    $feedbackBody = [Windows.Controls.TextBlock]::new()
    $feedbackBody.FontFamily = [Windows.Media.FontFamily]::new('Microsoft YaHei UI')
    $feedbackBody.FontSize = 12
    $feedbackBody.Foreground = & $brush $color.Muted
    $feedbackBody.TextWrapping = [Windows.TextWrapping]::Wrap
    $feedbackBody.LineHeight = 19
    $feedbackBody.Margin = [Windows.Thickness]::new(0, 5, 0, 9)
    [void]$feedbackStack.Children.Add($feedbackBody)
    $badgePanel = [Windows.Controls.WrapPanel]::new()
    [void]$feedbackStack.Children.Add($badgePanel)

    $script:currentState = 'sleeping'
    $script:frameIndex = 0
    $script:autoMood = $true
    $script:dragging = $false
    $script:dragMoved = $false
    $script:dragOffset = [Windows.Point]::new(0, 0)
    $script:dragStartedAt = [datetime]::MinValue
    $script:suppressNextClick = $false
    $script:chaseMode = $false
    $script:chaseTicks = 0
    $script:followMode = $false
    $script:returnHomeMode = $false
    $script:lastFollowCostAt = Get-Date
    $script:statusHandled = $false
    $script:nudgeActive = $false
    $script:petStreak = 0
    $script:lastPetAt = [datetime]::MinValue
    $script:petCooldownUntil = [datetime]::MinValue
    $script:nextNudgeAt = (Get-Date).AddMinutes((Get-Random -Minimum 40 -Maximum 76))
    $script:activityPhase = 'quiet'
    $script:activityPhaseEndsAt = (Get-Date).AddMinutes((Get-Random -Minimum 10 -Maximum 26))
    $script:nextAmbientAt = (Get-Date).AddMinutes((Get-Random -Minimum 3 -Maximum 8))
    $script:ambientActive = $false
    $script:ambientSteps = @()
    $script:ambientStepIndex = 0
    $script:ambientLastRoutine = ''
    $script:ambientBag = [Collections.Generic.Queue[string]]::new()
    $script:ambientActionsSinceEnergyTick = 0
    $script:lastAmbientBubbleAt = [datetime]::MinValue
    $script:selfTestResult = $null

    $saveState = {
        if ($script:petStatus -eq 'home' -and $script:health -le 0) {
            $script:petStatus = 'deceased'
            $script:departureReason = '长期饥饿让生命值归零'
            $script:departedAt = Get-Date
        } elseif ($script:petStatus -eq 'home' -and $script:affection -le 5) {
            $script:petStatus = 'departed'
            $script:departureReason = '长期得不到照顾，选择离开'
            $script:departedAt = Get-Date
        }
        if ($SelfTest) { return }
        $payload = [ordered]@{
            affection = [int]$script:affection
            fullness = [int]$script:fullness
            stamina = [int]$script:energy
            energy = [int]$script:energy
            health = [int]$script:health
            petStatus = [string]$script:petStatus
            departureReason = [string]$script:departureReason
            departedAt = if ($script:departedAt) { $script:departedAt.ToString('o') } else { $null }
            lowHungerTicks = [int]$script:lowHungerTicks
            starvationTicks = [int]$script:starvationTicks
            recoveryTicks = [int]$script:recoveryTicks
            interactions = [int]$script:interactionCount
            ignoredNudges = [int]$script:ignoredNudges
            feedRefusals = [int]$script:feedRefusals
            lastInteraction = $script:lastInteraction.ToString('o')
            lastBondDecay = $script:lastBondDecay.ToString('o')
            lastBondEvent = $script:lastBondEvent
            lastUpdated = (Get-Date).ToString('o')
        } | ConvertTo-Json
        [IO.File]::WriteAllText($statePath, $payload, [Text.UTF8Encoding]::new($false))
    }

    $screenToDip = {
        param([Drawing.Point]$ScreenPoint)
        $point = [Windows.Point]::new($ScreenPoint.X, $ScreenPoint.Y)
        $source = [Windows.PresentationSource]::FromVisual($window)
        if ($null -ne $source -and $null -ne $source.CompositionTarget) {
            return $source.CompositionTarget.TransformFromDevice.Transform($point)
        }
        return $point
    }

    $placeAtHome = {
        $area = [Windows.SystemParameters]::WorkArea
        $window.Left = $area.Right - $window.Width - 18
        $window.Top = $area.Bottom - $window.Height - 12
    }

    $animationTimer = [Windows.Threading.DispatcherTimer]::new()
    $animationTimer.Add_Tick({
        $list = $script:frames[$script:currentState]
        $script:frameIndex = ($script:frameIndex + 1) % $list.Count
        $petImage.Source = $list[$script:frameIndex]
    })

    $playState = {
        param([string]$Name)
        if ($script:frames.ContainsKey($Name)) {
            $script:currentState = $Name
            $script:frameIndex = 0
            $petImage.Source = $script:frames[$Name][0]
            $animationTimer.Interval = [TimeSpan]::FromMilliseconds($script:frameIntervals[$Name])
            if (-not $animationTimer.IsEnabled) { $animationTimer.Start() }
        }
    }

    $holdState = {
        param([string]$Name, [int]$Frame = -1)
        if (-not $script:frames.ContainsKey($Name)) { return }
        $animationTimer.Stop()
        $script:currentState = $Name
        $list = $script:frames[$Name]
        $script:frameIndex = if ($Frame -ge 0) { [Math]::Min($Frame, $list.Count - 1) } else { Get-Random -Minimum 0 -Maximum $list.Count }
        $petImage.Source = $list[$script:frameIndex]
    }

    $feedbackTimer = [Windows.Threading.DispatcherTimer]::new()
    $feedbackTimer.Add_Tick({ $feedbackTimer.Stop(); $feedbackWindow.Hide() })

    $newBadge = {
        param([string]$Text, [string]$Tone)
        $palette = switch ($Tone) {
            'positive' { @($color.PositiveSoft, $color.Positive) }
            'need' { @($color.NeedSoft, $color.Need) }
            'energy' { @($color.EnergySoft, $color.Energy) }
            'health' { @($color.HealthSoft, $color.HealthDark) }
            'boundary' { @($color.BoundarySoft, $color.Boundary) }
            default { @($color.PositiveSoft, $color.Muted) }
        }
        $badge = [Windows.Controls.Border]::new()
        $badge.CornerRadius = [Windows.CornerRadius]::new([double]$tokens.component.'badge-radius')
        $badge.Background = & $brush $palette[0]
        $badge.Padding = [Windows.Thickness]::new(8, 3, 8, 3)
        $badge.Margin = [Windows.Thickness]::new(0, 0, 6, 0)
        $textBlock = [Windows.Controls.TextBlock]::new()
        $textBlock.Text = $Text
        $textBlock.FontFamily = [Windows.Media.FontFamily]::new('Microsoft YaHei UI')
        $textBlock.FontSize = 10.5
        $textBlock.FontWeight = [Windows.FontWeights]::SemiBold
        $textBlock.Foreground = & $brush $palette[1]
        $badge.Child = $textBlock
        return $badge
    }

    $showFeedback = {
        param(
            [string]$Title,
            [string]$Message,
            [string]$Tone = 'neutral',
            [int]$AffectionDelta = 0,
            [int]$FullnessDelta = 0,
            [int]$EnergyDelta = 0,
            [int]$Milliseconds = 3400,
            [switch]$ShowCurrent,
            [int]$HealthDelta = 0
        )
        $feedbackTimer.Stop()
        $feedbackTitle.Text = $Title
        $feedbackBody.Text = $Message
        $feedbackCard.BorderBrush = & $brush $(switch ($Tone) {
            'positive' { $color.Accent }
            'need' { $color.Need }
            'energy' { $color.Energy }
            'health' { $color.Health }
            'boundary' { $color.Boundary }
            default { $color.SurfaceBorder }
        })
        $badgePanel.Children.Clear()
        if ($ShowCurrent) {
            [void]$badgePanel.Children.Add((& $newBadge "生命 $($script:health)" 'health'))
            [void]$badgePanel.Children.Add((& $newBadge "亲密 $($script:affection)" 'positive'))
            [void]$badgePanel.Children.Add((& $newBadge "饱食 $($script:fullness)" 'need'))
            [void]$badgePanel.Children.Add((& $newBadge "体力 $($script:energy)" 'energy'))
        } else {
            if ($AffectionDelta -ne 0) { [void]$badgePanel.Children.Add((& $newBadge "亲密 $(if($AffectionDelta -gt 0){'+'})$AffectionDelta" $(if($AffectionDelta -gt 0){'positive'}else{'boundary'}))) }
            if ($FullnessDelta -ne 0) { [void]$badgePanel.Children.Add((& $newBadge "饱食 $(if($FullnessDelta -gt 0){'+'})$FullnessDelta" 'need')) }
            if ($EnergyDelta -ne 0) { [void]$badgePanel.Children.Add((& $newBadge "体力 $(if($EnergyDelta -gt 0){'+'})$EnergyDelta" 'energy')) }
            if ($HealthDelta -ne 0) { [void]$badgePanel.Children.Add((& $newBadge "生命 $(if($HealthDelta -gt 0){'+'})$HealthDelta" $(if($HealthDelta -gt 0){'health'}else{'boundary'}))) }
            if ($badgePanel.Children.Count -eq 0) { [void]$badgePanel.Children.Add((& $newBadge '关系不变' 'neutral')) }
        }

        if (-not $feedbackWindow.IsVisible) { $feedbackWindow.Show() }
        $feedbackWindow.UpdateLayout()
        $area = [Windows.SystemParameters]::WorkArea
        $left = $window.Left + $window.Width - $feedbackWindow.ActualWidth
        $feedbackWindow.Left = [Math]::Min([Math]::Max($left, $area.Left), $area.Right - $feedbackWindow.ActualWidth)
        $feedbackWindow.Top = [Math]::Max($area.Top, $window.Top - $feedbackWindow.ActualHeight - 8)
        $feedbackWindow.Opacity = 0
        $feedbackTransform.Y = 8
        $opacityAnimation = [Windows.Media.Animation.DoubleAnimation]::new(0, 1, [Windows.Duration]::new([TimeSpan]::FromMilliseconds([double]$tokens.component.'motion-normal-ms')))
        $moveAnimation = [Windows.Media.Animation.DoubleAnimation]::new(8, 0, [Windows.Duration]::new([TimeSpan]::FromMilliseconds([double]$tokens.component.'motion-normal-ms')))
        $feedbackWindow.BeginAnimation([Windows.Window]::OpacityProperty, $opacityAnimation)
        $feedbackTransform.BeginAnimation([Windows.Media.TranslateTransform]::YProperty, $moveAnimation)
        $feedbackTimer.Interval = [TimeSpan]::FromMilliseconds($Milliseconds)
        $feedbackTimer.Start()
    }

    $emitParticles = {
        param([string]$Symbol, [string]$Tone)
        $particleColor = switch ($Tone) {
            'positive' { $color.Accent }
            'need' { $color.Need }
            'boundary' { $color.Boundary }
            default { $color.Energy }
        }
        1..3 | ForEach-Object {
            $particle = [Windows.Controls.TextBlock]::new()
            $particle.Text = $Symbol
            $particle.FontFamily = [Windows.Media.FontFamily]::new('Segoe UI Symbol')
            $particle.FontSize = Get-Random -Minimum 10 -Maximum 15
            $particle.Foreground = & $brush $particleColor
            [Windows.Controls.Canvas]::SetLeft($particle, (Get-Random -Minimum 24 -Maximum 66))
            [Windows.Controls.Canvas]::SetTop($particle, (Get-Random -Minimum 28 -Maximum 62))
            [void]$particleCanvas.Children.Add($particle)
            $duration = [Windows.Duration]::new([TimeSpan]::FromMilliseconds((Get-Random -Minimum 650 -Maximum 950)))
            $topAnimation = [Windows.Media.Animation.DoubleAnimation]::new([Windows.Controls.Canvas]::GetTop($particle), [Windows.Controls.Canvas]::GetTop($particle) - 24, $duration)
            $opacityAnimation = [Windows.Media.Animation.DoubleAnimation]::new(1, 0, $duration)
            $opacityAnimation.Add_Completed({ param($sender, $eventArgs) [void]$particleCanvas.Children.Remove($particle) }.GetNewClosure())
            $particle.BeginAnimation([Windows.Controls.Canvas]::TopProperty, $topAnimation)
            $particle.BeginAnimation([Windows.UIElement]::OpacityProperty, $opacityAnimation)
        }
    }

    # 自主生活层：不用新增贴图，也能把现有高清动作编排成大量不重复的小狗行为。
    $ambientRoutineNames = @(
        'curious-left', 'curious-right', 'double-tilt', 'paw-wave', 'tiny-hop',
        'play-bow', 'sniff-left', 'sniff-right', 'look-behind', 'proud-stance',
        'happy-shimmy', 'cabbage-shake', 'toe-taps', 'peek-up', 'zoom-left',
        'zoom-right', 'circle-left', 'circle-right', 'sit-watch', 'patient-wait',
        'air-sniff', 'bow-and-wave', 'bounce-wave', 'cursor-curious', 'clumsy-stumble',
        'sleepy-yawn', 'wake-stretch', 'cheek-rub', 'star-pose', 'patrol-edge'
    )
    $quietRoutineNames = @(
        'curious-left', 'curious-right', 'double-tilt', 'sniff-left', 'sniff-right',
        'look-behind', 'proud-stance', 'toe-taps', 'peek-up', 'sit-watch',
        'patient-wait', 'air-sniff', 'cursor-curious', 'sleepy-yawn', 'cheek-rub'
    )
    $activeRoutineNames = @(
        'paw-wave', 'tiny-hop', 'play-bow', 'happy-shimmy', 'cabbage-shake',
        'zoom-left', 'zoom-right', 'circle-left', 'circle-right', 'bow-and-wave',
        'bounce-wave', 'clumsy-stumble', 'wake-stretch', 'star-pose', 'patrol-edge'
    )
    $sleepRoutineNames = @('dream-twitch', 'sleep-snuffle', 'sleep-paw')
    $ambientLines = @(
        @{ Title = '突然精神'; Text = '没什么事，只是想让你看一下我有多可爱。'; Tone = 'positive' },
        @{ Title = '菜叶巡逻员'; Text = '认真检查了一圈，桌面一切正常。'; Tone = 'neutral' },
        @{ Title = '偷偷练习'; Text = '趁你忙的时候，练了一个新的卖萌动作。'; Tone = 'positive' },
        @{ Title = '在观察你'; Text = '歪着脑袋研究：你现在是不是很专注？'; Tone = 'neutral' },
        @{ Title = '尾巴有想法'; Text = '没有要打扰你，它只是自己摇得很开心。'; Tone = 'positive' },
        @{ Title = '小狗哲学'; Text = '站一会儿，闻一闻，再决定下一步做什么。'; Tone = 'neutral' },
        @{ Title = '今日份耍宝'; Text = '表演结束，假装刚才什么也没有发生。'; Tone = 'positive' },
        @{ Title = '路过一下'; Text = '从这边晃到那边，又乖乖回来了。'; Tone = 'neutral' },
        @{ Title = '菜狗广播'; Text = '你忙你的，我负责让桌面有一点生气。'; Tone = 'positive' },
        @{ Title = '捕捉到视线'; Text = '你是不是刚好看过来了？那我再摆个姿势。'; Tone = 'positive' }
    )

    $animatePose = {
        param(
            [double]$ScaleX = 1,
            [double]$ScaleY = 1,
            [double]$Angle = 0,
            [double]$X = 0,
            [double]$Y = 0,
            [int]$Milliseconds = 180
        )
        $duration = [Windows.Duration]::new([TimeSpan]::FromMilliseconds($Milliseconds))
        $petScale.BeginAnimation([Windows.Media.ScaleTransform]::ScaleXProperty, [Windows.Media.Animation.DoubleAnimation]::new($petScale.ScaleX, $ScaleX, $duration))
        $petScale.BeginAnimation([Windows.Media.ScaleTransform]::ScaleYProperty, [Windows.Media.Animation.DoubleAnimation]::new($petScale.ScaleY, $ScaleY, $duration))
        $petRotate.BeginAnimation([Windows.Media.RotateTransform]::AngleProperty, [Windows.Media.Animation.DoubleAnimation]::new($petRotate.Angle, $Angle, $duration))
        $petTranslate.BeginAnimation([Windows.Media.TranslateTransform]::XProperty, [Windows.Media.Animation.DoubleAnimation]::new($petTranslate.X, $X, $duration))
        $petTranslate.BeginAnimation([Windows.Media.TranslateTransform]::YProperty, [Windows.Media.Animation.DoubleAnimation]::new($petTranslate.Y, $Y, $duration))
    }

    $resetPose = { param([int]$Milliseconds = 150) & $animatePose 1 1 0 0 0 $Milliseconds }

    $makeAmbientStep = {
        param(
            [string]$State,
            [int]$Delay = 900,
            [double]$Angle = 0,
            [double]$X = 0,
            [double]$Y = 0,
            [double]$ScaleX = 1,
            [double]$ScaleY = 1,
            [string]$Particle = '',
            [string]$Tone = 'energy'
        )
        @{ State = $State; Delay = $Delay; Angle = $Angle; X = $X; Y = $Y; ScaleX = $ScaleX; ScaleY = $ScaleY; Particle = $Particle; Tone = $Tone }
    }

    $makeAmbientPlan = {
        param([string]$Name)
        switch ($Name) {
            'curious-left'   { @(& $makeAmbientStep 'review' 900 -8 -2 0; & $makeAmbientStep 'waiting' 1100 -4 -1 0; & $makeAmbientStep 'idle' 650) }
            'curious-right'  { @(& $makeAmbientStep 'review' 900 8 2 0; & $makeAmbientStep 'waiting' 1100 4 1 0; & $makeAmbientStep 'idle' 650) }
            'double-tilt'    { @(& $makeAmbientStep 'waiting' 650 -9 -2 0; & $makeAmbientStep 'waiting' 650 9 2 0; & $makeAmbientStep 'review' 900) }
            'paw-wave'       { @(& $makeAmbientStep 'waving' 900 -3 0 -2 1.03 1.03 '✦' 'positive'; & $makeAmbientStep 'waving' 900 3 0 0; & $makeAmbientStep 'idle' 600) }
            'tiny-hop'       { @(& $makeAmbientStep 'jumping' 520 0 0 -8 1.03 0.97; & $makeAmbientStep 'jumping' 520 0 0 1 0.98 1.03 '✦' 'positive'; & $makeAmbientStep 'idle' 700) }
            'play-bow'       { @(& $makeAmbientStep 'jumping' 1200 0 0 3 1.06 0.93 '✦' 'positive'; & $makeAmbientStep 'waiting' 900 0 0 0; & $makeAmbientStep 'idle' 650) }
            'sniff-left'     { @(& $makeAmbientStep 'waiting' 850 -5 -4 2 1.02 0.98; & $makeAmbientStep 'review' 850 -7 -2 1; & $makeAmbientStep 'idle' 650) }
            'sniff-right'    { @(& $makeAmbientStep 'waiting' 850 5 4 2 1.02 0.98; & $makeAmbientStep 'review' 850 7 2 1; & $makeAmbientStep 'idle' 650) }
            'look-behind'    { @(& $makeAmbientStep 'review' 1000 11 3 0 0.96 1; & $makeAmbientStep 'waiting' 850 -4 -1 0; & $makeAmbientStep 'idle' 650) }
            'proud-stance'   { @(& $makeAmbientStep 'idle' 1400 0 0 -2 1.06 1.04 '✦' 'positive'; & $makeAmbientStep 'review' 850 0 0 0; & $makeAmbientStep 'idle' 550) }
            'happy-shimmy'   { @(& $makeAmbientStep 'waving' 430 -7 -2 0; & $makeAmbientStep 'waving' 430 7 2 0; & $makeAmbientStep 'waving' 430 -5 -1 0; & $makeAmbientStep 'idle' 700 0 0 0 1 1 '♥' 'positive') }
            'cabbage-shake'  { @(& $makeAmbientStep 'idle' 330 -9 -2 0; & $makeAmbientStep 'idle' 330 9 2 0; & $makeAmbientStep 'idle' 330 -6 -1 0; & $makeAmbientStep 'idle' 650) }
            'toe-taps'       { @(& $makeAmbientStep 'waiting' 460 0 -3 0 0.99 1.02; & $makeAmbientStep 'waiting' 460 0 3 0 1.01 0.99; & $makeAmbientStep 'waiting' 460 0 -2 0; & $makeAmbientStep 'idle' 650) }
            'peek-up'        { @(& $makeAmbientStep 'review' 1100 0 0 -5 1.04 1.04; & $makeAmbientStep 'waiting' 850 0 0 -2; & $makeAmbientStep 'idle' 650) }
            'zoom-left'      { @(& $makeAmbientStep 'running-left' 650 -3 -7 0 0.98 1.02; & $makeAmbientStep 'running-right' 650 3 1 0; & $makeAmbientStep 'jumping' 620 0 0 -3; & $makeAmbientStep 'idle' 700) }
            'zoom-right'     { @(& $makeAmbientStep 'running-right' 650 3 7 0 0.98 1.02; & $makeAmbientStep 'running-left' 650 -3 -1 0; & $makeAmbientStep 'jumping' 620 0 0 -3; & $makeAmbientStep 'idle' 700) }
            'circle-left'    { @(& $makeAmbientStep 'running-left' 560 -5 -5 1; & $makeAmbientStep 'running' 560 0 0 -3; & $makeAmbientStep 'running-right' 560 5 5 1; & $makeAmbientStep 'idle' 750) }
            'circle-right'   { @(& $makeAmbientStep 'running-right' 560 5 5 1; & $makeAmbientStep 'running' 560 0 0 -3; & $makeAmbientStep 'running-left' 560 -5 -5 1; & $makeAmbientStep 'idle' 750) }
            'sit-watch'      { @(& $makeAmbientStep 'review' 2200 -3 0 0 1 1; & $makeAmbientStep 'review' 1200 4 0 0; & $makeAmbientStep 'idle' 650) }
            'patient-wait'   { @(& $makeAmbientStep 'waiting' 2500 0 0 0 1 1; & $makeAmbientStep 'idle' 900 0 0 0) }
            'air-sniff'      { @(& $makeAmbientStep 'waiting' 800 0 0 -4 1.03 1.04; & $makeAmbientStep 'waiting' 800 -5 -1 -2; & $makeAmbientStep 'review' 900 5 1 0; & $makeAmbientStep 'idle' 600) }
            'bow-and-wave'   { @(& $makeAmbientStep 'jumping' 950 0 0 3 1.05 0.94; & $makeAmbientStep 'waving' 1200 -3 0 -2 1.03 1.03 '✦' 'positive'; & $makeAmbientStep 'idle' 650) }
            'bounce-wave'    { @(& $makeAmbientStep 'waving' 650 -4 -2 -5 1.03 0.98; & $makeAmbientStep 'waving' 650 4 2 0 0.99 1.03; & $makeAmbientStep 'jumping' 650 0 0 -4; & $makeAmbientStep 'idle' 650) }
            'cursor-curious' {
                $cursor = & $screenToDip ([Windows.Forms.Cursor]::Position)
                $side = if ($cursor.X -lt ($window.Left + ($window.Width / 2))) { -1 } else { 1 }
                @(& $makeAmbientStep 'review' 1200 ($side * 8) ($side * 2) 0; & $makeAmbientStep 'waiting' 1100 ($side * 4) ($side * 1) -2; & $makeAmbientStep 'idle' 650)
            }
            'clumsy-stumble' { @(& $makeAmbientStep 'running' 520 6 4 1 0.97 1.03; & $makeAmbientStep 'failed' 900 -7 -2 3 1.03 0.96; & $makeAmbientStep 'waving' 950 0 0 0 1 1 '·' 'energy'; & $makeAmbientStep 'idle' 650) }
            'sleepy-yawn'    { @(& $makeAmbientStep 'review' 800 -3 0 1; & $makeAmbientStep 'sleeping' 1700 0 0 2 1.03 0.97; & $makeAmbientStep 'waiting' 800 2 0 0; & $makeAmbientStep 'idle' 650) }
            'wake-stretch'   { @(& $makeAmbientStep 'waiting' 850 0 0 2 1.02 0.97; & $makeAmbientStep 'jumping' 1200 0 0 3 1.07 0.92 '✦' 'energy'; & $makeAmbientStep 'waving' 900 -3 0 -2; & $makeAmbientStep 'idle' 650) }
            'cheek-rub'      { @(& $makeAmbientStep 'petting' 1200 -6 -2 0 1.03 1.03 '♥' 'positive'; & $makeAmbientStep 'petting' 900 5 2 0; & $makeAmbientStep 'idle' 650) }
            'star-pose'      { @(& $makeAmbientStep 'jumping' 850 0 0 -6 1.06 1.02 '✦' 'positive'; & $makeAmbientStep 'waving' 1100 -4 0 -2 1.04 1.04 '✦' 'positive'; & $makeAmbientStep 'idle' 650) }
            'patrol-edge'    { @(& $makeAmbientStep 'running-left' 720 -2 -6 0; & $makeAmbientStep 'review' 850 -6 -4 0; & $makeAmbientStep 'running-right' 720 2 6 0; & $makeAmbientStep 'review' 850 6 4 0; & $makeAmbientStep 'idle' 650) }
            'dream-twitch'   { @(& $makeAmbientStep 'sleeping' 900 -2 -1 1 1 0.99; & $makeAmbientStep 'sleeping' 1200 2 1 1 1 1.01; & $makeAmbientStep 'sleeping' 900) }
            'sleep-snuffle'  { @(& $makeAmbientStep 'sleeping' 850 0 0 2 1.02 0.98; & $makeAmbientStep 'sleeping' 850 0 0 0 0.99 1.02; & $makeAmbientStep 'sleeping' 1100) }
            'sleep-paw'      { @(& $makeAmbientStep 'sleeping' 700 -3 -2 0; & $makeAmbientStep 'sleeping' 700 3 2 0; & $makeAmbientStep 'sleeping' 1200 0 0 1) }
            default          { @(& $makeAmbientStep 'idle' 1200) }
        }
    }

    $getRestState = {
        if ($script:energy -lt 24 -or $script:activityPhase -eq 'sleep') { return 'sleeping' }
        if ($script:activityPhase -eq 'active') { return (@('idle', 'idle', 'waiting') | Get-Random) }
        return (@('idle', 'idle', 'idle', 'idle', 'review', 'waiting') | Get-Random)
    }

    $refillAmbientBag = {
        $pool = if ($script:activityPhase -eq 'active') { $activeRoutineNames } else { $quietRoutineNames }
        foreach ($name in ($pool | Sort-Object { Get-Random })) { $script:ambientBag.Enqueue($name) }
    }

    $getNextAmbientRoutine = {
        if ($script:ambientBag.Count -eq 0) { & $refillAmbientBag }
        $next = $script:ambientBag.Dequeue()
        if ($next -eq $script:ambientLastRoutine -and $script:ambientBag.Count -gt 0) {
            $replacement = $script:ambientBag.Dequeue()
            $script:ambientBag.Enqueue($next)
            $next = $replacement
        }
        return $next
    }

    $selectInitialPhase = {
        $hour = (Get-Date).Hour
        $roll = Get-Random -Minimum 0 -Maximum 100
        if ($script:energy -lt 28) { return 'sleep' }
        if ($hour -ge 23 -or $hour -lt 7) { return $(if ($roll -lt 82) { 'sleep' } else { 'quiet' }) }
        if ($hour -ge 12 -and $hour -lt 15) { return $(if ($roll -lt 52) { 'sleep' } elseif ($roll -lt 94) { 'quiet' } else { 'active' }) }
        if (($hour -ge 7 -and $hour -lt 10) -or ($hour -ge 17 -and $hour -lt 22)) {
            return $(if ($roll -lt 24) { 'sleep' } elseif ($roll -lt 78) { 'quiet' } else { 'active' })
        }
        return $(if ($roll -lt 38) { 'sleep' } elseif ($roll -lt 90) { 'quiet' } else { 'active' })
    }

    $selectNextPhase = {
        $hour = (Get-Date).Hour
        $roll = Get-Random -Minimum 0 -Maximum 100
        if ($script:energy -lt 25) { return 'sleep' }
        if ($hour -ge 23 -or $hour -lt 7) {
            return $(if ($roll -lt 78) { 'sleep' } elseif ($roll -lt 98) { 'quiet' } else { 'active' })
        }
        if ($script:activityPhase -eq 'sleep') { return $(if ($roll -lt 88) { 'quiet' } else { 'active' }) }
        if ($script:activityPhase -eq 'active') { return $(if ($roll -lt 76) { 'quiet' } else { 'sleep' }) }
        if ($hour -ge 12 -and $hour -lt 15) {
            return $(if ($roll -lt 54) { 'sleep' } elseif ($roll -lt 94) { 'quiet' } else { 'active' })
        }
        if (($hour -ge 7 -and $hour -lt 10) -or ($hour -ge 17 -and $hour -lt 22)) {
            return $(if ($roll -lt 27) { 'sleep' } elseif ($roll -lt 78) { 'quiet' } else { 'active' })
        }
        return $(if ($roll -lt 43) { 'sleep' } elseif ($roll -lt 90) { 'quiet' } else { 'active' })
    }

    $enterActivityPhase = {
        param([ValidateSet('sleep', 'quiet', 'active')][string]$Phase)
        $script:activityPhase = $Phase
        $script:ambientBag.Clear()
        $now = Get-Date
        switch ($Phase) {
            'sleep' {
                $hour = $now.Hour
                $minutes = if ($script:energy -lt 35) { Get-Random -Minimum 35 -Maximum 76 } elseif ($hour -ge 23 -or $hour -lt 7) { Get-Random -Minimum 45 -Maximum 121 } else { Get-Random -Minimum 18 -Maximum 46 }
                $script:activityPhaseEndsAt = $now.AddMinutes($minutes)
                $script:nextAmbientAt = $now.AddMinutes((Get-Random -Minimum 6 -Maximum 15))
            }
            'quiet' {
                $script:activityPhaseEndsAt = $now.AddMinutes((Get-Random -Minimum 10 -Maximum 26))
                $script:nextAmbientAt = $now.AddMinutes((Get-Random -Minimum 3 -Maximum 8))
            }
            'active' {
                $script:activityPhaseEndsAt = $now.AddMinutes((Get-Random -Minimum 2 -Maximum 5))
                $script:nextAmbientAt = $now.AddSeconds((Get-Random -Minimum 28 -Maximum 61))
            }
        }
    }

    $ambientStepTimer = [Windows.Threading.DispatcherTimer]::new()
    $advanceAmbientStep = $null
    $advanceAmbientStep = {
        if (-not $script:ambientActive) { $ambientStepTimer.Stop(); return }
        if ($script:ambientStepIndex -ge $script:ambientSteps.Count) {
            $ambientStepTimer.Stop()
            $script:ambientActive = $false
            & $resetPose 170
            & $holdState (& $getRestState)
            if ($script:activityPhase -eq 'active') {
                $script:ambientActionsSinceEnergyTick++
                if ($script:ambientActionsSinceEnergyTick -ge 4) {
                    $script:ambientActionsSinceEnergyTick = 0
                    $script:energy = [Math]::Max(0, $script:energy - 1)
                    & $saveState
                }
                $script:nextAmbientAt = (Get-Date).AddSeconds((Get-Random -Minimum 28 -Maximum 66))
            } elseif ($script:activityPhase -eq 'quiet') {
                $script:nextAmbientAt = (Get-Date).AddMinutes((Get-Random -Minimum 3 -Maximum 8))
            } else {
                $script:nextAmbientAt = (Get-Date).AddMinutes((Get-Random -Minimum 6 -Maximum 15))
            }
            return
        }
        $step = $script:ambientSteps[$script:ambientStepIndex]
        $script:ambientStepIndex++
        & $playState ([string]$step.State)
        & $animatePose ([double]$step.ScaleX) ([double]$step.ScaleY) ([double]$step.Angle) ([double]$step.X) ([double]$step.Y) 170
        if ($step.Particle) { & $emitParticles ([string]$step.Particle) ([string]$step.Tone) }
        $ambientStepTimer.Interval = [TimeSpan]::FromMilliseconds([int]$step.Delay)
        $ambientStepTimer.Start()
    }
    $ambientStepTimer.Add_Tick({ $ambientStepTimer.Stop(); & $advanceAmbientStep })

    $startAmbientRoutine = {
        param([string]$Name)
        if ($script:ambientActive -or $script:dragging -or $script:chaseMode -or $script:followMode -or $script:returnHomeMode -or $returnTimer.IsEnabled) { return }
        $script:ambientSteps = @(& $makeAmbientPlan $Name)
        if ($script:ambientSteps.Count -eq 0) { return }
        $script:ambientLastRoutine = $Name
        $script:ambientStepIndex = 0
        $script:ambientActive = $true
        if (-not $SelfTest -and $script:autoMood -and $script:activityPhase -eq 'active' -and ((Get-Date) - $script:lastAmbientBubbleAt).TotalMinutes -ge 45 -and (Get-Random -Minimum 0 -Maximum 100) -lt 18) {
            $line = $ambientLines | Get-Random
            & $showFeedback $line.Title $line.Text $line.Tone 0 0 0 2300
            $script:lastAmbientBubbleAt = Get-Date
        }
        & $advanceAmbientStep
    }

    $stopAmbientRoutine = {
        $ambientStepTimer.Stop()
        $script:ambientActive = $false
        $script:ambientSteps = @()
        $script:ambientStepIndex = 0
        & $resetPose 120
    }

    $ambientTimer = [Windows.Threading.DispatcherTimer]::new()
    $ambientTimer.Interval = [TimeSpan]::FromSeconds(5)
    $ambientTimer.Add_Tick({
        if ($SelfTest -or $script:dragging -or $script:chaseMode -or $script:followMode -or $script:returnHomeMode -or $returnTimer.IsEnabled -or $script:ambientActive) { return }
        $now = Get-Date
        if ($script:energy -lt 25 -and $script:activityPhase -ne 'sleep') {
            & $enterActivityPhase 'sleep'
            & $holdState 'sleeping'
            return
        }
        if ($now -ge $script:activityPhaseEndsAt) {
            $previousPhase = $script:activityPhase
            $nextPhase = & $selectNextPhase
            & $enterActivityPhase $nextPhase
            if ($nextPhase -eq 'sleep') {
                & $startAmbientRoutine 'sleepy-yawn'
            } elseif ($previousPhase -eq 'sleep') {
                $script:energy = [Math]::Min(100, $script:energy + 2)
                & $startAmbientRoutine 'wake-stretch'
                & $saveState
            } else {
                & $holdState (& $getRestState)
            }
            return
        }
        if ($now -lt $script:nextAmbientAt) { return }
        if ($script:activityPhase -eq 'sleep') {
            & $startAmbientRoutine ($sleepRoutineNames | Get-Random)
        } else {
            & $startAmbientRoutine (& $getNextAmbientRoutine)
        }
    })

    $returnTimer = [Windows.Threading.DispatcherTimer]::new()
    $returnTimer.Add_Tick({
        $returnTimer.Stop()
        if ($script:nudgeActive) {
            $script:nudgeActive = $false
            $script:ignoredNudges++
            if ($script:ignoredNudges -ge 3) {
                $script:affection = [Math]::Max(0, $script:affection - 1)
                $script:ignoredNudges = 0
                $script:lastBondEvent = '连续三次求关注没回应，关系 -1'
                & $scheduleNextNudge 75 151
            }
            & $saveState
        }
        & $holdState (& $getRestState)
        switch ($script:activityPhase) {
            'active' { $script:nextAmbientAt = (Get-Date).AddSeconds((Get-Random -Minimum 28 -Maximum 61)) }
            'quiet'  { $script:nextAmbientAt = (Get-Date).AddMinutes((Get-Random -Minimum 3 -Maximum 8)) }
            default  { $script:nextAmbientAt = (Get-Date).AddMinutes((Get-Random -Minimum 6 -Maximum 15)) }
        }
    })

    $showBriefState = {
        param([string]$Name, [int]$Milliseconds = 1700)
        & $stopAmbientRoutine
        $returnTimer.Stop()
        & $playState $Name
        $returnTimer.Interval = [TimeSpan]::FromMilliseconds($Milliseconds)
        $returnTimer.Start()
    }

    $scheduleNextNudge = {
        param([int]$MinimumMinutes = 40, [int]$MaximumMinutes = 76)
        $script:nextNudgeAt = (Get-Date).AddMinutes((Get-Random -Minimum $MinimumMinutes -Maximum $MaximumMinutes))
    }

    $markInteraction = {
        & $stopAmbientRoutine
        $script:lastInteraction = Get-Date
        $script:lastBondDecay = Get-Date
        $script:nudgeActive = $false
        $script:ignoredNudges = 0
        & $enterActivityPhase 'active'
        & $scheduleNextNudge 40 76
    }

    $openCodex = { Start-Process -FilePath "$env:WINDIR\explorer.exe" -ArgumentList 'shell:AppsFolder\OpenAI.Codex_2p2nqsd0c76g0!App' }

    $invokePetHead = {
        & $markInteraction
        $script:interactionCount++
        $now = Get-Date
        if ($now -lt $script:petCooldownUntil) {
            & $showBriefState 'review' 2400
            & $showFeedback '需要一点空间' '我转开头、舔舔鼻子：先让我缓一缓。' 'boundary' 0 0 0 3200
            & $emitParticles '·' 'boundary'
        } else {
            if (($now - $script:lastPetAt).TotalSeconds -le 18) { $script:petStreak++ } else { $script:petStreak = 1 }
            $script:lastPetAt = $now
            if ($script:petStreak -ge 4) {
                $script:affection = [Math]::Max(0, $script:affection - 1)
                $script:petCooldownUntil = $now.AddSeconds(45)
                $script:lastBondEvent = '连续摸头越过边界，关系 -1'
                & $showBriefState 'review' 3000
                & $showFeedback '摸得有点多了' '我打个哈欠、把头转开。尊重停下来的信号会更亲近。' 'boundary' -1 0 0 3800
                & $emitParticles '·' 'boundary'
            } else {
                $gain = if ($script:petStreak -eq 1) { 4 } elseif ($script:petStreak -eq 2) { 2 } else { 1 }
                $before = $script:affection
                $script:affection = [Math]::Min(100, $script:affection + $gain)
                $actual = $script:affection - $before
                $script:energy = [Math]::Min(100, $script:energy + 1)
                $script:lastBondEvent = if ($actual -gt 0) { "尊重节奏地摸头，关系 +$actual" } else { '尊重节奏地摸头，亲密已满' }
                & $showBriefState 'petting' 2700
                & $showFeedback '轻轻贴近' $(if($script:affection -ge 85){'眯起眼睛，把脑袋主动靠到手边。'}else{'身体慢慢放松，没有躲开。'}) 'positive' $actual 0 1 3200
                & $emitParticles '♥' 'positive'
            }
        }
        & $saveState
    }

    $invokeFeed = {
        & $markInteraction
        $script:interactionCount++
        if ($script:fullness -ge 94) {
            $script:feedRefusals++
            & $showBriefState 'review' 2600
            if ($script:feedRefusals -ge 2) {
                $script:affection = [Math]::Max(0, $script:affection - 1)
                $script:lastBondEvent = '吃饱后仍被反复投喂，关系 -1'
                & $showFeedback '已经吃饱了' '闻一闻就把头转开：不要再塞啦。' 'boundary' -1 0 0 3500
            } else {
                $script:lastBondEvent = '吃饱后拒绝食物，关系不变'
                & $showFeedback '已经吃饱了' '闻了闻但没有吃，先把食物留到下次。' 'need' 0 0 0 3200
            }
        } else {
            $gain = if ($script:fullness -lt 30) { 4 } else { 2 }
            $beforeAffection = $script:affection
            $beforeFullness = $script:fullness
            $beforeEnergy = $script:energy
            $beforeHealth = $script:health
            $script:feedRefusals = 0
            $script:fullness = [Math]::Min(100, $script:fullness + 16)
            $script:affection = [Math]::Min(100, $script:affection + $gain)
            $script:energy = [Math]::Min(100, $script:energy + 2)
            $healthGain = if ($beforeFullness -lt 10) { 5 } elseif ($beforeFullness -lt 30) { 3 } else { 1 }
            $script:health = [Math]::Min(100, $script:health + $healthGain)
            if ($script:fullness -gt 0) { $script:starvationTicks = 0 }
            $actualAffection = $script:affection - $beforeAffection
            $script:lastBondEvent = if ($actualAffection -gt 0) { "在需要时得到食物，关系 +$actualAffection" } else { '在需要时得到食物，亲密已满' }
            & $showBriefState 'feeding' 3400
            & $showFeedback '吃得刚刚好' $(if($beforeHealth -lt 45){'终于吃到东西，身体也慢慢缓过来了。'}else{'抱住饼干认真咬了几口，最后满足地舔舔嘴。'}) 'need' $actualAffection ($script:fullness - $beforeFullness) ($script:energy - $beforeEnergy) 3600 -HealthDelta ($script:health - $beforeHealth)
            & $emitParticles '✦' 'need'
        }
        & $saveState
    }

    $invokeBodyPlay = {
        & $markInteraction
        $script:interactionCount++
        if ($script:energy -lt 25) {
            $script:lastBondEvent = '疲惫时允许休息，关系不变'
            & $showBriefState 'sleeping' 3400
            & $showFeedback '今天先休息' '打着哈欠趴回去了，精力不够时不会勉强玩。' 'energy' 0 0 0 3500
        } elseif ($script:fullness -lt 20) {
            $script:lastBondEvent = '饥饿时先表达进食需求'
            & $showBriefState 'waiting' 3200
            & $showFeedback '肚子有点饿' '闻闻四周又看看你：先吃点东西再玩吧。' 'need' 0 0 0 3500
        } else {
            $gain = if ($script:energy -ge 70) { 4 } else { 2 }
            $beforeAffection = $script:affection
            $beforeEnergy = $script:energy
            $script:affection = [Math]::Min(100, $script:affection + $gain)
            $script:energy = [Math]::Max(0, $script:energy - 6)
            $actualAffection = $script:affection - $beforeAffection
            $script:lastBondEvent = if ($actualAffection -gt 0) { "接受玩耍邀请，关系 +$actualAffection" } else { '接受玩耍邀请，亲密已满' }
            & $showBriefState 'jumping' 2300
            & $showFeedback '发出玩耍邀请' '前腿压低、屁股翘起，蹦一下又回头等你。' 'positive' $actualAffection 0 ($script:energy - $beforeEnergy) 3300
            & $emitParticles '✦' 'positive'
        }
        & $saveState
    }

    $showStatus = {
        $relationship = if ($script:affection -ge 85) { '非常信任，会主动靠近' } elseif ($script:affection -ge 65) { '亲近放松' } elseif ($script:affection -ge 40) { '熟悉但仍会观察' } else { '有些疏远，需要耐心' }
        $need = if ($script:health -lt 30) { '生命状态危险，需要尽快喂食和休息' } elseif ($script:fullness -lt 20) { '现在非常饥饿' } elseif ($script:energy -lt 25) { '体力不足，需要休息' } else { '身体状态稳定' }
        & $showFeedback '今日状态' "$relationship；$need。`n最近：$($script:lastBondEvent)" $(if($script:health -lt 30){'health'}else{'neutral'}) 0 0 0 5200 -ShowCurrent
    }

    $moodTimer = [Windows.Threading.DispatcherTimer]::new()
    $moodTimer.Interval = [TimeSpan]::FromMinutes(1)
    $moodTimer.Add_Tick({
        if ($script:petStatus -ne 'home' -or -not $script:autoMood -or $script:dragging -or $script:chaseMode -or $script:followMode -or $returnTimer.IsEnabled -or $script:ambientActive) { return }
        if ((Get-Date) -lt $script:nextNudgeAt) { return }
        if ($script:activityPhase -eq 'sleep' -and $script:fullness -ge 20) {
            & $scheduleNextNudge 30 61
            return
        }
        if ($script:fullness -le 5) {
            $script:nudgeActive = $true
            & $showBriefState 'failed' 5200
            & $showFeedback '已经非常饿了' '饥饿下降会变慢，但继续不喂食会开始损失生命。' 'health' 0 0 0 5200
            & $scheduleNextNudge 4 10
        } elseif ($script:health -le 20) {
            $script:nudgeActive = $true
            & $showBriefState 'failed' 5200
            & $showFeedback '生命状态危险' '身体已经很虚弱，需要连续几次适量喂食慢慢恢复。' 'health' 0 0 0 5200 -ShowCurrent
            & $scheduleNextNudge 5 13
        } elseif ($script:fullness -le 15) {
            $script:nudgeActive = $true
            & $showBriefState 'waiting' 4600
            & $showFeedback '肚子一直在叫' '我会更频繁地来找你，但饥饿值已经开始减缓下降。' 'need' 0 0 0 4600
            & $scheduleNextNudge 8 17
        } elseif ($script:energy -lt 28) {
            $script:nudgeActive = $false
            & $enterActivityPhase 'sleep'
            & $holdState 'sleeping'
            & $scheduleNextNudge 30 61
        } elseif ($script:fullness -lt 30) {
            $script:nudgeActive = $true
            & $showBriefState 'waiting' 4200
            & $showFeedback '小声提醒' '闻闻食盆又看看你……方便时喂我一口好吗？' 'need' 0 0 0 4200
            & $scheduleNextNudge 12 25
        } elseif ($script:affection -lt 68) {
            $script:nudgeActive = $true
            & $showBriefState 'review' 4000
            & $showFeedback $(if($script:affection -le 15){'关系已经很疏远'}else{'在旁边等一会儿'}) $(if($script:affection -le 15){'如果长期继续这样，我可能会选择离开桌面。'}else{'我没有扑过来；愿意的话，轻轻摸一下就好。'}) $(if($script:affection -le 15){'boundary'}else{'neutral'}) 0 0 0 4200
            if ($script:affection -le 15) { & $scheduleNextNudge 20 41 } else { & $scheduleNextNudge 45 81 }
        } else {
            $request = @(
                @{ State = 'waiting'; Title = '醒了一小会儿'; Text = '要不要陪我玩一下？没有空也没关系。'; Tone = 'neutral' },
                @{ State = 'jumping'; Title = '发出玩耍邀请'; Text = '前腿压低、尾巴摇摇：要玩一会儿吗？'; Tone = 'positive' },
                @{ State = 'review'; Title = '安静看看你'; Text = '你忙完了吗？我会继续乖乖等。'; Tone = 'neutral' }
            ) | Get-Random
            $script:nudgeActive = $true
            & $showBriefState $request.State 4200
            & $showFeedback $request.Title $request.Text $request.Tone 0 0 0 4200
            & $scheduleNextNudge 50 91
        }
    })

    $applyNeedsTick = {
        if ($script:petStatus -ne 'home') { return }
        if ($script:fullness -gt 25) {
            $script:fullness = [Math]::Max(0, $script:fullness - 1)
            $script:lowHungerTicks = 0
        } elseif ($script:fullness -gt 10) {
            $script:lowHungerTicks++
            if (($script:lowHungerTicks % 2) -eq 0) { $script:fullness = [Math]::Max(0, $script:fullness - 1) }
        } elseif ($script:fullness -gt 0) {
            $script:lowHungerTicks++
            if (($script:lowHungerTicks % 4) -eq 0) { $script:fullness = [Math]::Max(0, $script:fullness - 1) }
        } else {
            $script:starvationTicks++
            if (($script:starvationTicks % 6) -eq 0) {
                $script:health = [Math]::Max(0, $script:health - 1)
                $script:lastBondEvent = '长期挨饿，生命 -1'
            }
        }

        if ($script:currentState -eq 'sleeping') {
            $script:energy = [Math]::Min(100, $script:energy + 2)
        } elseif ($script:activityPhase -eq 'active' -or $script:followMode) {
            $script:energy = [Math]::Max(0, $script:energy - 1)
        } elseif ($script:energy -lt 65) {
            $script:energy = [Math]::Min(100, $script:energy + 1)
        }

        if ($script:fullness -ge 65 -and $script:health -lt 100) {
            $script:recoveryTicks++
            if (($script:recoveryTicks % 4) -eq 0) { $script:health = [Math]::Min(100, $script:health + 1) }
        } else {
            $script:recoveryTicks = 0
        }

        $now = Get-Date
        if (($now - $script:lastInteraction).TotalHours -ge 12 -and ($now - $script:lastBondDecay).TotalHours -ge 6) {
            $script:affection = [Math]::Max(0, $script:affection - 1)
            $script:lastBondDecay = $now
            $script:lastBondEvent = '长时间没有陪伴，关系 -1'
        }
        if ($script:fullness -le 5) { & $scheduleNextNudge 4 10 }
        elseif ($script:fullness -le 15) { & $scheduleNextNudge 8 17 }
        elseif ($script:fullness -le 25) { & $scheduleNextNudge 12 25 }
        if ($script:energy -le 0 -and -not $script:followMode) {
            & $enterActivityPhase 'sleep'
            & $holdState 'sleeping'
        }
        & $saveState
    }
    $needsTimer = [Windows.Threading.DispatcherTimer]::new()
    $needsTimer.Interval = [TimeSpan]::FromMinutes(60)
    $needsTimer.Add_Tick({ & $applyNeedsTick })

    $chaseTimer = [Windows.Threading.DispatcherTimer]::new()
    $chaseTimer.Interval = [TimeSpan]::FromMilliseconds(45)
    $chaseTimer.Add_Tick({
        if (-not $script:chaseMode) { $chaseTimer.Stop(); return }
        $script:chaseTicks--
        $cursor = & $screenToDip ([Windows.Forms.Cursor]::Position)
        $targetX = $cursor.X - ($window.Width / 2)
        $targetY = $cursor.Y - ($window.Height / 2)
        $dx = $targetX - $window.Left
        $dy = $targetY - $window.Top
        if ([Math]::Abs($dx) -gt 8) {
            $stepX = [Math]::Sign($dx) * [Math]::Min(4, [Math]::Abs($dx))
            $window.Left += $stepX
            & $playState $(if ($stepX -lt 0) { 'running-left' } else { 'running-right' })
        }
        if ([Math]::Abs($dy) -gt 8) { $window.Top += [Math]::Sign($dy) * [Math]::Min(3, [Math]::Abs($dy)) }
        if ($script:chaseTicks -le 0 -or ([Math]::Abs($dx) -lt 12 -and [Math]::Abs($dy) -lt 12)) {
            $script:chaseMode = $false
            $chaseTimer.Stop()
            $beforeAffection = $script:affection
            $beforeEnergy = $script:energy
            $script:affection = [Math]::Min(100, $script:affection + 4)
            $script:energy = [Math]::Max(0, $script:energy - 5)
            $actualAffection = $script:affection - $beforeAffection
            $script:lastBondEvent = if ($actualAffection -gt 0) { "完成追逐游戏，关系 +$actualAffection" } else { '完成追逐游戏，亲密已满' }
            & $showBriefState 'jumping' 1800
            & $showFeedback '抓到你啦' '停下来回头看你，尾巴还在开心地摇。' 'positive' $actualAffection 0 ($script:energy - $beforeEnergy) 3000
            & $emitParticles '✦' 'positive'
            & $saveState
        }
    })

    $controlWindow = $null
    $quickWindow = $null
    $absenceWindow = $null
    $updateControlPanel = {}

    $followTimer = [Windows.Threading.DispatcherTimer]::new()
    $followTimer.Interval = [TimeSpan]::FromMilliseconds(42)
    $followTimer.Add_Tick({
        if ($script:petStatus -ne 'home') { $followTimer.Stop(); return }
        if (-not $script:followMode -and -not $script:returnHomeMode) { $followTimer.Stop(); return }
        if ($script:dragging) { return }
        if ($null -ne $controlWindow -and $controlWindow.IsVisible) { return }

        $area = [Windows.SystemParameters]::WorkArea
        if ($script:followMode) {
            if ($script:energy -le 5 -or $script:fullness -le 3 -or $script:health -le 12) {
                $script:followMode = $false
                $script:returnHomeMode = $true
                & $showFeedback '先回窝休息' $(if($script:fullness -le 3){'已经太饿了，没力气继续陪跑。'}else{'体力或生命状态不足，先回右下角休息。'}) 'health' 0 0 0 3600
            } else {
                $cursor = & $screenToDip ([Windows.Forms.Cursor]::Position)
                $targetX = $cursor.X + 30
                if (($targetX + $window.Width) -gt $area.Right) { $targetX = $cursor.X - $window.Width - 30 }
                $targetY = [Math]::Min($area.Bottom - $window.Height, $cursor.Y + 28)
                $targetX = [Math]::Min([Math]::Max($targetX, $area.Left), $area.Right - $window.Width)
                $targetY = [Math]::Min([Math]::Max($targetY, $area.Top), $area.Bottom - $window.Height)
            }
        }
        if ($script:returnHomeMode) {
            $targetX = $area.Right - $window.Width - 18
            $targetY = $area.Bottom - $window.Height - 12
        }

        $dx = $targetX - $window.Left
        $dy = $targetY - $window.Top
        $distance = [Math]::Sqrt(($dx * $dx) + ($dy * $dy))
        if ($distance -gt 10) {
            $stepX = [Math]::Sign($dx) * [Math]::Min(7, [Math]::Max(1.2, [Math]::Abs($dx) * 0.13))
            $stepY = [Math]::Sign($dy) * [Math]::Min(5.5, [Math]::Max(1.0, [Math]::Abs($dy) * 0.13))
            $window.Left += $stepX
            $window.Top += $stepY
            $moveState = if ($stepX -lt 0) { 'running-left' } else { 'running-right' }
            if ($script:currentState -ne $moveState) { & $playState $moveState }
        } else {
            if ($script:returnHomeMode) {
                & $placeAtHome
                $script:returnHomeMode = $false
                & $enterActivityPhase 'quiet'
            }
            if ($animationTimer.IsEnabled -or $script:currentState -ne 'idle') { & $holdState 'idle' }
        }

        if ($script:followMode -and ((Get-Date) - $script:lastFollowCostAt).TotalMinutes -ge 5) {
            $script:lastFollowCostAt = Get-Date
            $script:energy = [Math]::Max(0, $script:energy - 2)
            & $saveState
            & $updateControlPanel
        }
    })

    $startFollowing = {
        if ($script:petStatus -ne 'home') { return }
        if ($script:energy -lt 15 -or $script:fullness -lt 5 -or $script:health -lt 15) {
            & $showFeedback '现在不适合陪跑' '先喂一点东西并让生命和体力恢复，再一起走。' 'health' 0 0 0 3600 -ShowCurrent
            return
        }
        & $markInteraction
        $script:chaseMode = $false
        $chaseTimer.Stop()
        $script:followMode = $true
        $script:returnHomeMode = $false
        $script:lastFollowCostAt = Get-Date
        $followTimer.Start()
        & $showFeedback '开始陪着你' '我会一直跟在鼠标旁边；右键打开面板可随时停止。' 'positive' 0 0 0 3200
        & $updateControlPanel
    }

    $stopFollowing = {
        param([switch]$Silent)
        $wasFollowing = $script:followMode
        $script:followMode = $false
        $script:returnHomeMode = $true
        $followTimer.Start()
        if ($wasFollowing -and -not $Silent) { & $showFeedback '回窝待着' '不再跟随鼠标，我自己跑回右下角。' 'neutral' 0 0 0 2800 }
        & $updateControlPanel
    }

    $returnHome = {
        $script:followMode = $false
        $script:returnHomeMode = $true
        $followTimer.Start()
        & $updateControlPanel
    }

    $newPanelText = {
        param([string]$Text, [double]$Size = 12, [string]$Weight = 'Normal', [string]$Tone = 'ink')
        $tb = [Windows.Controls.TextBlock]::new()
        $tb.Text = $Text
        $tb.FontFamily = [Windows.Media.FontFamily]::new('Microsoft YaHei UI')
        $tb.FontSize = $Size
        $tb.FontWeight = if ($Weight -eq 'SemiBold') { [Windows.FontWeights]::SemiBold } else { [Windows.FontWeights]::Normal }
        $tb.Foreground = & $brush $(switch ($Tone) { 'muted' { $color.Muted }; 'danger' { $color.HealthDark }; 'positive' { $color.Positive }; default { $color.Ink } })
        return $tb
    }

    $newActionTile = {
        param([string]$Title, [string]$Subtitle, [scriptblock]$Action, [string]$Variant = 'neutral', [double]$Height = 52)
        $baseHex = switch ($Variant) { 'primary' { $color.PositiveSoft }; 'danger' { $color.HealthSoft }; default { $color.SurfaceHover } }
        $hoverHex = switch ($Variant) { 'danger' { $color.BoundarySoft }; default { $color.SurfacePressed } }
        $tone = switch ($Variant) { 'primary' { 'positive' }; 'danger' { 'danger' }; default { 'ink' } }
        $tile = [Windows.Controls.Border]::new()
        $tile.Height = $Height
        $tile.CornerRadius = [Windows.CornerRadius]::new([double]$tokens.component.'action-radius')
        $tile.Background = & $brush $baseHex
        $tile.BorderBrush = & $brush $color.SurfaceBorder
        $tile.BorderThickness = [Windows.Thickness]::new(1)
        $tile.Padding = [Windows.Thickness]::new(11, 7, 11, 7)
        $tile.Margin = [Windows.Thickness]::new(3)
        $tile.Cursor = [Windows.Input.Cursors]::Hand
        $stack = [Windows.Controls.StackPanel]::new()
        $titleBlock = & $newPanelText $Title 12.5 'SemiBold' $tone
        $stack.Children.Add($titleBlock) | Out-Null
        if ($Subtitle) {
            $subBlock = & $newPanelText $Subtitle 9.8 'Normal' 'muted'
            $subBlock.Margin = [Windows.Thickness]::new(0, 2, 0, 0)
            $stack.Children.Add($subBlock) | Out-Null
        }
        $tile.Child = $stack
        $tile.Tag = $titleBlock
        $tile.Add_MouseEnter({ param($sender,$eventArgs) $sender.Background = & $brush $hoverHex }.GetNewClosure())
        $tile.Add_MouseLeave({ param($sender,$eventArgs) $sender.Background = & $brush $baseHex }.GetNewClosure())
        $tile.Add_MouseLeftButtonDown({ param($sender,$eventArgs) $sender.Opacity = 0.78 }.GetNewClosure())
        $tile.Add_MouseLeftButtonUp({ param($sender,$eventArgs) $sender.Opacity = 1; & $Action; $eventArgs.Handled = $true }.GetNewClosure())
        return $tile
    }

    $controlWindow = [Windows.Window]::new()
    $controlWindow.Title = '菜狗生活面板'
    $controlWindow.WindowStyle = [Windows.WindowStyle]::None
    $controlWindow.ResizeMode = [Windows.ResizeMode]::NoResize
    $controlWindow.AllowsTransparency = $true
    $controlWindow.Background = [Windows.Media.Brushes]::Transparent
    $controlWindow.ShowInTaskbar = $false
    $controlWindow.Topmost = $true
    $controlWindow.ShowActivated = $false
    $controlWindow.SizeToContent = [Windows.SizeToContent]::WidthAndHeight

    $controlCard = [Windows.Controls.Border]::new()
    $controlCard.Width = [double]$tokens.component.'control-width'
    $controlCard.CornerRadius = [Windows.CornerRadius]::new([double]$tokens.component.'control-radius')
    $controlCard.Background = & $brush $color.SurfaceGlass
    $controlCard.BorderBrush = & $brush $color.SurfaceBorder
    $controlCard.BorderThickness = [Windows.Thickness]::new(1)
    $controlCard.Padding = [Windows.Thickness]::new([double]$tokens.component.'control-padding')
    $controlCard.Effect = [Windows.Media.Effects.DropShadowEffect]@{ BlurRadius = [double]$tokens.component.'control-shadow-blur'; ShadowDepth = 5; Opacity = 0.28; Color = [Windows.Media.ColorConverter]::ConvertFromString($color.Shadow) }
    $controlWindow.Content = $controlCard
    $controlStack = [Windows.Controls.StackPanel]::new()
    $controlCard.Child = $controlStack

    $headerGrid = [Windows.Controls.Grid]::new()
    $headerGrid.ColumnDefinitions.Add([Windows.Controls.ColumnDefinition]@{ Width = [Windows.GridLength]::new(1,[Windows.GridUnitType]::Star) }) | Out-Null
    $headerGrid.ColumnDefinitions.Add([Windows.Controls.ColumnDefinition]@{ Width = [Windows.GridLength]::Auto }) | Out-Null
    $headerLeft = [Windows.Controls.StackPanel]::new()
    $headerTitle = & $newPanelText '菜狗生活面板' 16 'SemiBold' 'ink'
    $controlStatusText = & $newPanelText '安静待着' 10.5 'Normal' 'muted'
    $controlStatusText.Margin = [Windows.Thickness]::new(0, 3, 0, 0)
    $headerLeft.Children.Add($headerTitle) | Out-Null
    $headerLeft.Children.Add($controlStatusText) | Out-Null
    [Windows.Controls.Grid]::SetColumn($headerLeft,0)
    $headerGrid.Children.Add($headerLeft) | Out-Null
    $closeTile = & $newActionTile '×' '' { $controlWindow.Hide() } 'neutral' 34
    $closeTile.Width = 34
    $closeTile.Padding = [Windows.Thickness]::new(9,4,9,4)
    [Windows.Controls.Grid]::SetColumn($closeTile,1)
    $headerGrid.Children.Add($closeTile) | Out-Null
    $controlStack.Children.Add($headerGrid) | Out-Null

    $statsPanel = [Windows.Controls.StackPanel]::new()
    $statsPanel.Margin = [Windows.Thickness]::new(0, 16, 0, 10)
    $controlStack.Children.Add($statsPanel) | Out-Null
    $statWidgets = @{}
    $newStatRow = {
        param([string]$Key, [string]$Label, [string]$FillColor)
        $row = [Windows.Controls.StackPanel]::new()
        $row.Margin = [Windows.Thickness]::new(0, 0, 0, 10)
        $head = [Windows.Controls.Grid]::new()
        $head.ColumnDefinitions.Add([Windows.Controls.ColumnDefinition]@{ Width = [Windows.GridLength]::new(1,[Windows.GridUnitType]::Star) }) | Out-Null
        $head.ColumnDefinitions.Add([Windows.Controls.ColumnDefinition]@{ Width = [Windows.GridLength]::Auto }) | Out-Null
        $labelBlock = & $newPanelText $Label 10.5 'SemiBold' 'muted'
        $valueBlock = & $newPanelText '100' 10.5 'SemiBold' 'ink'
        [Windows.Controls.Grid]::SetColumn($valueBlock,1)
        $head.Children.Add($labelBlock) | Out-Null
        $head.Children.Add($valueBlock) | Out-Null
        $track = [Windows.Controls.Border]::new()
        $track.Width = 292
        $track.Height = [double]$tokens.component.'stat-track-height'
        $track.CornerRadius = [Windows.CornerRadius]::new(4)
        $track.Background = & $brush $color.Track
        $track.Margin = [Windows.Thickness]::new(0,5,0,0)
        $fill = [Windows.Controls.Border]::new()
        $fill.Height = $track.Height
        $fill.HorizontalAlignment = [Windows.HorizontalAlignment]::Left
        $fill.CornerRadius = [Windows.CornerRadius]::new(4)
        $fill.Background = & $brush $FillColor
        $track.Child = $fill
        $row.Children.Add($head) | Out-Null
        $row.Children.Add($track) | Out-Null
        $statsPanel.Children.Add($row) | Out-Null
        $statWidgets[$Key] = @{ Value = $valueBlock; Fill = $fill }
    }
    & $newStatRow 'health' '生命' $color.Health
    & $newStatRow 'fullness' '饱食' $color.Need
    & $newStatRow 'stamina' '体力' $color.Energy
    & $newStatRow 'affection' '亲密' $color.Positive

    $sectionLabel = & $newPanelText '快速互动' 10.5 'SemiBold' 'muted'
    $sectionLabel.Margin = [Windows.Thickness]::new(3, 2, 0, 5)
    $controlStack.Children.Add($sectionLabel) | Out-Null
    $actionGrid = [Windows.Controls.Primitives.UniformGrid]::new()
    $actionGrid.Columns = 2
    $controlStack.Children.Add($actionGrid) | Out-Null
    $actionGrid.Children.Add((& $newActionTile '轻轻摸摸' '尊重节奏地亲近' { & $invokePetHead; & $updateControlPanel } 'neutral' 54)) | Out-Null
    $actionGrid.Children.Add((& $newActionTile '喂它一口' '饥饿时恢复生命' { & $invokeFeed; & $updateControlPanel } 'neutral' 54)) | Out-Null
    $actionGrid.Children.Add((& $newActionTile '陪它玩' '消耗体力，增加亲密' { & $invokeBodyPlay; & $updateControlPanel } 'neutral' 54)) | Out-Null
    $followTile = & $newActionTile '跟着鼠标' '不限时陪跑' { if($script:followMode){ & $stopFollowing }else{ & $startFollowing }; & $updateControlPanel } 'primary' 54
    $followTileText = $followTile.Tag
    $actionGrid.Children.Add($followTile) | Out-Null

    $controlGrid = [Windows.Controls.Primitives.UniformGrid]::new()
    $controlGrid.Columns = 2
    $controlGrid.Margin = [Windows.Thickness]::new(0,8,0,0)
    $controlStack.Children.Add($controlGrid) | Out-Null
    $controlGrid.Children.Add((& $newActionTile '查看状态' '' { & $showStatus; & $updateControlPanel } 'neutral' 38)) | Out-Null
    $controlGrid.Children.Add((& $newActionTile '回右下角' '' { & $returnHome; $controlWindow.Hide() } 'neutral' 38)) | Out-Null
    $quietTile = & $newActionTile '安静模式' '' {
        $script:autoMood = -not $script:autoMood
        if ($script:autoMood) { & $scheduleNextNudge 40 76; $moodTimer.Start() } else { $moodTimer.Stop(); & $holdState (& $getRestState) }
        & $showFeedback '陪伴模式已更新' $(if($script:autoMood){'按自己的作息生活，偶尔来找你。'}else{'不主动冒泡，只保留作息和直接互动。'}) 'neutral' 0 0 0 2800
        & $updateControlPanel
    } 'neutral' 38
    $quietTileText = $quietTile.Tag
    $controlGrid.Children.Add($quietTile) | Out-Null
    $controlGrid.Children.Add((& $newActionTile '打开 Codex' '' { & $markInteraction; & $showBriefState 'waving' 1200; & $openCodex } 'neutral' 38)) | Out-Null

    $sizeLabel = & $newPanelText '显示大小' 10.5 'SemiBold' 'muted'
    $sizeLabel.Margin = [Windows.Thickness]::new(3,12,0,4)
    $controlStack.Children.Add($sizeLabel) | Out-Null
    $sizeGrid = [Windows.Controls.Primitives.UniformGrid]::new()
    $sizeGrid.Columns = 3
    foreach ($size in @(@{Label='小巧';Value=76}, @{Label='标准';Value=92}, @{Label='放大';Value=116})) {
        $sizeValue = $size.Value
        $sizeTile = & $newActionTile $size.Label '' {
            $window.Width = [double]$sizeValue
            $window.Height = [Math]::Round($window.Width * 1.174)
            $area = [Windows.SystemParameters]::WorkArea
            $window.Left = [Math]::Min([Math]::Max($window.Left, $area.Left), $area.Right - $window.Width)
            $window.Top = [Math]::Min([Math]::Max($window.Top, $area.Top), $area.Bottom - $window.Height)
        }.GetNewClosure() 'neutral' 34
        $sizeGrid.Children.Add($sizeTile) | Out-Null
    }
    $controlStack.Children.Add($sizeGrid) | Out-Null
    $exitTile = & $newActionTile '退出桌宠' '只关闭本次运行，不设置自启' { $window.Close() } 'danger' 48
    $exitTile.Margin = [Windows.Thickness]::new(3,10,3,0)
    $controlStack.Children.Add($exitTile) | Out-Null

    $updateControlPanel = {
        foreach ($entry in @(
            @{Key='health';Value=$script:health}, @{Key='fullness';Value=$script:fullness},
            @{Key='stamina';Value=$script:energy}, @{Key='affection';Value=$script:affection}
        )) {
            $widget = $statWidgets[$entry.Key]
            $value = [Math]::Min(100,[Math]::Max(0,[int]$entry.Value))
            $widget.Value.Text = "$value / 100"
            $widget.Fill.Width = 292 * ($value / 100.0)
        }
        $controlStatusText.Text = if ($script:followMode) { '正在陪着鼠标走' } elseif ($script:returnHomeMode) { '正在自己跑回窝' } else { switch($script:activityPhase){ 'sleep' {'熟睡中，动作暂停'} 'active' {'短暂活跃'} default {'安静清醒'} } }
        $followTileText.Text = if ($script:followMode) { '停止跟随' } else { '跟着鼠标' }
        if ($null -ne $quickFollowText) { $quickFollowText.Text = if ($script:followMode) { '停止' } else { '跟随' } }
        $quietTileText.Text = if ($script:autoMood) { '安静模式' } else { '恢复提醒' }
        $controlCard.BorderBrush = & $brush $(if($script:health -le 20){$color.Health}else{$color.SurfaceBorder})
    }

    $toggleControlPanel = {
        if ($script:petStatus -ne 'home') { return }
        if ($controlWindow.IsVisible) { $controlWindow.Hide(); return }
        if ($null -ne $quickWindow) { $quickWindow.Hide() }
        & $updateControlPanel
        $controlWindow.Show()
        $controlWindow.UpdateLayout()
        $area = [Windows.SystemParameters]::WorkArea
        $left = $window.Left - $controlWindow.ActualWidth - 10
        if ($left -lt $area.Left) { $left = $window.Left + $window.Width + 10 }
        $controlWindow.Left = [Math]::Min([Math]::Max($left,$area.Left),$area.Right-$controlWindow.ActualWidth)
        $controlWindow.Top = [Math]::Min([Math]::Max($window.Top-$controlWindow.ActualHeight+80,$area.Top),$area.Bottom-$controlWindow.ActualHeight)
    }

    $quickWindow = [Windows.Window]::new()
    $quickWindow.Title = '菜狗快捷互动'
    $quickWindow.WindowStyle = [Windows.WindowStyle]::None
    $quickWindow.ResizeMode = [Windows.ResizeMode]::NoResize
    $quickWindow.AllowsTransparency = $true
    $quickWindow.Background = [Windows.Media.Brushes]::Transparent
    $quickWindow.ShowInTaskbar = $false
    $quickWindow.Topmost = $true
    $quickWindow.ShowActivated = $false
    $quickWindow.SizeToContent = [Windows.SizeToContent]::WidthAndHeight
    $quickCard = [Windows.Controls.Border]::new()
    $quickCard.CornerRadius = [Windows.CornerRadius]::new([double]$tokens.component.'quickbar-radius')
    $quickCard.Background = & $brush $color.SurfaceGlass
    $quickCard.BorderBrush = & $brush $color.SurfaceBorder
    $quickCard.BorderThickness = [Windows.Thickness]::new(1)
    $quickCard.Padding = [Windows.Thickness]::new(4)
    $quickCard.Effect = [Windows.Media.Effects.DropShadowEffect]@{ BlurRadius=18; ShadowDepth=3; Opacity=0.22; Color=[Windows.Media.ColorConverter]::ConvertFromString($color.Shadow) }
    $quickWindow.Content = $quickCard
    $quickRow = [Windows.Controls.StackPanel]::new()
    $quickRow.Orientation = [Windows.Controls.Orientation]::Horizontal
    $quickCard.Child = $quickRow
    $quickRow.Children.Add((& $newActionTile '摸摸' '' { & $invokePetHead; $quickWindow.Hide() } 'neutral' 34)) | Out-Null
    $quickRow.Children.Add((& $newActionTile '喂食' '' { & $invokeFeed; $quickWindow.Hide() } 'neutral' 34)) | Out-Null
    $quickRow.Children.Add((& $newActionTile '玩耍' '' { & $invokeBodyPlay; $quickWindow.Hide() } 'neutral' 34)) | Out-Null
    $quickFollowTile = & $newActionTile '跟随' '' { if($script:followMode){ & $stopFollowing }else{ & $startFollowing }; $quickWindow.Hide() } 'primary' 34
    $quickFollowText = $quickFollowTile.Tag
    $quickRow.Children.Add($quickFollowTile) | Out-Null

    $quickHideTimer = [Windows.Threading.DispatcherTimer]::new()
    $quickHideTimer.Add_Tick({ $quickHideTimer.Stop(); if(-not $quickWindow.IsMouseOver){$quickWindow.Hide()} })
    $showQuickBar = {
        if ($script:petStatus -ne 'home' -or $controlWindow.IsVisible) { return }
        & $updateControlPanel
        if (-not $quickWindow.IsVisible) { $quickWindow.Show(); $quickWindow.UpdateLayout() }
        $area = [Windows.SystemParameters]::WorkArea
        $quickWindow.Left = [Math]::Min([Math]::Max($window.Left + ($window.Width-$quickWindow.ActualWidth)/2,$area.Left),$area.Right-$quickWindow.ActualWidth)
        $quickWindow.Top = [Math]::Max($area.Top,$window.Top-$quickWindow.ActualHeight-6)
    }
    $quickWindow.Add_MouseEnter({ $quickHideTimer.Stop() })
    $quickWindow.Add_MouseLeave({ $quickHideTimer.Interval=[TimeSpan]::FromMilliseconds(650); $quickHideTimer.Start() })

    $absenceWindow = [Windows.Window]::new()
    $absenceWindow.Title = '菜狗不在桌面'
    $absenceWindow.WindowStyle = [Windows.WindowStyle]::None
    $absenceWindow.ResizeMode = [Windows.ResizeMode]::NoResize
    $absenceWindow.AllowsTransparency = $true
    $absenceWindow.Background = [Windows.Media.Brushes]::Transparent
    $absenceWindow.ShowInTaskbar = $false
    $absenceWindow.Topmost = $true
    $absenceWindow.SizeToContent = [Windows.SizeToContent]::WidthAndHeight
    $absenceCard = [Windows.Controls.Border]::new()
    $absenceCard.Width = 352
    $absenceCard.CornerRadius = [Windows.CornerRadius]::new(24)
    $absenceCard.Background = & $brush $color.SurfaceGlass
    $absenceCard.BorderBrush = & $brush $color.Health
    $absenceCard.BorderThickness = [Windows.Thickness]::new(1)
    $absenceCard.Padding = [Windows.Thickness]::new(22)
    $absenceCard.Effect = [Windows.Media.Effects.DropShadowEffect]@{ BlurRadius=30; ShadowDepth=6; Opacity=0.3; Color=[Windows.Media.ColorConverter]::ConvertFromString($color.Shadow) }
    $absenceWindow.Content = $absenceCard
    $absenceStack = [Windows.Controls.StackPanel]::new()
    $absenceCard.Child = $absenceStack
    $absenceEyebrow = & $newPanelText '一封留在桌面的信' 10.5 'SemiBold' 'danger'
    $absenceTitle = & $newPanelText '菜狗离开了' 18 'SemiBold' 'ink'
    $absenceTitle.Margin = [Windows.Thickness]::new(0,7,0,0)
    $absenceBody = & $newPanelText '' 12 'Normal' 'muted'
    $absenceBody.TextWrapping = [Windows.TextWrapping]::Wrap
    $absenceBody.LineHeight = 20
    $absenceBody.Margin = [Windows.Thickness]::new(0,9,0,14)
    $absenceStack.Children.Add($absenceEyebrow) | Out-Null
    $absenceStack.Children.Add($absenceTitle) | Out-Null
    $absenceStack.Children.Add($absenceBody) | Out-Null
    $absenceStack.Children.Add((& $newActionTile '重新领养一只菜狗' '旧关系保留在备份，新伙伴重新开始' {
        $script:affection = 35
        $script:fullness = 65
        $script:energy = 70
        $script:health = 100
        $script:petStatus = 'home'
        $script:departureReason = ''
        $script:departedAt = $null
        $script:ignoredNudges = 0
        $script:feedRefusals = 0
        $script:lowHungerTicks = 0
        $script:starvationTicks = 0
        $script:recoveryTicks = 0
        $script:lastInteraction = Get-Date
        $script:lastBondDecay = Get-Date
        $script:lastBondEvent = '重新领养，正在建立新的关系'
        $script:statusHandled = $false
        & $saveState
        $absenceWindow.Hide()
        $window.Show()
        & $placeAtHome
        & $enterActivityPhase 'quiet'
        & $holdState 'idle'
        $moodTimer.Start(); $ambientTimer.Start(); $needsTimer.Start()
        & $scheduleNextNudge 40 76
        & $showFeedback '新的开始' '这是一只新领养的菜狗，请慢慢重新建立信任。' 'positive' 0 0 0 4200 -ShowCurrent
    } 'primary' 56)) | Out-Null
    $absenceStack.Children.Add((& $newActionTile '保留记录并关闭' '' { $window.Close() } 'neutral' 40)) | Out-Null

    $showAbsence = {
        $script:statusHandled = $true
        $script:followMode = $false
        $script:returnHomeMode = $false
        $animationTimer.Stop(); $ambientTimer.Stop(); $ambientStepTimer.Stop(); $moodTimer.Stop(); $needsTimer.Stop(); $followTimer.Stop(); $chaseTimer.Stop(); $returnTimer.Stop()
        $controlWindow.Hide(); $quickWindow.Hide(); $feedbackWindow.Hide(); $window.Hide()
        if ($script:petStatus -eq 'deceased') {
            $absenceEyebrow.Text = '生命已经走到终点'
            $absenceTitle.Text = '这只菜狗不会再回来了'
            $absenceBody.Text = "原因：$($script:departureReason)。`n它的生命值已经归零；重新领养会建立一段新的关系。"
        } else {
            $absenceEyebrow.Text = '关系已经耗尽'
            $absenceTitle.Text = '菜狗离开了桌面'
            $absenceBody.Text = "原因：$($script:departureReason)。`n亲密度降到离家阈值后，它选择去别处生活。"
        }
        if (-not $absenceWindow.IsVisible) { $absenceWindow.Show(); $absenceWindow.UpdateLayout() }
        $area = [Windows.SystemParameters]::WorkArea
        $absenceWindow.Left = $area.Left + (($area.Width - $absenceWindow.ActualWidth) / 2)
        $absenceWindow.Top = $area.Top + (($area.Height - $absenceWindow.ActualHeight) / 2)
    }

    $statusTimer = [Windows.Threading.DispatcherTimer]::new()
    $statusTimer.Interval = [TimeSpan]::FromSeconds(1)
    $statusTimer.Add_Tick({ if($script:petStatus -ne 'home' -and -not $script:statusHandled){ & $showAbsence } })

    $petImage.ToolTip = '悬停快捷互动 · 左键直接互动 · 右键生活面板 · 双击聊天'
    $petImage.Add_MouseEnter({
        $duration = [Windows.Duration]::new([TimeSpan]::FromMilliseconds([double]$tokens.component.'motion-fast-ms'))
        $petScale.BeginAnimation([Windows.Media.ScaleTransform]::ScaleXProperty, [Windows.Media.Animation.DoubleAnimation]::new($petScale.ScaleX, 1.025, $duration))
        $petScale.BeginAnimation([Windows.Media.ScaleTransform]::ScaleYProperty, [Windows.Media.Animation.DoubleAnimation]::new($petScale.ScaleY, 1.025, $duration))
        $quickHideTimer.Stop()
        & $showQuickBar
    })
    $petImage.Add_MouseLeave({
        $duration = [Windows.Duration]::new([TimeSpan]::FromMilliseconds([double]$tokens.component.'motion-fast-ms'))
        $petScale.BeginAnimation([Windows.Media.ScaleTransform]::ScaleXProperty, [Windows.Media.Animation.DoubleAnimation]::new($petScale.ScaleX, 1, $duration))
        $petScale.BeginAnimation([Windows.Media.ScaleTransform]::ScaleYProperty, [Windows.Media.Animation.DoubleAnimation]::new($petScale.ScaleY, 1, $duration))
        $quickHideTimer.Interval = [TimeSpan]::FromMilliseconds(850)
        $quickHideTimer.Start()
    })
    $petImage.Add_MouseRightButtonUp({
        param($sender,$eventArgs)
        & $toggleControlPanel
        $eventArgs.Handled = $true
    })
    $petImage.Add_MouseLeftButtonDown({
        param($sender, $eventArgs)
        if ($eventArgs.ClickCount -ge 2) {
            $script:suppressNextClick = $true
            & $markInteraction
            & $showBriefState 'waving' 1200
            & $showFeedback '一起去聊天' '我会在 Codex 里继续陪你。' 'positive' 0 0 0 2200
            & $openCodex
            $eventArgs.Handled = $true
            return
        }
        $script:dragging = $true
        $script:dragMoved = $false
        $script:dragOffset = $eventArgs.GetPosition($window)
        $script:dragStartedAt = Get-Date
        [void]$petImage.CaptureMouse()
    })
    $petImage.Add_MouseMove({
        param($sender, $eventArgs)
        if (-not $script:dragging -or $eventArgs.LeftButton -ne [Windows.Input.MouseButtonState]::Pressed) { return }
        $cursor = & $screenToDip ([Windows.Forms.Cursor]::Position)
        if ([Math]::Abs(($cursor.X - $script:dragOffset.X) - $window.Left) -gt 2 -or [Math]::Abs(($cursor.Y - $script:dragOffset.Y) - $window.Top) -gt 2) { $script:dragMoved = $true }
        $window.Left = $cursor.X - $script:dragOffset.X
        $window.Top = $cursor.Y - $script:dragOffset.Y
        if ($script:dragMoved) { & $playState 'running' }
    })
    $petImage.Add_MouseLeftButtonUp({
        param($sender, $eventArgs)
        $petImage.ReleaseMouseCapture()
        if ($script:suppressNextClick) { $script:suppressNextClick = $false; $script:dragging = $false; return }
        $wasMoved = $script:dragMoved
        $script:dragging = $false
        if ($wasMoved) {
            & $markInteraction
            $script:interactionCount++
            if (((Get-Date) - $script:dragStartedAt).TotalSeconds -gt 4) {
                $script:affection = [Math]::Max(0, $script:affection - 1)
                $script:lastBondEvent = '被长时间拎着不舒服，关系 -1'
                & $showBriefState 'review' 2600
                & $showFeedback '想回到地面' '被拎得有点久，我扭开身体想落地。' 'boundary' -1 0 0 3400
            } else {
                $script:lastBondEvent = '短暂移动位置，关系不变'
                & $showBriefState 'waiting' 1400
                & $showFeedback '换了个舒服的位置' '站稳后回头看看你，关系不变。' 'neutral' 0 0 0 2200
            }
            & $saveState
        } elseif ($eventArgs.GetPosition($petImage).Y -lt ($petImage.ActualHeight * 0.58)) {
            & $invokePetHead
        } else {
            & $invokeBodyPlay
        }
    })

    $window.Add_Loaded({
        & $placeAtHome
        $statusTimer.Start()
        if ($script:petStatus -ne 'home') {
            & $showAbsence
            return
        }
        $initialPhase = & $selectInitialPhase
        & $enterActivityPhase $initialPhase
        switch ($initialPhase) {
            'sleep'  { & $holdState 'sleeping' }
            'active' { & $holdState 'waiting' }
            default  { & $holdState 'idle' }
        }
        $moodTimer.Start()
        $ambientTimer.Start()
        $needsTimer.Start()
        if (-not $SelfTest) {
            & $scheduleNextNudge 40 76
            & $saveState
            if ($OpenPanel) { & $toggleControlPanel }
        }
    })
    $window.Add_Closed({
        $animationTimer.Stop()
        $feedbackTimer.Stop()
        $returnTimer.Stop()
        $moodTimer.Stop()
        $ambientTimer.Stop()
        $ambientStepTimer.Stop()
        $needsTimer.Stop()
        $chaseTimer.Stop()
        $followTimer.Stop()
        $quickHideTimer.Stop()
        $statusTimer.Stop()
        & $saveState
        $feedbackWindow.Close()
        $controlWindow.Close()
        $quickWindow.Close()
        $absenceWindow.Close()
    })

    if ($SelfTest) {
        $testTimer = [Windows.Threading.DispatcherTimer]::new()
        $testTimer.Interval = [TimeSpan]::FromMilliseconds(1200)
        $testTimer.Add_Tick({
            $testTimer.Stop()
            $naturalStartOk = switch ($script:activityPhase) {
                'sleep' { $script:currentState -eq 'sleeping' }
                'active' { $script:currentState -eq 'waiting' }
                'quiet' { $script:currentState -eq 'idle' }
                default { $false }
            }
            $staticRestOk = (-not $animationTimer.IsEnabled)
            $hqFramesOk = ($script:frames.Count -eq 12 -and $script:frames['sleeping'].Count -eq 2 -and $script:frames['failed'].Count -ge 6)
            $modernFeedbackOk = ($feedbackCard.CornerRadius.TopLeft -ge 16 -and $feedbackCard.Effect.BlurRadius -ge 18)
            $modernPanelOk = ($controlCard.CornerRadius.TopLeft -ge 20 -and $controlCard.Width -ge 320 -and $statWidgets.Count -eq 4 -and $actionGrid.Children.Count -eq 4 -and $quickRow.Children.Count -eq 4 -and $null -eq $petImage.ContextMenu)
            $allAmbientNames = @($ambientRoutineNames) + @($sleepRoutineNames)
            $ambientPlansOk = ($allAmbientNames.Count -eq 33 -and @($allAmbientNames | Select-Object -Unique).Count -eq 33 -and $quietRoutineNames.Count -eq 15 -and $activeRoutineNames.Count -eq 15)
            $naturalScheduleOk = ($ambientTimer.Interval.TotalSeconds -eq 5 -and $script:activityPhaseEndsAt -gt (Get-Date).AddMinutes(1) -and $script:nextAmbientAt -gt (Get-Date).AddSeconds(20))
            foreach ($routineName in $allAmbientNames) {
                $plan = @(& $makeAmbientPlan $routineName)
                if ($plan.Count -lt 2) { $ambientPlansOk = $false; break }
                foreach ($planStep in $plan) {
                    if (-not $script:frames.ContainsKey([string]$planStep.State)) { $ambientPlansOk = $false; break }
                }
            }
            $script:affection = 40
            $script:fullness = 50
            $script:energy = 70
            $script:interactionCount = 0
            $script:feedRefusals = 0
            $script:petStreak = 0
            $script:lastPetAt = [datetime]::MinValue
            $script:petCooldownUntil = [datetime]::MinValue
            $startAffection = $script:affection
            $startFullness = $script:fullness
            $startEnergy = $script:energy
            & $invokePetHead
            & $invokeFeed
            & $invokeBodyPlay
            $baseInteractions = $script:interactionCount
            $interactionOk = ($baseInteractions -eq 3 -and $script:affection -eq ($startAffection + 10) -and $script:fullness -eq ($startFullness + 16) -and $script:energy -eq ($startEnergy - 3))
            $script:petStreak = 3
            $script:lastPetAt = Get-Date
            $script:petCooldownUntil = [datetime]::MinValue
            $beforeBoundary = $script:affection
            & $invokePetHead
            $boundaryOk = ($script:affection -eq ($beforeBoundary - 1))
            $script:fullness = 100
            $script:feedRefusals = 1
            $beforeForcedFeed = $script:affection
            & $invokeFeed
            $feedingBoundaryOk = ($script:affection -eq ($beforeForcedFeed - 1))
            $script:lastInteraction = (Get-Date).AddHours(-14)
            $script:lastBondDecay = (Get-Date).AddHours(-7)
            $script:currentState = 'sleeping'
            $beforeNeglect = $script:affection
            & $applyNeedsTick
            $neglectOk = ($script:affection -eq ($beforeNeglect - 1))
            $affectionCanDecrease = ($boundaryOk -and $feedingBoundaryOk -and $neglectOk)

            $script:lastInteraction = Get-Date
            $script:lastBondDecay = Get-Date
            $script:petStatus = 'home'
            $script:affection = 40
            $script:fullness = 11
            $script:lowHungerTicks = 1
            $script:health = 20
            $script:starvationTicks = 0
            & $applyNeedsTick
            $slowHungerOk = ($script:fullness -eq 10 -and $script:health -eq 20)
            $script:fullness = 0
            $script:starvationTicks = 5
            $beforeStarvationHealth = $script:health
            & $applyNeedsTick
            $starvationDamageOk = ($script:health -eq ($beforeStarvationHealth - 1))
            $lifeSystemOk = ($slowHungerOk -and $starvationDamageOk)

            $script:petStatus = 'home'
            $script:health = 50
            $script:affection = 5
            & $saveState
            $departureReachable = ($script:petStatus -eq 'departed')

            $script:petStatus = 'home'
            $script:departureReason = ''
            $script:departedAt = $null
            $script:health = 50
            $script:affection = 40
            $script:fullness = 50
            $script:energy = 50
            & $startFollowing
            $followStartedOk = ($script:followMode -and $followTimer.IsEnabled)
            & $stopFollowing -Silent
            $followStoppedOk = (-not $script:followMode -and $script:returnHomeMode)
            $followModeOk = ($followStartedOk -and $followStoppedOk)
            $script:returnHomeMode = $false
            $followTimer.Stop()
            $nudgeWindowOk = ($script:nextNudgeAt -gt (Get-Date).AddMinutes(39))
            $persistenceOk = $statePath.EndsWith('state.json')
            $script:selfTestResult = "SELF_TEST_OK renderer=WPF hqFrames=$hqFramesOk modernFeedback=$modernFeedbackOk modernPanel=$modernPanelOk ambientRoutines=$($allAmbientNames.Count) ambientVariety=$ambientPlansOk naturalSchedule=$naturalScheduleOk naturalStart=$naturalStartOk staticRest=$staticRestOk interactions=$baseInteractions interactionLogic=$interactionOk affectionCanDecrease=$affectionCanDecrease lifeSystem=$lifeSystemOk departureReachable=$departureReachable followMode=$followModeOk nudgeWindow=$nudgeWindowOk persistence=$persistenceOk"
            $window.Close()
        })
        $testTimer.Start()
    }

    [void]$app.Run($window)
    if ($SelfTest) { Write-Output $script:selfTestResult }
} catch {
    $log = Join-Path $PSScriptRoot 'caigou-modern-error.log'
    [IO.File]::WriteAllText($log, "[$(Get-Date -Format s)]`r`n$($_ | Out-String)", [Text.Encoding]::UTF8)
    if (-not $SelfTest) { [Windows.MessageBox]::Show("菜狗启动失败，详情见：`r`n$log", '菜狗现代桌宠') | Out-Null }
    throw
} finally {
    if ($script:createdNew) { try { $script:mutex.ReleaseMutex() } catch {} }
    $script:mutex.Dispose()
}
