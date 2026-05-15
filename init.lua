-- ================================== 基础设置 ==================================
hs.alert.defaultStyle.textSize = 18

local function notify(msg)
  hs.alert.show(msg, 0.6)
end

local function launch(appName)
  local app = hs.application.get(appName)

  if app then
    app:unhide()
    app:activate(true)

    local win = app:mainWindow()
    if win then
      win:unminimize()
      win:focus()
    end
  else
    hs.execute('open -a "' .. appName .. '"')
  end
end

local function launchChromeApp(appName)
  local app = hs.application.get(appName)

  if app then
    app:unhide()
    app:activate(true)

    local win = app:mainWindow()
    if win then
      win:unminimize()
      win:focus()
    end

    return
  end

  local home = os.getenv("HOME")
  local appPaths = {
    home .. "/Applications/Chrome Apps.localized/" .. appName .. ".app",
    home .. "/Applications/Chrome Apps/" .. appName .. ".app",
    home .. "/Applications/Chrome 应用/" .. appName .. ".app",
    "/Applications/Chrome Apps.localized/" .. appName .. ".app",
    "/Applications/Chrome Apps/" .. appName .. ".app",
    "/Applications/Chrome 应用/" .. appName .. ".app",
  }

  for _, appPath in ipairs(appPaths) do
    if hs.fs.attributes(appPath) then
      hs.execute('open "' .. appPath .. '"')
      return
    end
  end

  hs.execute('open -a "' .. appName .. '"')
end

local function openPath(path)
  hs.execute('open "' .. path .. '"')
end

-- ================================== 输入法：终端自动切英文 ==================================
-- 系统英文输入源通常是 ABC 或 U.S.，这里两个都兼容。
local englishInputSources = {
  "com.apple.keylayout.ABC",
  "com.apple.keylayout.US",
}

local terminalBundleID = "com.apple.Terminal"

local terminalApps = {
  ["Terminal"] = true,
  ["终端"] = true,
}

local function isTerminalApplication(appObject, appName)
  if appObject and appObject:bundleID() == terminalBundleID then
    return true
  end

  return appName and terminalApps[appName] == true
end

local function switchToEnglishInputSource()
  local currentSourceID = hs.keycodes.currentSourceID()

  for _, sourceID in ipairs(englishInputSources) do
    if currentSourceID == sourceID then
      return true
    end
  end

  for _, sourceID in ipairs(englishInputSources) do
    hs.keycodes.currentSourceID(sourceID)

    if hs.keycodes.currentSourceID() == sourceID then
      return true
    end
  end

  return false
end

local function switchToEnglishInputSourceWithRetry()
  -- Terminal 新窗口创建后，macOS 可能会稍后恢复上一次中文输入法。
  -- 连续切几次，覆盖 Terminal / 系统恢复输入法的时机。
  hs.timer.doAfter(0.05, switchToEnglishInputSource)
  hs.timer.doAfter(0.25, switchToEnglishInputSource)
  hs.timer.doAfter(0.60, switchToEnglishInputSource)
end

local function terminalInputSourceWatcher(appName, eventType, appObject)
  if not isTerminalApplication(appObject, appName) then
    return
  end

  if eventType == hs.application.watcher.launched
      or eventType == hs.application.watcher.activated then
    switchToEnglishInputSourceWithRetry()
  end
end

terminalInputWatcher = hs.application.watcher.new(terminalInputSourceWatcher)
terminalInputWatcher:start()

-- ================================== 快捷键：应用启动/切换 ==================================
-- ⌘1 SourceTree
hs.hotkey.bind({"cmd"}, "1", function()
  hs.application.launchOrFocusByBundleID("com.torusknot.SourceTreeNotMAS")
  notify("SourceTree")
end)

-- ⌘2 备忘录（用 Bundle ID 最稳）
hs.hotkey.bind({"cmd"}, "2", function()
  hs.application.launchOrFocusByBundleID("com.apple.Notes")
  notify("备忘录")
end)

-- ⌘3 Telegram（原生客户端，已停用）
-- hs.hotkey.bind({"cmd"}, "3", function()
--   launch("Telegram")
--   notify("Telegram")
-- end)

-- ⌘3 Telegram Web（Chrome 应用）
hs.hotkey.bind({"cmd"}, "3", function()
  launchChromeApp("Telegram Web")
  notify("Telegram Web")
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

-- ⌘5 Codex
hs.hotkey.bind({"cmd"}, "5", function()
  launch("Codex")
  notify("Codex")
end)

-- ⌘I Google Chrome
hs.hotkey.bind({"cmd"}, "i", function()
  launch("Google Chrome")
  notify("Google Chrome")
end)

-- ⌘Y 网易有道翻译（有道词典）：已打开则显示到桌面，未打开则启动
hs.hotkey.bind({"cmd"}, "y", function()
  local bundleID = "com.youdao.YoudaoDict"

  local app = hs.application.get(bundleID)
  if app then
    app:unhide()
    app:activate(true)

    for _, win in ipairs(app:allWindows()) do
      win:unminimize()
      win:raise()
    end

    local win = app:mainWindow()
    if win then
      win:focus()
    end
  else
    hs.application.launchOrFocusByBundleID(bundleID)
  end

  notify("有道词典")
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

-- ⌘T：Terminal 未运行时只打开一个窗口；已运行时新建一个终端窗口
hs.hotkey.bind({"cmd"}, "t", function()
  local app = hs.application.get(terminalBundleID)

  if not app then
    -- Terminal 未运行时不要用 do script，否则可能和启动默认窗口叠加，打开两个窗口。
    hs.execute('open -a "Terminal"')
    switchToEnglishInputSourceWithRetry()
    notify("Terminal")
    return
  end

  local ok, _, err = hs.osascript.applescript([[
    tell application "Terminal"
      do script ""
      activate
    end tell
  ]])

  if ok then
    switchToEnglishInputSourceWithRetry()
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