# App 数据与空间

先按 `00-common.md` 定位 `APP`。目标 App 保持退出。以下代码在电脑端复用 `qs.py` 的 `download_tree`、`upload_tree`、`remove_tree`；它们处理普通文件/目录，不跨符号链接。目录迁移并非数据库记录合并。

```python
from qs import download_tree, upload_tree, remove_tree
```

## 大文件与占用分析

用 `s.listdir_attr(path)` 递归，`stat.S_ISREG(a.st_mode)` 累加 `a.st_size`，目录递归，链接只记录不跟随。分别列出 Documents、Library、Library/Caches、tmp 的总逻辑字节与最大文件。APFS 克隆、压缩和硬链接会让逻辑字节与真实释放空间不同，不宣称累计文件长度就是实际腾出空间。

## 缓存与临时文件清理

范围只有选定 App 的 `Library/Caches` 和/或 `tmp`。先列出并按需导出，然后删除**其中内容**，保留这两个根目录：

```python
cache = APP + '/Library/Caches'
for name in s.listdir(cache):
    remove_tree(s, cache + '/' + name)
```

删除前确保 `cache` 本身是普通目录而不是链接。不要把 Documents、整个 Library、AppGroup 或所有名字带 cache 的路径一并删除。重新打开 App，核实数据仍在；缓存再次增长正常。需要还原时把导出的文件按原相对路径上传。

## App 备份与恢复

快速备份 `Documents`、`Library`；需要完整当前临时状态时额外选 `tmp`。可把已确认属于该 App 的 AppGroup 作为独立 scope 备份，不能假设主容器涵盖共享数据。

```python
download_tree(s, APP + '/Documents', 'backup/Documents')
download_tree(s, APP + '/Library', 'backup/Library')
```

为每份备份记录 bundle ID、原容器路径、系统 build、时间和相对文件路径/SHA-256。先确认整个下载成功，再把本地暂存目录改名发布为备份。此时压缩为 ZIP 不再占手机额外空间。文件实时变化/SQLite WAL 未收拢时，退出 App 后重新采集一致快照。

恢复先核实目标 bundle ID 相同，并下载一份目标当前数据。按用户选定 scope 恢复：

- **合并恢复**：`upload_tree(s, 'backup/Documents', APP + '/Documents')`；同名文件替换、目标独有文件保留。
- **精确恢复**：对照备份清单，删除 scope 中备份没有的文件，再上传全部备份并逐文件核对哈希。只处理明确选中的 Documents/Library/tmp，不删除容器根或容器元数据。
- **导入别的工具备份**：先解包、找到真正的 Documents/Library 并核实清单/哈希；不把 `.wqbackup`、ZIP 或包名当作天然兼容证明。

新文件的 owner/data-protection 无法通过普通 SFTP 完整复制；现有文件原位覆盖可保留 inode/属性。恢复后打开 App 验证数据库、账号和媒体。Keychain/登录状态不会随容器文件备份迁移。

## 重置单个 App 数据

完整备份后，仅清除指定 App 的 Documents、Library、tmp 内的内容，保留容器根及系统元数据。重新打开 App 检查是否进入初始状态。若登录仍在，可能来自 Keychain；不要因此扩大删除范围。

## 跨 App 迁移：替换、合并、交换

定位 `SRC`、`DST` 两个已核实容器和要迁移的相对路径，例如 `Library/Preferences`。先把两边选中范围分别下载成电脑端 `source/`、`target-before/`。

| 模式 | 确切语义 |
| --- | --- |
| 替换 | 目标所选范围变成来源的镜像，删除目标多余项 |
| 合并 | 来源覆盖同名项，保留目标独有项 |
| 交换 | 来源暂存写入目标，目标暂存写回来源；每边按替换语义 |
| 移动 | 先复制并验证目标全部哈希，再删除来源选中范围 |

先在电脑形成目标结果与差异列表，再上传；QueryShare 没有目录原子交换接口，多文件复制中断后按日志/哈希继续，不直接清空重来。还原使用两边原始备份。聊天数据库合并需要对应 App 的 schema、账号密钥与索引适配，不能通过简单目录合并获得聊天记录行级合并。

## 插件/偏好配置迁移

默认只选 `Library/Preferences/*.plist`（需要时递归），不连带数十 GB 的聊天数据。来源主配置名若为 `<source.bundle.id>.plist`，且目标确实使用 `<target.bundle.id>.plist`，在电脑端改文件名后部署；不要批量替换所有 plist 文件名或内容中的 bundle ID。共享 suite 配置在 AppGroup 里，需单独映射。

目标 App 退出后替换配置，再重新打开读取。恢复写回原文件，对本次新建的配置则按记录删除。偏好被系统/程序缓存时重启手机，SFTP 不能强制 cfprefsd 重载。

## 重装前暂存与回迁

1. 下载所选文件/目录到电脑，记录来源 bundle ID、相对路径和哈希。
2. 校验完整性后才重装目标 App。
3. 重新启动一次 App 生成新容器，再退出。旧 UUID 已失效，重新定位新容器。
4. 按原相对路径回迁选定数据并核对哈希；验证 App 的版本/数据库兼容性。

## 导出或清理崩溃日志

从发现到的 SystemGroups 中定位 CrashReporter 相关容器，在其实际 `Library/Logs` 等目录中枚举 `.ips`/日志；路径和权限因系统不同，不硬编码某台手机的 UUID。先下载用户指定日志再本地分析。只在明确要清理时删除已导出的日志，不把不可读 SystemData 当成提权入口。

来源：[WQFiles](https://github.com/kolbicz/WQFiles)、[WQManager](https://github.com/hseons/WQManager)、[WCMigrate](https://github.com/yangokok886/WCMigrate)、[worse_finder](https://github.com/melvinsh/worse_finder)。这些流程由 Agent 组合 SFTP 原语完成，不依赖安装上述 App。
