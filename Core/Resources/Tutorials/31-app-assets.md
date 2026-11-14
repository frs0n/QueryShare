# App 声音与启动图

## 替换 App 通知声音

目标为选定 App 的数据容器或已核实属于该 App 的 AppGroup。按顺序扫描：`Library/Sounds/`、`Library/Sound/`、`Sounds/`、`Sound/`，只处理其中实际的普通音频文件。

上游扩展名：wav、caf、aif、aiff、m4a、mp3、aac、flac。它们不代表系统通知可播放所有这些编码；优先保持原文件编码。

1. 下载选定音频并备份，使用电脑端 `ffprobe` 查看 codec、采样率、声道数和时长。
2. 将新声音转换成原文件**相同编码、采样率和声道数**。例如原始为 44100Hz 单声道 PCM WAV 时，可用：

```sh
ffmpeg -i input.mp3 -t 29.9 -ar 44100 -ac 1 -c:a pcm_s16le replacement.wav
```

3. 用 `ffprobe` 验证输出，不仅看扩展名。上游限制小于 30 秒且不超过 32MiB。
4. `write_existing(s, REMOTE, original, replacement)` 原位替换。让 App 重新发一条真实通知测试；服务端指定声音、App 内音效、静音设置可能覆盖效果。
5. 还原时写回原音频，保持文件名。App 更新或重新下载声音后需重新定位。

## 新建同名通知声音覆盖

已知 App/通知实际请求的**准确文件名**时，在该 App 的 `Library/Sounds/<准确文件名>` 新建可播放的音频；不能猜名字，也不要修改只读 App bundle。声音名可从已有配置/用户提供的通知信息取得。只靠 SFTP 没有设备实时日志捕获能力。

目录不存在时只创建 `Library/Sounds`；先 lstat 确认父目录不是链接。文件用 `open(path,'wx')` 排他创建并回读。记录原来不存在；还原时核对文件还是此次创建的内容再删除。别把“文件上传成功”当成通知已引用它。

## 替换 App 启动快照

目标目录：

`APP/Library/SplashBoard/Snapshots/<bundleID> - {DEFAULT GROUP}/`

1. 让目标 App 正常启动过一次，再退出；保持 QueryShare 前台。枚举上述目录，选择实际的 png/jpg/jpeg/ktx 文件，备份每个原件与名称。
2. 读取每个原件的像素尺寸，替换图按原尺寸做居中 aspect-fill 裁切、sRGB、不透明背景。不同方向/外观快照分别处理，不能一张尺寸直接覆盖全部。
3. 普通图片可用 Pillow：

```python
from PIL import Image, ImageOps
from io import BytesIO
original = read(s, REMOTE)
with Image.open(BytesIO(original)) as im:
    size = im.size
with Image.open('photo.jpg') as im:
    image = ImageOps.fit(ImageOps.exif_transpose(im).convert('RGB'), size)
out = BytesIO()
image.save(out, format='PNG')
replacement = out.getvalue()
write_existing(s, REMOTE, original, replacement)
```

上游会输出 PNG 字节并保留快照文件名。若原件以 `AAPL\r\n\x1a\n` 开头，则是特殊快照容器：已核对的版本 HEAD 在字节 12…15、版本在 16、宽高为偏移 40/44 的 UInt32 little-endian。必须先验证头和版本为 1，不能用 PNG 解码器读取。GestaltX 的相应实现支持此类输入后仍输出 PNG；其他未知 ktx/快照格式不可仅凭扩展名套用，需匹配该格式的解码器。

4. 回读验证；冷启动 App 观察，系统可能重新生成快照。还原使用原文件字节，不删除 App 的整个 Library。该方法修改的是 SplashBoard 快照，不会改 App 内真正的 launch storyboard 或运行界面。

来源：[GestaltX AppSoundFiles.swift](https://github.com/huamidev/GestaltX/blob/72bf625befdb5e9e16d52c663e123f9fbc8ec7bf/GestaltX/AppSoundFiles.swift)、[AppSoundCodec.swift](https://github.com/huamidev/GestaltX/blob/72bf625befdb5e9e16d52c663e123f9fbc8ec7bf/GestaltX/AppSoundCodec.swift)、[LaunchArtworkFiles.swift](https://github.com/huamidev/GestaltX/blob/72bf625befdb5e9e16d52c663e123f9fbc8ec7bf/GestaltX/LaunchArtworkFiles.swift)、[LaunchArtworkImages.swift](https://github.com/huamidev/GestaltX/blob/72bf625befdb5e9e16d52c663e123f9fbc8ec7bf/GestaltX/LaunchArtworkImages.swift)。
