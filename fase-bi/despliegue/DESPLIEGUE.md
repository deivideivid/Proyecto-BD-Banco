# Despliegue del aplicativo

**Encargado:** Jerónimo Soto.

Aquí vamos a decidir dónde publicar el aplicativo para que el profesor y cualquiera del grupo
lo pueda abrir, también desde el celular. La primera idea es Replit, pero queremos comparar
antes de decidir.

## Lo que tenemos que tener en cuenta

- **La base pesa cerca de 560 MB** con el millón de transacciones. En G0 ya vimos que eso
  supera el plan gratis de Supabase (500 MB).
- **El aplicativo tiene un servidor en Python** que se conecta a PostgreSQL. No es una página
  suelta: el lugar donde lo publiquemos tiene que correr Python y llegar a la base.
- **Los datos son 100 % sintéticos**, así que no hay problema de privacidad si se publica.
- **Nunca subimos contraseñas** al repositorio: van como variables de entorno del servicio.

## Opciones que vamos a comparar

| Opción | Cómo sería | Lo que hay que averiguar |
|---|---|---|
| Replit | Servidor Python en Replit y la base en el PostgreSQL que ofrece Replit | Si el plan que tenemos aguanta el tamaño de la base y si el enlace queda siempre encendido |
| Render o Railway | Servidor Python en el servicio y la base en su PostgreSQL | Límites del plan gratis y si se apaga cuando nadie lo usa |
| Base reducida en la nube | Publicamos con una muestra de los datos (por ejemplo 1 de cada 10 transacciones) y dejamos la base completa en local | Si al profesor le sirve ver la muestra en línea y la base completa en la sustentación |
| Solo local en la sustentación | Corremos todo en el computador de Juan Diego y lo mostramos desde ahí | Si el profesor exige un enlace público |

## Qué tenemos que decidir

- [ ] Dónde va el servidor del aplicativo.
- [ ] Dónde va la base (completa o reducida).
- [ ] Si el enlace tiene que quedar encendido todo el tiempo o solo el día de la sustentación.
- [ ] Quién tiene las credenciales del servicio.

## Lo que decidimos

(Lo llenamos cuando Jerónimo traiga la comparación.)
