SET search_path TO screening, public;

CREATE OR REPLACE VIEW screening.v_analyst_pending_dashboard AS
SELECT 
    a.tenant_id,
    COALESCE(u.full_name, 'SIN ASIGNAR') AS analyst_name,
    a.id AS alert_id,
    a.status,
    a.entity_type,
    COALESCE(p.full_name, c.business_name) AS entity_name,
    l.name AS list_name,
    a.similarity_score,
    -- score
    CASE 
        WHEN a.similarity_score >= 95 THEN 'CRiTICO'
        WHEN a.similarity_score >= 85 THEN 'ALTO'
        WHEN a.similarity_score >= 75 THEN 'MEDIO'
        ELSE 'BAJO'
    END AS priority_level,
    a.created_at AS alert_date
FROM screening.alerts a
LEFT JOIN screening.users u ON a.assigned_to_id = u.id
JOIN screening.list_entries le ON a.list_entry_id = le.id
JOIN screening.lists l ON le.list_id = l.id
LEFT JOIN screening.persons p ON a.entity_id = p.id AND a.entity_type = 'PERSON'
LEFT JOIN screening.companies c ON a.entity_id = c.id AND a.entity_type = 'COMPANY'
WHERE a.status IN ('PENDING', 'REVIEWING')
ORDER BY a.similarity_score DESC, a.created_at ASC;

----------

CREATE OR REPLACE VIEW screening.v_screening_efficiency_metrics AS
SELECT
al.tenant_id,
l.name AS list_name,
  COUNT(*) AS total_matches,
  COUNT(*) FILTER (WHERE al.status = 'CONFIRMED') AS confirmed_matches,
  COUNT(*) FILTER (WHERE al.status = 'DISMISSED') AS false_positive_matches,
  ROUND(
    (COUNT(*) FILTER (WHERE al.status = 'CONFIRMED')::NUMERIC / 
    NULLIF(COUNT(*) FILTER (WHERE al.status IN ('CONFIRMED', 'DISMISSED')), 0)::NUMERIC) * 100,
  2) AS hit_rate_percentage, -- porcentaje POSITIVOS
  ROUND(
        (COUNT(*) FILTER (WHERE al.status = 'DISMISSED')::NUMERIC / 
        NULLIF(COUNT(*) FILTER (WHERE al.status IN ('CONFIRMED', 'DISMISSED')), 0)::NUMERIC) * 100, 
        2
    ) AS false_positive_rate_percentage -- porcentaje FALSOS POSITIVOS
FROM screening.alerts as al
INNER JOIN screening.list_entries AS le ON al.list_entry_id = le.id
INNER JOIN screening.lists l ON le.list_id = l.id
GROUP BY tenant_id, l.name;

----

CREATE OR REPLACE VIEW screening.v_alerts_aging AS
SELECT 
    a.tenant_id,
    a.id AS alert_id,
    a.status,
    COALESCE(u.full_name, 'SIN ASIGNAR') AS assigned_analyst,
    a.created_at AS detection_date,
    -- Tiempo transcurrido desde la creación hasta ahora o hasta su cierre:
    age(COALESCE(
        (SELECT MAX(changed_at) FROM screening.alert_history WHERE alert_id = a.id AND new_status IN ('CONFIRMED', 'DISMISSED')),
        NOW()
    ), a.created_at) AS total_aging,
    -- Días netos como número para facilitar dashboards:
    EXTRACT(DAY FROM (NOW() - a.created_at)) AS days_open,
    -- Alerta de SLA (ej: más de 3 días es crítico):
    CASE 
        WHEN a.status IN ('PENDING', 'REVIEWING') AND EXTRACT(DAY FROM (NOW() - a.created_at)) > 3 THEN 'FUERA DE SLA'
        WHEN a.status IN ('PENDING', 'REVIEWING') AND EXTRACT(DAY FROM (NOW() - a.created_at)) > 1 THEN 'EN RIESGO'
        ELSE 'A TIEMPO'
    END AS sla_status
FROM screening.alerts a
LEFT JOIN screening.users u ON a.assigned_to_id = u.id;

-----

CREATE OR REPLACE VIEW screening.v_analyst_productivity AS
SELECT 
    u.tenant_id,
    u.id AS user_id,
    u.full_name AS analyst_name,
    -- Alertas actualmente asignadas:
    (SELECT COUNT(*) FROM screening.alerts WHERE assigned_to_id = u.id AND status IN ('PENDING', 'REVIEWING')) AS current_backlog,
    -- Alertas cerradas (vía el log de estados para mayor precisión):
    COUNT(DISTINCT ah.alert_id) FILTER (WHERE ah.new_status IN ('CONFIRMED', 'DISMISSED')) AS alerts_resolved,
    -- Total de movimientos realizados (esfuerzo):
    COUNT(ah.id) AS total_actions,
    -- Promedio de acciones por alerta (complejidad del análisis):
    ROUND(AVG(COUNT(ah.id)) OVER (PARTITION BY u.id), 2) AS avg_actions_per_alert,
    -- Fecha de última actividad:
    MAX(ah.changed_at) AS last_active_at
FROM screening.users u
LEFT JOIN screening.alert_history ah ON u.id = ah.user_id
WHERE u.role = 'ANALYST' -- solo analistas
GROUP BY u.tenant_id, u.id, u.full_name;

-----

CREATE OR REPLACE VIEW screening.v_screening_coverage AS
  WITH entity_stats AS (
      SELECT 
          tenant_id,
          entity_type,
          entity_id,
          -- Verificamos si la entidad tiene al menos una alerta generada:
          EXISTS (
              SELECT 1 FROM screening.alerts a 
              WHERE a.entity_id = acc.entity_id 
              AND a.entity_type = acc.entity_type
          ) AS is_screened
      FROM screening.accounts acc
  )
SELECT 
    tenant_id,
    entity_type,
    COUNT(*) AS total_accounts,
    COUNT(*) FILTER (WHERE is_screened) AS screened_accounts,
    COUNT(*) FILTER (WHERE NOT is_screened) AS unscreened_accounts,
    -- Porcentaje de cobertura
    ROUND(
        (COUNT(*) FILTER (WHERE is_screened)::NUMERIC / COUNT(*)::NUMERIC) * 100, 
        2
    ) AS coverage_percentage
FROM entity_stats
GROUP BY tenant_id, entity_type;