# 系统配置

容器：`/private/var/containers/Shared/SystemGroup/systemgroup.com.apple.configurationprofiles`。

子目录：`Library/ConfigurationProfiles`。需要该目录实际可读写，通常为 iOS 27。此处修改本地监管标记，不改变 MDM 注册。

## 锁屏底部文字

目标：`SharedDeviceConfiguration.plist`，根字典 String 键 `LockScreenFootnote`。

```python
CONFIG = '/private/var/containers/Shared/SystemGroup/systemgroup.com.apple.configurationprofiles/Library/ConfigurationProfiles'
record = edit_plist(s, CONFIG + '/SharedDeviceConfiguration.plist', {
    ('LockScreenFootnote',): 'If found, please contact me'
})
```

若**确认文件不存在**（ENOENT，不是权限错误），本地生成 `plistlib.dumps({'LockScreenFootnote': text}, fmt=plistlib.FMT_BINARY)`，使用 SFTP `open(path, 'wx')` 排他创建。记录“原来不存在”；还原时仅在文件仍是此次内容时删除。已有文件必须合并键，不能覆盖整个字典。写入或还原校验后，要求用户点击主页底部 Respring，再锁屏查看文字。还原已有文件的字段用 `restore_plist`。

## 监管状态与组织名称

目标：`CloudConfigurationDetails.plist`，根字典：

| 项目 | 键 | 值/类型 |
| --- | --- | --- |
| 监管状态 | `IsSupervised` | Boolean `True` |
| 组织名称 | `OrganizationName` | String，用户指定文本 |

```python
record = edit_plist(s, CONFIG + '/CloudConfigurationDetails.plist', {
    ('IsSupervised',): True,
    ('OrganizationName',): 'My Organization',
})
```

要求用户退出并重新打开“设置”，检查监管说明/组织名称；仍显示旧值时要求点击主页底部 Respring。还原后执行相同的生效步骤。原文件不存在时不要编造完整的云配置文件。关闭监管是恢复原始字段（可能是 False 或原先没有该键），不是删除整个 configurationprofiles 容器。某些设置会触发设置助理页面，文件标记不代表完成真实组织注册。

来源：[Erosion ConfigView.swift](https://github.com/jailbreakdotparty/Erosion/blob/12c0a2d00c444c9b09112608b47d4d6c10e0df14/Erosion/Tweaks/ConfigView.swift)、[GestaltX SystemSettingsStore.swift](https://github.com/huamidev/GestaltX/blob/72bf625befdb5e9e16d52c663e123f9fbc8ec7bf/GestaltX/SystemSettingsStore.swift)。
