# ==================================================
# 错误退出
# ==================================================

function Fail($msg) {
    Write-Host ""
    Write-Host $msg -ForegroundColor Red
    Write-Host ""
    Pause
    exit 1
}

# ==================================================
# 根目录
# ==================================================

$rootDir = $PSScriptRoot
$cbjqDir  = Join-Path $rootDir "CBJQ"
$gameRoot = Join-Path $cbjqDir "game"

# ==================================================
# 检查汇总
# ==================================================
# 必要：CBJQ 目录、游戏结构、Game.exe、PAK 自动修复、补丁同步、MikuSB
# 可选：localization=1、ReShade

function Sync-PakFiles($sourceDir, $targetDir, $label) {

    if (!(Test-Path $sourceDir)) {
        Fail "缺少 $label 目录：$sourceDir"
    }

    $sourcePaks = Get-ChildItem -Path $sourceDir -Filter *.pak -File -Recurse -ErrorAction Stop

    if (!$sourcePaks) {
        Fail "$label 目录中没有 pak 文件：$sourceDir"
    }

    if (!(Test-Path $targetDir)) {
        New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
    }

    foreach ($sourcePak in $sourcePaks) {

        $relativePath = $sourcePak.FullName.Substring($sourceDir.Length).TrimStart('\', '/')
        $targetPak = Join-Path $targetDir $relativePath
        $targetPakDir = Split-Path $targetPak -Parent
        $shouldCopy = $true

        if (!(Test-Path $targetPakDir)) {
            New-Item -ItemType Directory -Path $targetPakDir -Force | Out-Null
        }

        if (Test-Path $targetPak) {

            try {
                $sourceHash = (Get-FileHash -Path $sourcePak.FullName -Algorithm SHA256 -ErrorAction Stop).Hash
                $targetHash = (Get-FileHash -Path $targetPak -Algorithm SHA256 -ErrorAction Stop).Hash

                if ($sourceHash -eq $targetHash) {
                    Write-Host "$label 已同步：$($sourcePak.Name)"
                    $shouldCopy = $false
                }
                else {
                    Write-Host "$label 哈希不一致，准备覆盖：$($sourcePak.Name)"
                }
            }
            catch {
                Write-Host "$label 哈希校验失败，准备覆盖：$($sourcePak.Name)"
            }
        }
        else {
            Write-Host "$label 缺失，准备复制：$($sourcePak.Name)"
        }

        if ($shouldCopy) {
            Copy-Item `
                -Path $sourcePak.FullName `
                -Destination $targetPak `
                -Force

            Write-Host "$label 已复制：$($sourcePak.Name)"
        }
    }
}

# ==================================================
# 路径
# ==================================================

$engineDir = Join-Path $gameRoot "Engine"
$gameDir   = Join-Path $gameRoot "Game"

$gameExe = Join-Path $gameDir "Binaries\Win64\Game.exe"

$win64Dir = Join-Path $gameDir "Binaries\Win64"

# ==================================================
# PAK / GM_Patch
# ==================================================

$pakFile = Join-Path $gameDir "Content\Paks\Patch_GM-Windows_100_P.pak"

$gmPatchDir    = Join-Path $rootDir "GM_Patch"
$gmPatchSource = Join-Path $gmPatchDir "Patch_GM-Windows_100_P.pak"

# ==================================================
# 可选项状态
# ==================================================

$localizationEnabled = $false
$reshadeEnabled = $false
$localizationMode = "auto"
$reshadeMode = "off"

# ==================================================
# 配置
# ==================================================

$configFile = Join-Path $rootDir "config.json"

$gameFeatureLevel = "ES31"
$gameChannelId = "jinshan"
$gameGclid = "CBJQ_setup"
$hideGameWindow = $true

if (Test-Path $configFile) {
    try {
        $config = Get-Content -Path $configFile -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        Fail "配置文件读取失败：$configFile - $($_.Exception.Message)"
    }

    if ($null -ne $config.optional) {
        if ($null -ne $config.optional.localization) {
            $localizationMode = $config.optional.localization.ToString().ToLower()
        }
        if ($null -ne $config.optional.reshade) {
            $reshadeMode = $config.optional.reshade.ToString().ToLower()
        }
    }

    if ($null -ne $config.launch) {
        if ($null -ne $config.launch.featureLevel) {
            $gameFeatureLevel = $config.launch.featureLevel.ToString()
        }
        if ($null -ne $config.launch.channelId) {
            $gameChannelId = $config.launch.channelId.ToString()
        }
        if ($null -ne $config.launch.gclid) {
            $gameGclid = $config.launch.gclid.ToString()
        }
        if ($null -ne $config.launch.hideGameWindow) {
            $hideGameWindow = [bool]$config.launch.hideGameWindow
        }
    }
}

if (@("auto", "on", "off") -notcontains $localizationMode) {
    Fail "配置项 optional.localization 仅支持 auto/on/off，当前值：$localizationMode"
}

if (@("auto", "on", "off") -notcontains $reshadeMode) {
    Fail "配置项 optional.reshade 仅支持 auto/on/off，当前值：$reshadeMode"
}

# ==================================================
# ReShade
# ==================================================

$reshadeRoot      = Join-Path $rootDir "reshade"
$reshadeShaders   = Join-Path $reshadeRoot "reshade-shaders"

$targetShadersDir = Join-Path $win64Dir "reshade-shaders"

$iniSource        = Join-Path $reshadeRoot "ReShade.ini"
$presetSource     = Join-Path $reshadeRoot "ReShadePreset.ini"

$iniTarget        = Join-Path $win64Dir "ReShade.ini"
$presetTarget     = Join-Path $win64Dir "ReShadePreset.ini"

# ==================================================
# 其他
# ==================================================

$userDir   = $gameRoot
$injectExe = Join-Path $rootDir "reshade\inject.exe"
$mikuExe   = Join-Path $rootDir "MikuSB-win-x64\MikuSB.exe"

# ==================================================
# 检查 CBJQ
# ==================================================

if (!(Test-Path $cbjqDir)) {
    Fail "缺少 CBJQ 目录：$cbjqDir"
}

# ==================================================
# 检查结构
# ==================================================

if (!(Test-Path $gameRoot) -or !(Test-Path $engineDir) -or !(Test-Path $gameDir)) {
    Fail "游戏目录结构错误"
}

# ==================================================
# Game.exe
# ==================================================

if (!(Test-Path $gameExe)) {
    Fail "缺失 Game.exe：$gameExe"
}

# ==================================================
# 必要项完成后再进入可选项
# ==================================================

Write-Host "必要项检查完成，开始检查可选项..."

# ==================================================
# localization 检查（可选，自动修正）
# ==================================================

$localizationFile = Join-Path $cbjqDir "localization.txt"
$localizationValue = $null

if ($localizationMode -eq "off") {
    Write-Host "配置关闭 localization，跳过 localization 分支"
}
else {
    if (!(Test-Path $localizationFile)) {
        if ($localizationMode -eq "on") {
            try {
                Set-Content -Path $localizationFile -Value "localization = 1" -Encoding ASCII
                $localizationEnabled = $true
                Write-Host "localization.txt 不存在，已按配置创建并设置为 1"
            }
            catch {
                Fail "配置要求启用 localization，但创建 localization.txt 失败：$localizationFile"
            }
        }
        else {
            Write-Host "localization.txt 不存在，跳过 localization 分支"
        }
    }
    else {
        try {
            $localizationValue = (Get-Content -Path $localizationFile -ErrorAction Stop | Select-Object -First 1).Trim()
        }
        catch {
            if ($localizationMode -eq "on") {
                Fail "配置要求启用 localization，但读取 localization.txt 失败：$localizationFile"
            }
            else {
                Write-Host "读取 localization.txt 失败，跳过 localization 分支：$localizationFile"
            }
        }

        if ($localizationValue -match '^localization\s*=\s*1$') {
            $localizationEnabled = $true
            Write-Host "localization=1，启用 localization 分支"
        }
        elseif ($null -ne $localizationValue) {
            try {
                Set-Content -Path $localizationFile -Value "localization = 1" -Encoding ASCII
                $localizationEnabled = $true
                Write-Host "localization 已修正为 1"
            }
            catch {
                if ($localizationMode -eq "on") {
                    Fail "配置要求启用 localization，但修正 localization 失败：$localizationFile"
                }
                else {
                    Write-Host "localization 修正失败，跳过 localization 分支：$localizationFile"
                }
            }
        }
    }
}

# ==================================================
# PAK 自动修复（GM_Patch）
# ==================================================

$pakDir = Split-Path $pakFile -Parent

if (!(Test-Path $pakFile)) {

    Write-Host "未找到 PAK，尝试复制 GM_Patch..."

    $pakDir = Split-Path $pakFile -Parent

    if (!(Test-Path $pakDir)) {
        New-Item -ItemType Directory -Path $pakDir -Force | Out-Null
    }

    if (Test-Path $gmPatchSource) {

        Copy-Item `
            -Path $gmPatchSource `
            -Destination $pakFile `
            -Force

        Write-Host "PAK 已复制"
    }
    else {
        Fail "缺失 GM_Patch：$gmPatchSource"
    }
}

# ==================================================
# AntiHarmonyPatch 同步
# ==================================================

Write-Host "=== AntiHarmonyPatch 同步 ==="
Write-Host "目标目录：$pakDir"

$antiHarmonyDir = Join-Path $rootDir "AntiHarmonyPatch"

Sync-PakFiles `
    -sourceDir $antiHarmonyDir `
    -targetDir $pakDir `
    -label "AntiHarmonyPatch"

# ==================================================
# ReShade 检查（可选）
# ==================================================

Write-Host "=== ReShade 检查 ==="

if ($reshadeMode -eq "off") {
    Write-Host "配置关闭 ReShade，跳过 ReShade 分支"
}
elseif ((Test-Path $reshadeRoot) -and (Test-Path $reshadeShaders) -and (Test-Path $injectExe)) {

    $reshadeReady = $true

    if (!(Test-Path $targetShadersDir)) {

        try {

            New-Item `
                -ItemType Junction `
                -Path $targetShadersDir `
                -Target $reshadeShaders `
                -Force | Out-Null

            Write-Host "Shaders 已创建 Junction"
        }
        catch {

            Write-Host "Junction失败，改复制..."

            try {
                Copy-Item `
                    -Path $reshadeShaders `
                    -Destination $targetShadersDir `
                    -Recurse `
                    -Force

                Write-Host "Shaders 已复制"
            }
            catch {
                $reshadeReady = $false
                Write-Host "Shaders 处理失败，跳过 ReShade 分支"
            }
        }
    }
    else {
        Write-Host "Shaders 已存在"
    }

    if ($reshadeReady -and !(Test-Path $iniTarget)) {

        if (Test-Path $iniSource) {

            try {
                Copy-Item `
                    -Path $iniSource `
                    -Destination $iniTarget `
                    -Force

                Write-Host "ReShade.ini 已复制"
            }
            catch {
                $reshadeReady = $false
                Write-Host "ReShade.ini 复制失败，跳过 ReShade 分支"
            }
        }
        else {
            $reshadeReady = $false
            Write-Host "缺少 ReShade.ini 源文件，跳过 ReShade 分支"
        }
    }
    elseif ($reshadeReady) {
        Write-Host "ReShade.ini 已存在"
    }

    if ($reshadeReady -and !(Test-Path $presetTarget)) {

        if (Test-Path $presetSource) {

            try {
                Copy-Item `
                    -Path $presetSource `
                    -Destination $presetTarget `
                    -Force

                Write-Host "ReShadePreset.ini 已复制"
            }
            catch {
                $reshadeReady = $false
                Write-Host "ReShadePreset.ini 复制失败，跳过 ReShade 分支"
            }
        }
        else {
            $reshadeReady = $false
            Write-Host "缺少 ReShadePreset.ini 源文件，跳过 ReShade 分支"
        }
    }
    elseif ($reshadeReady) {
        Write-Host "ReShadePreset.ini 已存在"
    }

    if ($reshadeReady) {
        $reshadeEnabled = $true
        Write-Host "ReShade 分支已准备好"
    }
}
else {
    if ($reshadeMode -eq "on") {
        Fail "配置要求启用 ReShade，但 ReShade 相关文件缺失"
    }
    else {
        Write-Host "ReShade 相关文件缺失，跳过 ReShade 分支"
    }
}

# ==================================================
# Miku 检查（必要）
# ==================================================

Write-Host "=== Miku 检查 ==="

if (Test-Path $mikuExe) {
    Write-Host "MikuSB 已准备好"
}
else {
    Fail "MikuSB 不存在：$mikuExe"
}

# ==================================================
# 启动前所有检查已完成

Write-Host ""
Write-Host "=== 检查汇总完成 ==="
Write-Host "必要项全部通过，准备进入启动阶段"
Write-Host "可选项状态：localization=$localizationEnabled, ReShade=$reshadeEnabled"
Write-Host "可选项配置：localizationMode=$localizationMode, reshadeMode=$reshadeMode"
Write-Host "必要项状态：MikuSB=ready"
Write-Host ""

# ==================================================
# Inject
# ==================================================

Write-Host "=== Inject ==="

if ($reshadeEnabled) {

    Start-Process `
        -FilePath $injectExe `
        -WorkingDirectory (Split-Path $injectExe) `
        -ArgumentList '"Game.exe"'

    Start-Sleep -Milliseconds 500

    Write-Host "Inject OK"
}
else {
    Write-Host "跳过 Inject"
}

# ==================================================
# Game
# ==================================================

Write-Host "=== Game ==="

$windowStyle = if ($hideGameWindow) { "Hidden" } else { "Normal" }

Start-Process `
    -FilePath $gameExe `
    -WorkingDirectory (Split-Path $gameExe) `
    -ArgumentList @(
        "-FeatureLevel$gameFeatureLevel"
        "-ChannelID=$gameChannelId"
        "-userdir=`"$userDir`""
        "-gclid=$gameGclid"
    ) `
    -WindowStyle $windowStyle

Write-Host "Game OK"

# ==================================================
# Miku
# ==================================================

Write-Host "=== Miku ==="

Start-Process `
    -FilePath $mikuExe `
    -WorkingDirectory (Split-Path $mikuExe)

Write-Host "Miku OK"

# ==================================================
# 完成
# ==================================================

Write-Host ""
Write-Host "全部流程完成"

exit 0
