# 设备与硬件菜单

以下均修改 MobileGestalt 的 `CacheExtra`，套用 `00-common.md` 的 `edit_plist` 与 `restore_plist`。除型号名称外，值均为 **Integer 1**。**写入或还原校验后，要求用户点击主页底部 Respring，再重开对应设置页/App。** 开关机提示音的真实声音要通过完整关机/开机测试，Respring 不会产生开机声音。

| 玩法 | 键 | 实际检查 |
| --- | --- | --- |
| 开关机提示音 | `QHxt+hGLaBPbQJbXiUJX3w` | 辅助功能的开关机声音选项与实际声音 |
| 充电上限菜单 | `37NVydb//GP/GrhuTN+exg` | 电池 → 充电；菜单出现不证明电量会按上限停止 |
| 轻点唤醒 | `yZf3GTRMGTuwSV/lD7Cagw` | 辅助功能 → 触控，并锁屏实测 |
| Camera Control 设置 | `CwvKxM2cEogD3p+HYgaW0Q`、`oOV1jhJbdV3AddkcCg0AEA` | 两键都写 1；不会添加实体相机按钮 |
| Action Button 设置 | `cT44WE1EohiwRzhsZ8xEsw` | 设置中的操作按钮页面；不会添加实体按键 |
| 碰撞 SOS 菜单 | `HCzWusHQwZDea6nNhaKndw` | 紧急 SOS 页；不得把菜单出现当作碰撞检测可用 |
| Audio Mix | `aVL5GE3tx0LSCI/ErfrJGA` | 支持素材的编辑选项 |
| FaceTime 空间音频 | `/EVOCjM/Nmb2roP5ebtEFA` | FaceTime 中的支持情况 |

例：充电上限菜单。

```python
record = edit_plist(s, MG, {('CacheExtra', '37NVydb//GP/GrhuTN+exg'): 1})
```

## 自定义型号显示名称

仅修改 Artwork 字典里的 String `ArtworkDeviceProductDescription`，不修改 ProductType、主板或 CPU：

```python
record = edit_plist(s, MG, {
    ('CacheExtra', 'oPeik/9e8lQWMszEjbPzng', 'ArtworkDeviceProductDescription'): 'My iPhone'
})
```

修改或还原后要求用户点击主页底部 Respring，再重开设置查看使用该字段的型号名称。此项不是系统“设备名称”设置，也不把设备变成另一型号。

来源：[GestaltEdit/GestaltTweaks.swift](https://github.com/frs0n/GestaltEdit/blob/6c5f8843641e7304259a3fcc56e7c133509e155c/GestaltEdit/GestaltTweaks.swift)、[GestaltX/Capabilities.swift](https://github.com/huamidev/GestaltX/blob/72bf625befdb5e9e16d52c663e123f9fbc8ec7bf/GestaltX/Capabilities.swift)。
