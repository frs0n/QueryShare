"""Computer-side helpers for QueryShare tutorials. Import after opening SFTP."""
import copy
import json
import plistlib
import stat
import uuid
from pathlib import Path

MG = '/private/var/containers/Shared/SystemGroup/systemgroup.com.apple.mobilegestaltcache/Library/Caches/com.apple.MobileGestalt.plist'
DELETE = object()


def read(s, path):
    with s.open(path, 'rb') as f:
        return f.read()


def write_existing(s, path, expected, data):
    attrs = s.lstat(path)
    if not stat.S_ISREG(attrs.st_mode):
        raise ValueError('Expected an existing regular file: ' + path)
    if read(s, path) != expected:
        raise RuntimeError('File changed before write: ' + path)
    with s.open(path, 'r+b') as f:
        f.write(data)
        f.truncate(len(data))
        f.flush()
    if read(s, path) != data:
        raise RuntimeError('Read-back mismatch; retain backup: ' + path)


def _parent(root, keys):
    node = root
    for key in keys[:-1]:
        node = node[key]
        if not isinstance(node, dict):
            raise ValueError('Expected dictionary: ' + str(keys))
    return node, keys[-1]


def _encoded(root, original):
    fmt = plistlib.FMT_BINARY if original.startswith(b'bplist00') else plistlib.FMT_XML
    return plistlib.dumps(root, fmt=fmt, sort_keys=False)


def edit_plist(s, path, changes, backup_dir='queryshare-backups', expected=None):
    original = read(s, path)
    if expected is not None and original != expected:
        raise RuntimeError('File changed while preparing patch: ' + path)
    root = plistlib.loads(original)
    paths = list(changes)
    if not paths or any(not isinstance(p, tuple) or not p for p in paths):
        raise ValueError('Use nonempty tuple paths')
    if any(a != b and len(a) < len(b) and b[:len(a)] == a for a in paths for b in paths):
        raise ValueError('Overlapping parent/child paths')
    for keys, value in changes.items():
        parent, key = _parent(root, keys)
        if value is DELETE:
            parent.pop(key, None)
        else:
            parent[key] = copy.deepcopy(value)
    candidate = _encoded(root, original)
    folder = Path(backup_dir) / str(uuid.uuid4())
    folder.mkdir(parents=True, mode=0o700)
    (folder / 'before.plist').write_bytes(original)
    (folder / 'after.plist').write_bytes(candidate)
    (folder / 'change.json').write_text(json.dumps({'path': path, 'keys': paths}), encoding='utf-8')
    write_existing(s, path, original, candidate)
    return str(folder)


def restore_plist(s, record):
    folder = Path(record)
    meta = json.loads((folder / 'change.json').read_text(encoding='utf-8'))
    before = plistlib.loads((folder / 'before.plist').read_bytes())
    after = plistlib.loads((folder / 'after.plist').read_bytes())
    path = meta['path']
    current_bytes = read(s, path)
    current = plistlib.loads(current_bytes)
    if path == MG:
        for key in ('CacheUUID', 'CacheVersion'):
            if current.get(key) != before.get(key):
                raise RuntimeError('MobileGestalt layout changed; do not restore an old record')
    for keys in meta['keys']:
        old_parent, key = _parent(before, keys)
        new_parent, _ = _parent(after, keys)
        parent, _ = _parent(current, keys)
        # Encode values for a type-sensitive comparison (True is not Integer 1).
        def packed(d):
            return plistlib.dumps({'exists': key in d, 'value': d.get(key, '')}, fmt=plistlib.FMT_BINARY)
        if packed(parent) not in (packed(new_parent), packed(old_parent)):
            raise RuntimeError('Field changed since this operation: ' + str(keys))
        if key in old_parent:
            parent[key] = copy.deepcopy(old_parent[key])
        else:
            parent.pop(key, None)
    write_existing(s, path, current_bytes, _encoded(current, current_bytes))


def download_tree(s, remote, local):
    """Copy regular files/directories; reject links instead of following them."""
    local = Path(local)
    info = s.lstat(remote)
    if stat.S_ISDIR(info.st_mode):
        local.mkdir(parents=True, exist_ok=True)
        for entry in s.listdir_attr(remote):
            name = entry.filename
            if name in ('.', '..') or '/' in name or '\\' in name:
                raise ValueError('Invalid child name')
            download_tree(s, remote.rstrip('/') + '/' + name, local / name)
    elif stat.S_ISREG(info.st_mode):
        local.parent.mkdir(parents=True, exist_ok=True)
        s.get(remote, str(local))
    else:
        raise ValueError('Unsupported link/special file: ' + remote)


def upload_tree(s, local, remote):
    """Merge files from a local tree; never delete destination-only entries."""
    local = Path(local)
    if local.is_symlink():
        raise ValueError('Local symbolic link: ' + str(local))
    try:
        current = s.lstat(remote)
    except FileNotFoundError:
        current = None
    if local.is_dir():
        if current is None:
            s.mkdir(remote)
        elif not stat.S_ISDIR(current.st_mode):
            raise ValueError('Destination is not a directory: ' + remote)
        for item in local.iterdir():
            upload_tree(s, item, remote.rstrip('/') + '/' + item.name)
    elif local.is_file():
        data = local.read_bytes()
        if current is None:
            with s.open(remote, 'wx') as f:
                f.write(data)
            if read(s, remote) != data:
                raise RuntimeError('Read-back mismatch: ' + remote)
        else:
            write_existing(s, remote, read(s, remote), data)
    else:
        raise ValueError('Unsupported local item: ' + str(local))


def remove_tree(s, remote):
    """Delete exactly the selected tree; callers must first back it up."""
    if stat.S_ISDIR(s.lstat(remote).st_mode):
        for name in s.listdir(remote):
            if name in ('.', '..') or '/' in name or '\\' in name:
                raise ValueError('Invalid child name')
            remove_tree(s, remote.rstrip('/') + '/' + name)
        s.rmdir(remote)
    else:
        s.remove(remote)
