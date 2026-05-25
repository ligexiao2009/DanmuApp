# DanmuApp

iOS 弹幕播放器，支持 B站、腾讯、芒果TV、爱奇艺、直播吧、腾讯体育弹幕源。

## 功能

- 多源弹幕（B站/腾讯/芒果/爱奇艺/直播吧/腾讯体育）
- 芒果 ID 自动识别（文件名含 `mango_HHMMSS_videoId` 自动切换源）
- 弹幕去重（基于文本+时间+ctime 的 contentHash）
- 腾讯体育实时弹幕轮询
- 剧集库海报浏览与详情
- 字幕支持（SRT/ASS/UTF-8/UTF-16/GB18030）
- KSMEPlayer（FFmpeg）优先，支持 AC3/DTS 等编码
- 全屏控制条 10s 自动隐藏

## 依赖

- KSPlayer + FFmpegKit
- SwiftUI + AVKit

## 构建

Xcode 打开 `DanmuApp.xcodeproj`，选择真机或模拟器运行。
