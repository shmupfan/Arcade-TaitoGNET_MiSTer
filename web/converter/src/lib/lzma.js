// Raw LZMA1 decoder for CHD 'lzma' hunks: no header, no end marker, known
// output size. Written from the LZMA specification (Igor Pavlov's LzmaSpec.cpp,
// public domain). chd.py hands these hunks to Python's lzma module (liblzma,
// FORMAT_RAW) with lc=3 lp=0 pb=2; like liblzma with max_length, decoding stops
// when the output is full.

import { ConvertError } from "./util.js";

const NUM_STATES = 12;
const LEN_LOW_BITS = 3, LEN_MID_BITS = 3, LEN_HIGH_BITS = 8;
const LEN_LOW_SYMBOLS = 1 << LEN_LOW_BITS, LEN_MID_SYMBOLS = 1 << LEN_MID_BITS;
const POS_STATES_MAX = 16;
const END_POS_MODEL_INDEX = 14;
const NUM_FULL_DISTANCES = 1 << (END_POS_MODEL_INDEX >> 1);
const NUM_ALIGN_BITS = 4;
const NUM_LEN_TO_POS_STATES = 4;
const MATCH_MIN_LEN = 2;

// length decoder layout (offsets inside its block of probabilities)
const LEN_CHOICE = 0, LEN_CHOICE2 = 1, LEN_LOW = 2;
const LEN_MID = LEN_LOW + POS_STATES_MAX * LEN_LOW_SYMBOLS;
const LEN_HIGH = LEN_MID + POS_STATES_MAX * LEN_MID_SYMBOLS;
const LEN_SIZE = LEN_HIGH + (1 << LEN_HIGH_BITS);

function layout(lc, lp) {
  let o = 0;
  const L = {};
  const take = (name, n) => { L[name] = o; o += n; };
  take("isMatch", NUM_STATES << 4);
  take("isRep", NUM_STATES);
  take("isRepG0", NUM_STATES);
  take("isRepG1", NUM_STATES);
  take("isRepG2", NUM_STATES);
  take("isRep0Long", NUM_STATES << 4);
  take("posSlot", NUM_LEN_TO_POS_STATES << 6);
  take("posDecoders", 1 + NUM_FULL_DISTANCES - END_POS_MODEL_INDEX);
  take("align", 1 << NUM_ALIGN_BITS);
  take("lenDec", LEN_SIZE);
  take("repLenDec", LEN_SIZE);
  take("literal", 0x300 << (lc + lp));
  L.size = o;
  return L;
}

export function makeLzmaDecoder(dictSize, lc = 3, lp = 0, pb = 2) {
  const L = layout(lc, lp);
  const probs = new Uint16Array(L.size);
  const pbMask = (1 << pb) - 1, lpMask = (1 << lp) - 1;

  return function decode(src, outSize) {
    const out = new Uint8Array(outSize);
    probs.fill(1024);
    const inLen = src.length;
    if (inLen < 5 || src[0] !== 0) throw new ConvertError("lzma: bad stream start");
    let ip = 1;
    let range = 0xffffffff;
    let code = ((src[1] << 24) >>> 0) + (src[2] << 16) + (src[3] << 8) + src[4];
    ip = 5;
    if (code === range) throw new ConvertError("lzma: corrupted stream");

    const bit = (i) => {
      const p = probs[i];
      const bound = (range >>> 11) * p;
      let b;
      if (code < bound) {
        range = bound;
        probs[i] = p + ((2048 - p) >>> 5);
        b = 0;
      } else {
        range -= bound;
        code -= bound;
        probs[i] = p - (p >>> 5);
        b = 1;
      }
      if (range < 0x1000000) {
        if (ip >= inLen) throw new ConvertError("lzma: input too short");
        range *= 256;
        code = code * 256 + src[ip++];
      }
      return b;
    };
    const tree = (base, numBits) => {
      let m = 1;
      for (let i = 0; i < numBits; i++) m = (m << 1) + bit(base + m);
      return m - (1 << numBits);
    };
    const reverse = (base, numBits) => {
      let m = 1, sym = 0;
      for (let i = 0; i < numBits; i++) {
        const b = bit(base + m);
        m = (m << 1) + b;
        sym |= b << i;
      }
      return sym;
    };
    const direct = (numBits) => {
      let res = 0;
      for (let i = 0; i < numBits; i++) {
        range = range >>> 1;
        let b = 0;
        if (code >= range) {
          code -= range;
          b = 1;
        }
        if (range < 0x1000000) {
          if (ip >= inLen) throw new ConvertError("lzma: input too short");
          range *= 256;
          code = code * 256 + src[ip++];
        }
        res = res * 2 + b;
      }
      return res;
    };
    const len = (base, posState) => {
      if (bit(base + LEN_CHOICE) === 0) return tree(base + LEN_LOW + (posState << LEN_LOW_BITS), LEN_LOW_BITS);
      if (bit(base + LEN_CHOICE2) === 0) return LEN_LOW_SYMBOLS + tree(base + LEN_MID + (posState << LEN_MID_BITS), LEN_MID_BITS);
      return LEN_LOW_SYMBOLS + LEN_MID_SYMBOLS + tree(base + LEN_HIGH, LEN_HIGH_BITS);
    };

    let state = 0, rep0 = 0, rep1 = 0, rep2 = 0, rep3 = 0;
    let pos = 0;
    while (pos < outSize) {
      const posState = pos & pbMask;
      if (bit(L.isMatch + (state << 4) + posState) === 0) {
        const prev = pos > 0 ? out[pos - 1] : 0;
        const litState = ((pos & lpMask) << lc) + (prev >> (8 - lc));
        const base = L.literal + 0x300 * litState;
        let sym = 1;
        if (state >= 7) {
          if (rep0 >= pos) throw new ConvertError("lzma: distance beyond output");
          let matchByte = out[pos - rep0 - 1];
          do {
            const matchBit = (matchByte >> 7) & 1;
            matchByte <<= 1;
            const b = bit(base + ((1 + matchBit) << 8) + sym);
            sym = (sym << 1) | b;
            if (matchBit !== b) break;
          } while (sym < 0x100);
        }
        while (sym < 0x100) sym = (sym << 1) | bit(base + sym);
        out[pos++] = sym - 0x100;
        state = state < 4 ? 0 : state < 10 ? state - 3 : state - 6;
        continue;
      }
      let n;
      if (bit(L.isRep + state) !== 0) {
        if (pos === 0) throw new ConvertError("lzma: repeat at start");
        if (bit(L.isRepG0 + state) === 0) {
          if (bit(L.isRep0Long + (state << 4) + posState) === 0) {
            state = state < 7 ? 9 : 11;
            out[pos] = out[pos - rep0 - 1];
            pos++;
            continue;
          }
        } else {
          let dist;
          if (bit(L.isRepG1 + state) === 0) {
            dist = rep1;
          } else {
            if (bit(L.isRepG2 + state) === 0) {
              dist = rep2;
            } else {
              dist = rep3;
              rep3 = rep2;
            }
            rep2 = rep1;
          }
          rep1 = rep0;
          rep0 = dist;
        }
        n = len(L.repLenDec, posState);
        state = state < 7 ? 8 : 11;
      } else {
        rep3 = rep2;
        rep2 = rep1;
        rep1 = rep0;
        n = len(L.lenDec, posState);
        state = state < 7 ? 7 : 10;
        const lenState = n < NUM_LEN_TO_POS_STATES - 1 ? n : NUM_LEN_TO_POS_STATES - 1;
        const posSlot = tree(L.posSlot + (lenState << 6), 6);
        if (posSlot < 4) {
          rep0 = posSlot;
        } else {
          const numDirect = (posSlot >> 1) - 1;
          let dist = (2 | (posSlot & 1)) * 2 ** numDirect;
          if (posSlot < END_POS_MODEL_INDEX) {
            dist += reverse(L.posDecoders + dist - posSlot, numDirect);
          } else {
            dist += direct(numDirect - NUM_ALIGN_BITS) * 16;
            dist += reverse(L.align, NUM_ALIGN_BITS);
          }
          rep0 = dist;
        }
        if (rep0 === 0xffffffff) throw new ConvertError("lzma: end marker before the end of the hunk");
        if (rep0 >= dictSize || rep0 >= pos) throw new ConvertError("lzma: distance beyond output");
      }
      n += MATCH_MIN_LEN;
      const end = Math.min(pos + n, outSize);
      const from = pos - rep0 - 1;
      for (let k = 0; pos < end; k++) out[pos++] = out[from + k];
    }
    return out;
  };
}
