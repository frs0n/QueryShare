# 文件与数据包

## 文本、JSON、XML 与 plist

选中具体文件下载到电脑，保留原始编码和换行。文本按已识别编码解码后修改；JSON 使用 `json.loads`/`json.dumps`，XML 用解析器处理，回写前重新解析。二进制文件不要先当 UTF-8 解码。普通文件读写复用 `00-common.md`。

plist 使用 `plistlib`；Boolean、Integer、Real、Data、Date、Array、Dictionary 各有实际类型。用 tuple 路径精确编辑、增加或删除：

```python
record = edit_plist(s, REMOTE, {
    ('Preferences', 'Enabled'): True,
    ('Preferences', 'Count'): 3,
    ('Preferences', 'Ratio'): 0.75,
    ('Preferences', 'TokenData'): bytes.fromhex('010203'),
    ('ObsoleteKey',): DELETE,
})
```

不存在的中间字典不会自动创建，需先核实结构。格式保留为原来的 binary/XML；还原用该次 `record`。数组项目的添加/删除/重排在本地构造完整数组，再替换该数组字段。数字键名、带 `/` 的哈希键均保持原字符串。

## Hex 补丁与搜索

```python
from pathlib import Path
original = read(s, REMOTE)
Path('original.bin').write_bytes(original)
offset = 0x120
expected = bytes.fromhex('01020304')
replacement = bytes.fromhex('05060708')
assert len(expected) == len(replacement)
assert original[offset:offset+len(expected)] == expected
candidate = original[:offset] + replacement + original[offset+len(expected):]
write_existing(s, REMOTE, original, candidate)
```

搜索用 `bytes.find` 并继续搜下一处；结构补丁要求唯一匹配且验证周边结构，不能默认选第一处。大文件按偏移分块读取/写入，保留每个修改区间的原字节。还原反向写回原片段并验证。没有匹配版本的偏移/模式就不能应用补丁。

## SQLite 数据修改

1. 退出目标 App，下载数据库和实际存在的 `-wal`、`-shm`，按同名放在电脑的同目录，保留原始副本。
2. 在**工作副本**上通过 Python sqlite3 打开，检查 `PRAGMA quick_check` 与 schema；加密数据库需要正确密钥，不能当明文修复。
3. 用 SQLite `backup()` API 从该一致快照生成独立工作数据库；按已核实的表/字段执行参数化 SQL，提交后再次 quick_check。
4. App 保持退出，确认远程主库和 sidecar 的哈希均未变化。备份仍有效后，替换主库并处理旧 sidecar：仅移除此次已备份的旧 WAL/SHM，不能让旧 WAL 在新主库上重放。跨文件操作会中断，期间不要打开 App。
5. 回读主库做校验，再开 App 检查。恢复时成组恢复原主库和对应 sidecar，不能把一个时期的主库与另一个时期的 WAL 混用。

SQL 的具体业务改法依 App schema，不提供通用“合并聊天记录/解锁购买”的猜测 SQL。

## ZIP 导入、导出、文件/目录操作

下载后本地用 zipfile 创建 ZIP；大目录先按 `40-app-data.md` 的下载流程采集一致副本。解包前遍历所有 ZipInfo，拒绝：绝对路径、`..`、反斜杠路径、符号链接/特殊文件、重复/大小写冲突条目，以及异常解压总量。逐项写入独立临时目录，确认每个目标仍在该目录内。不要直接 extractall 后上传未知文件。

普通操作使用 SFTP：mkdir、rename、remove、rmdir、symlink、readlink、chmod、utime。`rename` 不覆盖目标，明确需要覆盖时使用 `s.posix_rename(src,dst)`。需要上传整个目录用 `upload_tree`；跨容器移动用已备份的“复制 → 校验 → 删除来源”，不能假设 rename 跨卷可用。权限/属主受 iOS 限制，chmod 不是绕过访问控制的方法。

## 文件包部署与卸载

使用电脑端任务 manifest，不假装它兼容 WorkTweaks 的私有包格式：

```json
{
  "bundleID": "com.example.target",
  "container": "Apps",
  "files": [
    {"source": "payload/settings.plist", "destination": "Library/Preferences/com.example.target.plist", "sha256": "<payload SHA-256>"}
  ]
}
```

1. 解包和路径验证依上一节；source/destination 均为受限相对路径，禁止逃出包/目标容器。
2. 按 manifest 的类别和 bundle ID 定位真正容器。AppGroup/Daemon 使用它自己的标识，不复用 App UUID。
3. 核实 payload 哈希与格式，记录每个目标的原始内容或“原来不存在”。
4. 逐文件部署，已有文件原位写入，新文件排他创建；回读校验并保存部署清单。目标变化则停止，不能盲目覆盖。
5. 卸载部署包：只恢复清单中的目标文件；本次新建的目标仅在内容仍匹配 payload 时删除。用户后来改过的文件先报告冲突。

此处部署的是数据文件。dylib、Mach-O、.deb 上传到容器不等于已安装可运行的调整；terminal_worse 的 Python/脚本运行能力来自它自身 a-Shell，不属于 QueryShare 的 SFTP 服务。

来源：[WQFiles](https://github.com/kolbicz/WQFiles)、[WorkTweaks](https://github.com/adnan120hz/WorkTweaks)、[terminal_worse](https://github.com/xz1c/terminal_worse)。SQLite/包清单部分是基于现有文件能力的电脑端操作方法。
