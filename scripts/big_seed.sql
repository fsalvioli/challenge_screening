-- Script de generación de volumen
INSERT INTO screening.list_entries (list_id, full_name, tax_id, country_code, risk_level)
SELECT 
    (SELECT id FROM screening.lists LIMIT 1),
    'Persona Ficticia ' || i,
    (10000000 + i)::text,
    CASE WHEN i % 2 = 0 THEN 'ARG' ELSE 'USA' END,
    (random() * 3)::int
FROM generate_series(1, 1000000) AS i;