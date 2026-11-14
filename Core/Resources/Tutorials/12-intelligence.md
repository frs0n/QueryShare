# 地区与智能

目标文件为 `MG`。`CacheExtra` 字段使用 `00-common.md` 的 `edit_plist`；结构字节修改使用下方单独的步骤。**本页 Siri/AI、地区、硬件身份及 CacheData 修改或还原校验后，同样要求用户点击主页底部 Respring。**功能是否可用还取决于机型、语言、系统与 Apple 服务。

## 地区代码与销售地区

- 地区代码：String `h63QSdBCiT/z0WU6rdQv6Q`。
- 销售地区：String `zHeENZu+wbg7PUprwNwBWg` 或旧键 `yK+xavymRGZ3xWc1tb8XDg`，只修改当前已存在的键。两个都没有时，不为销售地区补键。

| 地区 | RegionCode | 销售后缀（仅用户需要一起修改时） |
| --- | --- | --- |
| 美国 | LL | LL/A |
| 日本 | J | J/A |
| 中国大陆 | CH | CH/A |
| 香港 | ZP | ZP/A |
| 台湾 | TA | TA/A |
| 韩国 | KH | KH/A |
| 英国 | B | B/A |
| 德国 | D | D/A |
| 法国 | FN | FN/A |
| 加拿大 | C | C/A |
| 澳大利亚 | X | X/A |
| 新加坡 | ZA | ZA/A |
| 印度 | HN | HN/A |
| 越南 | VN | VN/A |

上游有将 ZA 标成香港的冲突；本表采用 Regitela 的映射，不将 ZA 与 ZP 混用。

```python
# 只改 RegionCode：不触碰销售地区。
record = edit_plist(s, MG, {('CacheExtra', 'h63QSdBCiT/z0WU6rdQv6Q'): 'LL'})
```

需要同步销售地区时，先读 `plistlib.loads(read(s, MG))['CacheExtra']`，只把实际存在的销售键加入同一次 `changes`，值为 `'LL/A'`。

## 智能能力

以下都位于 `CacheExtra`。它们是独立选项，不能因为要其中一项就全部写入。

| 玩法 | 键 | 值/类型 |
| --- | --- | --- |
| Apple Intelligence 能力 | `A62OafQ85EJAiiqKn4agtg` | Integer 1 |
| Siri AI Mode（仅 iOS 27） | `a3n5T9sFtlyQ74NEp9ESxg` | Integer 2；两阶段方法见下节 |
| Audio Intelligence | `rb2tKZxlj0Gm2tBmUQSLqQ` | Integer 1 |
| Personal Translator | `M1n2sAqf33NAOgZRGxQYBA` | Integer 1 |
| 照片 Clean Up | `XNCjqOupLM/S8fNyxRNQTA` | Integer 1 |
| 手写合成 | `YgYIIViDt1kgzyIsIV61vA` | Integer 1 |
| 始终聆听 Hey Siri | `TusANsf9Lfe3P/9fIXXSrQ` | Integer 1 |
| On-Device Siri 原值恢复 | `K/R1GfGfCkXvEhaPS2Vrng` | 使用原机备份的类型和值；不能通用写 1 |

## 老机型 Siri AI：下载阶段临时伪装，使用阶段恢复原机型

适用 **iOS 27**。`SiriMode` 不是明文键：应添加/修改 `CacheExtra['a3n5T9sFtlyQ74NEp9ESxg']`，类型为 **Integer**，值为 **2**。不要写成 String `'2'`，也不要误改 On-Device Siri 的另一把键。

### 1. 临时伪装以下载模型

记录本次修改前的 ProductType，供下载完成后还原。仅写入用于下载的受支持机型标识；示例 `iPhone18,1` 来自 WorkTweaks 的 iPhone 17 Pro 选项，不顺带伪装 CPU、主板、监管型号或地区。

```python
# DOWNLOAD_MODEL 按选定的下载机型填写，例如 'iPhone18,1'。
download_record = edit_plist(s, MG, {
    ('CacheExtra', 'h9jDsbgj7xIVeIQ8S3/X3Q'): DOWNLOAD_MODEL,
})
```

要求用户点击主页底部 Respring，然后在手机的 Apple Intelligence/Siri 设置中完成模型下载。**确认下载完成后**进入下一阶段；仅出现候补/下载入口不算完成。不伪装机型时老机型无法完成此处的 Siri AI 下载。

### 2. 恢复原机型，再设置 SiriMode

```python
# 仅恢复本次临时伪装的 ProductType，保留已下载模型与其他无关设置。
restore_plist(s, download_record)
# 日常使用依靠 SiriMode=2，不继续维持伪装。
siri_record = edit_plist(s, MG, {
    ('CacheExtra', 'a3n5T9sFtlyQ74NEp9ESxg'): 2,
})
```

要求用户点击主页底部 Respring 后测试 Siri AI、Face ID 和听写。**使用阶段不需要持续伪装机型**，不把保持伪装作为必要条件。此处也不要求顺带打开生成模型能力、改充电菜单或应用下面的旧 CacheData 配方。若之前其他工具已经改过主板/CPU等字段，先按本页“原机身份恢复”恢复那些原值，再测试。

撤销 SiriMode 修改：`restore_plist(s, siri_record)` 后要求用户点击主页底部 Respring。该流程按用户提供的两阶段方法整理；本次未进行真机验证。

## Siri AI Cache Patch（其他项目的旧配方）

该项保留用于覆盖上游玩法，不是前述 iOS 27 两阶段方法的必需步骤。这与 SiriMode 键是不同操作：修改 CacheData 中一个字节。来源在 CacheVersion 24A446 的文件上验证过形状，但不保证其他 build。不要按 XML 显示的“第 104 行”直接改文件；序列化换行会变化。

```python
import plistlib
original = read(s, MG)
root = plistlib.loads(original)
data = bytearray(root['CacheData'])
def matches(offset):
    chunk = data[offset:offset+51]
    return (len(chunk) == 51 and chunk[13] == 1 and chunk[21] in (0, 2)
            and all(v == 0 for i, v in enumerate(chunk) if i not in (13, 21)))
guide = 97 * 51
if matches(guide):
    offset = guide
else:
    hits = [i for i in range(0, len(data)-50, 51) if matches(i)]
    assert len(hits) == 1, 'Siri cache pattern missing or ambiguous'
    offset = hits[0]
data[offset+21] = 2
record = edit_plist(s, MG, {('CacheData',): bytes(data)}, expected=original)
```

来源的组合实验还会打开本页 AI 能力、将 ProductType 设为 `iPhone18,1`（iPhone 17 Pro），以及启用 `11-device.md` 的充电上限菜单。然后要求用户点击主页底部 Respring，在“Apple Intelligence 与 Siri”尝试加入候补并等待；上游给出约 15 分钟、接电并打开存储页约一小时的下载尝试步骤，**也明确模型可能仍拒绝下载**。该组合用于记录旧配方；iOS 27 的日常使用按前述 SiriMode 两阶段流程。

恢复本次缓存改动使用 `restore_plist`，校验后要求用户点击主页底部 Respring；原始字节不一定为 0，不能用“关闭就是写 0”代替原值恢复。

## green-tea / not-green-tea / WAPI 缓存字节

这三项不是简单追加 CacheExtra 键。本节仅适用于上游已验证的布局：

- `CacheUUID = 7F1DF278-18B7-4E5A-8425-09E8830DE9AF`（忽略大小写）。
- `CacheData` 必须为 6480 字节（720 个槽，每槽 8 字节值，后接 720 字节有效位）。
- green-tea 槽 383；not-green-tea 槽 506；wapi 槽 694。
- 每个目标有效位 `data[5760 + index]` 必须为 1；8 字节槽的第一字节为 0/1，其余七字节必须全为 0。
- `CacheExtra` 不得存在同名覆盖：`iyfxmLogGVIaH7aEgqwcIA`/`green-tea`、`4snMZS8LJkSctKypt2m+xA`/`not-green-tea`、`hiHut/WR+B9Lx/vd0WyeNg`/`wapi`。

```python
import plistlib
original = read(s, MG)
root = plistlib.loads(original)
assert root['CacheUUID'].upper() == '7F1DF278-18B7-4E5A-8425-09E8830DE9AF'
data = bytearray(root['CacheData'])
assert len(data) == 6480
extra = root['CacheExtra']
assert not any(k in extra for k in ('iyfxmLogGVIaH7aEgqwcIA', 'green-tea',
    '4snMZS8LJkSctKypt2m+xA', 'not-green-tea', 'hiHut/WR+B9Lx/vd0WyeNg', 'wapi'))
# 只选所需改动：区域缓存实验 {383: 0, 506: 1}；关闭 WAPI {694: 0}。
slots = {383: 0, 506: 1}
for i, value in slots.items():
    assert data[5760+i] == 1 and data[i*8] in (0, 1)
    assert data[i*8+1:i*8+8] == bytes(7)
    data[i*8] = value
record = edit_plist(s, MG, {('CacheData',): bytes(data)}, expected=original)
```

不同 UUID/长度不能沿用这些偏移；需要从**该设备的** libMobileGestalt 解析对应布局。SFTP 不提供读取设备内存的方法，拿不到匹配库/布局时此教程不适用。还原使用同布局的 `restore_plist`，校验后要求用户点击主页底部 Respring，再验证；不以效果不明显为理由乱改其他字节。

## 硬件伪装与原机身份恢复

相关字段是 ProductType `h9jDsbgj7xIVeIQ8S3/X3Q`、HardwareModel `oYicEKzVTz4/CxxE05pEgQ`、CPU `5pYKlGnYYBzGvAlIU8RjEQ`、监管型号 `97JDvERpVwO+GHtthIh7hA`。来源项目存在设备伪装与分阶段激活玩法，但没有一组跨机型通用值。

完整硬件伪装使用对应机型的字段与 CacheData 配置。恢复时，从同一设备、同一 CacheUUID/CacheVersion 的原始 MG 记录取上述字段，通过 `edit_plist` 写回相应 `CacheExtra` 键，保留 AI、地区等无关字段，再要求用户点击主页底部 Respring，并检查 Face ID 与听写。

WorkTweaks 的单字段 ProductType 伪装可用以下值；Siri 模型下载后按前述流程恢复原 ProductType：iPhone 15 Pro/Max=`iPhone16,1`/`iPhone16,2`，16/Plus=`iPhone17,3`/`iPhone17,4`，16 Pro/Max=`iPhone17,1`/`iPhone17,2`，17/Pro/Pro Max/Air=`iPhone18,3`/`iPhone18,1`/`iPhone18,2`/`iPhone18,4`，Duo=`iPhone19,4`（上游标注 iOS 27.3+）。例如 `edit_plist(s, MG, {('CacheExtra', 'h9jDsbgj7xIVeIQ8S3/X3Q'): 'iPhone18,1'})`。关闭时恢复自己的原值，不统一写一个默认 iPhone 型号。

Siri 缓存与 ProductType 伪装来源：[WorkTweaks GestaltManager.swift](https://github.com/adnan120hz/WorkTweaks/blob/373446ff36511827a4bb18ff75bfd59b2b415af2/worse_query/GestaltManager.swift)、[TweaksView.swift](https://github.com/adnan120hz/WorkTweaks/blob/373446ff36511827a4bb18ff75bfd59b2b415af2/worse_query/TweaksView.swift)。

键名映射：[GestaltX/GestaltDocument.swift](https://github.com/huamidev/GestaltX/blob/72bf625befdb5e9e16d52c663e123f9fbc8ec7bf/GestaltX/GestaltDocument.swift)。

来源：[GestaltX/Capabilities.swift](https://github.com/huamidev/GestaltX/blob/72bf625befdb5e9e16d52c663e123f9fbc8ec7bf/GestaltX/Capabilities.swift)、[GestaltX/DeviceCacheOptions.swift](https://github.com/huamidev/GestaltX/blob/72bf625befdb5e9e16d52c663e123f9fbc8ec7bf/GestaltX/DeviceCacheOptions.swift)、[GestaltX/MobileGestaltCacheLayout.swift](https://github.com/huamidev/GestaltX/blob/72bf625befdb5e9e16d52c663e123f9fbc8ec7bf/GestaltX/MobileGestaltCacheLayout.swift)、[Regitela/Region.swift](https://github.com/ichitaso/Regitela/blob/main/Regitela/Region.swift)。
