# 内部功能标记

均写 MobileGestalt `CacheExtra`，Integer `1`；写入和原值还原复用 `00-common.md`，重启生效。每次只选需要的标记，便于验证影响。

| 玩法 | 键 | 影响 |
| --- | --- | --- |
| Apple Internal Install | `EqrsVvjcYDdxHBiQmGhAWw` | 上游用于内部功能/菜单，如 Metal HUD；可能影响系统 App 安装等服务 |
| InternalBuild | `LBJfwOEzExRxzlAnSuI7eg` | 系统级内部构建标记，包含存储页面表现变化，不能只当成“显示更多存储信息” |
| Internal Settings Bundle | `Oji6HRoPi7rH7HPdWVakuw` | 内部设置相关能力 |
| Security Research Device 标记 | `XYlJKKkj2hztRP1NWWnhlw` | 仅能力标记，不授予 Apple SRD 权限或签名能力 |

```python
record = edit_plist(s, MG, {('CacheExtra', 'Oji6HRoPi7rH7HPdWVakuw'): 1})
```

核实所需菜单/功能，并检查 App Store、系统 App 安装和相关服务。出现异常时按此次记录还原原值，不能将所有内部标记统一写 0。

WorkTweaks 还提供同一组内部功能的 **CacheData 二进制写法**：从设备自己的 libMobileGestalt 找到上述 install、settings bundle、build 三个键对应的槽偏移，每个槽写入 UInt64 little-endian 1。其算法在 `__TEXT,__cstring` 定位键，再在 `__AUTH_CONST,__const`（或 `__DATA_CONST,__const`）找引用，从记录偏移 `0x9a` 读取 UInt16 索引并乘 8。必须核实库与当前 CacheUUID 匹配、三个索引唯一且各 `offset+8 <= len(CacheData)`，再同时写入并保留原八字节。单靠 SFTP 取不到已加载系统库时，这个变体不能执行；不能拿 CacheExtra 哈希值计算一个偏移。还原恢复原八字节，不写猜测的 0。

二进制变体来源：[WorkTweaks GestaltManager.swift](https://github.com/adnan120hz/WorkTweaks/blob/373446ff36511827a4bb18ff75bfd59b2b415af2/worse_query/GestaltManager.swift)。

来源：[GestaltX/Capabilities.swift](https://github.com/huamidev/GestaltX/blob/72bf625befdb5e9e16d52c663e123f9fbc8ec7bf/GestaltX/Capabilities.swift)。
