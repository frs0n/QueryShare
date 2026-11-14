# 通用操作

## 连接与定位

```python
import getpass, paramiko
client = paramiko.SSHClient()
client.load_system_host_keys()
# 首次连接先核对 QueryShare Logs 中的 host fingerprint，再将主机密钥加入 known_hosts。
client.connect(HOST, port=2222, username='mobile', password=getpass.getpass())
s = client.open_sftp()
s.get('/Agent/qs.py', 'qs.py')
from qs import read, write_existing, edit_plist, restore_plist, DELETE, MG
```

`HOST` 是应用显示的手机 IP。`/Agent` 是只读教程目录。`/Containers` 下的 Apps、Extensions、AppGroups、Daemons、SystemGroups、SystemData 是真实容器的别名。按 bundle ID 查找，使用返回的完整目录名，不猜 UUID：

```python
roots = [p for p in s.listdir('/Containers/Apps') if '[com.apple.mobilephone]' in p]
assert len(roots) == 1, roots
APP = '/Containers/Apps/' + roots[0]
print(s.listdir(APP))
```

没有 bundle ID 标签时，先核实容器元数据；不要凭相似名字修改。发现仍在进行时刷新目录。AppGroup 需单独定位，不能用 App 的 UUID 拼出来。

## 修改 plist 的统一写法

路径使用 tuple；哈希键本身可能含 `/`，不能把它当路径分隔符。表中的 Integer 1 必须写 Python `1`，Boolean true 写 `True`。

```python
record = edit_plist(s, MG, {
    ('CacheExtra', 'YlEtTtHlNesRBMal1CqRaA'): 1,
})
print(record)  # 电脑端本次操作的备份目录
# 还原此次操作涉及的字段，保留之后对其他字段的修改：
restore_plist(s, record)
```

`qs.py` 保存修改前/后的 plist 与变更字段列表，在写前比较原文件，在写后比较完整字节。已有文件通过 `r+b` 原位写入，最后截断到正确长度。多文件操作不具备事务性；发生中断时保留备份，并核实已修改到哪里。

MobileGestalt 固定路径已放入 `MG` 常量。其 SystemGroup 访问通常需要 iOS 27；以实际读写结果为准。不存在/无权限时停止，不创建一份空的 MobileGestalt。只改教程列出的字段。`CacheData`、`CacheUUID`、`CacheVersion` 与硬件身份不要随意替换。

## 二进制与普通文件

```python
from pathlib import Path
original = read(s, REMOTE)
Path('original.bin').write_bytes(original)
candidate = ...  # 本地处理
write_existing(s, REMOTE, original, candidate)
# 原文件整份还原，要求当前文件还是此次写入的结果：
write_existing(s, REMOTE, candidate, original)
```

## 修改完成后，Agent 应要求用户做什么

所有文件写入并回读验证完成后，再安排生效动作。**修改和还原执行同一规则**，一批改动合并提示一次。

| 本次修改 | Agent 的下一步 |
| --- | --- |
| 所有 MobileGestalt 修改：CacheExtra、CacheData、Siri/AI、地区、机型身份、显示布局、硬件菜单、多任务、内部标记 | 要求用户点击 QueryShare 主页（Connection）底部 **Respring**，完成后检查对应功能 |
| PosterBoard 壁纸安装/移除/重置、锁屏脚注 | 要求用户点击主页底部 **Respring**，再打开壁纸图库/锁屏检查 |
| 监管状态/组织名称 | 退出并重开“设置”；仍显示旧值时要求点击主页底部 **Respring** |
| App 偏好/数据、通知声音、启动快照、拨号缓存图片 | 按该教程重开目标 App 或切换外观；需要系统界面重载时要求 **Respring** |
| 只读浏览/分析、下载备份、导出、普通缓存清理 | 无需 Respring |

需要 Respring 时，直接对用户说：**“修改已写入并校验，请点击 QueryShare 主页（Connection）底部的 Respring，完成后重新打开 QueryShare 并连接，我再检查效果。”** 先结束当前文件传输，保存本次修改/还原记录。可能需要重新点 Start。

不要只说“刷新/重载”而不指出按钮。Respring 后先回读确认改动仍在，再请用户核实实际功能。未生效时检查路径、键名、类型、下载状态和设备支持情况，**不要默认要求完整重启，也不要循环 Respring 或盲目重写文件**。

SFTP 不能远程点击按钮；处理代码在电脑运行，Respring 由用户在手机完成。
