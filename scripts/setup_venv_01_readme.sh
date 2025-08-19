1# probar sintaxis
bash -n scripts/setup_venv_01.sh

# 2) usando requirements.txt
chmod +x scripts/setup_venv_01.sh
bash scripts/setup_venv_01.sh -r requirements.txt


source .venv/scripts/activate

# verificar que venv este activo
echo $VIRTUAL_ENV
which python
python -V
python -c "import sys; print(sys.executable)"
pip -V


python -m pip install -U pip setuptools wheel
python -m pip install -r requirements.txt






source .venv/scripts/deactivate


#############
#Ejecuta el consumer con un grupo NUEVO y commits más frecuentes
python consumer_to_mongo.py \
  --bootstrap 51.57.73.26:29092 --topic user-topic \
  --mongo "mongodb://admin:pass@51.57.73.26:27017/?authSource=admin" \
  --db streamdb --coll raw_messages \
  --group raw-writer-2 --commit-every 10


#En otra terminal, produce algunos mensajes:
python scripts/send_kafka_burst.py --bootstrap 51.57.73.26:29092 --topic user-topic \
  --clients 10 --duration 120 --min-delay 0.5 --max-delay 3

# ejemplo usando un TXT exportado del dataset

python send_kafka_burst.py --bootstrap 51.57.73.26:29092 --topic user-topic \
  --clients 10 --duration 300 \
  --text-file ./corpus.txt \
  --min-delay 0.5 --max-delay 3.0


  

Verifica en Mongo:

#En Mongo Express deberías ver la DB streamdb y la colección raw_messages con documentos.
# Conteo rápido desde tu PC:
python - <<'PY'
from pymongo import MongoClient
mc = MongoClient("mongodb://admin:pass@51.57.73.26:27017/?authSource=admin")
print(mc.streamdb.raw_messages.count_documents({}))
PY

#descargar el dataset
rm -rf "/c/Users/mario.brenes/.cache/huggingface/hub/datasets--stanfordnlp--sentiment140"
rm -rf /z/hf_cache
mkdir -p /z/hf_cache # yo trabajo con la unidad Z:\
export HF_HOME=/z/hf_cache
python scripts/export_sentiment140.py --out corpus.txt --fmt txt --max 1000 --shuffle

# descarga del dataset desde la VM debido a fallo local:
python - <<'PY'
import os, random
from datasets import load_dataset
def clean(s): return s.replace("\r"," ").replace("\n"," ").strip()
MAX=5000
ds = load_dataset("stanfordnlp/sentiment140", trust_remote_code=True)
rows=[]
for split in ds.keys():
    for r in ds[split]:
        t=clean(str(r.get("text","")))
        if t: rows.append(t)
random.Random(42).shuffle(rows)
rows=rows[:MAX]
os.makedirs("/home/azureuser/corpus", exist_ok=True)
open("/home/azureuser/corpus/corpus.txt","w",encoding="utf-8").write("\n".join(rows))
print("WROTE", len(rows))
PY
#************
azureuser@vm-cftec-m62025-SINT646-labs:~/corpus$ python - <<'PY'
> import os, random
> from datasets import load_dataset
> def clean(s): return s.replace("\r"," ").replace("\n"," ").strip()
> MAX=5000
> ds = load_dataset("stanfordnlp/sentiment140", trust_remote_code=True)
> rows=[]
> for split in ds.keys():
>     for r in ds[split]:
>         t=clean(str(r.get("text","")))
>         if t: rows.append(t)
> random.Random(42).shuffle(rows)
> rows=rows[:MAX]
> os.makedirs("/home/azureuser/corpus", exist_ok=True)
> open("/home/azureuser/corpus/corpus.txt","w",encoding="utf-8").write("\n".join(rows))
> print("WROTE", len(rows))
> PY
Downloading data: 100%|███████████████████████████████████████████████████████████████████████| 81.4M/81.4M [00:01<00:00, 66.3MB/s]
Generating train split: 100%|██████████████████████████████████████████████████| 1600000/1600000 [01:51<00:00, 14346.52 examples/s]
Generating test split: 100%|███████████████████████████████████████████████████████████| 498/498 [00:00<00:00, 12591.03 examples/s]
WROTE 5000
(.venv) azureuser@vm-cftec-m62025-SINT646-labs:~/corpus$ 
#************
# en tu laptop, en la carpeta donde quieres el archivo
scp azureuser@51.57.73.26:/home/azureuser/corpus/corpus.txt ./corpus.txt
