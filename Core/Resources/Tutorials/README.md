# QueryShare 修改教程

通过 SFTP 读取本目录。先读 `00-common.md`，再按目标读取对应文件。示例 Python 均在电脑端运行，`s` 为已经连接的 Paramiko SFTPClient。目录按修改对象分类，同一玩法只归入一个文件。

| 分类 | 教程 | 内容 |
| --- | --- | --- |
| 通用操作 | [00-common.md](00-common.md)、[qs.py](qs.py) | 容器定位、读写、plist 修改、备份与还原 |
| 显示与界面 | [10-display.md](10-display.md) | 灵动岛、布局、AOD 及变体、视差、HDR、Liquid Glass、PWM、DisplayPort |
| 设备与硬件菜单 | [11-device.md](11-device.md) | 型号名称、开关机声音、充电限制、轻点唤醒、按钮、SOS、音频 |
| 地区与智能 | [12-intelligence.md](12-intelligence.md) | 地区、AI、Siri、翻译、消除、手写、green-tea、WAPI、硬件身份恢复 |
| 多任务与设备类别 | [13-multitasking.md](13-multitasking.md) | 台前调度、iPad App、Pencil、iPadOS 模式 |
| 内部功能 | [14-internal.md](14-internal.md) | InternalInstall、InternalBuild、内部设置、SRD 标记 |
| 系统配置 | [20-configuration.md](20-configuration.md) | 锁屏文字、监管状态、组织名称 |
| 壁纸与拨号主题 | [30-appearance.md](30-appearance.md) | Collections、Mercury、视频、描述符安装/移除/重置、拨号键图片 |
| App 声音与启动图 | [31-app-assets.md](31-app-assets.md) | 通知声音替换/新建/恢复、SplashBoard 启动快照 |
| App 数据与空间 | [40-app-data.md](40-app-data.md) | 大文件、缓存、日志、备份恢复、重置、迁移/交换/合并、插件配置、重装暂存 |
| 文件与数据包 | [50-file-editing.md](50-file-editing.md) | 文本、JSON、plist、hex、SQLite、ZIP、数据包部署 |

这是根据上游源码整理的操作方法，核对日期为 2026-11-14；不是每项都经过 QueryShare 真机验证。教程中的能力标记与硬件功能、生效结果分开描述。需要重启或切换界面的步骤由用户在手机完成。
