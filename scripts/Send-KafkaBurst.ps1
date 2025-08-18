<#
.SYNOPSIS
Produce muchos mensajes hacia Apache Kafka desde Windows usando PowerShell, sin instalar utilidades de Kafka.

.DESCRIPTION
Crea un entorno virtual de Python en %TEMP%, instala kafka-python y lanza N procesos productores
en paralelo. Cada proceso envia mensajes JSON simples con timestamp a un topic.

.PARAMETER Bootstrap
Host:puerto del broker Kafka (ej: 51.57.73.26:29092).

.PARAMETER Topic
Nombre del topic (ej: user-topic).

.PARAMETER Clients
Numero de procesos clientes en paralelo. Default: 10.

.PARAMETER Rate
Mensajes por segundo promedio por cliente (distribucion Poisson). Default: 2.0.

.PARAMETER DurationSec
Segundos totales de envio. 0 = corre hasta Ctrl+C. Default: 60.

.PARAMETER MaxPerClient
Maximo de mensajes por cliente. 0 = ilimitado. Default: 0.

.PARAMETER TextFile
Ruta a archivo opcional con frases (una por linea) para variar el texto.

.EXAMPLE
.\Send-KafkaBurst.ps1 -Bootstrap "51.57.73.26:29092" -Topic "user-topic" -Clients 20 -Rate 3 -DurationSec 120

.NOTES
Requiere Python 3.x en PATH. No cambia la infraestructura. Usa PLAINTEXT.
#>

param(
  [Parameter(Mandatory=$true)][string]$Bootstrap,
  [Parameter(Mandatory=$true)][string]$Topic,
  [int]$Clients = 10,
  [double]$Rate = 2.0,
  [int]$DurationSec = 60,
  [int]$MaxPerClient = 0,
  [string]$TextFile = ""
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

function Find-Python {
  try { (& python --version) 2>$null | Out-Null; if ($LASTEXITCODE -eq 0) { return "python" } } catch {}
  try { (& py -3 --version) 2>$null | Out-Null; if ($LASTEXITCODE -eq 0) { return "py -3" } } catch {}
  return $null
}

# 0) Verificar Python
$py = Find-Python
if (-not $py) { throw "Python 3 no encontrado. Instala Python 3.x y reintenta." }

# 1) Preparar carpeta de trabajo y venv
$root = Join-Path $env:TEMP ("kafka-burst-" + (Get-Date -Format "yyyyMMdd-HHmmss"))
$null = New-Item -ItemType Directory -Force -Path $root
$venv = Join-Path $root ".venv"
Write-Host "Workdir: $root"

if ($py -eq "python") { & python -m venv $venv } else { & py -3 -m venv $venv }
$pyExe = (Resolve-Path (Join-Path $venv "Scripts\python.exe")).Path

& $pyExe -m pip install --upgrade pip --quiet
& $pyExe -m pip install --quiet kafka-python

# 2) Escribir productor Python
$producerPy = @"
#!/usr/bin/env python3
import argparse, json, os, sys, time, uuid, random
from datetime import datetime, timezone
from kafka import KafkaProducer

def parse_args():
    p = argparse.ArgumentParser(description="Kafka producer client (one process = one client)")
    p.add_argument("--bootstrap", required=True)
    p.add_argument("--topic", required=True)
    p.add_argument("--client-id", default=None)
    p.add_argument("--rate", type=float, default=2.0)
    p.add_argument("--max", type=int, default=0)
    p.add_argument("--text-file", default=None)
    return p.parse_args()

def load_corpus(path):
    if not path:
        return [
            "me encanta este servicio",
            "el sistema esta caido",
            "la experiencia fue neutral",
            "excelente atencion",
            "mala calidad en la ultima entrega",
            "soporte rapido y util",
            "lento y con errores",
            "todo bien por ahora",
        ]
    try:
        with open(path, "r", encoding="utf-8") as f:
            lines = [ln.strip() for ln in f if ln.strip()]
        return lines or ["mensaje"]
    except Exception:
        return ["mensaje"]

def main():
    args = parse_args()
    client_id = args.client_id or f"client-{uuid.uuid4().hex[:8]}"
    corpus = load_corpus(args.text_file)

    producer = KafkaProducer(
        bootstrap_servers=args.bootstrap,
        acks=1,
        linger_ms=10,
        value_serializer=lambda v: json.dumps(v, ensure_ascii=False).encode("utf-8"),
        key_serializer=lambda v: v.encode("utf-8") if v is not None else None,
    )

    sent = 0
    try:
        while True:
            text = random.choice(corpus)
            now = datetime.now(timezone.utc).isoformat()
            user_id = f"user_{random.randint(1, 100000):05d}"
            msg_id = str(uuid.uuid4())
            payload = {"id": msg_id, "client_id": client_id, "user_id": user_id, "text": text, "ts": now}
            producer.send(args.topic, key=client_id, value=payload)
            sent += 1
            if sent % 100 == 0:
                producer.flush()
                print(f"metric client={client_id} sent={sent}", flush=True)
            delay = random.expovariate(args.rate) if args.rate > 0 else 0.0
            time.sleep(delay)
            if args.max and sent >= args.max:
                break
    except KeyboardInterrupt:
        pass
    finally:
        producer.flush()
        producer.close()
        print(f"done client={client_id} sent={sent}", flush=True)

if __name__ == "__main__":
    sys.exit(main())
"@
$producerPath = Join-Path $root "producer_client.py"
Set-Content -Path $producerPath -Value $producerPy -Encoding UTF8 -NoNewline

# 3) Lanzar N clientes con redireccion a logs
$procs = @()
$logs  = @()
for ($i = 1; $i -le $Clients; $i++) {
  $cid = "ps-$i"
  $log = Join-Path $root ("client-$i.log")
  $argsP = @($producerPath, "--bootstrap", $Bootstrap, "--topic", $Topic, "--client-id", $cid, "--rate", "$Rate")
  if ($MaxPerClient -gt 0) { $argsP += @("--max", "$MaxPerClient") }
  if ($TextFile -ne "")   { $argsP += @("--text-file", $TextFile) }

  $p = Start-Process -FilePath $pyExe -ArgumentList $argsP `
        -RedirectStandardOutput $log -RedirectStandardError $log `
        -NoNewWindow -PassThru
  $procs += $p
  $logs  += $log
  Write-Host ("started client {0} pid={1}" -f $cid, $p.Id)
}

# 4) Duracion y parada
if ($DurationSec -gt 0) {
  Write-Host "running for $DurationSec seconds..."
  Start-Sleep -Seconds $DurationSec
  Write-Host "stopping..."
  foreach ($p in $procs) { if (-not $p.HasExited) { try { $p.Kill() } catch {} } }
} else {
  Write-Host "running until Ctrl+C. press Ctrl+C to stop."
  try { while ($true) { Start-Sleep -Seconds 5 } } catch {
    foreach ($p in $procs) { if (-not $p.HasExited) { try { $p.Kill() } catch {} } }
  }
}

# 5) Resumen
Start-Sleep -Seconds 2
$total = 0
for ($i = 0; $i -lt $procs.Count; $i++) {
  $log = $logs[$i]
  $sent = 0
  if (Test-Path $log) {
    $last = Get-Content $log -Tail 200 -ErrorAction SilentlyContinue
    foreach ($ln in $last) {
      if ($ln -match "done client=.* sent=(\d+)") { $sent = [int]$Matches[1]; break }
      if ($ln -match "metric client=.* sent=(\d+)") { $sent = [int]$Matches[1] }
    }
  }
  $total += $sent
  Write-Host ("client {0}: sent={1}" -f ($i+1), $sent)
}
Write-Host ("TOTAL sent={0}" -f $total)
Write-Host ("logs in: {0}" -f $root)
