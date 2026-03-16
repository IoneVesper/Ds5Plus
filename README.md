# Ds5plus

一个面向 **蓝牙 DualSense(DS5) 无线直驱** 的 macOS 实验 App。

当前版本不再走“音频复制到手柄扬声器”的路线，而是改成：

- 通过 `IOHIDManager`
- 发现已通过蓝牙配对的 DualSense
- 直接发送 **Bluetooth HID Output Report**
- 驱动 DS5 的 **兼容振动输出**

## 当前能力

- 自动发现蓝牙连接的 DualSense / DualSense Edge
- 可选择目标手柄
- 直接发送蓝牙 HID 输出报告 `0x31`
- 已包含：
  - 报告序号 `seq_tag`
  - 固定 `tag = 0x10`
  - 兼容振动 flag
  - CRC32 校验
- 提供两种测试模式：
  - 持续输出
  - 脉冲输出

## 运行方式

1. 用 Xcode 打开：
   - `/Users/pengyu/Downloads/Ds5plus/Ds5plus.xcodeproj`
2. 先在 macOS 蓝牙设置中配对并连接 DualSense
3. 运行 App
4. 点击“刷新设备”
5. 选择你的 DualSense
6. 调整左右电机强度
7. 点击：
   - `开始持续输出`
   - 或 `发送单次脉冲`

## 说明

这里使用的是 **DualSense 蓝牙 HID 兼容振动路径**，属于最小可行验证版本：

- 优点：
  - 不依赖 USB
  - 不依赖系统已有震动支持
  - 只要蓝牙连上并能通过 HID 发报告，就能验证无线直驱
- 限制：
  - 当前主要是“兼容振动”
  - 还不是完整的“音频 -> 高级触觉映射引擎”
  - 还没实现自适应扳机、灯条等更多输出字段

## 下一步建议

如果继续推进，我建议下一步直接做：

1. **音频包络 -> HID 震动映射**
   - 采集系统音频或某 App 音频
   - 提取低频/包络
   - 实时映射到蓝牙 HID 振动强度

2. **更完整的 DualSense 输出报告支持**
   - 自适应扳机
   - 灯条 / player LEDs
   - mute LED

3. **设备稳定性处理**
   - 自动重连
   - 断开恢复
   - 多手柄管理
