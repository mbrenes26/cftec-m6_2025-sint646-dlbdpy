Registro de tarea exitosa — Conexión SSH a la VM en Azure
Objetivo
Conectarse por SSH a la máquina virtual vm-cftec-m62025-SINT646-lab01 creada con Terraform, validando:

Configuración correcta de NSG (puerto 22 abierto).

Clave pública SSH correctamente configurada.

VM operativa y accesible desde internet.

Pasos ejecutados
Confirmación de IP pública

Desde Azure Portal, en el recurso pip-cftec-m62025-SINT646-lab01, se verificó que la IP pública asignada es:

Copy
Edit
4.155.211.247
Verificación de reglas de seguridad

Se comprobó que el Network Security Group (NSG) asociado a la Subnet incluye la regla:

makefile
Copy
Edit
Name: Allow-SSH
Direction: Inbound
Protocol: TCP
Port: 22
Action: Allow
Source: Any
Esto asegura que el puerto 22 está abierto para conexiones SSH desde cualquier origen (configuración de laboratorio).

Ejecución del comando SSH

Desde la máquina local (Windows con Git Bash), se ejecutó:

bash
Copy
Edit
ssh -i ~/.ssh/id_rsa azureuser@4.155.211.247
Donde:

-i ~/.ssh/id_rsa → ruta de la clave privada correspondiente a la clave pública configurada en Terraform.

azureuser → usuario administrador definido en la VM.

4.155.211.247 → IP pública de la VM.

Aceptación de huella digital

Como era la primera conexión, el sistema mostró:

nginx
Copy
Edit
The authenticity of host '4.155.211.247' can't be established...
Se respondió:

bash
Copy
Edit
yes
El sistema agregó la huella a la lista de known hosts.

Ingreso de passphrase de la clave privada

Al haberse configurado la clave privada con passphrase, el cliente SSH solicitó:

swift
Copy
Edit
Enter passphrase for key '/c/Users/mario.brenes/.ssh/id_rsa':
Se ingresó la passphrase correcta.

Acceso exitoso a la VM

La sesión SSH se estableció mostrando:

css
Copy
Edit
Welcome to Ubuntu 20.04.6 LTS (GNU/Linux 5.15.0-1089-azure x86_64)
Información del sistema:

OS: Ubuntu 20.04.6 LTS

IP interna: 10.0.1.4

Usuario: azureuser

Estado: sin actualizaciones críticas pendientes (0 updates inmediatas).

Aviso de reinicio requerido por cambios en el sistema:

pgsql
Copy
Edit
*** System restart required ***
Resultado
✅ Conexión SSH establecida con éxito.
La VM es accesible remotamente desde internet y está lista para configuración adicional (instalación de Docker y otros servicios).

Registro de tarea — Verificación y actualización del sistema operativo
Objetivo
Verificar y actualizar el sistema operativo Ubuntu 20.04.6 LTS de la VM vm-cftec-m62025-SINT646-lab01 para garantizar que se encuentra al día antes de instalar Docker y otros servicios.

Pasos ejecutados
Conexión a la VM por SSH

Desde la máquina local:

bash
Copy
Edit
ssh -i ~/.ssh/id_rsa azureuser@4.155.211.247
Actualización de listas de paquetes

Comando:

bash
Copy
Edit
sudo apt update
Resultado:

perl
Copy
Edit
Hit:1 http://azure.archive.ubuntu.com/ubuntu focal InRelease
Hit:2 http://azure.archive.ubuntu.com/ubuntu focal-updates InRelease
Hit:3 http://azure.archive.ubuntu.com/ubuntu focal-backports InRelease
Hit:4 http://azure.archive.ubuntu.com/ubuntu focal-security InRelease
Reading package lists... Done
Building dependency tree       
Reading state information... Done
All packages are up to date.
Interpretación:

Todas las listas de paquetes están actualizadas.

No hay actualizaciones pendientes en los repositorios estándar de Ubuntu.

Actualización de paquetes instalados

Comando:

bash
Copy
Edit
sudo apt upgrade -y
Resultado:

javascript
Copy
Edit
Calculating upgrade... Done
The following security updates require Ubuntu Pro with 'esm-infra' enabled:
  <lista de paquetes ESM>
0 upgraded, 0 newly installed, 0 to remove and 0 not upgraded.
Interpretación:

No hay actualizaciones disponibles en los repositorios estándar.

Algunos paquetes con soporte extendido (ESM) requieren Ubuntu Pro para recibir parches de seguridad.

Conclusión

No fue necesario ejecutar:

bash
Copy
Edit
sudo apt autoremove -y
sudo reboot
El sistema ya estaba en el estado más reciente posible sin habilitar Ubuntu Pro.

Resultado
✅ El sistema está actualizado y no presenta paquetes pendientes de actualización en los repositorios estándar de Ubuntu 20.04.

Registro de tarea — Instalación y configuración de Docker en la VM
Objetivo
Instalar y habilitar Docker Engine en la VM vm-cftec-m62025-SINT646-lab01 para permitir la ejecución de contenedores necesarios en el laboratorio.

Pasos ejecutados
Conexión a la VM por SSH

bash
Copy
Edit
ssh -i ~/.ssh/id_rsa azureuser@4.155.211.247
Instalación de Docker

Comando:

bash
Copy
Edit
sudo apt install -y docker.io
Resultado:

pgsql
Copy
Edit
docker.io is already the newest version (26.1.3-0ubuntu1~20.04.1).
0 upgraded, 0 newly installed, 0 to remove and 0 not upgraded.
Interpretación:

Docker ya estaba instalado en la última versión disponible.

Habilitar el servicio Docker para que arranque automáticamente

bash
Copy
Edit
sudo systemctl enable docker
Resultado:

nginx
Copy
Edit
docker
Iniciar el servicio Docker

bash
Copy
Edit
sudo systemctl start docker
Verificar versión de Docker instalada

bash
Copy
Edit
docker --version
Resultado:

nginx
Copy
Edit
Docker version 26.1.3, build 26.1.3-0ubuntu1~20.04.1
Agregar el usuario azureuser al grupo docker

bash
Copy
Edit
sudo usermod -aG docker azureuser
Esto permite ejecutar comandos Docker sin sudo.

Cerrar la sesión SSH

bash
Copy
Edit
exit
Es necesario reconectarse para que la pertenencia al grupo docker se aplique.

Resultado
✅ Docker instalado, habilitado y configurado correctamente en la VM.
El usuario azureuser ya tiene permisos para usar Docker sin privilegios de administrador en la próxima sesión.

Registro de tarea — Prueba de funcionamiento de Docker con hello-world
Objetivo
Verificar que Docker está instalado y operativo en la VM vm-cftec-m62025-SINT646-lab01, permitiendo la ejecución de contenedores y la descarga de imágenes desde Docker Hub.

Pasos ejecutados
Conexión a la VM

bash
Copy
Edit
ssh -i ~/.ssh/id_rsa azureuser@4.155.211.247
Ejecución del contenedor de prueba

bash
Copy
Edit
docker run hello-world
Acción:

El cliente Docker (docker) envió la orden al demonio (dockerd).

Como la imagen hello-world no estaba disponible localmente, Docker la descargó desde Docker Hub.

Se creó un contenedor temporal que ejecutó un script de verificación.

El mensaje de bienvenida confirmó que todo está funcionando.

Salida obtenida:

vbnet
Copy
Edit
Unable to find image 'hello-world:latest' locally
latest: Pulling from library/hello-world
e6590344b1a5: Pull complete
Digest: sha256:ec153840d1e635ac434fab5e377081f17e0e15afab27beb3f726c3265039cfff
Status: Downloaded newer image for hello-world:latest

Hello from Docker!
This message shows that your installation appears to be working correctly.
...
Interpretación:

Docker pudo comunicarse con el demonio y descargar imágenes desde Internet.

El contenedor se ejecutó exitosamente.

El usuario azureuser tiene permisos correctos para ejecutar Docker sin sudo.

Resultado
✅ Docker operativo y listo para ejecutar contenedores para los servicios requeridos por el laboratorio (HBase, MongoDB, Redis).

Registro de tarea — Implementación de MongoDB en contenedor Docker
Objetivo
Desplegar MongoDB en la VM vm-cftec-m62025-SINT646-lab01 como contenedor Docker para uso en el laboratorio.

Pasos ejecutados
Conexión a la VM

bash
Copy
Edit
ssh -i ~/.ssh/id_rsa azureuser@4.155.211.247
Descarga de la imagen oficial de MongoDB

bash
Copy
Edit
docker pull mongo:latest
Resultado:

makefile
Copy
Edit
latest: Pulling from library/mongo
32f112e3802c: Pull complete
...
Status: Downloaded newer image for mongo:latest
docker.io/library/mongo:latest
Creación de volumen persistente para datos

bash
Copy
Edit
docker volume create mongo_data
Resultado:

nginx
Copy
Edit
mongo_data
Ejecución del contenedor MongoDB

bash
Copy
Edit
docker run -d \
  --name mongodb \
  -p 27017:27017 \
  -v mongo_data:/data/db \
  -e MONGO_INITDB_ROOT_USERNAME=admin \
  -e MONGO_INITDB_ROOT_PASSWORD=admin123 \
  mongo:latest
Resultado:

Copy
Edit
030a105e7146f4a6d71207787b5a3488472c5478575258466b90c1d33db67e70
Verificación de contenedor activo

bash
Copy
Edit
docker ps
Resultado:

bash
Copy
Edit
CONTAINER ID   IMAGE          COMMAND                  CREATED          STATUS          PORTS                                           NAMES
030a105e7146   mongo:latest   "docker-entrypoint.s…"   23 seconds ago   Up 22 seconds   0.0.0.0:27017->27017/tcp, :::27017->27017/tcp   mongodb
Acceso a la consola de MongoDB

bash
Copy
Edit
docker exec -it mongodb mongosh -u admin -p admin123
Resultado:

sql
Copy
Edit
Connecting to: mongodb://<credentials>@127.0.0.1:27017
Using MongoDB: 8.0.12
Using Mongosh: 2.5.6
test>
Confirmación de conexión local exitosa.

Resultado
✅ MongoDB desplegado correctamente como contenedor en la VM.
Funciona en el puerto 27017 y es accesible localmente desde la propia VM.
Datos persistentes en el volumen Docker mongo_data.

Registro de tarea — Implementación de Redis en contenedor Docker
Objetivo
Desplegar Redis en la VM vm-cftec-m62025-SINT646-lab01 como contenedor Docker con persistencia de datos.

Pasos ejecutados
Conexión a la VM

bash
Copy
Edit
ssh -i ~/.ssh/id_rsa azureuser@4.155.211.247
Descarga de la imagen oficial de Redis

bash
Copy
Edit
docker pull redis:latest
Resultado:

makefile
Copy
Edit
latest: Pulling from library/redis
59e22667830b: Pull complete
...
Status: Downloaded newer image for redis:latest
docker.io/library/redis:latest
Creación de volumen persistente

bash
Copy
Edit
docker volume create redis_data
Resultado:

nginx
Copy
Edit
redis_data
Ejecución del contenedor Redis

bash
Copy
Edit
docker run -d \
  --name redis \
  -p 6379:6379 \
  -v redis_data:/data \
  redis:latest
Resultado:

nginx
Copy
Edit
a7c3bd235592357277ed0396e550bc2fa13f86d7325fe5132900a53d221c2453
Verificación de contenedor activo

bash
Copy
Edit
docker ps
Resultado:

bash
Copy
Edit
CONTAINER ID   IMAGE          COMMAND                  CREATED         STATUS         PORTS                                           NAMES
a7c3bd235592   redis:latest   "docker-entrypoint.s…"   7 seconds ago   Up 6 seconds   0.0.0.0:6379->6379/tcp, :::6379->6379/tcp       redis
030a105e7146   mongo:latest   "docker-entrypoint.s…"   2 minutes ago   Up 2 minutes   0.0.0.0:27017->27017/tcp, :::27017->27017/tcp   mongodb
Conexión al cliente Redis

bash
Copy
Edit
docker exec -it redis redis-cli
Resultado:

makefile
Copy
Edit
127.0.0.1:6379>
Prueba de conexión
Dentro del cliente Redis:

bash
Copy
Edit
ping
Resultado esperado:

nginx
Copy
Edit
PONG
Para salir:

bash
Copy
Edit
exit
Resultado
✅ Redis desplegado y funcionando en el puerto 6379, con persistencia de datos en el volumen redis_data.
Disponible para uso en el laboratorio junto con MongoDB.


Registro de tarea — Implementación de HBase en contenedor Docker
Objetivo
Desplegar HBase en la VM vm-cftec-m62025-SINT646-lab01 como contenedor Docker en modo standalone para uso en el laboratorio.

Pasos ejecutados
Conexión a la VM

bash
Copy
Edit
ssh -i ~/.ssh/id_rsa azureuser@4.155.211.247
Descarga de la imagen de HBase

bash
Copy
Edit
docker pull harisekhon/hbase
Resultado:

vbnet
Copy
Edit
Using default tag: latest
latest: Pulling from harisekhon/hbase
...
Status: Downloaded newer image for harisekhon/hbase:latest
docker.io/harisekhon/hbase:latest
Creación de volumen persistente

bash
Copy
Edit
docker volume create hbase_data
Resultado:

nginx
Copy
Edit
hbase_data
Ejecución del contenedor HBase

bash
Copy
Edit
docker run -d \
  --name hbase \
  -p 16000:16000 \
  -p 16010:16010 \
  -p 16020:16020 \
  -p 16030:16030 \
  -p 2181:2181 \
  -v hbase_data:/hbase-data \
  harisekhon/hbase
Resultado:

nginx
Copy
Edit
c218beae29577eba6ed9fbf29beef520fdbedbdbed2895ec4d6c4046d68ea4f8
Verificación de contenedor activo

bash
Copy
Edit
docker ps
Resultado:

bash
Copy
Edit
CONTAINER ID   IMAGE              COMMAND                  CREATED          STATUS          PORTS                                                                                      NAMES
c218beae2957   harisekhon/hbase   "/entrypoint.sh"         8 seconds ago    Up 7 seconds    0.0.0.0:2181->2181/tcp, 0.0.0.0:16000->16000/tcp, 0.0.0.0:16010->16010/tcp, 0.0.0.0:16020->16020/tcp, 0.0.0.0:16030->16030/tcp   hbase
Revisión de logs

bash
Copy
Edit
docker logs hbase --tail 20
Resultado:

Se muestran mensajes de inicialización de HMaster y HRegionServer.

Zookeeper inició correctamente en el puerto 2181.

HBase está listo para aceptar conexiones.

Puertos expuestos
16000 → HMaster

16010 → Web UI de HMaster (http://4.155.211.247:16010)

16020 → HRegionServer

16030 → Web UI de HRegionServer

2181 → Zookeeper

Resultado
✅ HBase desplegado y operativo en la VM, con acceso local y remoto a sus puertos y persistencia de datos en el volumen hbase_data.

📄 Registro de tarea — Implementación de MongoDB y Mongo Express en contenedores Docker
Fecha: 06/agosto/2025
Responsable: Mario Brenes

Objetivo
Desplegar MongoDB y Mongo Express en la VM del laboratorio, utilizando contenedores Docker, para disponer de una base de datos NoSQL y su interfaz web de administración, accesible desde la red pública del laboratorio.

Actividades realizadas
Verificación de Docker en la VM

Confirmado que Docker está instalado y operativo (docker --version).

Verificado que el usuario azureuser pertenece al grupo docker para ejecutar sin sudo.

Despliegue de MongoDB

Creado volumen persistente:

bash
Copy
Edit
docker volume create mongo_data
Contenedor MongoDB:

bash
Copy
Edit
docker run -d \
  --name mongodb \
  -p 27017:27017 \
  -v mongo_data:/data/db \
  -e MONGO_INITDB_ROOT_USERNAME=admin \
  -e MONGO_INITDB_ROOT_PASSWORD=admin123 \
  mongo:latest
Verificado acceso local con:

bash
Copy
Edit
docker exec -it mongodb mongosh -u admin -p admin123 --authenticationDatabase admin
Despliegue de Mongo Express

Inicialmente intentado con --link mongodb:mongo, pero fallaba la resolución de hostname en Docker moderno.

Confirmado que Mongo Express se ejecuta correctamente y expone el puerto 8081.

Se mantuvo la autenticación web por defecto de laboratorio (admin / pass).

Comando final utilizado:

bash
Copy
Edit
docker run -d \
  --name mongo-express \
  -p 8081:8081 \
  -e ME_CONFIG_MONGODB_ADMINUSERNAME=admin \
  -e ME_CONFIG_MONGODB_ADMINPASSWORD=admin123 \
  -e ME_CONFIG_MONGODB_SERVER=mongodb \
  mongo-express:latest
Apertura de puerto en NSG

Modificado network.tf para agregar regla NSG que permita acceso HTTP en puerto 8081 solo desde mi IP pública.

Aplicado cambio con terraform apply.

Verificación de acceso

Acceso exitoso a la interfaz web de Mongo Express desde:

cpp
Copy
Edit
http://4.155.211.247:8081
Autenticación web:

makefile
Copy
Edit
Usuario: admin
Contraseña: pass
Confirmado listado de bases de datos admin, config y local.

Resultados
MongoDB operativo y accesible en la VM del laboratorio.

Mongo Express funcional como herramienta gráfica para administración de MongoDB.

Acceso restringido mediante NSG para mejorar seguridad en el laboratorio.

Próximos pasos
Implementar RedisInsight para Redis con interfaz web en puerto 8001.

Documentar el despliegue de herramientas gráficas para Redis y validar conectividad.

Consolidar documentación para entrega final del laboratorio.

Registro de tarea — Implementación de RedisInsight en contenedor Docker
Objetivo
Implementar la interfaz gráfica RedisInsight en un contenedor Docker dentro de la VM vm-cftec-m62025-SINT646-lab01, para administrar y monitorear la base de datos Redis desplegada previamente.

Procedimiento
1. Preparación
Verificar que Redis está corriendo en el contenedor redis en el puerto 6379.

Confirmar que el puerto 8001 está abierto en el NSG para la IP del cliente:

bash
Copy
Edit
terraform -chdir=terraform state show azurerm_network_security_group.lab_nsg | grep -A5 8001
2. Primer intento con imagen latest
bash
Copy
Edit
docker run -d \
  --name redisinsight \
  -p 8001:8001 \
  --restart unless-stopped \
  redislabs/redisinsight:latest
Problema encontrado:

El contenedor quedaba detenido en:

sql
Copy
Edit
Running docker-entry.sh
El puerto 8001 aparecía abierto, pero al acceder devolvía:

nginx
Copy
Edit
ERR_CONNECTION_REFUSED
curl http://localhost:8001 devolvía Connection reset by peer.

Logs sin información adicional después del arranque.

3. Diagnóstico
Confirmado que no era un problema de firewall/NSG (regla ya habilitada).

Revisado que el contenedor corría (docker ps) pero sin inicializar la UI.

Conclusión: bug en la imagen latest.

4. Solución aplicada
Ejecutar RedisInsight con versión estable 1.14.0:

bash
Copy
Edit
docker run -d \
  --name redisinsight \
  -p 8001:8001 \
  --restart unless-stopped \
  redislabs/redisinsight:1.14.0
Esta versión inicializó correctamente y mostró la UI.

5. Validación de acceso
Acceso exitoso desde el navegador:

cpp
Copy
Edit
http://4.155.211.247:8001
Pantalla inicial solicitando conectar una base de datos Redis.

Verificación de logs:

bash
Copy
Edit
docker logs redisinsight
Mostró inicio correcto del servicio.

Resultado
RedisInsight desplegado correctamente.

Interfaz disponible en http://4.155.211.247:8001.

Lista para configurar conexión al contenedor redis local.

Notas
Para producción, considerar versión 2.x de RedisInsight (requiere ajustes de imagen y compatibilidad).

Mantener el puerto 8001 abierto solo para IP autorizada por seguridad.

RedisInsight 1.x está en End of Life, pero se mantiene en este laboratorio por simplicidad y estabilidad.

Registro de tarea — Implementación de HBase en contenedor Docker
Objetivo
Implementar Apache HBase en contenedor Docker con sus puertos de administración accesibles vía web, permitiendo monitorear el estado de Master y RegionServer.

Procedimiento
1. Preparación
Verificar que Docker esté instalado y corriendo.

Abrir puertos 16010 (Master UI) y 16030 (RegionServer UI) en el NSG para la IP autorizada 190.108.74.42.

2. Implementación
bash
Copy
Edit
docker pull harisekhon/hbase:latest
docker volume create hbase_data

docker run -d \
  --name hbase \
  -p 16000:16000 \
  -p 16010:16010 \
  -p 16020:16020 \
  -p 16030:16030 \
  -p 2181:2181 \
  -v hbase_data:/hbase-data \
  harisekhon/hbase
3. Validación
Master UI: http://4.155.211.247:16010

RegionServer UI: http://4.155.211.247:16030

Logs:

bash
Copy
Edit
docker logs hbase --tail 20
Mostraron inicio exitoso y disponibilidad de servicios.

Resultado
HBase funcionando y accesible vía web.

Puertos seguros, expuestos solo a IP autorizada.

Preparado para pruebas de integración con otras BD del laboratorio.

Registro de tarea — Implementación de Mongo Express en contenedor Docker
Objetivo
Implementar Mongo Express como interfaz web para administrar la base de datos MongoDB ya desplegada en contenedor Docker.

Procedimiento
1. Preparación
Confirmar que MongoDB está en ejecución (docker ps).

Abrir puerto 8081 en el NSG para la IP 190.108.74.42.

2. Implementación
bash
Copy
Edit
docker run -d \
  --name mongo-express \
  -p 8081:8081 \
  -e ME_CONFIG_MONGODB_ADMINUSERNAME=admin \
  -e ME_CONFIG_MONGODB_ADMINPASSWORD=admin123 \
  -e ME_CONFIG_MONGODB_SERVER=mongodb \
  --link mongodb:mongodb \
  mongo-express:latest
Nota: En laboratorio se usó admin / pass para simplificar autenticación.

3. Validación
Acceso web: http://4.155.211.247:8081

Visualización de bases de datos: admin, config, local.

Logs:

bash
Copy
Edit
docker logs mongo-express --tail 20
Mostraron conexión establecida a MongoDB.

Resultado
Interfaz web funcional para gestión de MongoDB.

Puertos y acceso restringidos a IP autorizada.

Configuración válida para fines de laboratorio.

Registro de tarea — Implementación de RedisInsight en contenedor Docker
Objetivo
Implementar RedisInsight para administración gráfica de Redis en contenedor Docker, facilitando visualización y configuración.

Procedimiento
1. Preparación
Confirmar Redis en ejecución (docker ps).

Abrir puerto 8001 en el NSG para la IP 190.108.74.42.

2. Problemas detectados
Imagen latest de RedisInsight no inicializaba correctamente.

Logs mostraban:

sql
Copy
Edit
Running docker-entry.sh
y no continuaba.

curl http://localhost:8001 devolvía Connection reset by peer.

3. Solución aplicada
Usar versión estable 1.14.0:

bash
Copy
Edit
docker run -d \
  --name redisinsight \
  -p 8001:8001 \
  --restart unless-stopped \
  redislabs/redisinsight:1.14.0
4. Validación
Acceso exitoso: http://4.155.211.247:8001

Pantalla inicial solicitando conexión a Redis existente.

Logs mostraron inicio correcto.

Resultado
RedisInsight desplegado y accesible vía web.

Configuración válida para entornos de laboratorio.

Puerto expuesto solo a IP autorizada.