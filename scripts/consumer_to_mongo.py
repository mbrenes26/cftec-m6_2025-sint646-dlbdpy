#!/usr/bin/env python3
"""
Kafka -> MongoDB (documento MINIMAL)
Guarda UNICAMENTE: { _id, user_id, comment }

Ejemplo:
  python scripts/consumer_to_mongo_min.py \
    --bootstrap 51.57.73.26:29092 --topic user-topic \
    --mongo "mongodb://admin:pass@51.57.73.26:27017/?authSource=admin" \
    --db streamdb --coll raw_messages_min \
    --group raw-writer-min --batch 100 --commit-every 100
"""

import argparse, json, sys, uuid
from datetime import datetime, timezone
from typing import List, Dict
from pymongo import MongoClient, ReplaceOne, ASCENDING
from kafka import KafkaConsumer

def parse_args():
    p = argparse.ArgumentParser(description="Kafka -> MongoDB (minimal)")
    p.add_argument("--bootstrap", required=True)
    p.add_argument("--topic", required=True)
    p.add_argument("--group", default="raw-writer-min")
    p.add_argument("--mongo", required=True)
    p.add_argument("--db", default="streamdb")
    p.add_argument("--coll", default="raw_messages_min")
    p.add_argument("--batch", type=int, default=100, help="tamano batch Mongo")
    p.add_argument("--commit-every", type=int, default=100, help="commit offsets cada N docs")
    return p.parse_args()

def to_minimal(rec_value: bytes) -> Dict:
    try:
        payload = json.loads(rec_value.decode("utf-8"))
    except Exception:
        # Si llega texto plano, lo metemos como comment
        txt = rec_value.decode("utf-8", errors="replace")
        return {"_id": str(uuid.uuid4()), "user_id": None, "comment": txt}

    meta = payload.get("meta") or {}
    doc_id = meta.get("id") or payload.get("id") or str(uuid.uuid4())
    comment = payload.get("comment") or payload.get("text")
    user_id = payload.get("user_id")
    return {"_id": doc_id, "user_id": user_id, "comment": comment}

def main():
    a = parse_args()

    mc = MongoClient(a.mongo)
    col = mc[a.db][a.coll]
    col.create_index([("user_id", ASCENDING)], background=True)

    consumer = KafkaConsumer(
        a.topic,
        bootstrap_servers=a.bootstrap,
        group_id=a.group,
        enable_auto_commit=False,
        auto_offset_reset="earliest",
    )

    buf: List[Dict] = []
    ingested = 0
    print("listo. consumiendo...")
    try:
        while True:
            records = consumer.poll(timeout_ms=1000, max_records=a.batch)
            if not records:
                # si no hay datos pendientes, vaciamos buffer si hubiera
                if buf:
                    ops = [ReplaceOne({"_id": d["_id"]}, d, upsert=True) for d in buf if d.get("comment")]
                    if ops:
                        col.bulk_write(ops, ordered=False)
                        ingested += len(ops)
                        if ingested % a.commit_every == 0:
                            consumer.commit()
                            print(f"ingestados={ingested}", flush=True)
                    buf.clear()
                continue

            for _, msgs in records.items():
                for rec in msgs:
                    d = to_minimal(rec.value)
                    if d.get("comment"):  # solo documentos con comment valido
                        buf.append(d)

            if len(buf) >= a.batch:
                ops = [ReplaceOne({"_id": d["_id"]}, d, upsert=True) for d in buf]
                if ops:
                    col.bulk_write(ops, ordered=False)
                    ingested += len(ops)
                    if ingested % a.commit_every == 0:
                        consumer.commit()
                        print(f"ingestados={ingested}", flush=True)
                buf.clear()

    except KeyboardInterrupt:
        pass
    finally:
        if buf:
            ops = [ReplaceOne({"_id": d["_id"]}, d, upsert=True) for d in buf if d.get("comment")]
            if ops:
                col.bulk_write(ops, ordered=False)
                ingested += len(ops)
        try:
            consumer.commit()
        except Exception:
            pass
        consumer.close()
        mc.close()
        print(f"fin. total_ingestado={ingested}")

if __name__ == "__main__":
    sys.exit(main())
