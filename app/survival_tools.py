import argparse
import math
import wave
from array import array
from pathlib import Path


MORSE_MAP = {
    "A": ".-",
    "B": "-...",
    "C": "-.-.",
    "D": "-..",
    "E": ".",
    "F": "..-.",
    "G": "--.",
    "H": "....",
    "I": "..",
    "J": ".---",
    "K": "-.-",
    "L": ".-..",
    "M": "--",
    "N": "-.",
    "O": "---",
    "P": ".--.",
    "Q": "--.-",
    "R": ".-.",
    "S": "...",
    "T": "-",
    "U": "..-",
    "V": "...-",
    "W": ".--",
    "X": "-..-",
    "Y": "-.--",
    "Z": "--..",
    "0": "-----",
    "1": ".----",
    "2": "..---",
    "3": "...--",
    "4": "....-",
    "5": ".....",
    "6": "-....",
    "7": "--...",
    "8": "---..",
    "9": "----.",
    ".": ".-.-.-",
    ",": "--..--",
    "?": "..--..",
    "!": "-.-.--",
    "-": "-....-",
    "/": "-..-.",
    "@": ".--.-.",
    "(": "-.--.",
    ")": "-.--.-",
    ":": "---...",
    ";": "-.-.-.",
    "=": "-...-",
    "+": ".-.-.",
    "_": "..--.-",
    "\"": ".-..-.",
    "'": ".----.",
}

REVERSE_MORSE_MAP = {v: k for k, v in MORSE_MAP.items()}

DTMF_MAP = {
    "1": (697, 1209),
    "2": (697, 1336),
    "3": (697, 1477),
    "A": (697, 1633),
    "4": (770, 1209),
    "5": (770, 1336),
    "6": (770, 1477),
    "B": (770, 1633),
    "7": (852, 1209),
    "8": (852, 1336),
    "9": (852, 1477),
    "C": (852, 1633),
    "*": (941, 1209),
    "0": (941, 1336),
    "#": (941, 1477),
    "D": (941, 1633),
}


def encode_morse(text: str) -> str:
    words = []
    for word in text.upper().split():
        encoded_chars = []
        for ch in word:
            if ch in MORSE_MAP:
                encoded_chars.append(MORSE_MAP[ch])
            else:
                encoded_chars.append("?")
        words.append(" ".join(encoded_chars))
    return " / ".join(words)


def decode_morse(code: str) -> str:
    tokens = code.replace("|", "/").strip().split()
    out = []
    for tok in tokens:
        if tok == "/":
            out.append(" ")
            continue
        out.append(REVERSE_MORSE_MAP.get(tok, "?"))
    return "".join(out).replace("  ", " ").strip()


def _append_sine(samples: array, freq_hz: float, seconds: float, sample_rate: int, volume: float) -> None:
    count = int(seconds * sample_rate)
    if count <= 0:
        return
    amp = max(0.0, min(1.0, volume)) * 32767.0
    for n in range(count):
        t = n / sample_rate
        value = int(amp * math.sin(2.0 * math.pi * freq_hz * t))
        samples.append(value)


def _append_dual_sine(
    samples: array,
    freq_a_hz: float,
    freq_b_hz: float,
    seconds: float,
    sample_rate: int,
    volume: float,
) -> None:
    count = int(seconds * sample_rate)
    if count <= 0:
        return
    amp = max(0.0, min(1.0, volume)) * 32767.0
    for n in range(count):
        t = n / sample_rate
        value = int(
            amp
            * 0.5
            * (
                math.sin(2.0 * math.pi * freq_a_hz * t)
                + math.sin(2.0 * math.pi * freq_b_hz * t)
            )
        )
        samples.append(value)


def _append_silence(samples: array, seconds: float, sample_rate: int) -> None:
    count = int(seconds * sample_rate)
    if count <= 0:
        return
    samples.extend([0] * count)


def write_wav_pcm16(samples: array, output_path: Path, sample_rate: int) -> None:
    output_path.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(output_path), "wb") as wav_out:
        wav_out.setnchannels(1)
        wav_out.setsampwidth(2)
        wav_out.setframerate(sample_rate)
        wav_out.writeframes(samples.tobytes())


def morse_to_wav(
    text: str,
    output_path: Path,
    wpm: float = 18.0,
    freq_hz: float = 700.0,
    sample_rate: int = 44100,
    volume: float = 0.45,
) -> str:
    unit = 1.2 / max(1.0, wpm)
    dit = unit
    dah = 3.0 * unit
    intra = unit
    inter_char = 3.0 * unit
    inter_word = 7.0 * unit

    samples = array("h")
    words = text.upper().split()
    for w_idx, word in enumerate(words):
        for c_idx, ch in enumerate(word):
            code = MORSE_MAP.get(ch)
            if not code:
                continue
            for s_idx, symbol in enumerate(code):
                duration = dit if symbol == "." else dah
                _append_sine(samples, freq_hz=freq_hz, seconds=duration, sample_rate=sample_rate, volume=volume)
                if s_idx < len(code) - 1:
                    _append_silence(samples, seconds=intra, sample_rate=sample_rate)
            if c_idx < len(word) - 1:
                _append_silence(samples, seconds=inter_char, sample_rate=sample_rate)
        if w_idx < len(words) - 1:
            _append_silence(samples, seconds=inter_word, sample_rate=sample_rate)

    write_wav_pcm16(samples, output_path, sample_rate)
    return encode_morse(text)


def dtmf_to_wav(
    symbols: str,
    output_path: Path,
    tone_ms: int = 140,
    gap_ms: int = 70,
    sample_rate: int = 44100,
    volume: float = 0.45,
) -> str:
    tone_s = max(1, tone_ms) / 1000.0
    gap_s = max(0, gap_ms) / 1000.0
    samples = array("h")

    normalized = symbols.upper().replace(" ", "")
    used = []
    for ch in normalized:
        pair = DTMF_MAP.get(ch)
        if not pair:
            continue
        used.append(ch)
        _append_dual_sine(
            samples,
            freq_a_hz=pair[0],
            freq_b_hz=pair[1],
            seconds=tone_s,
            sample_rate=sample_rate,
            volume=volume,
        )
        _append_silence(samples, seconds=gap_s, sample_rate=sample_rate)

    write_wav_pcm16(samples, output_path, sample_rate)
    return "".join(used)


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Indigo survival tools: Morse encode/decode + Morse/DTMF WAV generation."
    )
    sub = parser.add_subparsers(dest="cmd", required=True)

    p_morse_encode = sub.add_parser("morse-encode", help="Encode text to Morse.")
    p_morse_encode.add_argument("--text", required=True, help="Plain text input.")

    p_morse_decode = sub.add_parser("morse-decode", help="Decode Morse to text.")
    p_morse_decode.add_argument("--code", required=True, help="Morse code input (use '/' between words).")

    p_morse_wav = sub.add_parser("morse-wav", help="Generate Morse code WAV from text.")
    p_morse_wav.add_argument("--text", required=True, help="Text to encode.")
    p_morse_wav.add_argument("--out", required=True, help="Output WAV file path.")
    p_morse_wav.add_argument("--wpm", type=float, default=18.0, help="Words per minute.")
    p_morse_wav.add_argument("--freq", type=float, default=700.0, help="Tone frequency Hz.")
    p_morse_wav.add_argument("--sample-rate", type=int, default=44100, help="Sample rate.")
    p_morse_wav.add_argument("--volume", type=float, default=0.45, help="Volume 0.0-1.0.")

    p_dtmf_wav = sub.add_parser("dtmf-wav", help="Generate DTMF tones WAV from a symbol sequence.")
    p_dtmf_wav.add_argument("--symbols", required=True, help="Digits/symbols like 911# or A23D.")
    p_dtmf_wav.add_argument("--out", required=True, help="Output WAV file path.")
    p_dtmf_wav.add_argument("--tone-ms", type=int, default=140, help="Tone duration in milliseconds.")
    p_dtmf_wav.add_argument("--gap-ms", type=int, default=70, help="Silence gap in milliseconds.")
    p_dtmf_wav.add_argument("--sample-rate", type=int, default=44100, help="Sample rate.")
    p_dtmf_wav.add_argument("--volume", type=float, default=0.45, help="Volume 0.0-1.0.")

    args = parser.parse_args()

    if args.cmd == "morse-encode":
        print(encode_morse(args.text))
        return

    if args.cmd == "morse-decode":
        print(decode_morse(args.code))
        return

    if args.cmd == "morse-wav":
        output = Path(args.out)
        encoded = morse_to_wav(
            text=args.text,
            output_path=output,
            wpm=args.wpm,
            freq_hz=args.freq,
            sample_rate=args.sample_rate,
            volume=args.volume,
        )
        print(f"Morse: {encoded}")
        print(f"WAV: {output}")
        return

    if args.cmd == "dtmf-wav":
        output = Path(args.out)
        used = dtmf_to_wav(
            symbols=args.symbols,
            output_path=output,
            tone_ms=args.tone_ms,
            gap_ms=args.gap_ms,
            sample_rate=args.sample_rate,
            volume=args.volume,
        )
        print(f"Symbols used: {used}")
        print(f"WAV: {output}")
        return


if __name__ == "__main__":
    main()
