# 语流 · LingoLive

macOS 原生简体中文全拼输入法。边写中文，边看英文，确认后直接上屏。

- **光标旁看译文。** 输入框实时显示中文草稿，原生浮窗显示中文候选和整句英文预览，跟随浅色／深色外观。
- **两种输出。** 回车提交英文，Tab 保留中文。输入法只提交文字，不替你发送消息。
- **本机翻译。** 拼音使用 Rime；翻译使用 Apple Translation 的低延迟离线模型。语言包下载完成后无需联网、账号、API 密钥或辅助功能权限。应用不保存输入历史。

## 安装与试用

本机构建包为 Apple Silicon、macOS 27.0 或更新版本。源码要求 macOS 26.4 SDK 或更新版本；实际安装包的系统下限还取决于构建时使用的 Homebrew 动态库。其他 macOS 版本与机型尚未实测。

如果 macOS 27 上的语流会间歇性无法切换，优先使用 `-System.pkg`：双击打开并在 macOS 安装器中授权。安装器会将语流安装到 `/Library/Input Methods`，向系统注册；当前用户的旧版会备份到 `~/Library/Application Support/LingoLive/Input Method Backups`，避免两个副本互相干扰。装完后重新打开受影响的应用再切换；若仍灰显，保存工作后注销并重新登录。开发用安装包未公证。

以下是无需管理员权限的用户版安装步骤：

1. 解压安装包。在终端进入解压后的 `LingoLive` 文件夹，运行 `./install.sh "$PWD/LingoLive.app"`。本机开发包使用临时签名，未经过 Apple 公证；在其他 Mac 上应优先从源码本机编译，或使用经过公证的包。
2. 打开 **系统设置 → 键盘 → 文字输入 → 编辑 → ＋ → 简体中文**，选中 **语流**，点添加。列表没有刷新时，关闭并重新打开系统设置；首次安装后仍找不到或输入源没有生效时，保存工作、注销并重新登录一次。
3. 在菜单栏的输入法菜单选 **语流**。安装时会打开设置窗口；如需重新打开，从语流输入法菜单选「设置与离线语言包…」，按提示下载简体中文和英语。也可在「系统设置 → 通用 → 语言与地区 → 翻译语言」下载。
4. 在文本编辑里键入 `qingbazuixinbanwenjianfageiwo.`，看到 “Please send me the latest version of the file.” 后按回车。请先在普通编辑框试用；安全输入框由系统控制，应用兼容性可能不同。

| 按键 | 操作 |
| --- | --- |
| 拼音字母 | 输入草稿，浮窗自动更新译文 |
| 空格 / 数字 1–5 | 选择当前页的中文候选，继续写这句话 |
| ↑ / ↓、Page Up / Down | 翻候选页 |
| 回车 | 确认英文；译文尚未就绪时先等待 |
| Tab | 提交中文（也可用 Shift＋回车） |
| Esc | 清空当前草稿并取消等待中的提交 |

待译草稿离开输入框时优先保留为中文。翻译失败时保留草稿，仍可按 Tab 提交原文。整句通常比孤立词更准确；同音词请先选对，专有名词、数字和关键措辞请以上屏前看到的译文为准。

## 开发与验证

安装 Xcode 或对应版本的 Command Line Tools，以及 Homebrew：

```sh
brew install librime
./Scripts/build.sh
./Scripts/test.sh
./Scripts/install.sh
./Scripts/package.sh
./Scripts/package-system.sh
```

`build/LingoLive.app` 包含拼音词库和运行库；使用安装包不需要 Homebrew。构建脚本固定了词库版本并核对 SHA-256，第三方许可证随应用附带。若设置 `CODESIGN_IDENTITY`，构建会使用该签名；公证和对外分发需单独完成。

测试使用真实 Rime 词库和 Apple Translation，覆盖候选、整句预览、中文和英文提交、退格、焦点离开及取消提交。离线模型未安装时，翻译相关测试会明确跳过。8 条短句的本机引擎抽测中，预热后耗时中位数约 16–24 毫秒；自动预览额外等待约 90 毫秒以合并快速连打。整句预览在组合逻辑测试中约 110–123 毫秒。以上数字不代表所有输入框、句长或设备。

卸载时，在键盘设置移除「语流」，再将实际安装的 `LingoLive.app` 移到废纸篓：用户版在 `~/Library/Input Methods`，系统版在 `/Library/Input Methods`。

交互参考：[LO 语境输入法](https://forum.trae.cn/t/topic/146090)、[浮译 FloatTrans](https://github.com/krisir/floattrans)。引擎：[Apple InputMethodKit](https://developer.apple.com/documentation/inputmethodkit)、[Apple Translation](https://developer.apple.com/documentation/translation)、[Rime](https://github.com/rime/librime)。
