# Manual de usuario

Sistema de Biblioteca

Este manual explica cómo usar el sistema. Tiene dos partes: la de **clientes** (quienes piden libros) y la de **bibliotecarios** (quienes administran la biblioteca). Al inicio hay una sección común sobre cómo entrar.

## Contenido

1. [Cómo entrar al sistema](#1-cómo-entrar-al-sistema)
2. [Guía del cliente](#2-guía-del-cliente)
3. [Guía del bibliotecario](#3-guía-del-bibliotecario)
4. [Reglas del sistema](#4-reglas-del-sistema)
5. [Mensajes que puedes encontrar](#5-mensajes-que-puedes-encontrar)
6. [Preguntas frecuentes](#6-preguntas-frecuentes)
7. [Glosario](#7-glosario)

---

## 1. Cómo entrar al sistema

![Inicio de sesión](capturas/login.png)

1. Abre la dirección del sistema en tu navegador (si lo estás probando en tu computadora, es `http://127.0.0.1:5000`).
2. En **Correo o usuario** escribe:
   - Si eres **cliente**: tu correo electrónico.
   - Si eres **bibliotecario**: tu nombre de usuario.
3. En **Contraseña** escribe tu contraseña y presiona **Iniciar sesión**.

Según tu rol, llegas a una pantalla distinta:

| Rol | Pantalla inicial |
| --- | --- |
| Cliente | **Mis libros** |
| Bibliotecario | **Panel** |

### Si te equivocas de contraseña

El sistema te avisa con *"El usuario o la contraseña no son correctos"*. No dice cuál de las dos falló, a propósito, para proteger las cuentas.

Después de **5 intentos fallidos seguidos**, la cuenta se **bloquea durante 15 minutos**, aunque escribas bien la contraseña. Puedes esperar ese tiempo, o pedirle al bibliotecario que te restablezca la contraseña, lo que también desbloquea la cuenta.

Si tu cuenta está desactivada, verás *"Tu cuenta está desactivada. Contacta al bibliotecario."*

### Tu sesión

- La sesión dura **8 horas**. Pasado ese tiempo, el sistema te pide entrar de nuevo.
- Abajo del menú lateral aparecen tu nombre y tu rol. Ahí mismo están **Cambiar contraseña** y **Cerrar sesión**.
- Si usas un computador compartido, cierra siempre la sesión al terminar.

### Cambiar tu contraseña

1. En el menú lateral, haz clic en **Cambiar contraseña**.
2. Escribe tu contraseña actual, la nueva, y la nueva otra vez para confirmarla.
3. Presiona **Guardar contraseña**.

La contraseña nueva debe tener **al menos 8 caracteres, con letras y números**.

Ninguna persona puede ver tu contraseña, ni siquiera el bibliotecario. Si la olvidas, el bibliotecario puede darte una **contraseña temporal**, y luego tú la cambias por una tuya.

---

## 2. Guía del cliente

El menú lateral tiene cinco secciones: **Catálogo**, **Mis libros**, **Mis solicitudes**, **Mis multas** y **Mi perfil**.

### 2.1 Catálogo: buscar libros y solicitarlos

![Catálogo](capturas/catalogo.png)

El catálogo muestra todos los libros de la biblioteca. Arriba a la derecha hay un **buscador**: escribe parte de un título, un autor o una categoría y la tabla se filtra mientras escribes. No importan las mayúsculas ni las tildes.

La última columna muestra la **disponibilidad**. Cada copia física del libro es un pequeño lomo:

| Lo que ves | Significa |
| --- | --- |
| Lomo **verde** | Copia disponible para prestar |
| Lomo **gris** | Copia no disponible (prestada, en reparación o perdida) |
| **"2 de 3"** | Hay 2 copias disponibles de 3 que tiene la biblioteca |
| **"Agotado"** | Hay copias, pero ninguna disponible ahora |
| **"Sin copias"** | La biblioteca todavía no tiene copias de este libro |

**Cómo solicitar un libro**

1. Busca el libro. Si tiene copias disponibles, verás el botón **Solicitar** en su fila.
2. Presiona **Solicitar**. El sistema te lleva a **Mis solicitudes** con el aviso *"Solicitud enviada. El bibliotecario la revisará."*
3. En el catálogo, ese libro pasa a mostrar **"Solicitud enviada"**.

Solicitar un libro **no lo aparta**: si otra persona lo pide antes y se acaban las copias, la solicitud no se podrá aprobar.

### 2.2 Mis solicitudes

Aquí ves todas las solicitudes que has hecho, con su estado:

| Estado | Qué significa |
| --- | --- |
| **En revisión** | El bibliotecario todavía no la ha revisado. Puedes cancelarla con **Cancelar solicitud**. |
| **Aprobada** | Ya quedó registrado el préstamo a tu nombre. Pasa por la biblioteca a recoger el libro. |
| **Rechazada** | El bibliotecario no la aprobó. Debajo verás el **motivo**. |
| **Cancelada** | La cancelaste tú. |

Puedes tener **hasta 3 solicitudes pendientes** a la vez. La parte de arriba te dice cuántas llevas (por ejemplo, *"Tienes 2 de 3 solicitudes pendientes de revisión"*).

### 2.3 Mis libros

![Mis libros](capturas/cliente-mis-libros.png)

Es tu pantalla principal. Muestra:

- Un resumen: cuántos libros tienes prestados y cuántos están con retraso.
- **Avisos en rojo** si tienes libros vencidos o multas pendientes.
- Una franja con tus cifras: préstamos en total, activos ahora, vencidos y devoluciones tardías.
- **Libros que tengo ahora**: cada libro con el código de su copia, cuándo se prestó, cuándo vence y su estado (*Al día* o *Vencido, N días de retraso*).
- **Mi historial**: todos los libros que has usado, con su estado y la multa, si la hubo.

El plazo de préstamo es de **14 días**. Los libros se devuelven en la biblioteca, con el bibliotecario.

### 2.4 Mis multas

Si devuelves un libro **después de su fecha de vencimiento**, el sistema genera una multa automáticamente. En esta pantalla ves cada multa con los días de retraso, el monto, la fecha en que se generó y su estado (*Pendiente* o *Pagada el ...*).

- La multa es de **₡100 por cada día de retraso** (el valor exacto aparece al pie de la pantalla).
- Para **pagarla**, acércate al mostrador de la biblioteca: solo el bibliotecario registra pagos.
- **Mientras tengas multas pendientes, no puedes solicitar libros nuevos.**

### 2.5 Mi perfil

Muestra tus datos: nombre, correo (que es también tu nombre de acceso), teléfono y dirección. Desde aquí puedes ir a **Cambiar contraseña**.

No puedes editar tus datos por tu cuenta. Si algo cambió, pídele al bibliotecario que lo actualice.

### 2.6 Si algo no funciona

| Situación | Qué hacer |
| --- | --- |
| No veo el botón Solicitar en un libro | El libro está agotado, o ya lo solicitaste ("Solicitud enviada") |
| Me dice que tengo multas pendientes | Revisa **Mis multas** y paga en el mostrador |
| Me dice que ya tengo el libro | Ya lo tienes prestado. Aparece en **Mis libros** |
| Llegué al máximo de solicitudes | Espera a que revisen las pendientes, o cancela alguna |
| Olvidé mi contraseña | Pídele al bibliotecario que la restablezca |

---

## 3. Guía del bibliotecario

El menú lateral tiene: **Panel**, **Catálogo**, **Préstamos**, **Vencidos**, **Multas**, **Usuarios**, **Nuevo préstamo**, **Solicitudes** y **Auditoría**.

El número dorado que aparece junto a **Solicitudes** indica cuántas están esperando tu revisión.

### 3.1 Panel

![Panel](capturas/panel.png)

Es la pantalla de inicio. Muestra la situación de la biblioteca de un vistazo:

- **Cinco cifras:** préstamos activos, vencidos, copias disponibles (por ejemplo, *16 de 24*), monto en multas pendientes y el porcentaje de devoluciones a tiempo.
- **Un aviso** cuando hay solicitudes pendientes de revisión.
- **Requieren atención:** los préstamos vencidos hace más tiempo.
- **Usuarios con más retrasos:** cada nombre lleva a su perfil.
- **Préstamos por mes:** un gráfico de los últimos 12 meses. La barra dorada es el mes actual, que sigue en curso.
- **Libros más prestados** (los empates comparten posición) y **préstamos por categoría**.
- **Actividad reciente:** los últimos cambios del sistema.

### 3.2 Catálogo: libros, autores, categorías y copias

En el **Catálogo** haces clic en el título de cualquier libro para abrir su ficha.

**Crear un libro**

1. En el Catálogo, presiona **Nuevo libro**.
2. Completa el formulario:
   - **Título** y **ISBN** (10 o 13 dígitos; puedes escribir guiones). El mismo ISBN no se puede registrar dos veces.
   - **Año de publicación** (opcional).
   - **Categoría**.
   - **Autores**: marca las casillas de uno o varios autores. El libro debe tener al menos uno.
   - **Copias iniciales**: cuántas copias físicas llegaron (de 0 a 50).
3. Presiona **Crear libro**. Cada copia recibe automáticamente su código de barras (por ejemplo, BIB-0025).

> **Consejo:** si falta un autor o una categoría, hay enlaces debajo de cada campo para agregarlos. Al guardar, vuelves al formulario **en blanco**, así que conviene crear primero el autor o la categoría y después el libro.

**La ficha de un libro**

![Ficha de un libro](capturas/libro.png)

- **Editar libro** cambia el título, ISBN, año, categoría y autores.
- **Agregar copias**: escribe la cantidad (1 a 50) y presiona **Agregar**. Los códigos continúan la numeración.
- La tabla de **copias** muestra el código, el estado (*Disponible*, *Prestado a ...*, *En reparación*, *Perdido*) y cuántas veces se ha prestado.
- Para **cambiar el estado de una copia**, elige el nuevo estado, escribe el **motivo** (obligatorio) y presiona **Cambiar**. Sirve para marcar una copia como en reparación o perdida, o volver a dejarla disponible.
- Una copia **prestada** no se puede modificar hasta que se devuelva.

### 3.3 Registrar un préstamo

1. En el menú, entra a **Nuevo préstamo** (o presiona el botón del Panel).
2. Elige el **Usuario**. Solo aparecen los usuarios activos.
3. Elige el **Ejemplar**. Solo aparecen las copias disponibles.
4. Presiona **Registrar préstamo**.

El préstamo vence a los **14 días**. El sistema rechaza el préstamo, con un aviso claro, si el usuario está inactivo, si tiene multas pendientes o si la copia ya no está disponible.

### 3.4 Préstamos y devoluciones

**Préstamos** lista todos los préstamos activos, con los más urgentes arriba. **Vencidos** muestra solo los que ya pasaron su fecha. En ambas hay un buscador por libro, usuario o código. El nombre de cada usuario lleva a su perfil.

**Registrar una devolución**

1. Busca el préstamo y presiona **Registrar devolución** en su fila.
2. El sistema avisa el resultado. Si el libro llegó tarde, el aviso indica los días de retraso y **la multa generada**, por ejemplo: *"Devolución registrada con 16 días de retraso. Se generó una multa de ₡1 600."*

La copia queda otra vez disponible automáticamente.

**Corregir un préstamo**

Si un préstamo se registró a la persona equivocada, o con otra copia, presiona **Corregir** en su fila.

1. Elige el usuario y/o el ejemplar correctos.
2. Escribe el **motivo** de la corrección (obligatorio).
3. Presiona **Guardar corrección**.

Las fechas del préstamo **no cambian**. La copia equivocada vuelve a quedar disponible y la correcta pasa a prestada. Se aplican las mismas reglas que al prestar: el nuevo usuario debe estar activo y sin multas, y la nueva copia debe estar disponible. Solo se pueden corregir préstamos **activos**: uno ya devuelto no se corrige.

### 3.5 Multas

La pantalla **Multas** lista todas las multas, con las pendientes primero, y suma cuánto se debe en total.

- **Registrar pago:** presiona el botón en la fila de la multa cuando la persona pague. La multa pasa a *Pagada* con la fecha del día.
- **Anular pago:** si un pago se registró por error, presiona **Anular pago** en esa fila, escribe el **motivo** y confirma. La multa vuelve a estar pendiente y la persona vuelve a quedar bloqueada para pedir libros.

### 3.6 Usuarios

![Perfil de un usuario](capturas/perfil-usuario.png)

**Usuarios** lista a todas las personas registradas, con su ubicación, cuántos préstamos han hecho, **qué libros tienen ahora**, sus multas y su estado. El buscador encuentra por nombre, correo, lugar o incluso por **libro**: escribe *Rayuela* y verás quién lo tiene.

**Crear un usuario**

1. Presiona **Nuevo usuario**.
2. Completa nombre, apellido y correo. El teléfono (8 dígitos) y la dirección (provincia, cantón, distrito y señas) son opcionales.
3. Presiona **Crear usuario**.

Al crearlo, el sistema genera también su cuenta y te muestra una **contraseña temporal** en un aviso verde. **Se muestra una sola vez**: anótala y entrégasela a la persona, que después puede cambiarla desde **Cambiar contraseña**. El correo será su nombre de acceso.

**El perfil de un usuario**

Haz clic en un nombre para abrir su perfil. Muestra:

- Una franja de cifras: préstamos en total, activos, vencidos, devoluciones tardías y monto en multas.
- **Libros que tiene ahora**, con los botones **Corregir** y **Registrar devolución**.
- **Datos**: correo, teléfono, dirección y el estado de su cuenta (activa, bloqueada o desactivada).
- **Historial de libros**: todos los libros que ha usado, con fechas, estado y multa.

**Editar un usuario**

Presiona **Editar datos** en su perfil. Puedes cambiar cualquier dato, incluido el estado con la casilla **Usuario activo**. Ten en cuenta que:

- No se puede **desactivar** a alguien que tiene préstamos activos: primero hay que registrar sus devoluciones.
- Los usuarios **nunca se borran**, solo se desactivan, para conservar su historial.
- Si cambias el correo, cambia también su nombre de acceso.

**Restablecer una contraseña**

Si alguien olvidó su contraseña, presiona **Restablecer contraseña** en su perfil y confirma. El sistema genera una **contraseña temporal nueva**, que se muestra **una sola vez**. Esto también **desbloquea** la cuenta si estaba bloqueada por intentos fallidos. Tú nunca ves la contraseña anterior, y nadie puede verla.

### 3.7 Solicitudes de los clientes

![Solicitudes](capturas/solicitudes.png)

**Solicitudes** lista lo que los clientes piden, con las pendientes primero (las más antiguas arriba). Cada fila muestra a la persona, el libro, cuándo lo pidió y cuántas copias disponibles tiene hoy.

- **Aprobar:** el sistema toma la primera copia disponible y **registra el préstamo** con todas las reglas de siempre. El aviso te dice qué copia entregar y a quién, por ejemplo: *"Solicitud aprobada. Se registró el préstamo de "Rayuela" (BIB-0010): entrégalo a Sofía Jiménez."*
- **Rechazar:** escribe el **motivo** (obligatorio) y presiona **Rechazar**. La persona lo verá en su pantalla.
- Si el libro ya **no tiene copias disponibles**, solo aparece **Rechazar**.

Las solicitudes resueltas quedan abajo, con quién las resolvió.

### 3.8 Auditoría

![Auditoría](capturas/auditoria.png)

**Auditoría** es el historial de todo lo que se ha hecho en el sistema. Cada fila dice:

- **Fecha y hora** (en hora de Costa Rica).
- **Evento**: por ejemplo, *Préstamo registrado*, *Multa pagada*, *Libro creado* o *Solicitud aprobada*. Las correcciones, los pagos anulados y los usuarios desactivados aparecen en rojo para que se noten.
- **Responsable**: la cuenta que hizo el cambio (cliente o bibliotecario).
- **Afecta a**: la persona y el libro involucrados.
- **Qué cambió**: por ejemplo, *"Usuario: Valeria Rojas → Lucía Hernández"*.
- **Motivo**: el que se escribió al corregir o rechazar.

Puedes filtrar por **tipo de evento** y usar el buscador. Se muestran los últimos 300 cambios. **El historial no se puede modificar ni borrar**, ni siquiera por un administrador.

---

## 4. Reglas del sistema

| Tema | Regla |
| --- | --- |
| Plazo de préstamo | 14 días |
| Multa | ₡100 por cada día de retraso, que se genera al devolver el libro |
| Multas pendientes | La persona no puede pedir ni solicitar libros hasta pagarlas |
| Solicitudes | Máximo 3 pendientes por persona, sin repetir libro, y solo de libros con copias disponibles |
| Contraseñas | Mínimo 8 caracteres, con letras y números. Se guardan cifradas y nadie puede verlas |
| Bloqueo de cuenta | 5 intentos fallidos bloquean la cuenta 15 minutos |
| Sesión | Dura 8 horas |
| Usuarios | No se borran, se desactivan. No se puede desactivar a quien tiene préstamos activos |
| Copias | Una copia prestada no se puede modificar hasta devolverla. El estado "prestado" nunca se pone a mano |
| Correcciones | Siempre exigen un motivo y quedan en la auditoría |
| ISBN | 10 o 13 dígitos, sin repetirse aunque se escriba con o sin guiones |
| Teléfono | 8 dígitos (se guarda como 8812-3456) |
| Historial | No se puede modificar ni borrar |

---

## 5. Mensajes que puedes encontrar

### Al iniciar sesión

| Mensaje | Qué significa |
| --- | --- |
| El usuario o la contraseña no son correctos | Algún dato está mal escrito |
| Demasiados intentos fallidos. Intenta de nuevo en N minutos | La cuenta está bloqueada temporalmente |
| Tu cuenta está desactivada. Contacta al bibliotecario | La cuenta o el usuario están inactivos |

### Al pedir o solicitar libros

| Mensaje | Qué significa | Qué hacer |
| --- | --- | --- |
| El usuario N tiene multas pendientes de pago | La persona debe una multa | Registrar el pago primero |
| Tienes multas pendientes de pago. Págalas para poder solicitar libros | Es lo mismo, visto por el cliente | Pagar en el mostrador |
| El usuario N está inactivo y no puede pedir libros | Usuario desactivado | Reactivarlo desde **Editar datos** |
| El ejemplar N no está disponible | Ya está prestado, en reparación o perdido | Elegir otra copia |
| No hay copias disponibles de este libro por ahora | Todas las copias están en uso | Esperar una devolución |
| Ya tienes prestado este libro | La persona ya tiene una copia | No se necesita hacer nada |
| Ya enviaste una solicitud para este libro | Ya hay una pendiente | Esperar la respuesta |
| Ya tienes 3 solicitudes pendientes | Alcanzó el máximo | Cancelar alguna o esperar |

### Al aprobar o rechazar solicitudes

| Mensaje | Qué significa |
| --- | --- |
| No hay copias disponibles de este libro. Puedes rechazar la solicitud o esperar una devolución | Se acabaron las copias desde que se solicitó |
| La solicitud ya fue resuelta | Otra persona ya la aprobó o rechazó |
| Indica el motivo del rechazo | El motivo es obligatorio |

### Al corregir o cambiar estados

| Mensaje | Qué significa |
| --- | --- |
| Indica el motivo de la corrección / del cambio de estado / para anular el pago | El motivo es obligatorio |
| No hay nada que corregir: el usuario y el ejemplar son los mismos | No se cambió ningún dato |
| El préstamo N ya fue devuelto y no se puede corregir | Solo se corrigen préstamos activos |
| El ejemplar está prestado. Registra primero la devolución | No se puede cambiar el estado de una copia prestada |
| La multa N no está pagada, no hay un pago que anular | Esa multa sigue pendiente |

### Al guardar datos

| Mensaje | Qué significa |
| --- | --- |
| El ISBN debe tener 10 o 13 dígitos | Revisa el ISBN |
| Ya existe un libro con el ISBN ... | Ese libro ya está registrado |
| Elige al menos un autor / una categoría válida | Faltan datos obligatorios |
| Ya existe un usuario con el correo ... | El correo se repite (sin importar las mayúsculas) |
| El teléfono debe tener 8 dígitos | Escribe por ejemplo 8812-3456 |
| El usuario tiene N préstamo(s) activo(s). Registra las devoluciones antes de desactivarlo | No se puede desactivar aún |
| La contraseña debe tener al menos 8 caracteres / una letra y un número | Elige una contraseña más segura |

### Páginas de error

| Pantalla | Qué significa |
| --- | --- |
| **Sin permiso** | Tu cuenta no puede ver esa página. Por ejemplo, un cliente intentó abrir una pantalla del bibliotecario |
| **Solicitud no válida** | La página caducó. Vuelve a cargarla e inténtalo de nuevo |
| **Página no encontrada** | La dirección no existe |

---

## 6. Preguntas frecuentes

**¿Puedo ver la contraseña de otra persona?**
No. Las contraseñas se guardan cifradas y nadie puede leerlas, ni el bibliotecario. Solo se pueden restablecer.

**¿Cuándo se genera una multa?**
Al **registrar la devolución** de un libro que llegó después de su fecha de vencimiento. Mientras el libro siga sin devolverse, el retraso se ve como "vencido", pero todavía no hay multa.

**¿Se puede deshacer una devolución?**
No desde la pantalla. Las correcciones solo aplican a préstamos activos. Si una devolución se registró por error, hay que pedirle a quien administra la base de datos que la revise.

**¿Qué pasa con las solicitudes si se acaban las copias?**
Siguen pendientes, pero no se pueden aprobar. El bibliotecario puede rechazarlas con un motivo o esperar una devolución.

**¿Por qué el catálogo muestra un libro "Agotado" si la biblioteca lo tiene?**
Porque todas sus copias están prestadas, en reparación o perdidas. En cuanto se devuelva una, vuelve a estar disponible.

**¿Cómo agrego a otro bibliotecario?**
La aplicación no tiene una pantalla para eso. Se hace con una instrucción SQL; está explicada en el [Manual técnico](MANUAL_TECNICO.md#9-mantenimiento-y-operación).

**¿Puedo entrar desde el celular?**
La interfaz se adapta a pantallas pequeñas. En ese caso, el menú lateral pasa a la parte de arriba.

---

## 7. Glosario

| Término | Significado |
| --- | --- |
| **Libro** | La obra (por ejemplo, *Rayuela*), con su ISBN, título y autores |
| **Ejemplar o copia** | Cada copia física de un libro, con su propio código de barras |
| **Préstamo activo** | Un libro que está en manos de una persona y no se ha devuelto |
| **Vencido** | Un préstamo activo que ya pasó su fecha de devolución |
| **Multa** | Cobro por devolver un libro tarde |
| **Solicitud** | El pedido de un cliente para que se le preste un libro, pendiente de aprobación |
| **Cuenta** | El acceso de una persona al sistema (correo o usuario y contraseña) |
| **Auditoría** | El historial que registra quién hizo cada cambio, cuándo y por qué |
| **Contraseña temporal** | La que genera el sistema al crear un usuario o restablecer su clave; se cambia después |
