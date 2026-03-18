此为项目来自社区 [linux.do](https://linux.do)

---

# Ds5Plus

通过蓝牙 HID 在 macOS 上实现 DualSense 无线音频驱动震动。

## 项目简介

Ds5Plus 是一个 macOS 应用，目标是在 **蓝牙无线连接** 下直接驱动 **DualSense / DualSense Edge** 的震动，并将 **系统音频** 实时映射为手柄震动与动态灯条反馈。

它主要用于补足部分游戏在 macOS 上**没有原生无线 DualSense 震动**的体验，同时尽量保持轻量、低延迟和可调节。

## 当前功能

- macOS 下的 DualSense 蓝牙 HID 直驱
- 基于系统音频捕获的实时震动映射
- 内置游戏预设，包括：
  - 丝之歌
  - TUNIC
- 支持用户自定义预设
- 支持灯条预设颜色与自定义颜色编辑
- 支持显示手柄剩余电量
- 支持轻量日志与日志大小上限设置
- 支持中文 / English 界面切换

## 运行要求

- 支持蓝牙的 macOS
- 已完成配对的 **DualSense** 或 **DualSense Edge**
- 需要授予“屏幕录制”权限，以进行系统音频捕获
- 建议使用 Xcode 16+ 构建

## 构建方式

使用 Xcode 打开：

`/Users/pengyu/Downloads/Ds5plus/Ds5plus.xcodeproj`

或在终端执行：

```bash
xcodebuild \
  -project /Users/pengyu/Downloads/Ds5plus/Ds5plus.xcodeproj \
  -scheme Ds5plus \
  -configuration Debug \
  -derivedDataPath /Users/pengyu/Downloads/Ds5plus/build \
  CODE_SIGNING_ALLOWED=NO build
```

生成后的 app 路径：

`/Users/pengyu/Downloads/Ds5plus/build/Ds5plus.app`

## 说明
 - 基于音频解析实现的无线的Ds5震动
 - 震动预设的个性化调整
 - 显示Ds5手柄电量（使用时为黄色、充电时为绿色、电量低于20%时为红色）
 - 对手柄灯条的颜色的色相、饱和度、亮度提供现有选项和自定义功能
 - 针对空洞骑士：丝之歌、tunic 这两款游戏做了特殊优化过的现成预设

## 许可证

本项目采用 **GNU Affero General Public License v3.0（AGPL-3.0）**。
