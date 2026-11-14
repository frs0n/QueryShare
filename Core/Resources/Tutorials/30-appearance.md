# 壁纸与拨号主题

## PosterBoard 容器与 provider

从 `/Containers/Apps` 定位 bundle ID `com.apple.PosterBoard`。令 `PB` 为它的真实路径或完整别名。枚举：

`PB/Library/Application Support/PRBPosterExtensionDataStore/<version>/Extensions/`

`<version>` 是磁盘上实际存在的数字版本目录，按数字从大到小查找；不要写死旧教程中的 `61`。

| 壁纸类型 | provider 目录 |
| --- | --- |
| Collections / CAML 动画 / 自定义照片帧 | `com.apple.WallpaperKit.CollectionsPoster` 或 `com.apple.Posters.CollectionsPosterApp` |
| Mercury | `com.apple.MercuryPoster` |
| 视频描述符 / VideoCAML | `com.apple.PhotosUIPrivate.PhotosPosterProvider` |

每个 provider 内目标是 `descriptors/`。相同版本有两个 Collections provider 时，按上游逻辑向实际存在的两个目录分别安装并记录。provider 不存在时停止，不凭名字新建一套 store。

## 导入 .tendies

1. `.tendies` 按 ZIP 读取；在电脑端依 `50-file-editing.md` 的解包规则解开。
2. 找 `descriptor(s)`、`ordered-descriptor(s)`、`video-descriptor(s)` 的子目录，或者包内 `container/Library/Application Support/.../Extensions/.../descriptors/` 的子目录。也可通过文件 `com.apple.posterkit.provider.descriptor.identifier` 识别单个描述符。
3. 包路径含 Mercury 对应 Mercury；含 video-descriptor、PhotosPoster，或内容中存在 `VideoCAML` 对应视频；其余明确为 Collections 的描述符按 Collections 处理。不确定 provider 时先查看包结构，不按扩展名猜。
4. Collections/视频每个描述符生成一个新的整数 ID，同时更新以下三个**存在的**文件：

| 文件名 | 修改 |
| --- | --- |
| `com.apple.posterkit.provider.descriptor.identifier` | UTF-8 十进制 ID 文本 |
| `com.apple.posterkit.provider.contents.userInfo` | plist 根键 Integer `wallpaperRepresentingIdentifier` |
| `Wallpaper.plist` | plist 根键 Integer `identifier` |

同一描述符用相同 ID。不要对 CAML、其他 plist 或所有相似数字做全局替换。Mercury 保留原始描述符名称和 ID。

5. 将描述符完整上传到对应 `descriptors/.queryshare-<UUID>` 临时目录，逐文件比较 SHA-256，再 rename 到 `descriptors/<新 UUID>`；Mercury 用原名，遇到同名先备份并明确处理，不覆盖未知原件。
6. 电脑端记录 provider、版本、最终相对目录、每个文件哈希。用于后续只移除这次导入，而不是清空整个 descriptors。
7. 刷新标记在 `PB/Library/Preferences/com.apple.PosterBoard.unprotectedUserDefaults.plist` 根字典：Boolean `PBF_RESET_FILE_PROTECTIONS = True`。已有 plist 用 `edit_plist` 合并；原来不存在的文件按 `20-configuration.md` 的排他创建方法处理。
8. 在手机刷新/重启 PosterBoard，必要时重启手机，然后打开壁纸图库选择新增项目。SFTP 不会打开或终止 PosterBoard。保留用户原壁纸选择，新增成功与实际显示分别检查。

## 用照片/视频生成壁纸

这是一种 **Collections 描述符**，与上一表的 VideoCAML provider 包不是同一格式。复用导入步骤安装，生成过程全在电脑完成。

以已验证 Collections 模板为底稿，或读取以下固定提交中的 [PosterBoardTemplate.swift](https://github.com/adnan120hz/WorkTweaks/blob/373446ff36511827a4bb18ff75bfd59b2b415af2/worse_query/PosterBoardTemplate.swift) 与 [PosterBoardMaker.swift](https://github.com/adnan120hz/WorkTweaks/blob/373446ff36511827a4bb18ff75bfd59b2b415af2/worse_query/PosterBoardMaker.swift)。模板中的 `providerInfoBase64` 是 NSKeyedArchiver 数据，应 Base64 解码原样保存，不拿普通空 plist 代替。

生成结构：

```text
<descriptor>/
  com.apple.posterkit.provider.descriptor.identifier   # 整数 ID 的 UTF-8 文本
  com.apple.posterkit.role.identifier                  # PRPosterRoleLockScreen
  providerInfo.plist                                  # 模板中的归档数据
  versions/1/contents/
    com.apple.posterkit.provider.contents.userInfo
    <ID>.Custom-<screenClass>.wallpaper/
      Wallpaper.plist
      <ID>.Custom_Background-<screenClass>.ca/
        main.caml, index.xml, assetManifest.caml, assets/0.jpg...
      <ID>.Custom_Floating-<screenClass>.ca/
        main.caml, index.xml, assetManifest.caml
```

- `screenClass` 是目标屏幕的逻辑宽高与缩放，如 `390w-844h@3x~iphone`。从该手机现有描述符/已知屏幕信息读取，不能照抄示例当成所有设备通用。
- 照片缩放最长边不超过 1920，生成一张 `0.jpg`；上游使用 JPEG quality 0.9、时长 1 秒的一帧动画，并明确该照片变体没有真机验证。
- 视频取前 12 秒，最多 30fps，应用原视频旋转，最长边不超过 1920，连续编号 `0.jpg`…；可用电脑端 FFmpeg 抽帧。动画时长取实际帧数/采样帧率。
- 背景 `main.caml` 使用 `CAKeyframeAnimation`，`keyPath="contents"`、`beginTime="1e-100"`、`duration=<实际秒数>`、`repeatCount="inf"`、`removedOnCompletion="0"`，values 为按顺序的 `<CGImage src="assets/N.jpg"/>`。初始 contents 为 `assets/0.jpg`，layer bounds/position 与图片尺寸相符。
- 上游“loop”开关实际控制 `autoreverses` 的 0/1；`repeatCount` 仍为 inf。不要把它误写成关闭重复播放。
- `index.xml` 的 `documentWidth`、`documentHeight` 使用真实帧尺寸，`rootDocument=main.caml`、`assetManifest=assetManifest.caml`。Floating 层与 assetManifest 从模板原样取用。
- `Wallpaper.plist` 根字典：`appearanceAware=True`，`contentVersion=2.01`，`family='Custom'`，`identifier=<ID>`，`logicalScreenClass=<screenClass>`，`name=<名称>`，`version=1`；`assets.lockAndHome.default` 内设置 `backgroundAnimationFileName`、`floatingAnimationFileNameKey`、`identifier`、`name`、`type='LayeredAnimation'`。
- contents userInfo 根字典：`posterEnvironmentOverrides=b'{}'`、`wallpaperRepresentingFileName=<wallpaper目录名>`、`wallpaperRepresentingIdentifier=<ID>`。

生成后解析 plist/XML 并检查所有资源引用存在，再按导入流程上传。Mercury 格式不能靠把此模板的 provider 名替换一下生成，应使用有效 Mercury 包。

## 移除、重置与恢复

- 移除一份导入：先核对记录中每个文件的当前哈希，只删除该记录拥有的描述符；有其他变化先停止。恢复刷新标记的原字段，再刷新手机壁纸界面。
- 重置 Collections/Mercury/视频：先下载备份所选 provider 的整个 descriptors，清空**该 provider** 的子项，然后刷新。此操作会删除该分类的现有自定义内容，不是默认导入步骤。
- 恢复重置前状态：把备份目录按原 provider/版本/名称写回，校验并刷新。不要把旧版本 store 硬塞进新的 store 版本。

## 拨号键盘主题

目标 App：`com.apple.mobilephone`。先在手机打开拨号键盘，让缓存生成。路径为 `APP/Library/Caches/TelephonyUI-10`；旧系统可能为 TelephonyUI-8/9，必须按实际目录选择。

现有 PNG 文件由地区前缀、键名与状态后缀拼成。键名片段：`-1-`、`-2-A B C`、`-3-D E F`、`-4-G H I`、`-5-J K L`、`-6-M N O`、`-7-P Q R S`、`-8-T U V`、`-9-W X Y Z`、`-*-`、`-0-+`、`-#-`。后缀：`--mask.png`、`--white.png`、`-hi-mask.png`、`-hi-white.png`、`--white-bold.png`、`--mask-bold.png`。

1. 枚举并备份实际文件名；从现有缓存读取地区前缀，不能固定使用 other。
2. 逐个读取 PNG 尺寸/透明度，按原尺寸渲染替换图。mask 为浅色界面，white 为深色界面；高亮与 bold 也分别处理。上游另有 150/205/225 点尺寸和圆形裁切选项，可在电脑渲染时实现。
3. 用 `write_existing` 替换选中的实际 PNG；只替换相关键的变体。导入 ZIP 主题时先按键号、明暗/高亮/bold 对齐目标文件，不连同其他地区缓存一起覆盖。
4. 在手机 Phone 中切换明暗外观观察。上游特别提示**不要强制结束 Phone**，缓存可能重新生成；必要时重启。
5. 还原写回原 PNG。明确要重置整个键盘缓存时才清空所选 TelephonyUI 目录，再打开 Phone 重新生成。

来源：[Erosion PBHandler.swift](https://github.com/jailbreakdotparty/Erosion/blob/12c0a2d00c444c9b09112608b47d4d6c10e0df14/Erosion/Tweaks/PosterBoard/PBHandler.swift)、[KeypadManager.swift](https://github.com/jailbreakdotparty/Erosion/blob/12c0a2d00c444c9b09112608b47d4d6c10e0df14/Erosion/Tweaks/Keypads/KeypadManager.swift)、[GestaltX CustomizationThemes.swift](https://github.com/huamidev/GestaltX/blob/72bf625befdb5e9e16d52c663e123f9fbc8ec7bf/GestaltX/CustomizationThemes.swift)、[CustomizationStore.swift](https://github.com/huamidev/GestaltX/blob/72bf625befdb5e9e16d52c663e123f9fbc8ec7bf/GestaltX/CustomizationStore.swift)。
