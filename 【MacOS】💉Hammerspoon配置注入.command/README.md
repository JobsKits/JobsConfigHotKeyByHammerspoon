# `【MacOS】💉Hammerspoon配置注入.command`

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、入口与目录](#jobs-toc-heading-2)
- [二、只读验证](#jobs-toc-heading-3)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

读取包装目录上一级的 init.lua，按原有备份和授权流程部署到当前用户 Hammerspoon 配置；配套 init.lua 必须随工程保留。

## <span id="jobs-toc-heading-2" data-jobs-toc="v2">一、入口与目录 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

脚本与本 README 位于同名包装目录。查看[实际脚本](<./【MacOS】💉Hammerspoon配置注入.command>)及[上级工程说明](../README.md)后，按内置自述决定是否执行；运行位置从脚本实际路径解析，不依赖启动工作目录。迁移时保留工程的配套资源和相对层级。

## <span id="jobs-toc-heading-3" data-jobs-toc="v2">二、只读验证 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

在本 README 所在目录只检查原生语法：

```shell
/bin/zsh -n './【MacOS】💉Hammerspoon配置注入.command'
```

语法通过不代表真实下载、安装或配置写入已验收。交互沿用脚本自身确认与 Ctrl+C；日志、备份和退出状态以实际脚本自述为准。完整审查见总配置仓的 `项目相关报告/脚本统一审查.md`。

必需 Homebrew 的获取沿用本入口已有授权和安装路径选择：系统安装器按已声明官方 URL 轮询；用户目录只获取固定官方 release tag，在本轮私有暂存仓复用已收 Git 对象。临时网络错误持续退避（上限 30 秒），按 Ctrl+C 取消；本地、权限、认证、证书、版本及日志写入确定错误停止。获取成功后安装或业务只执行一次，不重放整个入口；终端显示真实进度，日志保持纯文本。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
