-- ================================== 基础设置 ==================================
hs.alert.defaultStyle.textSize = 18

local function notify(msg)
  hs.alert.show(msg, 0.6)
end

local function launch(appName)
  local app = hs.application.get(appName)
  if app then
    app:activate()
  else
    hs.execute('open -a "' .. appName .. '"')
  end
end

local function openPath(path)
  hs.execute('open "' .. path .. '"')
end

-- ================================== 快捷键：应用启动/切换 ==================================
-- ⌘1 SourceTree
hs.hotkey.bind({"cmd"}, "1", function()
  launch("SourceTree")
  notify("SourceTree")
end)

-- ⌘2 备忘录（用 Bundle ID 最稳）
hs.hotkey.bind({"cmd"}, "2", function()
  hs.application.launchOrFocusByBundleID("com.apple.Notes")
  notify("备忘录")
end)

-- ⌘3 Telegram
hs.hotkey.bind({"cmd"}, "3", function()
  launch("Telegram")
  notify("Telegram")
end)

-- ⌘4 LarkSuite（绝对路径 + 已运行则切前台）
hs.hotkey.bind({"cmd"}, "4", function()
  local app = hs.application.get("LarkSuite")
  if app then
    app:activate()
  else
    hs.execute('open "/Applications/LarkSuite.app"')
  end
  notify("LarkSuite")
end)

-- ⌘I Google Chrome
hs.hotkey.bind({"cmd"}, "i", function()
  launch("Google Chrome")
  notify("Google Chrome")
end)

-- ⌘Y 网易有道翻译（有道词典）
hs.hotkey.bind({"cmd"}, "y", function()
  launch("网易有道翻译")
  notify("网易有道翻译")
end)

-- ⌘⇧F Figma
hs.hotkey.bind({"cmd", "shift"}, "f", function()
  launch("Figma")
  notify("Figma")
end)

-- ⌘D 打开下载文件夹
hs.hotkey.bind({"cmd"}, "d", function()
  openPath(os.getenv("HOME") .. "/Downloads")
  notify("Downloads")
end)

-- ⌘T 打开 Terminal，并总是新建一个窗口
hs.hotkey.bind({"cmd"}, "t", function()
  local ok, _, err = hs.osascript.applescript([[
    tell application "Terminal"
      activate
      do script ""
    end tell
  ]])

  if ok then
    notify("Terminal")
  else
    notify("Terminal 打开失败")
    print("Terminal AppleScript error: " .. tostring(err))
  end
end)

-- ================================== 热重载（可选但强烈建议） ==================================
-- ⌘⌥⌃R 重新加载配置
hs.hotkey.bind({"cmd", "alt", "ctrl"}, "r", function()
  hs.reload()
end)

notify("Hammerspoon 配置已加载 ✅")
