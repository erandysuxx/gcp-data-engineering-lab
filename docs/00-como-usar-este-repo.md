# 00 · Cómo usar este repo

> Lee esto primero. Explica en qué orden avanzar, cómo trabajar con tu Claude, cuánto cuesta y cómo no dejar nada cobrando.

## La idea

El laboratorio arma **un solo pipeline realista**, de punta a punta:
- recibe el feed diario de ventas de retailers (sell-out);
- lo valida;
- lo modela en estrella;
- lo orquesta;
- lo despliega con CI/CD.

Cada tecnología aparece cuando el pipeline la **necesita**, no como un tutorial suelto. Así, en la entrevista puedes explicar *por qué* está cada pieza y qué alternativa descartaste.

## Orden recomendado

1. Lee [`01-el-rol`](01-el-rol.md) (30 min): qué se espera de ti y qué **no** necesitas estudiar.
2. Haz los labs en orden, del [`lab00`](../labs/lab00-setup) al [`lab07`](../labs/lab07-cicd-terraform). Antes de cada lab, lee su doc en `docs/`, que viene enlazado arriba en cada README.
3. Después de cada lab:
   - pide a tu Claude el quiz;
   - completa `PROGRESO.md`;
   - repasa la sección "Cuándo sí / cuándo no" del doc.
4. Al final, repasa [`11-guia-de-decisiones`](11-guia-de-decisiones.md) y practica [`interview/`](interview) **en voz alta y en inglés**.

Ritmo sugerido: unas 25–30 h en total, por ejemplo 2 semanas a 2–3 h por día.

## Trabajar con tu Claude

El `CLAUDE.md` de la raíz convierte a Claude en tu tutor. Algunas formas de pedirle:
- *"Vamos con el lab02, paso 6. Explícame qué vamos a medir antes de correrlo."*
- *"No me des la respuesta: dame una pista para escribir el MERGE."*
- *"Hazme el quiz del lab05. La última pregunta en inglés."*
- *"¿Por qué aquí Dataflow y no SQL? Verifícalo con el MCP de Google."*
- *"Simula una entrevista de 20 minutos sobre BigQuery y modelado. Al final, dame feedback."*

Configura el MCP de documentación y las skills oficiales de Google en el [lab00, paso 8](../labs/lab00-setup/README.md).

## Costos

| Recurso | Costo en este lab | Cuidado con |
|---|---|---|
| BigQuery | $0 (free tier: 1 TiB de consultas y 10 GiB de storage al mes) | Borrar las tablas grandes del lab02 |
| Cloud Storage | centavos | — |
| Cloud Run Job | ~$0 | — |
| Dataflow | centavos por job | Jobs que quedan corriendo (`--status active`) |
| Composer | **cobra mientras existe** | Solo en la parte B del lab06, ≤ 2 h, y borrarlo |
| Artifact Registry | centavos | Imágenes viejas |

El total esperado es de pocos dólares, muy por debajo de los US$300 del free trial, **siempre que Composer no quede prendido**.

## Limpieza

- Al terminar cada sesión: `scripts/teardown.sh composer`, si lo creaste.
- Al terminar el curso: `scripts/teardown.sh project`.

## Si algo falla

1. Lee el error completo. Casi siempre es un permiso (`403`, `PERMISSION_DENIED`): ¿qué identidad lo pidió y qué rol le falta?
2. Corre `scripts/preflight.sh`.
3. Pregúntale a tu Claude con el error pegado. Pídele que lo verifique con el MCP de documentación.
