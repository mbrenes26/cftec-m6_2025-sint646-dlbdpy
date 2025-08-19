#!/usr/bin/env python3
"""
SYNOPSIS
  Envia muchos mensajes a Apache Kafka generando N clientes en paralelo.
  Formato requerido del mensaje:
    {"user_id":"...", "comment":"..."}
  (Se agregan metadatos en 'meta' con id, client_id y ts.)

NOTA
  Puedes copiar este script a:
    - Windows: .venv/Scripts/
    - Linux/macOS: .venv/bin/
  o ejecutarlo desde scripts/ con Python del venv activo.

USO
  python -m pip install kafka-python
  python scripts/send_kafka_burst.py --bootstrap 51.57.73.26:29092 --topic user-topic \
    --clients 1 --max 10 --min-delay 0.5 --max-delay 3.0
"""

import argparse
import json
import random
import time
import uuid
import sys
from datetime import datetime, timezone
from multiprocessing import Process

try:
    from kafka import KafkaProducer
except Exception:
    print("ERROR: falta kafka-python. Instala con: python -m pip install kafka-python", file=sys.stderr)
    raise

DEFAULT_CORPUS = [
    "me encanta este servicio",
    "el sistema esta caido",
    "la experiencia fue neutral",
    "excelente atencion",
    "mala calidad en la ultima entrega",
    "soporte rapido y util",
    "lento y con errores",
    "todo bien por ahora",
]

def parse_args():
    p = argparse.ArgumentParser(description="Kafka burst producer")
    p.add_argument("--bootstrap", required=True, help="host:puerto del broker, ej: 51.57.73.26:29092")
    p.add_argument("--topic", required=True, help="topic destino, ej: user-topic")
    p.add_argument("--clients", type=int, default=10, help="numero de clientes en paralelo")
    p.add_argument("--max", type=int, default=0, help="max mensajes por cliente; 0 = ilimitado")
    p.add_argument("--duration", type=int, default=0, help="segundos totales por cliente; 0 = sin limite")
    p.add_argument("--min-delay", type=float, default=0.5, help="min espera entre mensajes (s)")
    p.add_argument("--max-delay", type=float, default=3.0, help="max espera entre mensajes (s)")
    p.add_argument("--text-file", default=None, help="archivo .txt con frases (una por linea)")
    return p.parse_args()

def load_texts(path):
    if not path:
        return DEFAULT_CORPUS
    try:
        with open(path, "r", encoding="utf-8") as f:
            lines = [ln.strip() for ln in f if ln.strip()]
        return lines or DEFAULT_CORPUS
    except Exception:
        return DEFAULT_CORPUS

def build_producer(bootstrap: str) -> KafkaProducer:
    return KafkaProducer(
        bootstrap_servers=bootstrap,
        acks=1,
        linger_ms=10,
        value_serializer=lambda v: json.dumps(v, ensure_ascii=False).encode("utf-8"),
        key_serializer=lambda v: v.encode("utf-8") if v is not None else None,
    )

def run_client(idx: int, args, texts):
    client_id = f"py-{idx:03d}"
    prod = build_producer(args.bootstrap)
    sent = 0
    start = time.time()
    try:
        while True:
            if args.max and sent >= args.max:
                break
            if args.duration and (time.time() - start) >= args.duration:
                break

            msg_id = str(uuid.uuid4())
            user_id = f"user_{random.randint(1, 100000):05d}"
            comment = random.choice(texts)
            now = datetime.now(timezone.utc).isoformat()

            # Formato requerido + metadatos
            payload = {
                "user_id": user_id,
                "comment": comment,
                "meta": {
                    "id": msg_id,
                    "client_id": client_id,
                    "ts": now
                }
            }

            prod.send(args.topic, key=client_id, value=payload)
            sent += 1
            if sent % 200 == 0:
                prod.flush()
                print(f"metric client={client_id} sent={sent}", flush=True)

            time.sleep(random.uniform(args.min_delay, args.max_delay))
    except KeyboardInterrupt:
        pass
    finally:
        prod.flush()
        prod.close()
        print(f"done client={client_id} sent={sent}", flush=True)

def main():
    args = parse_args()
    texts = load_texts(args.text_file)
    procs = []
    for i in range(1, max(1, args.clients) + 1):
        p = Process(target=run_client, args=(i, args, texts), daemon=False)
        p.start()
        procs.append(p)
        print(f"started client {i} pid={p.pid}")
    for p in procs:
        p.join()

if __name__ == "__main__":
    sys.exit(main())
