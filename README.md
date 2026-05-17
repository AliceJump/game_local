# 使用方式

前置说明：`gameBinDir` 必须设定，否则脚本无法找到游戏目录；游戏内启动方式见下方“游戏内部操作”。

## 游戏外部操作
> 提示：可以直接下载本仓库源包（Source code zip）后解压使用。  
> 提示：Release 自动打包文件不包含 `reshade` 目录；如需 ReShade，请下载源包。  

1. 移动游戏本体到本文件夹 `GameBin` 中。  
2. 按需编辑 `config.json`（详见[配置说明](#配置说明)）。如果不存在 `config.json`，脚本会在首次启动时提示你选择国服或外服模板，并自动复制生成 `config.json`。  
3. 点击 `点我.bat`。  

## MikuSB 目录要求
- 请将 MikuSB 程序放到仓库根目录下的 **`MikuSB-win-x64`** 文件夹中。  
- 启动脚本要求可执行文件路径为：`MikuSB-win-x64\MikuSB.exe`。  

## 配置说明

### 配置文件位置
`config.json` - 位于本仓库根目录，用于自定义游戏启动、补丁、可选项的行为。
`config-default.json` - 国服默认配置模板。
`config-international.json` - 外服默认配置模板。

### 执行语义
脚本里的模式统一遵循下面的规则：
- `on`：必须执行，失败就直接中断。
- `auto`：能执行就执行，不能执行就跳过，不中断。
- `off`：直接跳过。

文件类动作也统一成两种链路：
- 文本文件：先读取内容，再决定是否写回覆盖。
- 资源文件：先比对哈希，再决定是否覆盖复制。

### 配置结构

#### `paths` - 路径配置
| 配置项 | 可用值 | 默认值 | 说明 |
|-------|-------|--------|------|
| `gameBinDir` | **绝对路径** 或 相对路径 | `GameBin` | 游戏安装目录的父目录。**唯一支持绝对路径的项目**。如 `D:\GameInstall` 或 `GameBin` |
| `gameFolder` | 任意文件夹名 | `game` | 游戏根目录的文件夹名（位于 `gameBinDir` 下） |
| `reshadeDir` | 相对路径 | `reshade` | ReShade 配置目录（位于脚本根目录下） |
| `mikuExe` | 相对路径 | `MikuSB-win-x64/MikuSB.exe` | MikuSB 可执行文件路径 |
| `injectExe` | 相对路径 | `reshade/inject.exe` | ReShade Inject 工具路径 |

#### `patch` - 补丁控制
`patch` 是一个列表，每一项都是一个单键字典，key 为目录名，value 为同步方式。

支持的同步方式：`hash` / `incremental`

示例：
```json
"patch": [
  { "GM_Patch": "hash" },
  { "AntiHarmonyPatch": "hash" },
  { "Common_Patch": "hash" }
]
```

说明：脚本会同步这些目录下的全部 `.pak` 文件到 `Game\Content\Paks`。目录不存在或为空时会跳过。

#### `optional` - 可选功能
| 配置项 | 可用值 | 默认值 | 说明 |
|-------|-------|--------|------|
| `game` | `on` / `auto` / `off` | `on` | 游戏启动（Game.exe）。`on`=必须启动游戏，`auto`=尝试启动（失败则跳过），`off`=禁用游戏启动（Inject 和 Miku 仍会执行） |
| `localization` | `on` / `auto` / `off` | `auto` | 中文本地化。`on`=必须创建并启用，`auto`=能启用就启用，`off`=跳过 |
| `reshade` | `on` / `auto` / `off` | `auto` | ReShade 集成。同上 |

#### `launch` - 游戏启动参数
| 配置项 | 类型 | 默认值 | 说明 |
|-------|------|--------|------|
| `featureLevel` | 字符串 | `ES31` | 图形特性级别（`ES31` 为推荐） |
| `channelId` | 字符串 | `jinshan` | 渠道 ID |
| `gclid` | 字符串 | `CBJQ_setup` | Google Click ID（用于统计） |
| `hideGameWindow` | 布尔值 | `true` | 是否隐藏游戏窗口（最小化启动） |
| `noSplash` | 布尔值 | `false` | 是否禁用启动画面 |
| `mikuGameArg` | 布尔值 | `false` | MikuSB 启动时是否加上 `-game` 参数 |

### 配置示例

**最小配置（仅改游戏目录）：**
```json
{
  "paths": {
    "gameBinDir": "D:\\Programs\\steam\\steamapps\\common",
    "gameFolder": "SNOWBREAK"
  }
}
```

**完整配置示例：**
```json
{
  "paths": {
    "gameBinDir": "D:\\Programs\\steam\\steamapps\\common",
    "gameFolder": "SNOWBREAK",
    "reshadeDir": "reshade",
    "mikuExe": "MikuSB-win-x64/MikuSB.exe",
    "injectExe": "reshade/inject.exe"
  },
  "patch": [
    { "GM_Patch": "hash" },
    { "AntiHarmonyPatch": "hash" },
    { "Common_Patch": "hash" }
  ],
  "optional": {
    "game": "on",
    "localization": "auto",
    "reshade": "auto"
  },
  "launch": {
    "featureLevel": "ES31",
    "channelId": "jinshan",
    "gclid": "CBJQ_setup",
    "hideGameWindow": true
  }
}
```

**禁用所有补丁的配置：**
```json
{
  "patch": []
}
```

**启用增量同步（只补缺失 PAK）：**
```json
{
  "patch": [
    { "AntiHarmonyPatch": "incremental" }
  ]
}
```

## 游戏内部操作

### 国服
1. 先叉掉登录弹窗。  
2. 点击顶部 GM 按钮。  
3. 选择 功能 -> 常用类 -> 显示服务器列表。  
4. 点击右下角的执行。  
5. 点击右下角的服务器列表。  
6. 选择本地服务器。  
7. 将 `127.0.0.1` 后面的 `5000` 改成 `21000`。  
8. 点确定然后点新账号后可进入。  

### Steam 端
1. 查看 MIKUSB 提供的账户密码。  
2. 使用该账户密码登录。  
3. 点击下方黑框选择服务器后进入。  
