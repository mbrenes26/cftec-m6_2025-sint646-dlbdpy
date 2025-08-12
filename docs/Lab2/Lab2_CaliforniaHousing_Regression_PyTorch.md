Laboratorio 2 — Regresion con PyTorch en California Housing

# Objetivo: 
- Construir una red neuronal para regresion, 
- completar el pipeline (preprocesamiento, entrenamiento, evaluacion) y 
- correr 8 experimentos combinando: 
    - 2 funciones de perdida, 
    - 2 optimizadores y 2 arquitecturas.

Prepara el entorno: instalacion de dependencias y verificacion de versiones. Si ya tienes todo instalado, ejecuta igual para confirmar.


```python
# Instalacion/verificacion de dependencias basicas (persistente para el usuario actual)
import sys, importlib, subprocess, site

def pip_install_user(pkg):
    print(f"Installing (user): {pkg}")
    subprocess.check_call([sys.executable, "-m", "pip", "install", "--user", "-q", pkg])

def ensure(pkg_name, import_name=None):
    mod = import_name or pkg_name
    try:
        importlib.import_module(mod)
        print(f"OK: {pkg_name}")
    except Exception:
        pip_install_user(pkg_name)
        importlib.import_module(mod)
        print(f"OK (installed): {pkg_name}")

requirements = [
    ("numpy", "numpy"),
    ("pandas", "pandas"),
    ("matplotlib", "matplotlib"),
    ("scikit-learn", "sklearn"),
    ("torch", "torch"),
]

for pkg, mod in requirements:
    ensure(pkg, mod)

# Mostrar donde quedo la instalacion del usuario
print("User site-packages:", site.getusersitepackages())
print("Listo.")

```

    OK: numpy
    OK: pandas
    OK: matplotlib
    OK: scikit-learn
    OK: torch
    User site-packages: /home/azureuser/.local/lib/python3.8/site-packages
    Listo.



```python
# Imports y configuración de entorno (sin instalaciones)
import os, math, time, json, random
import numpy as np
import pandas as pd
import matplotlib.pyplot as plt

import torch
from torch import nn
from torch.utils.data import Dataset, DataLoader

from sklearn.datasets import fetch_california_housing
from sklearn.model_selection import train_test_split
from sklearn.preprocessing import StandardScaler
from sklearn.metrics import r2_score, mean_squared_error

# Reproducibilidad
SEED = 42
random.seed(SEED)
np.random.seed(SEED)
torch.manual_seed(SEED)
torch.backends.cudnn.deterministic = True
torch.backends.cudnn.benchmark = False

# Dispositivo (forzamos CPU en este laboratorio)
DEVICE = torch.device("cpu")
print(f"Using device: {DEVICE}")
print("Torch version:", torch.__version__)

```

    Using device: cpu
    Torch version: 2.4.1+cu121


Imports, configuracion de reproducibilidad y verificacion de versiones. Esta celda debe ejecutarse despues de instalar paquetes.


```python
# Imports y configuracion de entorno
import os, math, time, json, random
import numpy as np
import pandas as pd
import matplotlib.pyplot as plt

import torch
from torch import nn
from torch.utils.data import Dataset, DataLoader

from sklearn.datasets import fetch_california_housing
from sklearn.model_selection import train_test_split
from sklearn.preprocessing import StandardScaler
from sklearn.metrics import r2_score, mean_squared_error

# Reproducibilidad
SEED = 42
random.seed(SEED)
np.random.seed(SEED)
torch.manual_seed(SEED)
torch.backends.cudnn.deterministic = True
torch.backends.cudnn.benchmark = False

DEVICE = torch.device("cpu")
print(f"Using device: {DEVICE}")
print("Torch version:", torch.__version__)

```


    ---------------------------------------------------------------------------

    ModuleNotFoundError                       Traceback (most recent call last)

    Cell In[2], line 5
          3 import numpy as np
          4 import pandas as pd
    ----> 5 import matplotlib.pyplot as plt
          7 import torch
          8 from torch import nn


    ModuleNotFoundError: No module named 'matplotlib'


Config de hiperparametros base y de la matriz de experimentos. Centralizamos valores que usaremos en todo el notebook para poder ajustarlos facilmente y justificar elecciones.


```python
# Hiperparametros base
CFG = {
    "test_size": 0.2,
    "val_size": 0.2,
    "batch_size": 256,
    "epochs": 80,
    "lr_sgd": 0.05,
    "lr_adam": 0.001,
    "momentum": 0.9,
    "weight_decay": 0.0,
    "smoothl1_beta": 1.0,
    "architectures": [[64], [16, 8]],
    "losses": ["mse", "smoothl1"],
    "optimizers": ["sgd", "adam"],
}
CFG

```

Carga del dataset California Housing. Si hay internet, se usa fetch_california_housing y se guarda un CSV local para corridas futuras offline. Si no hay internet, se intenta leer el CSV local. La salida muestra forma, nombres de variables y el nombre del target.


```python
from pathlib import Path

DATA_DIR = Path("datasets")
DATA_DIR.mkdir(exist_ok=True)
csv_path = DATA_DIR / "california_housing.csv"

def load_dataset():
    try:
        data = fetch_california_housing(as_frame=True)
        df = data.frame.copy()
        df.to_csv(csv_path, index=False)
        feature_names = list(data.feature_names)
        target_name = data.target_names[0] if hasattr(data, "target_names") else "MedHouseValue"
        return df, feature_names, target_name
    except Exception as e:
        print("Fallo fetch_california_housing, usando CSV local:", e)
        if not csv_path.exists():
            raise FileNotFoundError(f"No existe {csv_path}. Ejecute con internet al menos una vez.")
        df = pd.read_csv(csv_path)
        feature_names = [c for c in df.columns if c not in ("MedHouseVal", "target")]
        target_name = "MedHouseVal" if "MedHouseVal" in df.columns else "target"
        return df, feature_names, target_name

df, feature_names, target_name = load_dataset()
print("Shape:", df.shape)
print("Features:", feature_names)
print("Target:", target_name)
df.head()

```

EDA basica: estadisticas descriptivas por columna para entender escalas, rangos y posibles outliers.


```python
df.describe().T

```

EDA basica: histograma del target para ver distribucion y asimetria. Esto ayuda a interpretar MSE y R2.


```python
plt.figure()
df[target_name].hist(bins=50)
plt.xlabel(target_name)
plt.ylabel("count")
plt.title("Distribucion del target")
plt.show()

```

Division en conjuntos y normalizacion. Se separa en train, val y test. Luego se normalizan features con StandardScaler usando solo train para evitar leakage. Se imprime la forma de cada split.


```python
X = df[feature_names].values.astype(np.float32)
y = df[target_name].values.astype(np.float32).reshape(-1, 1)

X_train_full, X_test, y_train_full, y_test = train_and_test = train_test_split(
    X, y, test_size=CFG["test_size"], random_state=SEED
)

X_train, X_val, y_train, y_val = train_test_split(
    X_train_full, y_train_full, test_size=CFG["val_size"], random_state=SEED
)

scaler = StandardScaler()
X_train = scaler.fit_transform(X_train)
X_val = scaler.transform(X_val)
X_test = scaler.transform(X_test)

print("Train:", X_train.shape, "Val:", X_val.shape, "Test:", X_test.shape)

```

Clases Dataset y DataLoader para tabular. Esto encapsula tensores y define lotes para entrenamiento, validacion y prueba. Tambien se define input_dim y output_dim.


```python
class TabularDataset(Dataset):
    def __init__(self, X, y):
        self.X = torch.from_numpy(X).float()
        self.y = torch.from_numpy(y).float()
    def __len__(self):
        return len(self.X)
    def __getitem__(self, idx):
        return self.X[idx], self.y[idx]

train_ds = TabularDataset(X_train, y_train)
val_ds   = TabularDataset(X_val, y_val)
test_ds  = TabularDataset(X_test, y_test)

train_dl = DataLoader(train_ds, batch_size=CFG["batch_size"], shuffle=True)
val_dl   = DataLoader(val_ds, batch_size=CFG["batch_size"], shuffle=False)
test_dl  = DataLoader(test_ds, batch_size=CFG["batch_size"], shuffle=False)

input_dim = X_train.shape[1]
output_dim = 1
input_dim, output_dim

```

Constructor de MLP flexible. Recibe lista de tamanos de capas ocultas y ensambla capas Lineales y ReLU. Tambien se imprime el numero de parametros para cada arquitectura.


```python
def build_mlp(input_dim, hidden_layers, output_dim=1):
    layers = []
    prev = input_dim
    for h in hidden_layers:
        layers.append(nn.Linear(prev, h))
        layers.append(nn.ReLU())
        prev = h
    layers.append(nn.Linear(prev, output_dim))
    model = nn.Sequential(*layers)
    return model

for arch in CFG["architectures"]:
    m = build_mlp(input_dim, arch, output_dim)
    print(f"Arch {arch}: params = {sum(p.numel() for p in m.parameters())}")

```

Funciones auxiliares: seleccion de funcion de perdida (MSE o SmoothL1), seleccion de optimizador (SGD o Adam) y loops de entrenamiento y evaluacion. El entrenamiento acumula perdida promedio por epoch. La evaluacion calcula MSE y R2.


```python
def get_loss(loss_name):
    if loss_name == "mse":
        return nn.MSELoss()
    elif loss_name == "smoothl1":
        return nn.SmoothL1Loss(beta=CFG["smoothl1_beta"])
    else:
        raise ValueError("loss_name invalido")

def get_optimizer(opt_name, params, lr):
    if opt_name == "sgd":
        return torch.optim.SGD(params, lr=lr, momentum=CFG["momentum"], weight_decay=CFG["weight_decay"])
    elif opt_name == "adam":
        return torch.optim.Adam(params, lr=lr, weight_decay=CFG["weight_decay"])
    else:
        raise ValueError("opt_name invalido")

def train_one_epoch(model, loader, criterion, optimizer):
    model.train()
    running = 0.0
    for xb, yb in loader:
        xb = xb.to(DEVICE)
        yb = yb.to(DEVICE)
        optimizer.zero_grad(set_to_none=True)
        preds = model(xb)
        loss = criterion(preds, yb)
        loss.backward()
        optimizer.step()
        running += loss.item() * xb.size(0)
    return running / len(loader.dataset)

@torch.no_grad()
def evaluate(model, loader):
    model.eval()
    all_preds = []
    all_targets = []
    for xb, yb in loader:
        xb = xb.to(DEVICE)
        preds = model(xb).cpu().numpy()
        all_preds.append(preds)
        all_targets.append(yb.numpy())
    y_true = np.vstack(all_targets)
    y_pred = np.vstack(all_preds)
    mse = mean_squared_error(y_true, y_pred)
    r2 = r2_score(y_true, y_pred)
    return {"mse": mse, "r2": r2}

```

Ejecutor de un experimento. Construye el modelo segun arquitectura, loss y optimizador; entrena por N epochs; guarda la historia de train loss y metricas de validacion; devuelve metricas de test.


```python
def run_experiment(arch, loss_name, opt_name, epochs, batch_size, lr):
    model = build_mlp(input_dim, arch, output_dim).to(DEVICE)
    criterion = get_loss(loss_name)
    optimizer = get_optimizer(opt_name, model.parameters(), lr=lr)
    history = {"train_loss": [], "val_mse": [], "val_r2": []}
    for ep in range(1, epochs+1):
        tloss = train_one_epoch(model, train_dl, criterion, optimizer)
        val_metrics = evaluate(model, val_dl)
        history["train_loss"].append(tloss)
        history["val_mse"].append(val_metrics["mse"])
        history["val_r2"].append(val_metrics["r2"])
    test_metrics = evaluate(model, test_dl)
    return model, history, test_metrics

```

Ejecucion de los 8 experimentos (2 perdidas x 2 optimizadores x 2 arquitecturas). Se registra historia por experimento y se consolidan metricas de test en un DataFrame ordenado por MSE ascendente.


```python
results = []
histories = {}
exp_id = 0

for arch in CFG["architectures"]:
    for loss_name in CFG["losses"]:
        for opt_name in CFG["optimizers"]:
            exp_id += 1
            lr = CFG["lr_sgd"] if opt_name == "sgd" else CFG["lr_adam"]
            print(f"Running exp {exp_id}: arch={arch}, loss={loss_name}, opt={opt_name}, lr={lr}")
            model, history, test_metrics = run_experiment(
                arch=arch,
                loss_name=loss_name,
                opt_name=opt_name,
                epochs=CFG["epochs"],
                batch_size=CFG["batch_size"],
                lr=lr,
            )
            tag = f"exp{exp_id}_arch{arch}_loss{loss_name}_opt{opt_name}"
            histories[tag] = history
            results.append({
                "exp_id": exp_id,
                "arch": str(arch),
                "loss": loss_name,
                "optimizer": opt_name,
                "epochs": CFG["epochs"],
                "batch_size": CFG["batch_size"],
                "lr": lr,
                "test_mse": test_metrics["mse"],
                "test_r2": test_metrics["r2"],
                "params": sum(p.numel() for p in model.parameters())
            })

results_df = pd.DataFrame(results).sort_values(by=["test_mse"]).reset_index(drop=True)
results_df

```

Persistencia de resultados y seleccion del mejor experimento segun MSE de test. Se guarda un CSV en outputs/ para documentar la corrida.


```python
from pathlib import Path

OUT_DIR = Path("outputs")
OUT_DIR.mkdir(exist_ok=True)
csv_out = OUT_DIR / "lab2_results.csv"
results_df.to_csv(csv_out, index=False)
print("Resultados guardados en:", csv_out.resolve())

best_row = results_df.iloc[0]
best_row

```

Graficas de aprendizaje del mejor experimento: curva de perdida de entrenamiento, MSE de validacion y R2 de validacion por epoch. Sirve para diagnosticar sobreajuste o subentrenamiento.


```python
best_tag = None
for k in histories.keys():
    if str(int(best_row["exp_id"])) in k:
        best_tag = k
        break

if best_tag is None:
    print("No se encontro el tag del mejor experimento.")
else:
    h = histories[best_tag]
    plt.figure()
    plt.plot(h["train_loss"])
    plt.xlabel("epoch")
    plt.ylabel("train_loss")
    plt.title(f"Train loss - {best_tag}")
    plt.show()

    plt.figure()
    plt.plot(h["val_mse"])
    plt.xlabel("epoch")
    plt.ylabel("val_mse")
    plt.title(f"Val MSE - {best_tag}")
    plt.show()

    plt.figure()
    plt.plot(h["val_r2"])
    plt.xlabel("epoch")
    plt.ylabel("val_r2")
    plt.title(f"Val R2 - {best_tag}")
    plt.show()

```

Guardado de un modelo de referencia. Se reentrena rapidamente el modelo con la mejor configuracion para exportar estado y parametros del escalador, utiles si se quisiera cargar el modelo luego.


```python
best_arch = eval(best_row["arch"])
best_loss = best_row["loss"]
best_opt  = best_row["optimizer"]
best_lr = CFG["lr_sgd"] if best_opt == "sgd" else CFG["lr_adam"]

best_model = build_mlp(input_dim, best_arch, output_dim).to(DEVICE)
criterion = get_loss(best_loss)
optimizer = get_optimizer(best_opt, best_model.parameters(), lr=best_lr)

for ep in range(5):
    _ = train_one_epoch(best_model, train_dl, criterion, optimizer)

model_out = OUT_DIR / "best_model_state.pt"
torch.save({
    "state_dict": best_model.state_dict(),
    "input_dim": input_dim,
    "arch": best_arch,
    "output_dim": output_dim,
    "scaler_mean": scaler.mean_.tolist(),
    "scaler_scale": scaler.scale_.tolist(),
}, model_out)
print("Modelo guardado en:", model_out.resolve())

```

Plantilla para documentar justificacion de hiperparametros y decisiones. Complete con su analisis.

Normalizacion: por que StandardScaler.

Arquitecturas: razon de elegir [64] vs [16, 8].

Perdidas: MSE vs SmoothL1 (robustez a outliers y efecto de beta).

Optimizadores: SGD con momentum vs Adam, ventajas y riesgos.

Learning rate, batch size y epochs: criterios de eleccion y ajustes observados.

Resultados, analisis y conclusiones.

Inserte la tabla results_df y resalte el experimento ganador segun MSE y R2 en test.

Interprete las curvas del mejor experimento.

Compare las combinaciones de perdida, optimizador y arquitectura.

Concluya con mejores practicas y proximos pasos.
