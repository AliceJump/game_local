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
$cbjqDir  = Join-Path $rootDir "GameBin"
$gameFolder = "game"
$gameRoot = Join-Path $cbjqDir $gameFolder

# ==================================================
# 检查汇总
# ==================================================
# 必要：GameBin 目录、游戏结构、Game.exe、PAK 自动修复、补丁同步、MikuSB
# 可选：localization=1、ReShade

function Sync-PakFiles($sourceDir, $targetDir, $label, $syncMode = "hash", $required = $false) {

    if (!(Test-Path $sourceDir)) {
        if ($required) { Fail "缺少 $label 目录：$sourceDir" }
        Write-Host "$label 目录不存在，跳过：$sourceDir"
        return
    }

    if (@("hash", "incremental") -notcontains $syncMode) {
        Fail "配置项 $label 同步模式仅支持 hash/incremental，当前值：$syncMode"
    }

    $sourcePaks = Get-ChildItem -Path $sourceDir -Filter *.pak -File -Recurse -ErrorAction Stop

    if (!$sourcePaks) {
        if ($required) { Fail "$label 目录中没有 pak 文件：$sourceDir" }
        Write-Host "$label 目录中没有 pak 文件，跳过：$sourceDir"
        return
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
            if ($syncMode -eq "incremental") {
                Write-Host "$label 已存在，跳过增量同步：$($sourcePak.Name)"
                $shouldCopy = $false
            }
            else {
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
# PAK / Patch List
# ==================================================

$pakTargetDir = Join-Path $gameDir "Content\Paks"

function Get-PatchEntries($patchConfig) {
    $defaultPatchEntries = @(
        [pscustomobject]@{ Directory = "GM_Patch"; SyncMode = "hash" },
        [pscustomobject]@{ Directory = "AntiHarmonyPatch"; SyncMode = "hash" },
        [pscustomobject]@{ Directory = "Common_Patch"; SyncMode = "hash" }
    )

    if ($null -eq $patchConfig) {
        return $defaultPatchEntries
    }

    $patchEntries = @()

    foreach ($patchItem in @($patchConfig)) {
        if ($null -eq $patchItem) {
            continue
        }

        $patchProperties = @($patchItem.PSObject.Properties | Where-Object { $_.MemberType -eq 'NoteProperty' })
        if ($patchProperties.Count -ne 1) {
            Fail "配置项 patch 的每一项必须且只能包含一个目录名和同步方式"
        }

        $directoryName = $patchProperties[0].Name
        $syncMode = $patchProperties[0].Value.ToString().ToLower()

        if (@("hash", "incremental") -notcontains $syncMode) {
            Fail "配置项 patch.$directoryName 仅支持 hash/incremental，当前值：$syncMode"
        }

        $patchEntries += [pscustomobject]@{
            Directory = $directoryName
            SyncMode = $syncMode
        }
    }

    return $patchEntries
}

# ==================================================
# 可选项状态
# ==================================================

$gameEnabled = $false
$localizationEnabled = $false
$reshadeEnabled = $false
$gameMode = "auto"
$localizationMode = "auto"
$reshadeMode = "auto"

# ==================================================
# 配置
$configFile = Join-Path $rootDir "config.json"
$configDefaultFile = Join-Path $rootDir "config-default.json"
$configInternationalFile = Join-Path $rootDir "config-international.json"
$configSourceFile = $configFile
$config = $null

$gameFeatureLevel = "ES31"
$gameChannelId = "jinshan"
$gameGclid = "CBJQ_setup"
$hideGameWindow = $true
$noSplash = $false
$mikuGameArg = $true

function Get-JsonConfig($path) {
    return Get-Content -Path $path -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
}

function Test-ModeAllowed($mode, $label) {
    if ((@("auto", "on", "off") -notcontains $mode)) {
        Fail "配置项 $label 仅支持 auto/on/off，当前值：$mode"
    }
}

function Set-TextFileIfNeeded($path, $content, $label, $required) {
    $current = $null

    if (Test-Path $path) {
        try {
            $current = (Get-Content -Path $path -ErrorAction Stop | Select-Object -First 1).Trim()
        }
        catch {
            if ($required) {
                Fail "配置要求启用 $label，但读取失败：$path"
            }
            Write-Host "读取 $label 失败，跳过：$path"
            return $false
        }

        if ($current -eq $content) {
            return $true
        }
    }

    try {
        Set-Content -Path $path -Value $content -Encoding ASCII
        return $true
    }
    catch {
        if ($required) {
            Fail "配置要求启用 $label，但写入失败：$path"
        }
        Write-Host "$label 写入失败，跳过：$path"
        return $false
    }
}

function Copy-FileByHash($sourcePath, $targetPath, $label, $required) {
    if (!(Test-Path $sourcePath)) {
        if ($required) {
            Fail "配置要求启用 $label，但源文件缺失：$sourcePath"
        }
        Write-Host "$label 源文件缺失，跳过：$sourcePath"
        return $false
    }

    $targetDir = Split-Path $targetPath -Parent
    if (!(Test-Path $targetDir)) {
        New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
    }

    if (Test-Path $targetPath) {
        try {
            $sourceHash = (Get-FileHash -Path $sourcePath -Algorithm SHA256 -ErrorAction Stop).Hash
            $targetHash = (Get-FileHash -Path $targetPath -Algorithm SHA256 -ErrorAction Stop).Hash

            if ($sourceHash -eq $targetHash) {
                Write-Host "$label 已同步：$(Split-Path -Leaf $sourcePath)"
                return $true
            }
        }
        catch {
            if ($required) {
                Fail "配置要求启用 $label，但哈希校验失败：$sourcePath"
            }
            Write-Host "$label 哈希校验失败，跳过：$sourcePath"
            return $false
        }
    }

    try {
        Copy-Item -Path $sourcePath -Destination $targetPath -Force
        Write-Host "$label 已复制：$(Split-Path -Leaf $sourcePath)"
        return $true
    }
    catch {
        if ($required) {
            Fail "配置要求启用 $label，但复制失败：$sourcePath"
        }
        Write-Host "$label 复制失败，跳过：$sourcePath"
        return $false
    }
}

function Test-InternationalConfigTarget($config) {
    if ($null -eq $config) { return $false }
    if ($null -eq $config.paths) { return $false }

    $gameBinDir = $null
    $gameFolder = $null

    if ($null -ne $config.paths.gameBinDir) { $gameBinDir = $config.paths.gameBinDir.ToString() }
    if ($null -ne $config.paths.gameFolder) { $gameFolder = $config.paths.gameFolder.ToString() }

    if ([string]::IsNullOrWhiteSpace($gameBinDir) -or [string]::IsNullOrWhiteSpace($gameFolder)) {
        return $false
    }

    return (Test-Path (Join-Path $gameBinDir $gameFolder))
}

if (!(Test-Path $configFile)) {
    Write-Host "未找到 config.json"
    Write-Host "请选择默认模板："
    Write-Host "1. 国服版本（config-default.json）"
    Write-Host "2. 外服版本（config-international.json）"

    $configChoice = Read-Host "请输入 1 或 2"

    switch ($configChoice) {
        "1" { $configSourceFile = $configDefaultFile }
        "2" { $configSourceFile = $configInternationalFile }
        default { Fail "无效选择：$configChoice" }
    }

    if (!(Test-Path $configSourceFile)) {
        Fail "缺少默认模板：$configSourceFile"
    }

    try {
        Copy-Item -Path $configSourceFile -Destination $configFile -Force
        Write-Host "已生成 config.json：$(Split-Path -Leaf $configSourceFile)"
    }
    catch {
        Fail "生成 config.json 失败：$($_.Exception.Message)"
    }
}

if ($null -eq $config) {
    try {
        $config = Get-JsonConfig $configFile
    }
    catch {
        Fail "配置文件读取失败：$configFile - $($_.Exception.Message)"
    }

    $configSourceFile = $configFile
}

if ($null -ne $config) {
    if ($null -ne $config.optional) {
        if ($null -ne $config.optional.game) { $gameMode = $config.optional.game.ToString().ToLower() }
        if ($null -ne $config.optional.localization) { $localizationMode = $config.optional.localization.ToString().ToLower() }
        if ($null -ne $config.optional.reshade) { $reshadeMode = $config.optional.reshade.ToString().ToLower() }
    }

    if ($null -ne $config.launch) {
        if ($null -ne $config.launch.featureLevel) { $gameFeatureLevel = $config.launch.featureLevel.ToString() }
        if ($null -ne $config.launch.channelId) { $gameChannelId = $config.launch.channelId.ToString() }
        if ($null -ne $config.launch.gclid) { $gameGclid = $config.launch.gclid.ToString() }
        if ($null -ne $config.launch.hideGameWindow) { $hideGameWindow = [bool]$config.launch.hideGameWindow }
        if ($null -ne $config.launch.noSplash) { $noSplash = [bool]$config.launch.noSplash }
        if ($null -ne $config.launch.mikuGameArg) { $mikuGameArg = [bool]$config.launch.mikuGameArg }
    }

    function Resolve-ConfiguredPath($p, $allowRooted) {
        if ($null -eq $p) { return $null }
        $s = $p.ToString()
        if ([System.IO.Path]::IsPathRooted($s)) {
            if ($allowRooted) { return $s }
            else { Fail "配置项路径 '$s' 不允许使用绝对路径，请改为相对于脚本目录的相对路径" }
        }
        return Join-Path $rootDir $s
    }

    if ($null -ne $config.paths) {
        if ($null -ne $config.paths.gameBinDir) { $cbjqDir = Resolve-ConfiguredPath $config.paths.gameBinDir $true }
        if ($null -ne $config.paths.gameFolder) { $gameFolder = $config.paths.gameFolder.ToString() }
        if ($null -ne $config.paths.reshadeDir) { $reshadeRoot = Resolve-ConfiguredPath $config.paths.reshadeDir $false }
        if ($null -ne $config.paths.injectExe) { $injectExe = Resolve-ConfiguredPath $config.paths.injectExe $false }
        if ($null -ne $config.paths.mikuExe) { $mikuExe = Resolve-ConfiguredPath $config.paths.mikuExe $false }
    }

    Test-ModeAllowed $gameMode "optional.game"
    Test-ModeAllowed $localizationMode "optional.localization"
    Test-ModeAllowed $reshadeMode "optional.reshade"

    if ($gameMode -eq "on") { $gameEnabled = $true }
    elseif ($gameMode -eq "auto") { $gameEnabled = $true }

    if ($localizationMode -eq "on") { $localizationEnabled = $true }
    elseif ($localizationMode -eq "auto") { $localizationEnabled = $true }

    if ($reshadeMode -eq "on") { $reshadeEnabled = $true }
    elseif ($reshadeMode -eq "auto") { $reshadeEnabled = $true }

    # 重新计算与 game 相关的路径
    $gameRoot = Join-Path $cbjqDir $gameFolder
    $engineDir = Join-Path $gameRoot "Engine"
    $gameDir   = Join-Path $gameRoot "Game"
    $gameExe = Join-Path $gameDir "Binaries\Win64\Game.exe"
    $win64Dir = Join-Path $gameDir "Binaries\Win64"
    $pakTargetDir = Join-Path $gameDir "Content\Paks"

    # ReShade 目标路径
    $targetShadersDir = Join-Path $win64Dir "reshade-shaders"
    $iniSource        = Join-Path $reshadeRoot "ReShade.ini"
    $presetSource     = Join-Path $reshadeRoot "ReShadePreset.ini"
    $iniTarget        = Join-Path $win64Dir "ReShade.ini"
    $presetTarget     = Join-Path $win64Dir "ReShadePreset.ini"

    $patchEntries = Get-PatchEntries $config.patch

    # 其他
    $userDir   = $gameRoot
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
# 检查 GameBin（可选）
# ==================================================

$programFolderPresent = $true
if (!(Test-Path $cbjqDir)) {
    Write-Host "缺少 GameBin 目录，跳过与程序文件夹相关的操作：$cbjqDir"
    $programFolderPresent = $false
}

# ==================================================
# 检查结构
# ==================================================

if ($programFolderPresent) {
    if (!(Test-Path $gameRoot) -or !(Test-Path $engineDir) -or !(Test-Path $gameDir)) {
        Fail "游戏目录结构错误"
    }
}
else {
    Write-Host "跳过游戏目录结构检查（GameBin 不存在）"
}

# ==================================================
# Game.exe
# ==================================================

# Game.exe 检查
if ($programFolderPresent) {
    if (!(Test-Path $gameExe)) {
        Fail "缺失 Game.exe：$gameExe"
    }
}
else {
    Write-Host "跳过 Game.exe 检查（GameBin 不存在）"
}

# ==================================================
# 必要项完成后再进入可选项
# ==================================================

Write-Host "必要项检查完成，开始检查可选项..."

# ==================================================
# localization 检查（可选，自动修正）
# ==================================================

if ($programFolderPresent) {
    $localizationFile = Join-Path $cbjqDir "localization.txt"

    switch ($localizationMode) {
        'off' {
            Write-Host "配置关闭 localization，跳过 localization 分支"
        }
        'on' {
            if (Set-TextFileIfNeeded $localizationFile "localization = 1" "localization" $true) {
                $localizationEnabled = $true
                Write-Host "localization 已启用"
            }
        }
        default {
            if (Set-TextFileIfNeeded $localizationFile "localization = 1" "localization" $false) {
                $localizationEnabled = $true
                Write-Host "localization 已同步"
            }
            else {
                Write-Host "localization 跳过"
            }
        }
    }
}
else {
    Write-Host "跳过 localization 检查（GameBin 不存在）"
}

# ==================================================
# PAK 自动修复
# ==================================================

$pakDir = $pakTargetDir

if ($programFolderPresent) {
    Write-Host "=== PAK 同步 ==="

    foreach ($patchEntry in $patchEntries) {
        $patchSourceDir = Join-Path $rootDir $patchEntry.Directory
        Sync-PakFiles -sourceDir $patchSourceDir -targetDir $pakTargetDir -label $patchEntry.Directory -syncMode $patchEntry.SyncMode
    }
}
else {
    Write-Host "跳过 PAK 自动修复（GameBin 不存在）"
}

# ==================================================
# ReShade 检查（可选）
# ==================================================

Write-Host "=== ReShade 检查 ==="

if ($programFolderPresent) {
    switch ($reshadeMode) {
        'off' {
            Write-Host "配置关闭 ReShade，跳过 ReShade 分支"
        }
        default {
            if ((Test-Path $reshadeRoot) -and (Test-Path $reshadeShaders) -and (Test-Path $injectExe)) {
                $reshadeReady = $true

                if (!(Test-Path $targetShadersDir)) {
                    try {
                        New-Item -ItemType Junction -Path $targetShadersDir -Target $reshadeShaders -Force | Out-Null
                        Write-Host "Shaders 已创建 Junction"
                    }
                    catch {
                        Write-Host "Junction失败，改复制..."

                        try {
                            Copy-Item -Path $reshadeShaders -Destination $targetShadersDir -Recurse -Force
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

                if ($reshadeReady) { $reshadeReady = (Copy-FileByHash $iniSource $iniTarget "ReShade.ini" ($reshadeMode -eq "on")) }
                if ($reshadeReady) { $reshadeReady = (Copy-FileByHash $presetSource $presetTarget "ReShadePreset.ini" ($reshadeMode -eq "on")) }

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
        }
    }
}
else {
    Write-Host "跳过 ReShade 检查（GameBin 不存在）"
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
Write-Host "可选项状态：game=$gameEnabled, localization=$localizationEnabled, ReShade=$reshadeEnabled"
Write-Host "可选项配置：gameMode=$gameMode, localizationMode=$localizationMode, reshadeMode=$reshadeMode"
Write-Host "必要项状态：MikuSB=ready"
Write-Host ""

# ==================================================
# Inject & Game & Miku
# ==================================================

# Inject
Write-Host "=== Inject ==="

if (Test-Path $injectExe) {
    Start-Process `
        -FilePath $injectExe `
        -WorkingDirectory (Split-Path $injectExe) `
        -ArgumentList '"Game.exe"'

    Start-Sleep -Milliseconds 500

    Write-Host "Inject OK"
}
else {
    if ($gameMode -eq "on") {
        Fail "Inject 不存在：$injectExe"
    }
    else {
        Write-Host "跳过 Inject（inject.exe 不存在）"
    }
}

# Game - 仅当 game 开关为 on/auto 时执行
if ($gameEnabled) {
    Write-Host "=== Game ==="

    if (Test-Path $gameExe) {
        $windowStyle = if ($hideGameWindow) { "Hidden" } else { "Normal" }
        $gameArgs = @(
            "-FeatureLevel$gameFeatureLevel"
            "-channelid=$gameChannelId"
            "-userdir=`"$gameRoot`""
            "-gclid=$gameGclid"
        )

        if ($noSplash) {
            $gameArgs += "-NoSplash"
        }

        Start-Process `
            -FilePath $gameExe `
            -WorkingDirectory (Split-Path $gameExe) `
            -ArgumentList $gameArgs `
            -WindowStyle $windowStyle

        Write-Host "Game OK"
    }
    else {
        if ($gameMode -eq "on") {
            Fail "Game.exe 不存在：$gameExe"
        }
        else {
            Write-Host "跳过 Game（Game.exe 不存在）"
        }
    }
}
else {
    Write-Host "=== Game ==="
    Write-Host "跳过 Game（game 开关已关闭）"
}

# Miku
Write-Host "=== Miku ==="

if (Test-Path $mikuExe) {
    $mikuArgs = @()
    if ($mikuGameArg) {
        $mikuArgs += "-game"
    }

    Start-Process `
        -FilePath $mikuExe `
        -WorkingDirectory (Split-Path $mikuExe) `
        -ArgumentList $mikuArgs
    Write-Host "Miku OK"
}
else {
    if ($gameMode -eq "on") {
        Fail "MikuSB 不存在：$mikuExe"
    }
    else {
        Write-Host "跳过 Miku（MikuSB 不存在）"
    }
}

# ==================================================
# 完成
# ==================================================

Write-Host ""
Write-Host "全部流程完成"

exit 0
