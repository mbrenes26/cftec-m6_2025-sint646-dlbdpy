#!/usr/bin/env python3
"""
Sentiment DL Worker (sin transformers.pipeline)

- Lee documentos NO procesados desde MongoDB.
- Predice sentimiento con el modelo HF 'tabularisai/multilingual-sentiment-analysis'
  usando PyTorch (AutoTokenizer + AutoModelForSequenceClassification; softmax manual).
- Marca el documento en Mongo como procesado (o error).
- Inserta una fila en MySQL (lab.dw_messages) con id,user_id,comment,label,score.
  La columna ingest_ts la genera MySQL con DEFAULT CURRENT_TIMESTAMP.

Uso ejemplo (VM):
  python3 scripts/sentiment_dl_worker.py \
    --mongo-uri "mongodb://admin:pass@127.0.0.1:27017/?authSource=admin" \
    --mongo-db streamdb --mongo-coll raw_messages \
    --mysql-host 127.0.0.1 --mysql-port 3306 \
    --mysql-user root --mysql-pass pass --mysql-db lab \
    --batch-size 64 --max-docs 0 --poll-wait 2 --raw-json

Requisitos:
  pip install torch transformers pymongo mysql-connector-python
"""

import argparse
import json
import logging
import signal
import sys
import time
from datetime import datetime, timezone
from typing import Dict, List

import mysql.connector
from mysql.connector import errorcode
from pymongo import MongoClient, ReturnDocument
from transformers import AutoTokenizer, AutoModelForSequenceClassification
import torch
import torch.nn.functional as F


def utcnow_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def parse_args():
    p = argparse.ArgumentParser(description="Sentiment DL Worker (HF + PyTorch, sin pipelines)")
    # MongoDB
    p.add_argument("--mongo-uri", required=True, help="URI de MongoDB (con authSource si aplica)")
    p.add_argument("--mongo-db", required=True, help="Nombre de la base en Mongo")
    p.add_argument("--mongo-coll", required=True, help="Nombre de la coleccion en Mongo")
    # MySQL
    p.add_argument("--mysql-host", default="127.0.0.1")
    p.add_argument("--mysql-port", type=int, default=3306)
    p.add_argument("--mysql-user", required=True)
    p.add_argument("--mysql-pass", required=True)
    p.add_argument("--mysql-db", required=True)
    # Inference
    p.add_argument("--model", default="tabularisai/multilingual-sentiment-analysis")
    p.add_argument("--max-length", type=int, default=256)
    p.add_argument("--batch-size", type=int, default=64)
    p.add_argument("--max-docs", type=int, default=0, help="0 = sin limite (corre continuamente)")
    p.add_argument("--poll-wait", type=float, default=2.0, help="segundos de espera cuando no hay pendientes")
    p.add_argument("--raw-json", action="store_true", help="guardar el documento original en dw_messages.raw_json")
    # Idempotencia
    p.add_argument("--upsert", action="store_true", help="ON DUPLICATE KEY UPDATE en MySQL")
    # Logging
    p.add_argument("--log-every", type=int, default=100)
    return p.parse_args()


def get_logger() -> logging.Logger:
    lg = logging.getLogger("dlworker")
    h = logging.StreamHandler(sys.stdout)
    h.setFormatter(logging.Formatter("[%(asctime)s] %(levelname)s: %(message)s"))
    lg.addHandler(h)
    lg.setLevel(logging.INFO)
    return lg


def connect_mysql(args):
    try:
        conn = mysql.connector.connect(
            host=args.mysql_host,
            port=args.mysql_port,
            user=args.mysql_user,
            password=args.mysql_pass,
            database=args.mysql_db,
            autocommit=True,
        )
        return conn
    except mysql.connector.Error as e:
        raise SystemExit(f"Error conectando a MySQL: {e}")


def build_insert_sql(use_upsert: bool) -> str:
    base = (
        "INSERT INTO dw_messages "
        "(id, user_id, comment, sentiment_label, sentiment_score, raw_json) "
        "VALUES (%s, %s, %s, %s, %s, %s)"
    )
    if use_upsert:
        base += (
            " ON DUPLICATE KEY UPDATE "
            "user_id=VALUES(user_id), comment=VALUES(comment), "
            "sentiment_label=VALUES(sentiment_label), sentiment_score=VALUES(sentiment_score), "
            "raw_json=VALUES(raw_json)"
        )
    return base


def label_code_from_id2label(idx: int, id2label: Dict[int, str]) -> str:
    """
    Mapea la etiqueta textual del modelo a las 5 clases del DWH:
      vneg, neg, neu, pos, vpos
    """
    name = id2label.get(int(idx), str(idx)).lower().strip()
    # Orden importa: detectar 'very negative' antes que 'negative', etc.
    if "very negative" in name:
        return "vneg"
    if name == "negative" or ("negative" in name and "very" not in name):
        return "neg"
    if "neutral" in name:
        return "neu"
    if "very positive" in name:
        return "vpos"
    if name == "positive" or ("positive" in name and "very" not in name):
        return "pos"
    # Fallback conservador
    return "neu"


def essential_str(v) -> str:
    return "" if v is None else str(v)


def lock_batch(coll, n: int) -> List[dict]:
    """
    Toma hasta n documentos sin procesar (ausencia de 'proc') y los marca como locked.
    Operacion atomica por doc con find_one_and_update para evitar carreras.
    """
    out = []
    for _ in range(n):
        doc = coll.find_one_and_update(
            {"proc": {"$exists": False}},
            {"$set": {"proc": {"status": "locked", "ts": utcnow_iso()}}},
            return_document=ReturnDocument.AFTER,
        )
        if not doc:
            break
        out.append(doc)
    return out


class GracefulExit(Exception):
    pass


def install_signal_handlers(log: logging.Logger):
    def _handler(signum, frame):
        log.info(f"Recibida senal {signum}. Saliendo de forma ordenada...")
        raise GracefulExit()

    signal.signal(signal.SIGINT, _handler)
    signal.signal(signal.SIGTERM, _handler)


def main():
    args = parse_args()
    log = get_logger()
    install_signal_handlers(log)

    # Conexiones
    mongo = MongoClient(args.mongo_uri)
    coll = mongo[args.mongo_db][args.mongo_coll]
    conn = connect_mysql(args)
    cursor = conn.cursor(prepared=True)
    insert_sql = build_insert_sql(args.upsert)

    # Modelo HF (sin pipeline)
    log.info(f"Cargando modelo: {args.model}")
    tok = AutoTokenizer.from_pretrained(args.model)
    mdl = AutoModelForSequenceClassification.from_pretrained(args.model)
    mdl.eval()

    # Info de clases
    id2label = getattr(mdl.config, "id2label", {0: "Very Negative", 1: "Negative", 2: "Neutral", 3: "Positive", 4: "Very Positive"})
    log.info(f"Clases del modelo: {id2label}")

    total_target = args.max_docs if args.max_docs > 0 else float("inf")
    processed = 0

    while processed < total_target:
        batch = lock_batch(coll, args.batch_size)
        if not batch:
            time.sleep(args.poll_wait)
            continue

        texts = [essential_str(d.get("comment", "")).strip() or " " for d in batch]

        try:
            enc = tok(texts, padding=True, truncation=True, max_length=args.max_length, return_tensors="pt")
            with torch.no_grad():
                out = mdl(**enc)
            probs = F.softmax(out.logits, dim=-1)
        except Exception as e:
            # Marca todo el lote como error de inferencia
            err = f"inferencia_fallo: {e}"
            for d in batch:
                coll.update_one({"_id": d["_id"]}, {"$set": {"proc.status": "error", "proc.ts": utcnow_iso(), "proc.error": err}})
            log.error(err)
            continue

        for d, prob in zip(batch, probs):
            try:
                idx = int(torch.argmax(prob).item())
                label = label_code_from_id2label(idx, id2label)
                score = float(prob[idx].item())

                raw_json = json.dumps(d, ensure_ascii=False) if args.raw_json else None
                params = (
                    str(d.get("_id")),
                    essential_str(d.get("user_id", "")),
                    essential_str(d.get("comment", "")),
                    label,
                    score,
                    raw_json,
                )
                cursor.execute(insert_sql, params)

                coll.update_one(
                    {"_id": d["_id"]},
                    {"$set": {"proc.status": "done", "proc.ts": utcnow_iso(), "pred.label": label, "pred.score": score}},
                )

                processed += 1
                if processed % args.log_every == 0:
                    log.info(f"Procesados: {processed}")

                if processed >= total_target:
                    break

            except mysql.connector.Error as me:
                # Error de MySQL: marcar doc en error
                err = f"mysql_error: {getattr(me, 'msg', me)}"
                coll.update_one({"_id": d["_id"]}, {"$set": {"proc.status": "error", "proc.ts": utcnow_iso(), "proc.error": err}})
                log.error(err)
            except Exception as e:
                err = f"proc_error: {e}"
                coll.update_one({"_id": d["_id"]}, {"$set": {"proc.status": "error", "proc.ts": utcnow_iso(), "proc.error": err}})
                log.error(err)

    log.info(f"Listo. Total procesados: {processed}")


if __name__ == "__main__":
    try:
        main()
    except GracefulExit:
        sys.exit(0)
    except KeyboardInterrupt:
        sys.exit(130)
