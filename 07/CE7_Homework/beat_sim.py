#!/usr/bin/env python3
# tako:run python3 beat_sim.py
"""第7回 簡易ビート検出のオフライン再現スクリプト（標準ライブラリのみ）

Processing 側（Stereo→Mono, LPF, Down Sampling, Bit Crusher, 4 bit packing）と
Arduino 側（BLOCK_SIZE ごとの2乗平均, IIR による平均エネルギー, 動的閾値,
立ち上がり検出, リフラクトリ期間）を Python で同じ手順で計算し，
パラメータを1つずつ変えたときのビート候補の出方を表にする。

実機との違い:
- millis() の代わりに「再生開始からのサンプル時刻 + 2000 ms」を使う
  （Processing 側が setup() で delay(2000) してから再生するため）
- シリアル通信の遅延・取りこぼしは模擬しない
"""
import argparse
import array
import math
import os
import statistics
import sys
import wave

DEFAULT_SOUND_DIR = "/Users/fukushimakenichi/2026/クリ/5/CE_Files/Sounds"
SONGS = ["Pattern1.wav", "Pattern2.wav", "Pattern3.wav",
         "StratoS.wav", "techno-trance.wav", "northside-drive.wav"]

# 配布コードの設定（4 bit 版 / 8 bit 版）
MODES = {
    "4bit": dict(factor=2, bits=4, rate=22050, block=256),
    "8bit": dict(factor=4, bits=8, rate=11025, block=128),
}
BASE = dict(th=2.0, tau=1.0, ref=200)


# ------------------------------------------------------------
# Processing 側
# ------------------------------------------------------------
def load_mono(path):
    w = wave.open(path)
    assert w.getsampwidth() == 2, "16 bit WAV のみ対応"
    ch, fs, n = w.getnchannels(), w.getframerate(), w.getnframes()
    a = array.array("h")
    a.frombytes(w.readframes(n))
    if sys.byteorder == "big":
        a.byteswap()
    if ch == 2:
        mono = [0.5 * (a[i] + a[i + 1]) / 32768.0 for i in range(0, len(a), 2)]
    else:
        mono = [x / 32768.0 for x in a]
    return mono, fs


def processing_side(mono, fs, factor, bits):
    """LowPassFilter → DownSampler → BitCrusher（.pde と同じ式）"""
    out_rate = fs / factor
    cutoff = 0.8 * (out_rate / 2.0)
    dt = 1.0 / fs
    rc = 1.0 / (2.0 * math.pi * cutoff)
    alpha = dt / (rc + dt)

    levels = (1 << bits) - 1
    mn = -(1 << (bits - 1))
    mx = (1 << (bits - 1)) - 1

    prev = 0.0
    counter = 0
    out = []
    for x in mono:
        prev = prev + alpha * (x - prev)
        counter += 1
        if counter >= factor:
            counter = 0
            v = min(1.0, max(-1.0, prev))
            # Processing の round() は Math.round（0.5 は切り上げ）
            q = math.floor((v + 1.0) * levels / 2.0 + 0.5) + mn
            out.append(min(mx, max(mn, q)))
    return out


def pack_unpack_4bit(values):
    """Processing の packing → Arduino の unpacking を通した値を返す"""
    out = []
    for i in range(0, len(values) - 1, 2):
        packed = ((values[i] & 0x0F) << 4) | (values[i + 1] & 0x0F)
        received = packed & 0xFF  # (byte) → port.write(value & 0xFF)
        s1 = (received >> 4) & 0x0F
        if s1 >= 8:
            s1 -= 16
        s2 = received & 0x0F
        if s2 >= 8:
            s2 -= 16
        out += [s1, s2]
    return out


def pass_8bit(values):
    """(byte)value → Serial.read() → (int8_t) の変換"""
    out = []
    for v in values:
        b = v & 0xFF
        out.append(b - 256 if b >= 128 else b)
    return out


# ------------------------------------------------------------
# Arduino 側
# ------------------------------------------------------------
def block_energies(samples, block):
    n = len(samples) // block
    return [sum(s * s for s in samples[k * block:(k + 1) * block]) / block
            for k in range(n)]


def detect(energies, block, rate, th, tau, ref):
    """ref=None なら CE7_*_dynTh，数値なら CE7_*_dynTh_Ref と同じ判定"""
    interval = block / rate
    a = interval / (tau + interval)
    avg = 0.0
    above = False
    last = 0
    beats = []
    for k, e in enumerate(energies):
        avg = avg + a * (e - avg)
        thr = th * avg
        now = 2000 + int((k + 1) * interval * 1000)  # millis() の代わり
        if ref is None:
            if not above and e > thr:
                beats.append(now)
                above = True
            if above and e <= thr:
                above = False
        else:
            rising = (not above) and e > thr
            above = e > thr
            if rising and now - last > ref:
                beats.append(now)
                last = now
    return beats


# ------------------------------------------------------------
# 評価用
# ------------------------------------------------------------
def tempo_candidates(energies, block, rate, lo_bpm=55, hi_bpm=250, top=3):
    """エネルギー増分の自己相関のピークからテンポ候補(BPM, 相対強度)を返す。
    倍テンポ・半テンポの区別はつかないので，比較の目安としてだけ使う。"""
    onset = [max(0.0, energies[i] - energies[i - 1]) for i in range(1, len(energies))]
    m = statistics.fmean(onset)
    onset = [x - m for x in onset]
    dt = block / rate
    lags = list(range(int(60 / hi_bpm / dt), int(60 / lo_bpm / dt) + 1))
    ac = [sum(onset[i] * onset[i + lag] for i in range(len(onset) - lag)) / (len(onset) - lag)
          for lag in lags]
    peaks = [(ac[i], lags[i]) for i in range(1, len(ac) - 1) if ac[i - 1] < ac[i] >= ac[i + 1]]
    peaks.sort(reverse=True)
    best = peaks[0][0]
    return [(60.0 / (lag * dt), c / best) for c, lag in peaks[:top]]


def peak_to_mean(energies):
    """短時間エネルギーの 95 パーセンタイル / 平均（閾値係数と比べる目安）"""
    s = sorted(energies)
    return s[int(0.95 * len(s))] / statistics.fmean(energies)


def summarize(beats, dur):
    ibis = [b - a for a, b in zip(beats, beats[1:])]
    rate = len(beats) / dur
    if len(ibis) < 2:
        return dict(n=len(beats), per_s=rate, med=float("nan"), short=float("nan"), cv=float("nan"))
    med = statistics.median(ibis)
    short = sum(1 for x in ibis if x < 150) / len(ibis)
    cv = statistics.pstdev(ibis) / statistics.fmean(ibis)
    return dict(n=len(beats), per_s=rate, med=med, short=short, cv=cv)


def fmt(s):
    return (f"{s['n']:5d} {s['per_s']:6.2f} {s['med']:7.0f} "
            f"{100 * s['short']:6.1f}% {s['cv']:5.2f}")


def self_test():
    # 4 bit の2の補数変換と packing の往復
    vals = list(range(-8, 8)) * 2
    assert pack_unpack_4bit(vals) == vals
    assert pass_8bit(list(range(-128, 128))) == list(range(-128, 128))
    # 一定エネルギー → 立ち上がり検出は最初の1回だけ
    assert len(detect([10.0] * 500, 256, 22050, 2.0, 1.0, None)) == 1
    # 無音では検出しない（0 > 0 は偽）
    assert detect([0.0] * 500, 256, 22050, 2.0, 1.0, 200) == []
    # 1ブロックおきのパルス（約23 ms間隔）: Ref なしは毎回，Ref 200 ms なら約200 ms 間隔に間引かれる
    pulses = ([0.0] * 60 + [100.0, 0.0] * 200)
    b0 = detect(pulses, 128, 11025, 2.0, 1.0, None)
    b1 = detect(pulses, 128, 11025, 2.0, 1.0, 200)
    assert len(b0) == 200
    assert all(y - x > 200 for x, y in zip(b1, b1[1:])) and len(b1) < len(b0) // 8
    # IIR の時定数: 一定入力に対し τ 秒後に約 63% に到達
    blk, rate, tau = 256, 22050, 1.0
    a = (blk / rate) / (tau + blk / rate)
    y = 0.0
    for _ in range(round(tau / (blk / rate))):
        y += a * (1.0 - y)
    assert 0.60 < y < 0.66, y
    print("self test: OK")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dir", default=DEFAULT_SOUND_DIR)
    ap.add_argument("--songs", nargs="*", default=SONGS)
    args = ap.parse_args()

    self_test()
    print("列: 検出数 / 毎秒 / 間隔の中央値[ms] / 150 ms 未満の間隔の割合 / 間隔の変動係数CV")

    for song in args.songs:
        mono, fs = load_mono(os.path.join(args.dir, song))
        dur = len(mono) / fs
        print(f"\n######## {song}  ({dur:.1f} s)")
        for mode, cfg in MODES.items():
            q = processing_side(mono, fs, cfg["factor"], cfg["bits"])
            q = pack_unpack_4bit(q) if cfg["bits"] == 4 else pass_8bit(q)
            rate = cfg["rate"]
            cache = {}

            def run(block=cfg["block"], th=BASE["th"], tau=BASE["tau"], ref=BASE["ref"]):
                if block not in cache:
                    cache[block] = block_energies(q, block)
                return summarize(detect(cache[block], block, rate, th, tau, ref), dur)

            base_e = block_energies(q, cfg["block"])
            cands = ", ".join(f"{b:.0f}({c:.2f})" for b, c in
                              tempo_candidates(base_e, cfg["block"], rate))
            print(f"--- {mode} ({rate} Hz)  テンポ候補[BPM(相対強度)]: {cands}"
                  f" / energy の p95/平均 = {peak_to_mean(base_e):.2f}")
            print(f"  基準(th={BASE['th']}, block={cfg['block']}, ref={BASE['ref']}): {fmt(run())}")
            beats = detect(base_e, cfg["block"], rate, BASE["th"], BASE["tau"], BASE["ref"])
            win = [0] * (int(dur) // 5 + 1)
            for t in beats:
                win[(t - 2000) // 5000] += 1
            print(f"  基準での 5 s ごとの検出数       : {win}")
            print(f"  リフラクトリなし                : {fmt(run(ref=None))}")
            for th in [1.4, 1.6, 1.8, 2.0, 2.2, 2.5, 3.0]:
                print(f"  THRESHOLD_FACTOR={th:<4}         : {fmt(run(th=th))}")
            for block in [cfg["block"] // 4, cfg["block"] // 2, cfg["block"], cfg["block"] * 2, cfg["block"] * 4]:
                print(f"  BLOCK_SIZE={block:<5}({1000 * block / rate:5.1f} ms) : {fmt(run(block=block))}")
            for ref in [50, 100, 200, 300, 400, 500]:
                print(f"  REFRACTORY_TIME={ref:<4}         : {fmt(run(ref=ref))}")

        # 音量を下げたとき（静かな曲を想定）の基準設定での検出数
        line = []
        for gain in [0.5, 0.25, 0.1]:
            quiet = [gain * x for x in mono]
            for mode, cfg in MODES.items():
                q = processing_side(quiet, fs, cfg["factor"], cfg["bits"])
                e = block_energies(q, cfg["block"])
                n = len(detect(e, cfg["block"], cfg["rate"], BASE["th"], BASE["tau"], BASE["ref"]))
                line.append(f"×{gain} {mode}: {n}（値 {len(set(q))} 種）")
        print("  音量を下げた場合の検出数: " + " / ".join(line))


if __name__ == "__main__":
    main()
