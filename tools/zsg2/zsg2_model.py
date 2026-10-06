#!/usr/bin/env python3
"""Reference model of the ZSG-2 for directed tests (docs/zsg2_rtl.md 4.5).

A line-by-line transcription of MAME's zsg2.cpp at commit 61c7940
(src/devices/sound/zsg2.cpp at 61c7940, docs/mame_sources.md; BSD-3-Clause, copyright holders Olivier
Galibert, R. Belmont, hap, superctr). C integer behaviour is kept: 32-bit
wrap of int and uint32 arithmetic, int16 truncation, arithmetic right
shifts. Test infrastructure only; nothing from it goes into the RTL.
Output clamp as sound.h put_int_clamp in 0.288: [-32768, 32767].
"""
import math


def u16(x): return x & 0xffff
def u32(x): return x & 0xffffffff
def s16(x):
    x &= 0xffff
    return x - 0x10000 if x & 0x8000 else x
def s32(x):
    x &= 0xffffffff
    return x - 0x100000000 if x & 0x80000000 else x


GAIN_TAB = [0] + [int(math.pow(10, -(31 - i) / 20.) * 65535.) & 0xffff for i in range(1, 32)]
STATUS_ACTIVE = 0x8000


class Chan:
    def __init__(self):
        self.v = [0] * 16
        self.status = 0
        self.cur_pos = 0
        self.step_ptr = 0
        self.step = 0
        self.start_pos = 0
        self.end_pos = 0
        self.loop_pos = 0
        self.page = 0
        self.vol = 0
        self.vol_initial = 0
        self.vol_target = 0
        self.vol_delta = 0
        self.output_cutoff = 0
        self.output_cutoff_initial = 0
        self.output_cutoff_target = 0
        self.output_cutoff_delta = 0
        self.emphasis_filter_state = 0
        self.output_filter_state = 0
        self.output_gain = [0] * 4
        self.samples = [0] * 5


class Zsg2:
    def __init__(self, blocks, shift_b=3):
        self.mem = blocks                 # list of 32-bit blocks (m_mem_blocks = len)
        self.chan = [Chan() for _ in range(48)]
        self.reg = [0] * 32
        self.read_address = 0
        self.sample_count = 0
        self.shift_b = shift_b            # 3 = 61c7940, 0 = 0.288

    # ---------------- memory ----------------
    def read_memory(self, offset):
        if offset >= len(self.mem):
            return 0
        return self.mem[offset]

    def prepare_samples(self, offset):
        block = self.read_memory(offset)
        if block == 0:
            return [0, 0, 0, 0]
        r = [block >> 8 & 0x7f, block >> 16 & 0x7f, block >> 24 & 0x7f,
             (block >> 9 & 0x40) | (block >> 18 & 0x20) | (block >> 27 & 0x10) | (block & 0xf)]
        shift = block >> 4 & 0xf
        return [s16(s16(x << 9) >> shift) for x in r]

    def filter_samples(self, ch):
        raw = self.prepare_samples(ch.page | ch.cur_pos)
        ch.samples[0] = ch.samples[4]
        for i in range(4):
            e = ch.emphasis_filter_state
            ch.emphasis_filter_state = s32(e + raw[i] - ((e + 0x20) >> 6))
            sample = ch.emphasis_filter_state >> 1
            ch.samples[i + 1] = max(-32768, min(32767, sample))

    # ---------------- one output sample ----------------
    def render(self):
        mix = [0, 0, 0, 0]
        for ch in self.chan:
            if not ch.status & STATUS_ACTIVE:
                continue
            ch.step_ptr = u32(ch.step_ptr + ch.step)
            if ch.step_ptr & 0xffff0000:
                ch.cur_pos = u32(ch.cur_pos + 1)
                if ch.cur_pos >= ch.end_pos:
                    ch.cur_pos = ch.loop_pos
                    if u32(ch.cur_pos + 1) >= ch.end_pos:
                        ch.vol = 0
                        ch.status &= ~STATUS_ACTIVE & 0xffff
                        continue
                if ch.cur_pos == ch.start_pos:
                    ch.emphasis_filter_state = 0
                ch.step_ptr &= 0xffff
                self.filter_samples(ch)
            pos = ch.step_ptr >> 14 & 3
            sample = ch.samples[pos]
            sample = s32(sample + ((u16(ch.step_ptr << 2) * s16(ch.samples[pos + 1] - sample)) >> 16))
            f = ch.output_filter_state
            ch.output_filter_state = s32(f + s32((sample - (f >> 16)) * ch.output_cutoff))
            sample = ch.output_filter_state >> 16
            if not ch.output_cutoff:
                ch.output_filter_state >>= 1
            sample = s32(sample * ch.vol) >> 16
            for o in range(4):
                g = ch.output_gain[o] & 0x1f
                os_ = -sample if ch.output_gain[o] & 0x80 else sample
                mix[o] = s32(mix[o] + ((os_ * GAIN_TAB[g]) >> 16))
            if self.sample_count & 1:
                ch.vol = self.ramp(ch.vol, ch.vol_target, ch.vol_delta)
                ch.output_cutoff = self.ramp(ch.output_cutoff, ch.output_cutoff_target, ch.output_cutoff_delta)
        self.sample_count = u32(self.sample_count + 1)
        return [max(-32768, min(32767, m)) for m in mix]

    @staticmethod
    def get_ramp(val):
        frac = s16(val << 12)
        frac = s16(((frac >> 12) ^ 8) << (val >> 4))
        return frac >> 4

    @staticmethod
    def ramp(current, target, delta):
        r = current + delta
        if delta < 0 and r < target:
            r = target
        elif delta >= 0 and r > target:
            r = target
        return u16(r)

    # ---------------- registers ----------------
    def chan_w(self, n, reg, data):
        ch = self.chan[n]
        if reg == 0x0:
            ch.start_pos = (ch.start_pos & 0xff00) | (data >> 8 & 0xff)
        elif reg == 0x1:
            ch.start_pos = (ch.start_pos & 0x00ff) | (data << 8 & 0xff00)
            ch.page = data << 8 & 0xff0000
        elif reg == 0x3:
            ch.status &= 0x8000
            ch.status |= data & 0x7fff
        elif reg == 0x4:
            ch.step = data + 1
        elif reg == 0x5:
            ch.loop_pos = (ch.loop_pos & 0xff00) | (data & 0xff)
            ch.output_gain[3] = data >> 8
        elif reg == 0x6:
            ch.end_pos = data
        elif reg == 0x7:
            ch.loop_pos = (ch.loop_pos & 0x00ff) | (data << 8 & 0xff00)
            ch.output_gain[2] = data >> 8
        elif reg == 0x8:
            ch.output_cutoff_initial = data
        elif reg == 0x9:
            ch.output_cutoff = data
        elif reg == 0xa:
            ch.vol_initial = data
        elif reg == 0xb:
            ch.vol = data
        elif reg == 0xc:
            ch.output_cutoff_target = data
        elif reg == 0xd:
            ch.output_gain[1] = data >> 8
            ch.output_cutoff_delta = self.get_ramp(data & 0xff)
        elif reg == 0xe:
            ch.vol_target = data
        elif reg == 0xf:
            ch.output_gain[0] = data >> 8
            ch.vol_delta = self.get_ramp(data & 0xff)
        ch.v[reg] = data

    def chan_r(self, n, reg):
        ch = self.chan[n]
        if reg == 0x3:
            return ch.status
        if reg == 0x9:
            return ch.output_cutoff
        if reg == 0xb:
            return ch.vol >> self.shift_b
        return ch.v[reg]

    def control_w(self, reg, data):
        if reg in (0, 1, 2):
            base = (reg & 3) << 4
            for i in range(16):
                if data & (1 << i):
                    ch = self.chan[base | i]
                    ch.status |= STATUS_ACTIVE
                    ch.cur_pos = u32(ch.start_pos - 1)
                    ch.step_ptr = 0x10000
                    ch.vol = 0
                    ch.vol_delta = 0x0400
                    ch.output_cutoff = ch.output_cutoff_initial
                    ch.output_filter_state = 0
        elif reg in (4, 5, 6):
            base = (reg & 3) << 4
            for i in range(16):
                if data & (1 << i):
                    ch = self.chan[base | i]
                    ch.vol = 0
                    ch.status &= ~STATUS_ACTIVE & 0xffff
        elif reg == 0x1c:
            self.read_address = (self.read_address & 0x3fffc000) | (data >> 2 & 0x00003fff)
        elif reg == 0x1d:
            self.read_address = (self.read_address & 0x00003fff) | (data << 14 & 0x3fffc000)
        elif reg < 0x20:
            self.reg[reg] = data

    def control_r(self, reg):
        if reg == 0x14:
            return 0
        if reg == 0x1e:
            return self.read_memory(self.read_address) & 0xffff
        if reg == 0x1f:
            return self.read_memory(self.read_address) >> 16
        if reg < 0x20:
            return self.reg[reg]
        return 0

    def write(self, offset, data):
        if offset < 0x300:
            self.chan_w(offset >> 4, offset & 0xf, data)
        else:
            self.control_w(offset - 0x300, data)

    def read(self, offset):
        if offset < 0x300:
            return self.chan_r(offset >> 4, offset & 0xf)
        return self.control_r(offset - 0x300)

    def reset(self):
        self.read_address = 0
        for r in (4, 5, 6):
            self.control_w(r, 0xffff)
        for n in range(48):
            for reg in range(16):
                self.chan_w(n, reg, 0)
        self.sample_count = 0
