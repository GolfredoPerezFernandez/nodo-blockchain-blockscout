Resumen de Pasos para Desplegar Blockscout con Ganache (y Depuración)

Transferencia Inicial del Proyecto:

Copiamos tu proyecto Blockscout local al servidor 192.168.50.59 en el directorio /home/projects/blockscout-docker usando scp.
Configuración Inicial de Docker Compose y Primer Intento de Arranque:

Navegamos a /home/projects/blockscout-docker/docker-compose.
Ejecutamos docker-compose up -d.
Problema Encontrado: Varios servicios no se iniciaban correctamente, especialmente backend y stats, debido a problemas de conexión con sus respectivas bases de datos (db y stats-db) y entre ellos.
Depuración de la Base de Datos Principal (db para backend):

Síntoma: Logs del backend mostraban errores de conexión a la base de datos db (PostgreSQL).
Verificación: docker logs db mostraba que PostgreSQL se estaba reiniciando o no aceptaba conexiones.
Solución (Iterativa):
Aseguramos que el volumen de datos de db (postgres-data) estuviera limpio para una inicialización fresca si era necesario (aunque no tuvimos que borrarlo explícitamente al final).
Modificamos docker-compose/envs/common-blockscout.env para asegurar que DATABASE_URL apuntara correctamente al servicio db (ej: postgresql://postgres:postgres@db:5432/blockscout_db).
Reiniciamos los servicios docker-compose up -d --build backend db.
Resultado: El servicio db se estabilizó y el backend pudo conectarse a él.
Depuración del Servicio ganache:

Síntoma: El backend no podía conectarse a ganache:8545.
Verificación: docker logs ganache mostraba que Ganache se estaba ejecutando y escuchando.
Solución:
Confirmamos que la variable de entorno ETHEREUM_JSONRPC_HTTP_URL en docker-compose/envs/common-blockscout.env estuviera configurada como http://ganache:8545.
Aseguramos que el servicio ganache estuviera en la misma red Docker que backend (lo cual es por defecto con Docker Compose).
Resultado: El backend pudo establecer conexión con ganache.
Depuración de la Base de Datos de Estadísticas (stats-db para stats):

Síntoma: Logs del servicio stats indicaban incapacidad para conectarse a stats-db.
Verificación: docker logs stats-db mostraba problemas similares a los de db inicialmente.
Solución:
Modificamos docker-compose/envs/common-stats.env para que DATABASE_URL apuntara correctamente a stats-db (ej: postgresql://postgres:postgres@stats-db:5432/stats_db).
Reiniciamos docker-compose up -d --build stats stats-db.
Resultado: El servicio stats-db se estabilizó y stats pudo conectarse.
Depuración de la Conexión proxy (Nginx) a stats:

Síntoma: La interfaz web no cargaba o el proxy tenía errores. docker logs proxy mostraba host not found in upstream "stats".
Causa: El servicio stats no estaba completamente operativo debido a sus problemas con stats-db, por lo que Nginx no podía resolverlo.
Solución: Una vez que stats-db y stats funcionaron (paso 5), este problema se resolvió automáticamente.
Resultado: El proxy pudo iniciarse correctamente y conectarse a los servicios backend.
Configuración del Frontend para WebSockets y API Host:

Síntoma: La interfaz de Blockscout en http://192.168.50.59 cargaba, pero no mostraba datos de bloques/transacciones. La consola del navegador mostraba errores de WebSocket: WebSocket connection to 'ws://localhost/socket/v2/websocket?vsn=2.0.0' failed.
Causa: El frontend estaba configurado para buscar el backend (para API y WebSockets) en localhost, pero desde el navegador del cliente, localhost es la máquina del cliente, no el servidor.
Solución:
Modificamos docker-compose/envs/common-frontend.env.
Cambiamos NEXT_PUBLIC_API_HOST=localhost a NEXT_PUBLIC_API_HOST=192.168.50.59.
Cambiamos NEXT_PUBLIC_APP_HOST=localhost a NEXT_PUBLIC_APP_HOST=192.168.50.59.
Reconstruimos y reiniciamos el servicio frontend: docker-compose up -d --no-deps --build frontend.
Resultado: El frontend pudo conectarse correctamente al backend en 192.168.50.59 para las API y los WebSockets.
Verificación Final:

Realizamos transacciones en Ganache usando MetaMask (conectado a http://192.168.50.59:8545).
Observamos los logs de ganache para confirmar la minería de nuevos bloques.
Observamos los logs del backend para confirmar la indexación de estos nuevos bloques y transacciones (específicamente, los mensajes de tx/per day chart mostrando min/max block numbers [0, 3] y num of transactions 3).
Refrescamos la interfaz de Blockscout en http://192.168.50.59 y confirmamos que los bloques y transacciones se mostraban.
Comandos Clave de Docker Compose Utilizados:

docker-compose up -d: Para iniciar/reiniciar todos los servicios.
docker-compose up -d --build <service_name>: Para reconstruir y reiniciar un servicio específico.
docker-compose up -d --no-deps --build <service_name>: Para reconstruir y reiniciar un servicio específico sin afectar/reiniciar sus dependencias.
docker-compose down: Para detener y eliminar los contenedores.
docker-compose logs <service_name>: Para ver los logs de un servicio.
docker-compose logs -f <service_name>: Para seguir los logs de un servicio en tiempo real. 

pasos para despliegue ahora: 

Guía de Despliegue de Blockscout con Ganache (Configuración Optimizada)

Prerrequisitos:

Servidor con Docker y Docker Compose instalados.
Proyecto Blockscout clonado o copiado en el servidor (ej. en /home/projects/blockscout-docker).
Archivos de entorno (.env) correctamente configurados (ver "Puntos Clave de Configuración" más abajo).
Pasos de Despliegue:

Navegar al Directorio de Docker Compose:
En la terminal de tu servidor, ve al directorio que contiene tu archivo docker-compose.yml:

cd /home/projects/blockscout-docker/docker-compose

bash


(Opcional pero Recomendado) Limpiar Despliegues Anteriores:
Si tienes contenedores de un despliegue anterior de este proyecto, es buena idea detenerlos y eliminarlos para asegurar un inicio limpio. Precaución: Esto eliminará los datos de los volúmenes si no están configurados para persistir externamente o si los volúmenes son anónimos.

docker-compose down -v 

bash


(La opción -v también elimina los volúmenes anónimos asociados). Si quieres preservar los datos de la base de datos, omite -v o asegúrate de que tus volúmenes estén nombrados y no se eliminen con down.

Construir las Imágenes (si es necesario) e Iniciar los Servicios:
Este comando construirá las imágenes si no existen localmente (o si se especifica --build) y luego iniciará todos los servicios definidos en tu docker-compose.yml en segundo plano (-d).

docker-compose up -d --build

bash


--build: Fuerza la reconstrucción de las imágenes. Es útil si has hecho cambios en los Dockerfiles o en archivos copiados durante la construcción de la imagen (como los archivos .env si se usan en tiempo de construcción, aunque para NEXT_PUBLIC_ se leen en tiempo de ejecución).
Monitorear el Arranque de los Servicios (Opcional pero Recomendado):
Abre varias terminales o usa tmux para ver los logs de los servicios clave mientras arrancan. Esto te ayudará a identificar problemas rápidamente.

Base de datos principal: docker-compose logs -f db
Nodo Ganache: docker-compose logs -f ganache
Backend de Blockscout: docker-compose logs -f backend
Base de datos de estadísticas: docker-compose logs -f stats-db
Servicio de estadísticas: docker-compose logs -f stats
Frontend: docker-compose logs -f frontend
Proxy (Nginx): docker-compose logs -f proxy
Espera a que las bases de datos se inicialicen completamente y que los servicios backend y stats indiquen que se han conectado a sus respectivas bases de datos y a Ganache.

Verificar la Aplicación:

Una vez que los logs indiquen que los servicios principales están en funcionamiento (especialmente proxy, frontend, backend, ganache, stats), abre tu navegador web y accede a Blockscout usando la IP de tu servidor: http://TU_IP_DE_SERVIDOR (ej. http://192.168.50.59)
Realiza una transacción en tu nodo Ganache (usando MetaMask configurado para apuntar a http://TU_IP_DE_SERVIDOR:8545) para generar datos.
Verifica que los nuevos bloques y transacciones aparezcan en la interfaz de Blockscout.
Puntos Clave de Configuración (Asegúrate de que estén así en tus archivos):

docker-compose/envs/common-blockscout.env:

DATABASE_URL=postgresql://postgres:postgres@db:5432/blockscout_db (o los usuarios/contraseñas que hayas definido)
ETHEREUM_JSONRPC_HTTP_URL=http://ganache:8545
INDEXER_DISABLE_EMPTY_BLOCKS_SANITIZER=false (o true si prefieres deshabilitarlo temporalmente durante la indexación inicial de una cadena grande)
docker-compose/envs/common-stats.env:

DATABASE_URL=postgresql://postgres:postgres@stats-db:5432/stats_db (o los usuarios/contraseñas que hayas definido)
BLOCKSCOUT_INSTANCE_URL=http://backend:4000
docker-compose/envs/common-frontend.env:

NEXT_PUBLIC_API_HOST=TU_IP_DE_SERVIDOR (ej. 192.168.50.59)
NEXT_PUBLIC_APP_HOST=TU_IP_DE_SERVIDOR (ej. 192.168.50.59)
NEXT_PUBLIC_API_PROTOCOL=http
NEXT_PUBLIC_APP_PROTOCOL=http
NEXT_PUBLIC_API_WEBSOCKET_PROTOCOL=ws
NEXT_PUBLIC_NETWORK_ID=1337 (o el Chain ID de tu Ganache)
Otras variables NEXT_PUBLIC_NETWORK_* según tu preferencia.
docker-compose/docker-compose.yml (y archivos de servicios como services/backend.yml, etc.):

Asegúrate de que los env_file apunten a los archivos .env correctos.
Verifica que los nombres de servicio coincidan con los usados en las URLs (ej. db, ganache, stats-db, backend).
Siguiendo estos pasos con los archivos ya configurados correctamente, el despliegue debería ser mucho más directo.
