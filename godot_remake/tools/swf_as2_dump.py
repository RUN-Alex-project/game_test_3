#!/usr/bin/env python3
"""ActionScript 2 bytecode disassembler for SWF files.

Python standard library only (project rule: no pip dependencies).

What it does
------------
1. Opens a SWF container (FWS uncompressed / CWS zlib), skips the frame
   rectangle and header fields, then walks the top level tag stream.
2. Tracks the *frame number* while walking (ShowFrame increments it) and binds
   every FrameLabel to the frame it appears on, so each action block can be
   attributed to a named frame such as a map name.
3. Recurses into DefineSprite so action blocks nested inside movie clips are
   also disassembled, and resolves which root frames a sprite is placed on
   (directly or through other sprites) by following PlaceObject2 records.
4. Collects action bytecode from every carrier tag:
   DoAction, DoInitAction, DefineButton, DefineButton2 (button condition
   actions) and PlaceObject2 clip actions.
5. Disassembles the AS2 opcodes and prints human readable output.
6. Optionally runs a small abstract stack interpreter over the disassembly and
   emits structured JSON "events" (variable assignments, member assignments,
   method calls, frame jumps) which is what makes the map link table
   recoverable.

7. Optionally reconstructs the original map link table (--map-links). Map
   changes in this title are not encoded as data tables: every exit is an
   instance of one shared "exit arrow" movie clip whose onClipEvent(load)
   assigns a per-instance variable `map`, while the clip's own onRelease does
   `_root.nowmap = map; _root.gotoAndStop(map)`. Recovering the graph therefore
   requires simulating the root display list (PlaceObject2 / RemoveObject2)
   because Flash keeps objects alive across frames, so some map frames inherit
   an exit arrow that was placed on an earlier frame.

Usage
-----
    python swf_as2_dump.py <file.swf> [--out disasm.txt] [--json events.json]
                                      [--map-links links.json]
                                      [--filter SUBSTR] [--quiet]

--filter only prints action blocks whose disassembly text contains SUBSTR.
"""

import argparse
import hashlib
import json
import os
import struct
import sys
import zlib

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")


# --------------------------------------------------------------------------
# primitive readers
# --------------------------------------------------------------------------

def decode_str(raw):
    """SWF >= 6 stores strings as UTF-8; fall back to GBK for odd authoring."""
    try:
        return raw.decode("utf-8")
    except UnicodeDecodeError:
        try:
            return raw.decode("gbk")
        except UnicodeDecodeError:
            return raw.decode("latin-1")


class Reader(object):
    def __init__(self, data, pos=0):
        self.d = data
        self.p = pos
        self._bitbuf = 0
        self._bitcnt = 0

    def align(self):
        self._bitbuf = 0
        self._bitcnt = 0

    def eof(self):
        return self.p >= len(self.d)

    def u8(self):
        v = self.d[self.p]
        self.p += 1
        return v

    def u16(self):
        v = struct.unpack_from("<H", self.d, self.p)[0]
        self.p += 2
        return v

    def s16(self):
        v = struct.unpack_from("<h", self.d, self.p)[0]
        self.p += 2
        return v

    def u32(self):
        v = struct.unpack_from("<I", self.d, self.p)[0]
        self.p += 4
        return v

    def s32(self):
        v = struct.unpack_from("<i", self.d, self.p)[0]
        self.p += 4
        return v

    def f32(self):
        v = struct.unpack_from("<f", self.d, self.p)[0]
        self.p += 4
        return v

    def f64(self):
        # ActionPush DOUBLE stores the two 32 bit words in swapped order.
        raw = self.d[self.p:self.p + 8]
        self.p += 8
        return struct.unpack("<d", raw[4:8] + raw[0:4])[0]

    def bits(self, n):
        v = 0
        for _ in range(n):
            if self._bitcnt == 0:
                self._bitbuf = self.d[self.p]
                self.p += 1
                self._bitcnt = 8
            v = (v << 1) | ((self._bitbuf >> (self._bitcnt - 1)) & 1)
            self._bitcnt -= 1
        return v

    def sbits(self, n):
        v = self.bits(n)
        if n and (v >> (n - 1)) & 1:
            v -= (1 << n)
        return v

    def cstring(self):
        end = self.d.index(b"\x00", self.p)
        raw = self.d[self.p:end]
        self.p = end + 1
        return decode_str(raw)

    def rect(self):
        self.align()
        nbits = self.bits(5)
        for _ in range(4):
            self.sbits(nbits)
        self.align()

    def matrix(self):
        self.align()
        if self.bits(1):
            nb = self.bits(5)
            self.sbits(nb)
            self.sbits(nb)
        if self.bits(1):
            nb = self.bits(5)
            self.sbits(nb)
            self.sbits(nb)
        nb = self.bits(5)
        self.sbits(nb)
        self.sbits(nb)
        self.align()

    def cxform(self, with_alpha):
        self.align()
        has_add = self.bits(1)
        has_mult = self.bits(1)
        nb = self.bits(4)
        count = 4 if with_alpha else 3
        if has_mult:
            for _ in range(count):
                self.sbits(nb)
        if has_add:
            for _ in range(count):
                self.sbits(nb)
        self.align()


# --------------------------------------------------------------------------
# SWF container
# --------------------------------------------------------------------------

TAG_NAMES = {
    0: "End", 1: "ShowFrame", 4: "PlaceObject", 5: "RemoveObject",
    7: "DefineButton", 9: "SetBackgroundColor", 12: "DoAction",
    26: "PlaceObject2", 28: "RemoveObject2", 34: "DefineButton2",
    39: "DefineSprite", 43: "FrameLabel", 59: "DoInitAction",
    69: "FileAttributes", 70: "PlaceObject3",
}

ACTION_CARRIERS = (7, 12, 34, 59)


def load_swf(path):
    with open(path, "rb") as fh:
        raw = fh.read()
    sig = raw[0:3]
    version = raw[3]
    declared = struct.unpack_from("<I", raw, 4)[0]
    if sig == b"FWS":
        body = raw[8:]
    elif sig == b"CWS":
        body = zlib.decompress(raw[8:])
    elif sig == b"ZWS":
        raise SystemExit("ZWS (LZMA) SWF is not supported by this tool")
    else:
        raise SystemExit("not a SWF file: %r" % (sig,))
    return {
        "path": path,
        "signature": sig.decode("ascii"),
        "version": version,
        "declared_length": declared,
        "file_size": len(raw),
        "sha256": hashlib.sha256(raw).hexdigest(),
        "body": body,
    }


class SwfWalker(object):
    """Walks the tag tree, keeping frame numbers and labels in sync."""

    def __init__(self, swf):
        self.swf = swf
        self.version = swf["version"]
        # every action block found, in discovery order
        self.blocks = []
        # frame -> label for the root timeline
        self.root_labels = {}
        # sprite id -> {frame: label}
        self.sprite_labels = {}
        # sprite id -> set of character ids placed inside it
        self.sprite_children = {}
        # root frame -> set of character ids placed on it
        self.root_frame_chars = {}
        self.sprite_frame_counts = {}
        self.tag_counter = 0
        self.warnings = []

    # -- container walking -------------------------------------------------

    def run(self):
        r = Reader(self.swf["body"])
        r.rect()
        r.u16()  # frame rate (8.8 fixed)
        self.root_frame_count = r.u16()
        self.walk_tags(r, len(self.swf["body"]), container=None)

    def walk_tags(self, r, end, container):
        """container is None for the root timeline, else the sprite id."""
        frame = 1
        labels = self.root_labels if container is None else \
            self.sprite_labels.setdefault(container, {})
        while r.p < end:
            tag_start = r.p
            try:
                code_len = r.u16()
            except (struct.error, IndexError):
                break
            code = code_len >> 6
            length = code_len & 0x3F
            if length == 0x3F:
                length = r.u32()
            body_start = r.p
            body_end = body_start + length
            if body_end > end:
                self.warnings.append(
                    "tag %d at 0x%X claims length %d beyond container end"
                    % (code, tag_start, length))
                break
            self.tag_counter += 1
            tag_index = self.tag_counter

            if code == 0:
                break
            elif code == 1:  # ShowFrame
                frame += 1
            elif code == 43:  # FrameLabel
                sub = Reader(self.swf["body"], body_start)
                try:
                    labels[frame] = sub.cstring()
                except ValueError:
                    pass
            elif code == 39:  # DefineSprite
                sub = Reader(self.swf["body"], body_start)
                sprite_id = sub.u16()
                self.sprite_frame_counts[sprite_id] = sub.u16()
                self.sprite_children.setdefault(sprite_id, set())
                self.walk_tags(sub, body_end, container=sprite_id)
            elif code in (4, 26, 70):
                self.parse_place(code, body_start, body_end, container, frame,
                                 tag_index)
            elif code in ACTION_CARRIERS:
                self.collect_actions(code, body_start, body_end, container,
                                     frame, tag_index)

            r.p = body_end
            r.align()
        # remember label map
        if container is None:
            self.root_labels = labels

    def parse_place(self, code, body_start, body_end, container, frame,
                    tag_index):
        data = self.swf["body"]
        r = Reader(data, body_start)
        try:
            if code == 4:  # PlaceObject
                char_id = r.u16()
                r.u16()  # depth
                self.note_placement(container, frame, char_id)
                return
            flags = r.u8()
            if code == 70:  # PlaceObject3 has a second flag byte
                flags2 = r.u8()
            else:
                flags2 = 0
            depth = r.u16()
            if code == 70 and (flags2 & 0x08):
                r.cstring()  # class name
            char_id = None
            if flags & 0x02:
                char_id = r.u16()
            if flags & 0x04:
                r.matrix()
            if flags & 0x08:
                r.cxform(True)
            if flags & 0x10:
                r.u16()  # ratio
            if flags & 0x20:
                r.cstring()  # name
            if flags & 0x40:
                r.u16()  # clip depth
            if code == 70:
                if flags2 & 0x01:
                    self.skip_filter_list(r)
                if flags2 & 0x02:
                    r.u8()
                if flags2 & 0x04:
                    r.u8()
            if char_id is not None:
                self.note_placement(container, frame, char_id)
            if flags & 0x80:
                self.parse_clip_actions(r, body_end, container, frame,
                                        tag_index, char_id, depth)
        except (IndexError, struct.error, ValueError) as exc:
            self.warnings.append("PlaceObject parse failed at 0x%X: %s"
                                 % (body_start, exc))

    def skip_filter_list(self, r):
        count = r.u8()
        for _ in range(count):
            fid = r.u8()
            if fid == 0:
                r.p += 8   # drop shadow
            elif fid == 1:
                r.p += 8   # blur
            elif fid == 2:
                r.p += 8   # glow
            elif fid == 3:
                r.p += 12  # bevel
            elif fid in (4, 5):
                nc = r.u8()
                r.p += nc * 5 + 12
            elif fid == 6:
                n = r.u8()
                r.p += 1 + n * 4 + 8
            elif fid == 7:
                r.p += 34  # color matrix (20 floats) approximated
            else:
                raise ValueError("unknown filter id %d" % fid)

    def parse_clip_actions(self, r, body_end, container, frame, tag_index,
                           char_id, depth):
        r.u16()  # reserved
        if self.version >= 6:
            r.u32()
        else:
            r.u16()
        while r.p < body_end:
            if self.version >= 6:
                flags = r.u32()
            else:
                flags = r.u16()
            if flags == 0:
                break
            size = r.u32()
            act_start = r.p
            if flags & 0x00020000:  # KeyPress
                r.u8()
                act_start = r.p
            act_end = min(r.p + size, body_end)
            self.add_block(container, frame, tag_index, 26, "ClipActions",
                           act_start, act_end,
                           extra={"clip_flags": "0x%08X" % flags,
                                  "character": char_id, "depth": depth})
            r.p = r.p + size

    def note_placement(self, container, frame, char_id):
        if container is None:
            self.root_frame_chars.setdefault(frame, set()).add(char_id)
        else:
            self.sprite_children.setdefault(container, set()).add(char_id)

    def collect_actions(self, code, body_start, body_end, container, frame,
                        tag_index):
        data = self.swf["body"]
        if code in (12, 59):
            r = Reader(data, body_start)
            extra = {}
            if code == 59:
                extra["sprite_id"] = r.u16()
            self.add_block(container, frame, tag_index, code,
                           TAG_NAMES.get(code, "Tag%d" % code),
                           r.p, body_end, extra=extra)
            return
        if code == 34:  # DefineButton2
            r = Reader(data, body_start)
            button_id = r.u16()
            r.u8()  # reserved / TrackAsMenu
            action_offset_pos = r.p
            action_offset = r.u16()
            if action_offset == 0:
                return
            p = action_offset_pos + action_offset
            while p < body_end:
                sub = Reader(data, p)
                cond_size = sub.u16()
                cond_flags = sub.u16()
                act_start = sub.p
                if cond_size == 0:
                    act_end = body_end
                else:
                    act_end = min(p + cond_size, body_end)
                self.add_block(container, frame, tag_index, 34,
                               "DefineButton2", act_start, act_end,
                               extra={"button_id": button_id,
                                      "cond": button_cond_text(cond_flags)})
                if cond_size == 0:
                    break
                p += cond_size
            return
        if code == 7:  # DefineButton
            r = Reader(data, body_start)
            button_id = r.u16()
            try:
                while True:
                    flags = r.u8()
                    if flags == 0:
                        break
                    r.u16()  # character
                    r.u16()  # depth
                    r.matrix()
            except (IndexError, struct.error):
                self.warnings.append("DefineButton %d record parse failed"
                                     % button_id)
                return
            self.add_block(container, frame, tag_index, 7, "DefineButton",
                           r.p, body_end,
                           extra={"button_id": button_id,
                                  "cond": "on(release)"})
            return

    def add_block(self, container, frame, tag_index, tag_code, tag_name,
                  start, end, extra=None):
        if end <= start:
            return
        self.blocks.append({
            "tag_index": tag_index,
            "tag_code": tag_code,
            "tag_name": tag_name,
            "container": "root" if container is None else "sprite%d" % container,
            "container_id": container,
            "frame": frame,
            "byte_start": start,
            "byte_end": end,
            "extra": extra or {},
        })

    # -- sprite -> root frame resolution -----------------------------------

    def build_placement_index(self):
        self.parents = {}
        for sprite_id, kids in self.sprite_children.items():
            for kid in kids:
                self.parents.setdefault(kid, set()).add(sprite_id)
        self.char_root_frames = {}
        for frame, chars in self.root_frame_chars.items():
            for c in chars:
                self.char_root_frames.setdefault(c, set()).add(frame)

    def root_frames_of(self, char_id, _seen=None):
        if _seen is None:
            _seen = set()
        if char_id in _seen:
            return set()
        _seen.add(char_id)
        frames = set(self.char_root_frames.get(char_id, ()))
        for parent in self.parents.get(char_id, ()):
            frames |= self.root_frames_of(parent, _seen)
        return frames


    # -- root display list simulation --------------------------------------

    def simulate_root_display(self):
        """Replay the root timeline PlaceObject2 / RemoveObject2 stream.

        Flash resolves the display list of frame N from every placement and
        removal tag between frame 1 and frame N, so an object placed once and
        never removed stays visible on later frames. Returns
        frame -> {depth: {"character", "map", "placed_on"}}.
        """
        data = self.swf["body"]
        r = Reader(data)
        r.rect()
        r.u16()
        r.u16()
        frame = 1
        display = {}
        snapshots = {}
        end = len(data)
        while r.p < end:
            code_len = r.u16()
            code = code_len >> 6
            length = code_len & 0x3F
            if length == 0x3F:
                length = r.u32()
            body_start = r.p
            body_end = body_start + length
            if code == 0:
                break
            if code == 1:
                snapshots[frame] = dict(display)
                frame += 1
            elif code == 28:
                sub = Reader(data, body_start)
                display.pop(sub.u16(), None)
            elif code == 26:
                sub = Reader(data, body_start)
                flags = sub.u8()
                depth = sub.u16()
                char_id = sub.u16() if flags & 0x02 else None
                if flags & 0x04:
                    sub.matrix()
                if flags & 0x08:
                    sub.cxform(True)
                if flags & 0x10:
                    sub.u16()
                if flags & 0x20:
                    sub.cstring()
                if flags & 0x40:
                    sub.u16()
                map_value = None
                if flags & 0x80:
                    map_value = self.clip_map_variable(sub, body_end)
                if char_id is not None:
                    display[depth] = {"character": char_id, "map": map_value,
                                      "placed_on": frame}
                elif depth in display and map_value is not None:
                    display[depth]["map"] = map_value
            r.p = body_end
            r.align()
        return snapshots

    def clip_map_variable(self, r, body_end):
        """Return the string a placement's clip actions assign to var `map`."""
        data = self.swf["body"]
        r.u16()
        if self.version >= 6:
            r.u32()
        else:
            r.u16()
        found = None
        while r.p < body_end:
            flags = r.u32() if self.version >= 6 else r.u16()
            if flags == 0:
                break
            size = r.u32()
            act_start = r.p
            if flags & 0x00020000:
                r.u8()
                act_start = r.p
            act_end = min(act_start + size, body_end)
            interp = Interp([])
            interp.run(parse_actions(data, act_start, act_end, []), "clip")
            for e in interp.events:
                if e["kind"] == "set_var" and e.get("name") == "map" \
                        and isinstance(e.get("value"), str):
                    found = e["value"]
            r.p = act_start + size
        return found


def button_cond_text(flags):
    names = []
    bits = [
        (0x0001, "idleToOverUp"), (0x0002, "overUpToIdle"),
        (0x0004, "overUpToOverDown"), (0x0008, "overDownToOverUp"),
        (0x0010, "overDownToOutDown"), (0x0020, "outDownToOverDown"),
        (0x0040, "outDownToIdle"), (0x0080, "idleToOverDown"),
        (0x0100, "overDownToIdle"),
    ]
    for bit, name in bits:
        if flags & bit:
            names.append(name)
    key = (flags >> 9) & 0x7F
    if key:
        names.append("keyPress(%d)" % key)
    return "+".join(names) if names else "cond0x%04X" % flags


# --------------------------------------------------------------------------
# AS2 action decoding
# --------------------------------------------------------------------------

ACTIONS = {
    0x00: "End", 0x04: "NextFrame", 0x05: "PreviousFrame", 0x06: "Play",
    0x07: "Stop", 0x08: "ToggleQuality", 0x09: "StopSounds", 0x0A: "Add",
    0x0B: "Subtract", 0x0C: "Multiply", 0x0D: "Divide", 0x0E: "Equals",
    0x0F: "Less", 0x10: "And", 0x11: "Or", 0x12: "Not", 0x13: "StringEquals",
    0x14: "StringLength", 0x15: "StringExtract", 0x17: "Pop",
    0x18: "ToInteger", 0x1C: "GetVariable", 0x1D: "SetVariable",
    0x20: "SetTarget2", 0x21: "StringAdd", 0x22: "GetProperty",
    0x23: "SetProperty", 0x24: "CloneSprite", 0x25: "RemoveSprite",
    0x26: "Trace", 0x27: "StartDrag", 0x28: "EndDrag", 0x29: "StringLess",
    0x2A: "Throw", 0x2B: "CastOp", 0x2C: "ImplementsOp",
    0x30: "RandomNumber", 0x31: "MBStringLength", 0x32: "CharToAscii",
    0x33: "AsciiToChar", 0x34: "GetTime", 0x35: "MBStringExtract",
    0x36: "MBCharToAscii", 0x37: "MBAsciiToChar", 0x3A: "Delete",
    0x3B: "Delete2", 0x3C: "DefineLocal", 0x3D: "CallFunction",
    0x3E: "Return", 0x3F: "Modulo", 0x40: "NewObject", 0x41: "DefineLocal2",
    0x42: "InitArray", 0x43: "InitObject", 0x44: "TypeOf", 0x45: "TargetPath",
    0x46: "Enumerate", 0x47: "Add2", 0x48: "Less2", 0x49: "Equals2",
    0x4A: "ToNumber", 0x4B: "ToString", 0x4C: "PushDuplicate",
    0x4D: "StackSwap", 0x4E: "GetMember", 0x4F: "SetMember",
    0x50: "Increment", 0x51: "Decrement", 0x52: "CallMethod",
    0x53: "NewMethod", 0x54: "InstanceOf", 0x55: "Enumerate2",
    0x60: "BitAnd", 0x61: "BitOr", 0x62: "BitXor", 0x63: "BitLShift",
    0x64: "BitRShift", 0x65: "BitURShift", 0x66: "StrictEquals",
    0x67: "Greater", 0x68: "StringGreater", 0x69: "Extends",
    0x81: "GotoFrame", 0x83: "GetURL", 0x87: "StoreRegister",
    0x88: "ConstantPool", 0x8A: "WaitForFrame", 0x8B: "SetTarget",
    0x8C: "GotoLabel", 0x8D: "WaitForFrame2", 0x8E: "DefineFunction2",
    0x8F: "Try", 0x94: "With", 0x96: "Push", 0x99: "Jump", 0x9A: "GetURL2",
    0x9B: "DefineFunction", 0x9D: "If", 0x9E: "Call", 0x9F: "GotoFrame2",
}


class PushVal(object):
    """One value from an ActionPush record."""

    def __init__(self, kind, value, const_index=None):
        self.kind = kind
        self.value = value
        self.const_index = const_index

    def text(self, pool):
        if self.kind == "string":
            return quote(self.value)
        if self.kind == "const":
            resolved = pool[self.const_index] \
                if 0 <= self.const_index < len(pool) else "<oob>"
            return "%s(c%d)" % (quote(resolved), self.const_index)
        if self.kind == "null":
            return "null"
        if self.kind == "undefined":
            return "undefined"
        if self.kind == "register":
            return "r%d" % self.value
        if self.kind == "boolean":
            return "true" if self.value else "false"
        return repr(self.value)

    def resolve(self, pool):
        """Concrete Python value, or an Unknown marker."""
        if self.kind == "string":
            return self.value
        if self.kind == "const":
            if 0 <= self.const_index < len(pool):
                return pool[self.const_index]
            return Unknown("const%d" % self.const_index)
        if self.kind == "null":
            return None
        if self.kind == "undefined":
            return Unknown("undefined")
        if self.kind == "register":
            return Unknown("r%d" % self.value)
        if self.kind == "boolean":
            return bool(self.value)
        return self.value


class Unknown(object):
    def __init__(self, desc):
        self.desc = desc

    def __repr__(self):
        return "<%s>" % self.desc


class FuncVal(object):
    def __init__(self, node):
        self.node = node


def quote(s):
    return "'" + s.replace("\\", "\\\\").replace("'", "\\'") \
        .replace("\n", "\\n").replace("\r", "\\r") + "'"


def parse_actions(data, start, end, pool):
    """Parse a byte range into a list of action nodes.

    DefineFunction / DefineFunction2 bodies are nested under 'body' because the
    body bytes sit between the definition record and the opcode that consumes
    the resulting function value.
    """
    nodes = []
    p = start
    while p < end:
        off = p
        code = data[p]
        p += 1
        if code == 0:
            nodes.append({"offset": off, "code": 0, "name": "End", "args": {}})
            break
        if code >= 0x80:
            if p + 2 > end:
                break
            length = struct.unpack_from("<H", data, p)[0]
            p += 2
        else:
            length = 0
        arg_start = p
        arg_end = min(p + length, end)
        node = {
            "offset": off,
            "code": code,
            "name": ACTIONS.get(code, "Unknown0x%02X" % code),
            "args": {},
        }
        try:
            decode_args(node, data, arg_start, arg_end, pool)
        except (IndexError, struct.error, ValueError) as exc:
            node["args"]["error"] = str(exc)
        p = arg_end
        if code in (0x9B, 0x8E):
            size = node["args"].get("code_size", 0)
            body_end = min(p + size, end)
            node["body"] = parse_actions(data, p, body_end, pool)
            node["body_range"] = (p, body_end)
            p = body_end
        nodes.append(node)
    return nodes


def decode_args(node, data, start, end, pool):
    code = node["code"]
    a = node["args"]
    r = Reader(data, start)
    if code == 0x96:  # Push
        vals = []
        while r.p < end:
            t = r.u8()
            if t == 0:
                vals.append(PushVal("string", r.cstring()))
            elif t == 1:
                vals.append(PushVal("float", r.f32()))
            elif t == 2:
                vals.append(PushVal("null", None))
            elif t == 3:
                vals.append(PushVal("undefined", None))
            elif t == 4:
                vals.append(PushVal("register", r.u8()))
            elif t == 5:
                vals.append(PushVal("boolean", r.u8()))
            elif t == 6:
                vals.append(PushVal("double", r.f64()))
            elif t == 7:
                vals.append(PushVal("int", r.s32()))
            elif t == 8:
                i = r.u8()
                vals.append(PushVal("const", None, i))
            elif t == 9:
                i = r.u16()
                vals.append(PushVal("const", None, i))
            else:
                a["error"] = "unknown push type %d" % t
                break
        a["values"] = vals
    elif code == 0x88:  # ConstantPool
        count = r.u16()
        strings = []
        for _ in range(count):
            if r.p >= end:
                break
            strings.append(r.cstring())
        a["pool"] = strings
        del pool[:]
        pool.extend(strings)
    elif code == 0x81:  # GotoFrame
        a["frame"] = r.u16()
    elif code == 0x8C:  # GotoLabel
        a["label"] = r.cstring()
    elif code == 0x8B:  # SetTarget
        a["target"] = r.cstring()
    elif code == 0x83:  # GetURL
        a["url"] = r.cstring()
        a["target"] = r.cstring()
    elif code == 0x9A:  # GetURL2
        a["flags"] = r.u8()
    elif code == 0x9F:  # GotoFrame2
        f = r.u8()
        a["flags"] = f
        a["play"] = bool(f & 0x01)
        if f & 0x02:
            a["scene_bias"] = r.u16()
    elif code == 0x99 or code == 0x9D:  # Jump / If
        a["offset"] = r.s16()
    elif code == 0x87:  # StoreRegister
        a["register"] = r.u8()
    elif code == 0x8A:  # WaitForFrame
        a["frame"] = r.u16()
        a["skip"] = r.u8()
    elif code == 0x8D:  # WaitForFrame2
        a["skip"] = r.u8()
    elif code == 0x94:  # With
        a["size"] = r.u16()
    elif code == 0x9B:  # DefineFunction
        a["name"] = r.cstring()
        n = r.u16()
        a["params"] = [r.cstring() for _ in range(n)]
        a["code_size"] = r.u16()
    elif code == 0x8E:  # DefineFunction2
        a["name"] = r.cstring()
        n = r.u16()
        a["register_count"] = r.u8()
        a["flags"] = r.u16()
        params = []
        for _ in range(n):
            reg = r.u8()
            params.append((reg, r.cstring()))
        a["params2"] = params
        a["code_size"] = r.u16()
    elif code == 0x8F:  # Try
        f = r.u8()
        a["flags"] = f
        a["try_size"] = r.u16()
        a["catch_size"] = r.u16()
        a["finally_size"] = r.u16()
        if f & 0x04:
            a["catch_register"] = r.u8()
        else:
            a["catch_name"] = r.cstring()


def format_node(node, pool, indent=0):
    lines = []
    pad = "    " * indent
    a = node["args"]
    name = node["name"]
    detail = ""
    if name == "Push":
        detail = " " + ", ".join(v.text(pool) for v in a.get("values", []))
    elif name == "ConstantPool":
        strings = a.get("pool", [])
        detail = " %d entries" % len(strings)
    elif name == "GotoFrame":
        detail = " frame=%d (0-based) -> frame %d" % (a["frame"], a["frame"] + 1)
    elif name == "GotoLabel":
        detail = " " + quote(a.get("label", ""))
    elif name == "SetTarget":
        detail = " " + quote(a.get("target", ""))
    elif name == "GetURL":
        detail = " url=%s target=%s" % (quote(a.get("url", "")),
                                        quote(a.get("target", "")))
    elif name == "GotoFrame2":
        detail = " flags=0x%02X play=%s" % (a.get("flags", 0),
                                            a.get("play", False))
        if "scene_bias" in a:
            detail += " scene_bias=%d" % a["scene_bias"]
    elif name in ("Jump", "If"):
        detail = " offset=%+d -> 0x%X" % (a.get("offset", 0),
                                          node["offset"] + 5 + a.get("offset", 0))
    elif name == "StoreRegister":
        detail = " r%d" % a.get("register", 0)
    elif name == "DefineFunction":
        detail = " name=%s params=[%s] code_size=%d" % (
            quote(a.get("name", "")), ", ".join(a.get("params", [])),
            a.get("code_size", 0))
    elif name == "DefineFunction2":
        detail = " name=%s params=[%s] regs=%d flags=0x%04X code_size=%d" % (
            quote(a.get("name", "")),
            ", ".join("r%d:%s" % (r, n) for r, n in a.get("params2", [])),
            a.get("register_count", 0), a.get("flags", 0),
            a.get("code_size", 0))
    elif name == "With":
        detail = " size=%d" % a.get("size", 0)
    elif name == "WaitForFrame":
        detail = " frame=%d skip=%d" % (a.get("frame", 0), a.get("skip", 0))
    if "error" in a:
        detail += "   ! %s" % a["error"]
    lines.append("%s%04X: %s%s" % (pad, node["offset"], name, detail))
    if name == "ConstantPool":
        strings = a.get("pool", [])
        for i in range(0, len(strings), 4):
            chunk = strings[i:i + 4]
            lines.append("%s      %s" % (
                pad, "  ".join("c%d=%s" % (i + j, quote(s))
                               for j, s in enumerate(chunk))))
    for child in node.get("body", []):
        lines.extend(format_node(child, pool, indent + 1))
    if node.get("body"):
        lines.append("%s    (end function body)" % pad)
    return lines


# --------------------------------------------------------------------------
# abstract stack interpreter -> structured events
# --------------------------------------------------------------------------

# code -> (pops, pushes) for opcodes handled generically
GENERIC_STACK = {
    0x0A: (2, 1), 0x0B: (2, 1), 0x0C: (2, 1), 0x0D: (2, 1), 0x0E: (2, 1),
    0x0F: (2, 1), 0x10: (2, 1), 0x11: (2, 1), 0x12: (1, 1), 0x13: (2, 1),
    0x14: (1, 1), 0x15: (3, 1), 0x17: (1, 0), 0x18: (1, 1), 0x20: (1, 0),
    0x22: (2, 1), 0x24: (3, 0), 0x25: (1, 0), 0x26: (1, 0), 0x28: (0, 0),
    0x29: (2, 1), 0x2A: (1, 0), 0x2B: (2, 1), 0x30: (1, 1), 0x31: (1, 1),
    0x32: (1, 1), 0x33: (1, 1), 0x34: (0, 1), 0x35: (3, 1), 0x36: (1, 1),
    0x37: (1, 1), 0x3A: (2, 1), 0x3B: (1, 1), 0x3E: (1, 0), 0x3F: (2, 1),
    0x41: (1, 0), 0x44: (1, 1), 0x45: (1, 1), 0x46: (1, 1), 0x48: (2, 1),
    0x4A: (1, 1), 0x4B: (1, 1), 0x50: (1, 1), 0x51: (1, 1), 0x54: (2, 1),
    0x55: (1, 1), 0x60: (2, 1), 0x61: (2, 1), 0x62: (2, 1), 0x63: (2, 1),
    0x64: (2, 1), 0x65: (2, 1), 0x66: (2, 1), 0x67: (2, 1), 0x68: (2, 1),
    0x69: (2, 0), 0x8D: (1, 0), 0x94: (1, 0), 0x9D: (1, 0), 0x9E: (1, 0),
    0x04: (0, 0), 0x05: (0, 0), 0x06: (0, 0), 0x07: (0, 0), 0x08: (0, 0),
    0x09: (0, 0), 0x27: (0, 0), 0x2C: (0, 0),
}


def val_text(v):
    if isinstance(v, Unknown):
        return "<%s>" % v.desc
    if isinstance(v, FuncVal):
        return "<function>"
    if isinstance(v, str):
        return v
    return v


def as_name(v):
    """String form usable as a variable / member name, else None."""
    return v if isinstance(v, str) else None


class Interp(object):
    def __init__(self, pool):
        self.pool = pool
        self.events = []

    def pop(self, stack, n):
        """Pop n operands and return them in push order (bottom first)."""
        out = []
        for _ in range(n):
            out.append(stack.pop() if stack else Unknown("underflow"))
        out.reverse()
        return out

    def pop_args(self, stack, n):
        """Pop n call arguments; the first argument sits on top of the stack."""
        return [stack.pop() if stack else Unknown("underflow")
                for _ in range(n)]

    def run(self, nodes, scope):
        stack = []
        for node in nodes:
            code = node["code"]
            a = node["args"]
            if code == 0x96:
                for v in a.get("values", []):
                    stack.append(v.resolve(self.pool))
            elif code == 0x88:
                self.pool[:] = a.get("pool", [])
            elif code == 0x1C:  # GetVariable
                (name,) = self.pop(stack, 1)
                n = as_name(name)
                stack.append(Unknown("var:%s" % n) if n
                             else Unknown("var:?"))
            elif code == 0x1D:  # SetVariable
                name, value = self.pop(stack, 2)
                self.emit("set_var", scope, node, name=val_text(name),
                          value=val_text(value))
            elif code == 0x3C:  # DefineLocal
                name, value = self.pop(stack, 2)
                self.emit("set_local", scope, node, name=val_text(name),
                          value=val_text(value))
            elif code == 0x4E:  # GetMember
                obj, name = self.pop(stack, 2)
                stack.append(Unknown("%s.%s" % (path_of(obj), val_text(name))))
            elif code == 0x4F:  # SetMember
                obj, name, value = self.pop(stack, 3)
                if isinstance(value, FuncVal):
                    self.run_function(value.node,
                                      "%s.%s" % (path_of(obj), val_text(name)))
                    self.emit("define_handler", scope, node,
                              object=path_of(obj), name=val_text(name))
                else:
                    self.emit("set_member", scope, node, object=path_of(obj),
                              name=val_text(name), value=val_text(value))
            elif code == 0x23:  # SetProperty
                target, index, value = self.pop(stack, 3)
                self.emit("set_property", scope, node, target=path_of(target),
                          index=val_text(index), value=val_text(value))
            elif code == 0x21:  # StringAdd
                b, c = self.pop(stack, 2)
                if isinstance(b, str) and isinstance(c, str):
                    stack.append(b + c)
                else:
                    stack.append(Unknown("concat(%s,%s)"
                                         % (path_of(b), path_of(c))))
            elif code == 0x47:  # Add2
                b, c = self.pop(stack, 2)
                if isinstance(b, str) and isinstance(c, str):
                    stack.append(b + c)
                else:
                    stack.append(Unknown("add(%s,%s)"
                                         % (path_of(b), path_of(c))))
            elif code == 0x49:  # Equals2
                b, c = self.pop(stack, 2)
                self.emit("compare", scope, node, left=val_text(b),
                          right=val_text(c))
                stack.append(Unknown("bool"))
            elif code == 0x4C:  # PushDuplicate
                top = stack[-1] if stack else Unknown("underflow")
                stack.append(top)
            elif code == 0x4D:  # StackSwap
                if len(stack) >= 2:
                    stack[-1], stack[-2] = stack[-2], stack[-1]
            elif code == 0x87:  # StoreRegister (peeks)
                pass
            elif code == 0x3D:  # CallFunction
                # push order is: args..., argCount, functionName
                argc, name = self.pop(stack, 2)
                args = self.pop_args(stack, safe_count(argc))
                self.emit("call_function", scope, node, name=val_text(name),
                          args=[val_text(x) for x in args])
                stack.append(Unknown("ret"))
            elif code == 0x52:  # CallMethod
                # push order is: args..., argCount, object, methodName
                argc, obj, name = self.pop(stack, 3)
                args = self.pop_args(stack, safe_count(argc))
                self.emit("call_method", scope, node, object=path_of(obj),
                          method=val_text(name),
                          args=[val_text(x) for x in args])
                stack.append(Unknown("ret"))
            elif code == 0x40:  # NewObject
                argc, name = self.pop(stack, 2)
                self.pop_args(stack, safe_count(argc))
                stack.append(Unknown("new %s" % val_text(name)))
            elif code == 0x53:  # NewMethod
                argc, obj, name = self.pop(stack, 3)
                self.pop_args(stack, safe_count(argc))
                stack.append(Unknown("new %s.%s" % (path_of(obj),
                                                    val_text(name))))
            elif code == 0x42:  # InitArray
                (argc,) = self.pop(stack, 1)
                self.pop(stack, safe_count(argc))
                stack.append(Unknown("array"))
            elif code == 0x43:  # InitObject
                (argc,) = self.pop(stack, 1)
                self.pop(stack, safe_count(argc) * 2)
                stack.append(Unknown("object"))
            elif code == 0x9F:  # GotoFrame2
                (target,) = self.pop(stack, 1)
                self.emit("goto", scope, node,
                          method="gotoAndPlay" if a.get("play")
                          else "gotoAndStop",
                          target=val_text(target), via="GotoFrame2")
            elif code == 0x8C:  # GotoLabel
                self.emit("goto", scope, node, method="gotoAndStop",
                          target=a.get("label"), via="GotoLabel")
            elif code == 0x81:  # GotoFrame
                self.emit("goto", scope, node, method="gotoAndStop",
                          target=a.get("frame", 0) + 1, via="GotoFrame")
            elif code == 0x8B:  # SetTarget
                self.emit("set_target", scope, node, target=a.get("target"))
            elif code == 0x83:  # GetURL
                self.emit("get_url", scope, node, url=a.get("url"),
                          target=a.get("target"))
            elif code in (0x9B, 0x8E):  # DefineFunction(2)
                fname = a.get("name", "")
                if fname:
                    self.run_function(node, fname)
                else:
                    stack.append(FuncVal(node))
            else:
                pops, pushes = GENERIC_STACK.get(code, (0, 0))
                self.pop(stack, pops)
                for _ in range(pushes):
                    stack.append(Unknown(node["name"]))

    def run_function(self, node, label):
        self.run(node.get("body", []), label)

    def emit(self, kind, scope, node, **kw):
        rec = {"kind": kind, "scope": scope, "offset": node["offset"]}
        rec.update(kw)
        self.events.append(rec)


def safe_count(v):
    if isinstance(v, (int, float)) and not isinstance(v, bool):
        n = int(v)
        return n if 0 <= n <= 64 else 0
    return 0


def path_of(v):
    if isinstance(v, Unknown):
        d = v.desc
        if d.startswith("var:"):
            return d[4:]
        return d
    if isinstance(v, str):
        return v
    if isinstance(v, FuncVal):
        return "<function>"
    return str(v)


# --------------------------------------------------------------------------
# driver
# --------------------------------------------------------------------------

def describe_block(walker, blk):
    bits = ["tag#%d %s" % (blk["tag_index"], blk["tag_name"])]
    if blk["container_id"] is None:
        label = walker.root_labels.get(blk["frame"])
        bits.append("root frame %d" % blk["frame"])
        if label:
            bits.append("label=%s" % label)
    else:
        sid = blk["container_id"]
        bits.append("sprite%d frame %d" % (sid, blk["frame"]))
        slabel = walker.sprite_labels.get(sid, {}).get(blk["frame"])
        if slabel:
            bits.append("sprite_label=%s" % slabel)
        rframes = sorted(walker.root_frames_of(sid))
        if rframes:
            names = []
            for f in rframes:
                lbl = walker.root_labels.get(f)
                names.append("%d%s" % (f, "(%s)" % lbl if lbl else ""))
            bits.append("root_frames=[%s]" % ",".join(names))
        else:
            bits.append("root_frames=[] (never placed / runtime attached)")
    for k, v in sorted(blk["extra"].items()):
        if v is not None:
            bits.append("%s=%s" % (k, v))
    bits.append("bytes=%d" % (blk["byte_end"] - blk["byte_start"]))
    return "  ".join(bits)


# Two distinct sentinels: UNCONFIRMED means the bytecode did not let us decide,
# NO_ASSIGNMENT means the block was fully disassembled and provably has none.
UNCONFIRMED = "UNCONFIRMED"
NO_ASSIGNMENT = "NO_ASSIGNMENT_IN_FRAME_SCRIPT"


def norm_ref(v):
    """Strip the <...> / var: decoration the interpreter puts on symbols."""
    if not isinstance(v, str):
        return v
    if v.startswith("<") and v.endswith(">"):
        v = v[1:-1]
    if v.startswith("var:"):
        v = v[4:]
    return v


def block_events(walker, blk):
    nodes = parse_actions(walker.swf["body"], blk["byte_start"],
                          blk["byte_end"], [])
    interp = Interp([])
    interp.run(nodes, "toplevel")
    return interp.events, nodes


def build_map_links(walker):
    """Reconstruct the original map graph from the exit arrow placements."""
    snapshots = walker.simulate_root_display()

    # Which characters are exit arrows? Any character whose placement carries
    # an onClipEvent assigning the per-instance variable `map`.
    arrow_chars = set()
    for state in snapshots.values():
        for slot in state.values():
            if slot["map"]:
                arrow_chars.add(slot["character"])

    # (root frame, depth) -> tag index of the ClipActions carrying `map`
    clip_tag = {}
    for blk in walker.blocks:
        if blk["tag_name"] == "ClipActions" and blk["container_id"] is None \
                and blk["extra"].get("depth") is not None:
            clip_tag[(blk["frame"], blk["extra"]["depth"])] = blk["tag_index"]

    # Per-block event scan: frame scripts, goto targets, arrow gate rules.
    frame_facts = {}
    entered_by = {}
    gates = []
    for blk in walker.blocks:
        events, _ = block_events(walker, blk)
        where = describe_block(walker, blk)
        if blk["container_id"] is None and blk["tag_code"] == 12:
            facts = frame_facts.setdefault(blk["frame"], {
                "nowmap_assignments": [], "spawn": {}})
            for e in events:
                if e["kind"] in ("set_var", "set_member") \
                        and e.get("name") == "nowmap" \
                        and isinstance(e.get("value"), str):
                    facts["nowmap_assignments"].append({
                        "value": e["value"],
                        "evidence": "tag#%d offset 0x%X" % (blk["tag_index"],
                                                            e["offset"]),
                    })
                if e["kind"] == "set_member" and e.get("object") == "renwu" \
                        and e.get("name") in ("_x", "_y"):
                    facts["spawn"][e["name"]] = e.get("value")
        for e in events:
            target = None
            if e["kind"] == "goto" and isinstance(e.get("target"), str):
                target = e["target"]
            elif e["kind"] == "call_method" \
                    and e.get("method") in ("gotoAndStop", "gotoAndPlay"):
                args = e.get("args") or []
                if args and isinstance(args[0], str):
                    target = args[0]
            if target and target in set(walker.root_labels.values()):
                entered_by.setdefault(target, []).append({
                    "from": where,
                    "evidence": "tag#%d offset 0x%X" % (blk["tag_index"],
                                                        e["offset"]),
                })
        # gate rules live in the arrow clip's own onRelease handler
        if blk["container_id"] in arrow_chars and blk["tag_code"] == 12:
            pending = None
            for e in events:
                if e["kind"] == "compare":
                    left = norm_ref(e.get("left"))
                    right = e.get("right")
                    if isinstance(left, str) and left.endswith("nowmap") \
                            and isinstance(right, str):
                        pending = (right, e["offset"])
                    elif left == "map" and pending \
                            and isinstance(right, str):
                        gates.append({"from_map": pending[0], "to_map": right,
                                      "message": None,
                                      "evidence": "tag#%d offset 0x%X"
                                                  % (blk["tag_index"],
                                                     pending[1])})
                        pending = None
                elif e["kind"] == "call_method" \
                        and e.get("method") == "alertbox" and gates:
                    args = e.get("args") or []
                    if args and gates[-1]["message"] is None:
                        gates[-1]["message"] = args[0]

    gate_index = {(g["from_map"], g["to_map"]): g for g in gates}

    maps = []
    for frame in sorted(walker.root_labels):
        label = walker.root_labels[frame]
        state = snapshots.get(frame, {})
        exits = []
        for depth in sorted(state):
            slot = state[depth]
            if slot["character"] not in arrow_chars or not slot["map"]:
                continue
            gate = gate_index.get((label, slot["map"]))
            tag_index = clip_tag.get((slot["placed_on"], depth))
            exits.append({
                "target": slot["map"],
                "depth": depth,
                "placed_on_frame": slot["placed_on"],
                "inherited_from_frame": None if slot["placed_on"] == frame
                else slot["placed_on"],
                "character": slot["character"],
                "evidence": "tag#%s ClipActions onClipEvent(load) map=%s "
                            "at root frame %d depth %d"
                            % (tag_index, slot["map"], slot["placed_on"],
                               depth),
                "gate": None if gate is None else {
                    "message": gate["message"],
                    "evidence": gate["evidence"],
                },
            })
        facts = frame_facts.get(frame, {"nowmap_assignments": [], "spawn": {}})
        spawn = facts["spawn"]
        maps.append({
            "frame_label": label,
            "frame": frame,
            "is_playable_map": bool(exits) or bool(spawn),
            "nowmap": facts["nowmap_assignments"] or NO_ASSIGNMENT,
            "nextmap": {
                "per_map_value": "NOT_A_PER_MAP_FIELD",
                "reason": "nextmap is a global boolean gate, never assigned a "
                          "map name anywhere in the SWF",
            },
            "owermap": {
                "per_map_value": "NOT_A_PER_MAP_FIELD",
                "reason": "owermap is the name of the map the player currently "
                          "protects (map occupation race), not a link",
            },
            "returnmap": {
                "per_map_value": "NOT_A_VARIABLE",
                "reason": "returnmap is a function on the root timeline that "
                          "does gotoAndStop(nowmap)",
            },
            "exits": exits,
            "player_spawn": [spawn.get("_x"), spawn.get("_y")]
            if spawn else UNCONFIRMED,
            "exit_arrow_count": len(exits),
            "entered_by": entered_by.get(label, []),
        })
    return {
        "sentinels": {
            "UNCONFIRMED": "the bytecode did not let us decide this field",
            "NO_ASSIGNMENT_IN_FRAME_SCRIPT":
                "the frame script was fully disassembled and provably contains "
                "no such assignment; this is a negative result, not an unknown",
            "NOT_A_PER_MAP_FIELD":
                "the variable exists but is global runtime state, it never "
                "holds a per-map link value",
        },
        "mechanism": {
            "summary": "There is no map table in the SWF. Each root frame "
                       "whose label is a map name carries one instance of the "
                       "shared exit-arrow movie clip per exit. The instance's "
                       "onClipEvent(load) assigns the per-instance variable "
                       "`map` to the destination frame label; the clip's own "
                       "onRelease does _root.nowmap = map followed by "
                       "_root.gotoAndStop(map).",
            "display_list_note": "Flash resolves a frame's display list from "
                                 "every PlaceObject2/RemoveObject2 between "
                                 "frame 1 and that frame, so a frame can "
                                 "inherit an arrow placed earlier and never "
                                 "removed. Exits with inherited_from_frame set "
                                 "are real in game but have no PlaceObject2 on "
                                 "their own frame.",
            "variables": {
                "nowmap": "string, the current map name; the only variable "
                          "that actually carries a map identity",
                "nextmap": "boolean gate, true means map switching is allowed; "
                           "never holds a map name",
                "owermap": "string, the map the player currently protects in "
                           "the map occupation race (misspelling of ownermap); "
                           "not a link to another map",
                "returnmap": "function on the root timeline: gotoAndStop("
                             "nowmap), or gotoAndStop the ending frame when "
                             "the day limit is exceeded",
                "map_race": "boolean, whether the occupation challenge is "
                            "still available today",
                "mapreward": "boolean, whether today's map reward was taken",
            },
        },
        "arrow_characters": sorted(arrow_chars),
        "gate_rules": gates,
        "maps": maps,
    }


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("swf")
    ap.add_argument("--out", help="write disassembly text here")
    ap.add_argument("--json", help="write structured events JSON here")
    ap.add_argument("--map-links", dest="map_links",
                    help="write the reconstructed map link table JSON here")
    ap.add_argument("--filter", help="only emit blocks containing this text")
    ap.add_argument("--quiet", action="store_true")
    args = ap.parse_args(argv)

    swf = load_swf(args.swf)
    walker = SwfWalker(swf)
    walker.run()
    walker.build_placement_index()

    data = swf["body"]
    text_parts = []
    header = [
        "SWF: %s" % os.path.abspath(swf["path"]),
        "signature=%s version=%d file_size=%d body_size=%d root_frames=%d"
        % (swf["signature"], swf["version"], swf["file_size"], len(data),
           walker.root_frame_count),
        "action blocks: %d" % len(walker.blocks),
        "root frame labels: %d" % len(walker.root_labels),
        "",
        "root timeline labels:",
    ]
    for f in sorted(walker.root_labels):
        header.append("  frame %-3d %s" % (f, walker.root_labels[f]))
    header.append("")
    header.append("=" * 78)
    text_parts.append("\n".join(header))

    json_blocks = []
    total_bytes = 0
    for blk in walker.blocks:
        pool = []
        nodes = parse_actions(data, blk["byte_start"], blk["byte_end"], pool)
        total_bytes += blk["byte_end"] - blk["byte_start"]
        pool_view = []
        # re-derive pool progressively for text rendering
        render_pool = []
        lines = []
        for node in nodes:
            if node["code"] == 0x88:
                render_pool = node["args"].get("pool", [])
            lines.extend(format_node(node, render_pool))
        body_text = "\n".join(lines)
        head = describe_block(walker, blk)
        block_text = "\n--- %s ---\n%s" % (head, body_text)
        if args.filter and args.filter not in block_text:
            continue
        text_parts.append(block_text)

        interp = Interp([])
        interp.run(nodes, "toplevel")
        rframes = []
        if blk["container_id"] is not None:
            rframes = sorted(walker.root_frames_of(blk["container_id"]))
        json_blocks.append({
            "tag_index": blk["tag_index"],
            "tag_name": blk["tag_name"],
            "container": blk["container"],
            "container_id": blk["container_id"],
            "frame": blk["frame"],
            "frame_label": walker.root_labels.get(blk["frame"])
            if blk["container_id"] is None else
            walker.sprite_labels.get(blk["container_id"], {}).get(blk["frame"]),
            "root_frames": [{"frame": f, "label": walker.root_labels.get(f)}
                            for f in rframes],
            "byte_start": blk["byte_start"],
            "byte_len": blk["byte_end"] - blk["byte_start"],
            "extra": {k: v for k, v in blk["extra"].items() if v is not None},
            "events": interp.events,
        })

    text = "\n".join(text_parts) + "\n"
    if args.out:
        with open(args.out, "w", encoding="utf-8", newline="\n") as fh:
            fh.write(text)
    elif not args.quiet:
        sys.stdout.write(text)

    if args.json:
        payload = {
            "swf": os.path.basename(swf["path"]),
            "version": swf["version"],
            "root_frame_count": walker.root_frame_count,
            "root_labels": {str(k): v for k, v in walker.root_labels.items()},
            "warnings": walker.warnings,
            "blocks": json_blocks,
        }
        with open(args.json, "w", encoding="utf-8", newline="\n") as fh:
            json.dump(payload, fh, ensure_ascii=False, indent=1)

    if args.map_links:
        links = build_map_links(walker)
        links["source"] = {
            "swf": os.path.basename(swf["path"]),
            "sha256": swf["sha256"],
            "file_size": swf["file_size"],
            "signature": swf["signature"],
            "swf_version": swf["version"],
            "root_frame_count": walker.root_frame_count,
            "action_blocks": len(walker.blocks),
            "parser_warnings": walker.warnings,
            "command": "python tools/swf_as2_dump.py <swf> --map-links <out>",
        }
        with open(args.map_links, "w", encoding="utf-8", newline="\n") as fh:
            json.dump(links, fh, ensure_ascii=False, indent=1)

    if not args.quiet:
        sys.stderr.write(
            "blocks=%d action_bytes=%d warnings=%d\n"
            % (len(walker.blocks), total_bytes, len(walker.warnings)))
        for w in walker.warnings[:20]:
            sys.stderr.write("  WARN %s\n" % w)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
