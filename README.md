# 使用方式

## 游戏外部操作
> 提示：可以直接下载本仓库源包（Source code zip）后解压使用。  
> 提示：Release 自动打包文件不包含 `reshade` 目录；如需 ReShade，请下载源包。  

1. 移动游戏本体到本文件夹 `CBJQ` 中。  
2. 按需编辑 `config.json`（`optional.localization` / `optional.reshade` 支持 `auto/on/off`，其中 `reshade` 默认 `off`）。  
3. 点击 `点我.bat`。  
4. `AntiHarmonyPatch` 自行添加到 `CBJQ\game\Game\Content\Paks` 中。  

## MikuSB 目录要求
- 请将 MikuSB 程序放到仓库根目录下的 **`MikuSB-win-x64`** 文件夹中。  
- 启动脚本要求可执行文件路径为：`MikuSB-win-x64\MikuSB.exe`。  

## 游戏内部操作
1. 先叉掉登录弹窗。  
2. 点击顶部 GM 按钮。  
3. 选择 功能 -> 常用类 -> 显示服务器列表。  
4. 点击右下角的执行。  
5. 点击右下角的服务器列表。  
6. 选择本地服务器。  
7. 将 `127.0.0.1` 后面的 `5000` 改成 `21000`。  
8. 点确定然后点新账号。  
