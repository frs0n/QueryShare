# 显示与界面

目标文件、写入和还原方法见 `00-common.md`。本页的键均位于 MobileGestalt `CacheExtra`；值为 **Integer**，不是 Boolean。选择需要的一行，不要整表全部写入。

| 玩法 | 键 → 值 | 生效/检查 |
| --- | --- | --- |
| 灵动岛能力 | `YlEtTtHlNesRBMal1CqRaA` → `1` | 重启后观察实时活动；布局见下段 |
| 全天候显示 | `2OOJf1VhaM7NxfRok3HbWQ` → `1`，`j8/Omm6s1lsmTDFsXjsBfA` → `1` | 重启，显示与亮度设置；非低刷屏可能耗电/烧屏 |
| AOD Vibrancy | `ykpu7qyhqFweVMKtxNylWA` → `1` | 检查锁屏 AOD 渲染 |
| AOD 高亮度 | `7brdL5xrEUWnlF9C0kdg5A` → `1` | 重启后检查；依赖面板 |
| AOD Flipbook | `aoJSd/MXk7M40NgXTM6x+g` → `1` | 锁屏 flipbook 部件；计数单独设置 |
| AOD Flipbook 数量 | `qqrspu7CpuPdZwSDxNY+Fg` → `3` | 上游实验值为 3，不能据此假设任意数量可用 |
| 关闭壁纸视差 | `UIParallaxCapability` → `0` | 重启/刷新锁屏后倾斜观察 |
| HDR 照片显示 | `a1r7npIrhXsZ7SmKRKC1eA` → `1` | 用支持 HDR 的素材观察，仍需屏幕支持 |
| Liquid Glass 低性能渲染 | `SAGvsp6O6kAQ4fEfDJpC4Q` → `1` | 重启观察玻璃渲染；明确要关闭时写 `0`，还原时用原值 |
| PWM 能力标记 | `6IejgN+1Fmu5/QrZFOIeNw` → `1` | 实验性，不能保证改变实际调光 |
| DisplayPort 能力标记 | `CoWnN4xo783YGn4wLrUatA` → `1` | 实验性，需对应输出硬件 |

例：

```python
record = edit_plist(s, MG, {('CacheExtra', 'UIParallaxCapability'): 0})
```

## 灵动岛位置/设备布局

修改 `CacheExtra['oPeik/9e8lQWMszEjbPzng']['ArtworkDeviceSubType']`，保留该字典其他成员，并打开本页的灵动岛能力。已核实的上游预设：

| 布局标签 | Integer subtype |
| --- | --- |
| iPhone X 手势（SE） | 2436 |
| iPhone 14 Pro / Pro Max | 2556 / 2796 |
| iPhone 16 Pro / Pro Max | 2622 / 2868 |
| iPhone Air | 2736 |

WorkTweaks 另有 15 Pro Max=`2976`、17/18 Pro=`2622`、17/18 Pro Max=`2868`、Duo=`2034` 的标签；18 系列标签要求 iOS 27.0.1+，Duo 要求 27.3+。其 14 Pro 标签映射为 `2436`，与上表 GestaltEdit 的 `2556` 不同。它们是各项目的布局预设标签，不是经过统一验证的设备分辨率表，不以型号名称推断效果。

```python
record = edit_plist(s, MG, {
    ('CacheExtra', 'oPeik/9e8lQWMszEjbPzng', 'ArtworkDeviceSubType'): 2556,
    ('CacheExtra', 'YlEtTtHlNesRBMal1CqRaA'): 1,
})
```

Artwork 字典缺失/类型不对时停止。subtype 是布局选择，不是实际分辨率，也不保证出现相同型号的岛形状。还原必须同时恢复本次涉及的 subtype 与能力键，不能删掉整个 Artwork 字典。

来源：[GestaltEdit/GestaltTweaks.swift](https://github.com/frs0n/GestaltEdit/blob/6c5f8843641e7304259a3fcc56e7c133509e155c/GestaltEdit/GestaltTweaks.swift)、[GestaltX/Capabilities.swift](https://github.com/huamidev/GestaltX/blob/72bf625befdb5e9e16d52c663e123f9fbc8ec7bf/GestaltX/Capabilities.swift)。

补充标签：[WorkTweaks GestaltManager.swift](https://github.com/adnan120hz/WorkTweaks/blob/373446ff36511827a4bb18ff75bfd59b2b415af2/worse_query/GestaltManager.swift)。
