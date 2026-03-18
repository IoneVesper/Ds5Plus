此为项目来自 https://linux.do 

# Ds5Plus

Wireless DualSense audio-reactive haptics driver for macOS over Bluetooth HID.

## Overview

Ds5Plus is a macOS app that drives **DualSense / DualSense Edge haptics wirelessly over Bluetooth HID** and maps **system audio** into controller vibration and dynamic lightbar feedback.

It is designed for games that do not expose native wireless DualSense haptics on macOS, while still keeping the experience lightweight, responsive, and customizable.

## Features

- Bluetooth HID direct drive for DualSense on macOS
- Audio-reactive haptics from system audio capture
- Game-tuned built-in presets, including:
  - Silksong
  - TUNIC
- Custom user presets
- Dynamic lightbar tint with preset colors and custom color editor
- Controller battery display
- Lightweight logging and adjustable log size limit
- Chinese / English interface switching

## Requirements

- macOS with Bluetooth support
- A paired **DualSense** or **DualSense Edge**
- Screen Recording permission for system audio capture
- Xcode 16+ recommended for building

## Build

Open the project in Xcode:

`/Users/pengyu/Downloads/Ds5plus/Ds5plus.xcodeproj`

Or build from Terminal:

```bash
xcodebuild \
  -project /Users/pengyu/Downloads/Ds5plus/Ds5plus.xcodeproj \
  -scheme Ds5plus \
  -configuration Debug \
  -derivedDataPath /Users/pengyu/Downloads/Ds5plus/build \
  CODE_SIGNING_ALLOWED=NO build
```

Built app path:

`/Users/pengyu/Downloads/Ds5plus/build/Ds5plus.app`

## Notes

- This project focuses on **wireless Bluetooth-only DualSense haptics**
- Wired USB haptics are not the target path here
- Audio-driven vibration is tuned to suppress background music as much as possible while preserving effects, movement, attacks, and impacts

## License

Licensed under the **GNU Affero General Public License v3.0 (AGPL-3.0)**.

---

# Ds5Plus（中文）

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

- 本项目聚焦于 **无线蓝牙 DualSense 震动**
- 不以有线 USB 路线为目标
- 音频震动逻辑会尽量压制背景音乐，只保留更有体感价值的环境音、步态、攻击、受击与瞬态事件

## 许可证

本项目采用 **GNU Affero General Public License v3.0（AGPL-3.0）**。
