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

更改 App 数据前退出目标 App。修改系统缓存后按具体教程重启/刷新，并分别报告“文件验证通过”和“手机实际效果”。SFTP 不能执行 killall、respring、reboot 或运行手机端 Python；所有处理代码在电脑运行。
