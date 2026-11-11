# Registro de horas

Control de horas interno para el equipo: cronómetro, proyectos, clientes, etiquetas,
calendario, panel e informes. **Todos los miembros ven las horas de los demás**; cada
persona edita solo las suyas y un administrador gestiona el equipo.

Web estática (un solo `index.html`) + [Supabase](https://supabase.com) (base de datos y login)
+ [Vercel](https://vercel.com) (alojamiento). No hay servidor propio que mantener.

## Puesta en marcha (≈15 min)

### 1. Supabase
1. Crea un proyecto en Supabase (plan gratuito).
2. Abre `supabase/schema.sql`, **cambia `TU-CORREO@EJEMPLO.COM` por tu correo** (será el primer admin) y pégalo en **SQL Editor → New query → Run**.
3. **Authentication → Sign In / Providers → Email**: deja el correo activado. Recomendado desactivar *Confirm email*
   (solo pueden registrarse correos que tú invitas; el correo integrado de Supabase tiene un límite muy bajo de envíos por hora).
4. **Project Settings → API**: copia *Project URL* y la clave *anon public*.
5. Pégalas en `config.js`.
6. (Después del paso de Vercel) **Authentication → URL Configuration**: pon la URL de tu web en *Site URL*
   (necesario para el enlace de "He olvidado la contraseña").

### 2. GitHub + Vercel
1. Sube este repo a GitHub (**privado**).
2. En Vercel: *Add New → Project → importa el repo*. No hay build: *Framework Preset: Other*, deja todo por defecto → *Deploy*.
3. Vercel te da una dirección tipo `registro-horas.vercel.app`. Cada `git push` a `main` la actualiza sola.

### 3. Primer uso
1. Abre la web → **Crear cuenta** con el correo del admin.
2. **Equipo → + Invitar**: añade el correo de cada persona y pásales el enlace. Ellas pulsan *Crear cuenta* con ese correo.
3. (Opcional) **Ajustes → Importar desde Clockify** para traer tu histórico.

## Cómo funciona la seguridad
- Solo pueden crear cuenta los correos de la tabla `allowed_emails` (lo comprueba la base de datos, no la web).
- Reglas RLS en todas las tablas: solo usuarios activos leen; cada persona escribe sus horas; solo el admin borra
  proyectos/clientes/etiquetas, cambia roles y ajustes.
- La web lleva `noindex` (meta + cabecera + `robots.txt`) para que no aparezca en buscadores. No la enlaces desde ninguna web pública.
- La clave `anon` en `config.js` es pública por diseño. **Nunca uses la `service_role` aquí.**

## Notas
- Los datos se refrescan solos cada minuto y al volver a la pestaña (no es tiempo real instantáneo).
- Se cargan todas las horas del equipo al entrar. Con equipos pequeños no hay problema; si algún día hay
  años de datos, habrá que filtrar por fechas.
- Para quitar a alguien: **Equipo → desactivar acceso** (sus horas se conservan).
