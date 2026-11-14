# 多任务与设备类别

目标为 MobileGestalt `CacheExtra`，写入/还原复用 `00-common.md`。这些项不能创造 Pencil、额外内存或其他硬件。

| 玩法 | 键 | 值/类型 | 生效 |
| --- | --- | --- | --- |
| 台前调度 | `qeaj75wk3HF4DwQ8qbIi7g` | Integer 1 | 重启；检查多任务设置与布局 |
| 允许 iPad App 类型 | `9MZ5AdH43csAUajl/dU+IQ` | Array of Integer `[1, 2]` | 重启；仍受应用分发/兼容性限制 |
| Apple Pencil 设置 | `yhHcB0iH0d1XzPO/CFd3ow` | Integer 1 | 重启并重开设置，需实际硬件支持 |

```python
record = edit_plist(s, MG, {('CacheExtra', '9MZ5AdH43csAUajl/dU+IQ'): [1, 2]})
```

## 实验性 iPadOS 模式

该玩法还涉及 CacheData 设备类别。只开五个 CacheExtra 键不是完整操作。上游旧算法在 CacheData 十六进制字符 1616…1816 范围找模式，按匹配位置计算类别 nibble；不能把某台手机的最终偏移套到另一台手机。

下面忠实描述该算法，并额外要求匹配唯一。它只证明结构符合该旧配方，**没有建立所有新系统的适配性**。不适用于字母数字密码的设备；上游提示关闭 Stage Manager 的 Show Dock 可能导致无法使用。用户明确选择此实验时，先保留完整原机缓存和可恢复设备备份。

```python
import plistlib, re
original = read(s, MG)
root = plistlib.loads(original)
assert isinstance(root['CacheExtra'], dict)
blob = root['CacheData']
assert isinstance(blob, bytes)
hexdata = blob.hex()
assert len(hexdata) > 1616
window = hexdata[1616:1816]
matches = [m for m in re.finditer(r'0+(?:5555)*([0-9a-f]{4})', window)
           if sum(c != '0' for c in m.group(1)) >= 3]
assert len(matches) == 1, 'No unique supported marker'
offset = 1616 + matches[0].start(1)
left, right = offset - 67, offset + 13
for p in (left, right):
    assert 0 < p < len(hexdata)-1
    assert hexdata[p] in '13' and hexdata[p-1] == hexdata[p+1] == '0'
updated = hexdata[:left] + '3' + hexdata[left+1:]
changes = {('CacheData',): bytes.fromhex(updated)}
for key in ('mG0AnH/Vy1veoqoLRAIgTA', 'UCG5MkVahJxG1YULbbd5Bg',
            'ZYqko/XM5zD3XBfN5RmaXA', 'nVh/gwNpy7Jv1NOk00CMrw',
            'uKc7FPnEO++lVhHWHFlGbQ'):
    changes[('CacheExtra', key)] = 1
record = edit_plist(s, MG, changes, expected=original)
```

重启后核实桌面、多任务、输入、音频和 App 布局。还原用该次记录，同时恢复 CacheData 和五个键，再重启。缓存结构不匹配时不绕过断言。

来源：[GestaltEdit/GestaltTweaks.swift](https://github.com/frs0n/GestaltEdit/blob/6c5f8843641e7304259a3fcc56e7c133509e155c/GestaltEdit/GestaltTweaks.swift)。
