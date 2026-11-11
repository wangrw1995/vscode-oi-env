# 实现说明：每条配置为什么这么写

这份文档解释仓库里每个文件的来由，以及踩过的坑。想改参数、或者想弄明白"为什么不是简单地在 tasks.json 里写一行 g++ 命令"，看这里。

---

## 1. 为什么用 `.bat` 包一层，而不是任务里直接写 g++ 命令

最直观的写法是：

```json
{ "type": "shell", "command": "g++ ${file} -o ${fileDirname}\\${fileBasenameNoExtension}.exe && ${fileDirname}\\${fileBasenameNoExtension}.exe" }
```

实际不可行，原因有三：

1. **`&&` 在 Windows PowerShell 5.1 里不存在**。而 VS Code 的默认终端配置文件就是 `powershell.exe`（5.1）。用 `&&` 会直接语法报错。PowerShell 7 才支持 `&&`，不能假定用户装了。
2. **引号嵌套地狱**。路径带空格时，`"${fileDirname}\\..."` 这种嵌套引号在 task → shell → 程序三层之间转义，极易出错且难排查。
3. **参数要统一、要能改**。`-O2`、`-Wl,--stack=...`、`-static` 这些应该集中在一处，而不是散落在 JSON 字符串里。

所以最终结构是：**tasks.json 只负责"调用"**，**`.bat` 负责"编译 + 运行"**。改编译参数只需要动 `.bat` 里那一行。

### 1.1 编译参数的选择

```
g++ -std=c++17 -O2 -Wall -Wl,--stack=268435456 -static main.cpp -o main.exe
```

| 参数 | 为什么 |
| --- | --- |
| `-std=c++17` | 目前大多数 OJ（洛谷、Codeforces）的默认语言标准，比 C++14 宽、比 C++20 稳 |
| `-O2` | 和评测机一致。用 `-O0` 会让常数大的题在本地跑得过、交上去 TLE |
| `-Wall` | 打开常用警告（未使用变量、隐式窄化），能在编译期抓住一部分低级错误 |
| `-Wl,--stack=268435456` | **最关键的一条**。MinGW 默认栈只有 2MB，深递归（线段树、树剖、DFS 搜状态）会直接栈溢出崩溃，看起来像"神秘 RE"。给到 256MB |
| `-static` | 生成不依赖 `libstdc++-6.dll` 的独立 exe。否则拷到别人机器上会报缺 DLL |

### 1.2 为什么 `.bat` 里绝不写中文

cmd.exe 解析批处理文件时，是**按当前控制台的 ANSI 代码页**（中文系统 = GBK/936）逐字节读的，而不是 UTF-8。如果 `.bat` 以 UTF-8 保存并写了中文，会出现两种故障：

- 报 `'件' is not recognized as an internal or external command`（一行中文被拆成多段）
- 更隐蔽的：某一行恰好吃掉了 `if` / `(` 的结构，导致整个流程静默跳过

我在这里实际踩过一次：第一版脚本里写了 `echo [编译]`，结果整个编译步骤没执行、只输出了一句莫名其妙的报错。

**结论**：脚本内的提示语一律用 ASCII（`[BUILD]` / `[RUN]` / `[DONE]`），中文只出现在 README 和 JSON 配置里。

### 1.3 为什么没有 `chcp 65001`

一开始为了"让程序输出中文不乱码"，在 `.bat` 开头加了 `chcp 65001`。结果发现：**`chcp 65001` 会把被重定向的 stdin 弄坏**。实测对比：

| 命令 | 结果 |
| --- | --- |
| `run.bat a.exe < in.txt`（带 `chcp 65001`） | 程序读到空输入，无输出 |
| 同上，去掉 `chcp` | 正常输出 |
| `type in.txt \| run.bat a.exe`（管道） | 两种情况都正常 |

原因是切换代码页会影响 conhost 对输入句柄的处理。为了不吃这个亏，最终放弃 `chcp`：OI 的输出以数字和 ASCII 为主，不值得为它引入一个会破坏 stdin 的副作用。

---

## 2. F5 为什么绑到 `workbench.action.tasks.runTask`

### 2.1 不能直接用默认 F5

VS Code 默认 `F5` = `workbench.action.debug.start`，也就是"进入调试"。它会启动 cppdbg 调试适配器、加载符号、停在 `main`（取决于配置），对"改一行、跑一下、看输出"的 OI 循环太重了，而且程序结束的控制台行为也不受控。

### 2.2 也不能绑 `workbench.action.tasks.build`

`tasks.build` 只会跑"默认生成任务"。概念上它是"编译"，把"编译并运行"塞进去会让 `Ctrl+Shift+B` 的语义也变得奇怪（按编译键却运行了程序）。

所以绑 `runTask` 并指定任务名：

```json
{
  "key": "f5",
  "command": "workbench.action.tasks.runTask",
  "args": "编译并运行 (F5)",
  "when": "!inDebugMode && (editorLangId == cpp || editorLangId == c)"
}
```

### 2.3 三个细节

- **`args` 必须是任务 `label` 的精确字符串**。任务重命名后这里要同步改，否则按 F5 会弹出一个"选择任务"的列表而不是直接运行——表现就是"按了没反应"。
- **`!inDebugMode` 不能少**。调试会话进行中时，`F5` 是"继续执行（Continue）"。不加这个条件，调试时按 F5 会去跑任务，断点调试直接废掉。
- **`editorLangId == cpp || c`**：只在 C/C++ 文件里劫持 F5。Python 的 F5 仍然是标准调试（对 Python 来说调试比裸跑更有用）。

### 2.4 F5 必须"打开文件夹"

这是 VS Code 的机制：`tasks.json` 属于**工作区**（workspace）级配置。用 `code main.cpp` 这种"单独打开一个文件"的方式，窗口没有工作区文件夹，`.vscode/tasks.json` 根本不会被加载，`runTask` 找不到任务 → 表现为按 F5 毫无反应。

排查方法：看 `code --status` 里有没有 `Folder (...)` 段落。

> 这个坑我排查了很久：一开始误以为是键盘绑定没生效，最后发现是测试时用 `-g file.cpp` 启动、窗口根本没打开文件夹。

---

## 3. 终端配置：为什么要关掉 WSL 探测

`settings.json` 里这几行不是"个人喜好"，是为了消除一个具体的骚扰弹窗：

```json
"terminal.integrated.useWslProfiles": false,
"terminal.integrated.profiles.windows": {
  "PowerShell": { "path": "C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe", "args": [] },
  "Command Prompt": { "path": "C:\\Windows\\System32\\cmd.exe", "args": [] }
},
"terminal.integrated.automationProfile.windows": { "...powershell.exe..." }
```

### 3.1 现象

没装 WSL 的机器上，一运行程序（或开终端）就弹出一个黑窗口：

```
适用于 Linux 的 Windows 子系统必须更新到最新版本才能继续。
按任意键安装适用于 Linux 的 Windows 子系统。
```

看起来像"C++ 要求安装 Linux"，实际跟 C++ 毫无关系。

### 3.2 根因

VS Code 在**枚举终端配置文件**时，会执行 `wsl.exe -l -q` 去列出 WSL 发行版，用来生成 "Ubuntu (WSL)" 这类终端选项。相关代码在 `resources/app/out/mainImpl.js`：

```js
exec("wsl.exe -l -q", { encoding: "utf16le", env: { ...process.env, WSL_UTF8: "0" }, timeout: 1000 }, ...)
// 失败时静默跳过，只写一条 trace: "WSL is not installed, so could not detect WSL profiles"
```

而在没装 WSL 的 Windows 11 上，`C:\Windows\System32\wsl.exe` 是个**空壳**：任何调用都会拉起那个交互式安装引导（甚至再 spawn 一个 `wsl.exe --update --confirm --prompt-before-exit`）。

### 3.3 证据

用 WMI 进程事件监视器做 A/B 对比：

| 操作 | 是否抓到 `wsl.exe` |
| --- | --- |
| 修复前，冷启动 VS Code（两次） | 两次都抓到 `wsl.exe --update --confirm --prompt-before-exit` |
| 修复后，冷启动 + 反复开终端 + 按 F5 | **0 次** |

### 3.4 修复

`terminal.integrated.useWslProfiles: false` 是根因开关，直接跳过那段探测。同时显式声明 `profiles.windows`，让 VS Code **不做**任何自动探测（Git Bash、Cygwin 也一并不探测），保证终端永远是 PowerShell。

`automationProfile.windows` 单独指定，是因为**任务**（`Ctrl+Shift+B`、F5 触发的构建）走的是 automation profile，它默认会跟随默认终端配置；显式钉死可以保证任务永远在 PowerShell 里跑。

---

## 4. CPH-NG 样例评测的配置

### 4.1 选型

- 原版 **CPH**（`DivyanshuAgrawal.competitive-programming-helper`）已停止维护。
- **CPH-NG**（`langningchen.cph-ng`）是社区维护的分支，v0.7.13，带中文界面，判定结果从 3 种扩到 11 种（AC PC PE WA TLE OLE RE CE SE SK RJ），并新增对拍、本地样例加载、编译缓存。

### 4.2 关键设置

```json
"cph-ng.languages.cppCompiler": "C:\\w64devkit\\bin\\g++.exe",
"cph-ng.languages.cppCompilerArgs": "-O2 -std=c++17 -Wall -DCPH -Wl,--stack=268435456",
"cph-ng.languages.cppObjcopy": "C:\\w64devkit\\bin\\objcopy.exe",
"cph-ng.sidebar.showOobe": false
```

- **编译器写绝对路径**。默认值是裸 `g++`，靠 PATH 解析；机器上若有多个 MinGW（或 PATH 顺序变了）会悄悄用错版本。
- **参数与 F5 对齐**（少了 `-static`，判题不需要可移植的 exe）。这样"本地跑得过"和"F5 跑得过"结论一致。
- **`-DCPH`** 是 CPH-NG 约定的宏，用来在代码里区分"评测环境"。
- **`showOobe: false`** 关掉首次引导弹窗，直接可用。

### 4.3 数据存在哪

题目数据保存在工作区的 `.cph-ng/<文件名>.bin`，内容其实是 **gzip 压缩的 JSON**：

```json
{
  "version": "0.7.13",
  "name": "hello",
  "testcases": {
    "<uuid>": {
      "stdin":  { "data": "..." },
      "answer": { "data": "..." },
      "isExpand": false,
      "isDisabled": false,
      "result": null
    }
  },
  "testcaseOrder": ["<uuid>", "..."],
  "src": { "path": "...", "hash": null }
}
```

IO 字段是 `{ "data": "..." }`（内联）或 `{ "path": "..." }`（存成文件）二选一——这是从扩展的序列化代码 `testcaseIoToDto` 里确认的。**不建议手改这个文件**，正常用侧边栏编辑即可；`.gitignore` 里已经把它排除。

### 4.4 从文件夹批量导入

配置项 `cph-ng.problem.inputFileExtensionList` 默认 `[".in"]`、`outputFileExtensionList` 默认 `[".ans", ".out"]`。所以在题目目录放：

```
tests/1.in    tests/1.ans
tests/2.in    tests/2.ans
```

侧边栏点 `From folder` 选这个目录，一次全部导入，按 basename 配对。

---

## 5. Code Runner 的定位

装了 Code Runner（`Ctrl+Alt+N`），但只作为**备用入口**：

- 优点：不需要工作区，单开一个 `.py`/`.cpp` 文件也能跑
- 缺点：它的 `executorMap` 是**用户级**配置，无法按项目定制；默认的 cpp executor 用 `&&` 拼接，在 PowerShell 5.1 下会失败

所以主路径走 F5（工作区级、参数可控），Code Runner 只在"临时看一眼一个文件"时用。

---

## 6. Python 部分

```json
"python.defaultInterpreterPath": "...Python312\\python.exe",
"python.terminal.activateEnvironment": true
```

- 显式指定解释器，避免 Pylance 在多个环境（比如同时装了 Miniconda）之间猜错
- `python.terminal.activateEnvironment` 保证在终端里跑时用的是同一个解释器
