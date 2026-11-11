# 常见问题排查

按"现象 → 原因 → 处理"组织。

---

## F5 按下去没反应

**最常见的原因是没打开文件夹。**

`tasks.json` 是工作区级配置。用"打开文件"的方式（双击 `.cpp`、`code main.cpp`）时窗口没有工作区，任务不会被加载，`runTask` 找不到任务就静默什么都不做。

验证：

```powershell
code --status | Select-String 'Folder'
```

没有 `Folder (...)` 输出 = 没打开文件夹。用 **文件 → 打开文件夹** 重新打开题目目录即可。

其他可能：

| 检查项 | 怎么查 |
| --- | --- |
| 当前文件是不是 C/C++ | 右下角语言模式，或 `editorLangId` |
| 任务是否存在 | `Ctrl+Shift+P` → `Tasks: Run Task`，看列表里有没有「编译并运行 (F5)」 |
| 任务名是否被改过 | `keybindings.json` 里的 `args` 必须与 `tasks.json` 的 `label` **完全一致** |
| 是否处于调试会话中 | 调试时 F5 是"继续"，这是故意的（`when: !inDebugMode`） |

---

## 一运行 C++ 就弹窗让我安装 Linux（WSL）

**现象**：黑色控制台窗口提示"适用于 Linux 的 Windows 子系统必须更新到最新版本才能继续"，看起来像是 C++ 需要 Linux。

**原因**：跟 C++ 无关。VS Code 在枚举终端配置文件时会执行 `wsl.exe -l -q` 探测 WSL 发行版；没装 WSL 的机器上 `wsl.exe` 是个空壳，一被调用就拉起安装引导。

**处理**：用户 `settings.json` 加：

```json
"terminal.integrated.useWslProfiles": false
```

（本仓库的 `install.ps1` 已经写入。）详细分析见 [implementation.md](implementation.md) 第 3 节。

**临时应急**：那个窗口直接按 `Ctrl+C` 或关掉即可，不影响程序运行。

---

## 中文输出乱码

分三种情况，处理方式不同：

| 场景 | 处理 |
| --- | --- |
| `.bat` 里的中文被拆坏（`'件' is not recognized`） | **不要在 `.bat` 里写中文**。cmd 按 ANSI 代码页解析批处理，UTF-8 中文必坏 |
| C++ 程序 `cout` 中文乱码 | 源码保存为 UTF-8；终端代码页与编码不一致时考虑改用英文提示 |
| 中文注释在编辑器里正常但终端报错 | 文件编码是 GBK，用右下角编码切换成 UTF-8 重开 |

**不要**为了中文输出在 `.bat` 里加 `chcp 65001`：它会破坏被重定向的 stdin，导致 `< in.txt` 方式喂数据时程序读到空输入。

---

## 程序"神秘地"崩溃 / RE，但没有报错信息

大概率是**栈溢出**。MinGW 默认栈只有 2MB，深递归（线段树、树剖、DFS 搜状态、快速排序最坏情况）会直接崩，而且不一定有提示。

本仓库已默认加上：

```
-Wl,--stack=268435456
```

256MB。真要更大，改 `.vscode/run-cpp.bat` 里那一行即可（单位是字节）。

---

## exe 拷到别的电脑上打不开 / 缺 DLL

默认动态链接 `libstdc++-6.dll`、`libgcc_s_seh-1.dll`。本仓库用 `-static` 编译成独立 exe，就不会有这个问题。

如果自己想手动编译，加上 `-static`：

```
g++ -std=c++17 -O2 -static main.cpp -o main.exe
```

---

## 编译报 "g++ 不是内部或外部命令"

`.bat` 里的查找顺序是：先看 `C:\w64devkit\bin\g++.exe`，再退回 PATH 里的 `g++`。两个都找不到就会报这个错。

处理：装 [w64devkit](https://github.com/skeeto/w64devkit) 解压到 `C:\w64devkit`，或把 `run-cpp.bat` 开头的 `GXX` 改成你的 g++ 实际路径。

---

## CPH-NG 提示编译失败，但 F5 能编过

检查这两条配置是否指向真实存在的文件：

```json
"cph-ng.languages.cppCompiler": "C:\\w64devkit\\bin\\g++.exe",
"cph-ng.languages.cppObjcopy": "C:\\w64devkit\\bin\\objcopy.exe"
```

CPH-NG 编译时会把参数拆开逐个传给编译器，**路径不能带引号**，也不要用 `g++` 这种裸名字（PATH 里有多个 MinGW 时会解析到别的版本）。

另外 CPH-NG 有编译缓存：源码 hash 没变时跳过编译。如果换了编译器参数想强制重编，在面板里 `Ctrl` + 点运行按钮（Force Compile）。

---

## CPH-NG 的样例数据在哪，能提交到 git 吗

在 `.cph-ng/<文件名>.bin`，是 **gzip 压缩的 JSON**，里面记录了源码绝对路径（`src.path`），换机器/换目录后就对不上了。

**不建议提交**，本仓库的 `.gitignore` 已排除。要共享测试数据，用 `tests/*.in` / `*.ans` + 面板里的 `From folder` 导入，这才是可移植的格式。

---

## 在第三方终端里敲 `code` 直接闪退

如果父进程是 Electron 应用（某些 IDE、Electron 封装的工具），会继承 `ELECTRON_RUN_AS_NODE=1`，导致 `Code.exe` 被当成 Node 进程启动并以 exit code 9 退出。

处理：启动前清掉这个变量

```powershell
Remove-Item Env:ELECTRON_RUN_AS_NODE
code .
```

正常从开始菜单/桌面快捷方式启动不受影响。

---

## 任务终端一执行就关掉，看不到输出

`.vscode/tasks.json` 里每个任务都有：

```json
"presentation": { "reveal": "always", "panel": "dedicated" }
```

`dedicated` = 给这个任务单独一个终端面板，任务结束后面板保留，输出可回看。如果被改成 `shared` 或删掉，可能会复用别的终端导致看起来"闪一下就没了"。
