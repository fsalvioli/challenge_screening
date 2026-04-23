# AI Context: Compliance Screening Engine

`Propósito del Sistema`
-Sistema SaaS Multi-tenant de Screening de personas y empresas contra listas de sanciones (OFAC, ONU, etc.) y PEPs. 
-El objetivo es detectar coincidencias mediante algoritmos de similitud y generar alertas para analistas de cumplimiento.

`Arquitectura de Datos (Reglas de Oro)`
-Schema: Todo reside en el esquema screening.

-Multi-tenancy: Aislamiento total mediante tenant_id. Las políticas de Row Level Security (RLS) son mandatorias.

-Particionamiento: La tabla alerts está particionada por created_at (Range).

-Importante: Cualquier Foreign Key hacia alerts DEBE ser compuesta: (alert_id, alert_created_at).

-Tipos de Entidad: Se maneja un modelo polimórfico (PERSON/COMPANY) mediante la columna entity_type y entity_id.

`🔄 Flujo de Trabajo (Data Pipeline)`
-Ingesta: Datos de clientes entran en persons o companies.

-Matching: La función run_screening() invoca a calculate_similarity().

-Alerting: Si el similarity_score > umbral, se inserta en alerts.

-Gestión: Analistas (users) revisan alertas, agregan alert_comments y cambian el estado, lo que dispara un registro en alert_status_log.

`🧠 Lógica de Similitud (Matching Engine)`
-Algoritmo: Basado en trigramas (pg_trgm) y limpieza de acentos (unaccent).

> Score: Escala 0-100.

> 95: Strong Match (Requiere acción inmediata).

> 75-95: Potential Match.

> 75: Ignorado o Low Match.

-Documentos: La normalización (quitar guiones, espacios, letras) es crítica antes de comparar tax_id.

`🛠️ Stack Tecnológico para el Agente`
-Motor: PostgreSQL 17+.

-Extensiones: uuid-ossp, pg_trgm, unaccent.

-Convención de Nombres: snake_case para todo. Prefijos: v_ (vistas), idx_ (índices), trg_ (triggers).

-----------------------------------

`🚩 Casos de Borde y Errores Comunes`
-División por cero: En las vistas de métricas, usar siempre NULLIF al calcular ratios.

-Performance: No buscar similitud de nombres sobre toda la tabla de listas; usar primero filtros de tax_id o country_code si están disponibles.

-UTC: Todas las marcas temporales son timestamptz.

---------------------------------

**Estrategia de Testing/Seeding**
-Reset manual: Para limpiar y recargar datos, el agente debe ejecutar TRUNCATE en orden inverso de jerarquía (comenzando por alerts y terminando en tenants) y luego correr el seed.sql.

-Uso de IDs: Como usamos UUIDs, el agente debe usar subconsultas (SELECT id FROM ...) en los scripts de semilla para asegurar la integridad referencial sin hardcodear strings largos.

### 🧪 Validación y Testing (AI-Ready)
El proyecto incluye un flujo de validación automatizable para agentes de IA:
1. Ejecutar `sql/schema.sql` para levantar la estructura.
2. Ejecutar `sql/small_seed.sql` para poblar datos maestros y transaccionales.
3. Ejecutar `sql/smoke_test.sql` para validar la integridad de las funciones de similitud y las vistas operativas.