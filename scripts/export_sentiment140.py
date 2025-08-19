#!/usr/bin/env python3
"""
Exporta el dataset Sentiment140 (Hugging Face) a TXT o JSONL.

USO
  python -m pip install datasets
  python scripts/export_sentiment140.py --out corpus.txt --fmt txt --max 50000 --shuffle
  python scripts/export_sentiment140.py --out corpus.jsonl --fmt jsonl --max 50000 --shuffle

SALIDA
  - txt   : una linea por tweet (solo texto)
  - jsonl : {"text": "...", "label": 0|4} por linea

NOTAS
  - Requiere permiso para ejecutar codigo remoto del dataset.
  - En Windows puedes ver un warning sobre symlinks del cache; es inofensivo.
"""

import argparse
import sys
import random
import json
from typing import List, Tuple

try:
    from datasets import load_dataset
except Exception as e:
    print("ERROR: falta la dependencia 'datasets'. Instala con: python -m pip install datasets", file=sys.stderr)
    raise

def parse_args():
    p = argparse.ArgumentParser(description="Exporta Sentiment140 a TXT o JSONL")
    p.add_argument("--out", required=True, help="ruta de salida (ej. corpus.txt o corpus.jsonl). usa '-' para stdout")
    p.add_argument("--fmt", choices=["txt", "jsonl"], default="txt", help="formato de salida")
    p.add_argument("--max", type=int, default=0, help="maximo de registros; 0 = todos")
    p.add_argument("--shuffle", action="store_true", help="barajar antes de exportar")
    p.add_argument("--min-len", type=int, default=1, help="longitud minima del texto")
    p.add_argument("--seed", type=int, default=42, help="semilla aleatoria (para --shuffle)")
    return p.parse_args()

def clean_text(s: str) -> str:
    # normaliza saltos de linea y espacios
    return s.replace("\r", " ").replace("\n", " ").strip()

def load_sentiment140() -> List[dict]:
    # trust_remote_code es necesario para este dataset
    ds = load_dataset("stanfordnlp/sentiment140", trust_remote_code=True)
    # concatenar todos los splits disponibles (p.ej., "train", "test" si existiera)
    parts = []
    for split in ds.keys():
        parts.extend(list(ds[split]))
    return parts

def build_rows(items: List[dict], min_len: int) -> List[Tuple[str, int]]:
    rows: List[Tuple[str, int]] = []
    for r in items:
        txt = clean_text(str(r.get("text", "")))
        if len(txt) < min_len:
            continue
        # algunos dumps usan 'sentiment' como 0/4
        try:
            label = int(r.get("sentiment", -1))
        except Exception:
            label = -1
        rows.append((txt, label))
    return rows

def write_out(path: str, fmt: str, rows: List[Tuple[str, int]]) -> int:
    out_fh = sys.stdout if path == "-" else open(path, "w", encoding="utf-8")
    n = 0
    try:
        if fmt == "txt":
            for text, _label in rows:
                out_fh.write(text + "\n")
                n += 1
        else:
            for text, label in rows:
                out_fh.write(json.dumps({"text": text, "label": label}, ensure_ascii=False) + "\n")
                n += 1
    finally:
        if out_fh is not sys.stdout:
            out_fh.close()
    return n

def main():
    args = parse_args()
    if args.shuffle:
        random.seed(args.seed)

    try:
        items = load_sentiment140()
    except Exception as e:
        print(f"ERROR cargando dataset: {e}", file=sys.stderr)
        return 2

    rows = build_rows(items, args.min_len)
    if args.shuffle:
        random.shuffle(rows)
    if args.max and args.max > 0:
        rows = rows[:args.max]

    if not rows:
        print("Dataset sin registros tras filtros. Ajusta --min-len o verifica el dataset.", file=sys.stderr)
        return 2

    n = write_out(args.out, args.fmt, rows)
    print(f"Escrito {n} registros en {args.out}", file=sys.stderr)
    return 0

if __name__ == "__main__":
    sys.exit(main())
