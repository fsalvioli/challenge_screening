-- 1. Insertar un Tenant (El Banco)
INSERT INTO screening.tenants (name) VALUES ('Banco de Ramos Mejía') RETURNING id;

-- 2. Insertar Usuarios/Analistas
INSERT INTO screening.users (tenant_id, full_name, role) 
VALUES 
((SELECT id FROM screening.tenants LIMIT 1), 'Franco Salvioli', 'SUPERVISOR'),
((SELECT id FROM screening.tenants LIMIT 1), 'Analista de Pruebas', 'ANALYST');

-- 3. Insertar Listas de Control
INSERT INTO screening.lists (name, description, list_type) 
VALUES 
('OFAC - SDN', 'Specially Designated Nationals and Blocked Persons List', 'SANCTIONS'),
('PEPs Argentina', 'Personas Expuestas Políticamente de Argentina', 'PEP'),
('Internal Watchlist', 'Lista negra interna del banco', 'INTERNAL');

-- 4. Insertar Entradas en Listas (Target de búsqueda)
INSERT INTO screening.list_entries (list_id, full_name, tax_id, country_code, risk_level)
VALUES 
((SELECT id FROM screening.lists WHERE name = 'OFAC - SDN'), 'Pablo Emilio Escobar', '12345678', 'COL', 3),
((SELECT id FROM screening.lists WHERE name = 'PEPs Argentina'), 'Juan Perez Político', '20-30405060-7', 'ARG', 2);

-- 5. Insertar Cuentas y Entidades (Clientes del banco)
INSERT INTO screening.persons (tenant_id, first_name, last_name, tax_id, tax_country)
VALUES 
((SELECT id FROM screening.tenants LIMIT 1), 'Pablo', 'Escobar', '12345678', 'COL');

-- Vinculamos una cuenta a esa persona
INSERT INTO screening.accounts (tenant_id, account_number, entity_type, entity_id)
VALUES 
((SELECT id FROM screening.tenants LIMIT 1), 'CBU-0000123456', 'PERSON', (SELECT id FROM screening.persons WHERE last_name = 'Escobar'));

-- 6. Simular Alertas y Logs (Para probar las vistas del Dashboard)
INSERT INTO screening.alerts (id, tenant_id, status, entity_type, entity_id, list_entry_id, similarity_score, created_at)
VALUES 
(gen_random_uuid(), (SELECT id FROM screening.tenants LIMIT 1), 'PENDING', 'PERSON', 
 (SELECT id FROM screening.persons WHERE last_name = 'Escobar'), 
 (SELECT id FROM screening.list_entries WHERE full_name ILIKE '%Escobar%'), 
 98.5, NOW() - INTERVAL '2 days');

-- Log de actividad para esa alerta
INSERT INTO screening.alert_status_log (alert_id, alert_created_at, old_status, new_status, changed_by)
VALUES 
((SELECT id FROM screening.alerts LIMIT 1), (SELECT created_at FROM screening.alerts LIMIT 1), 'PENDING', 'REVIEWING', (SELECT id FROM screening.users WHERE role = 'ANALYST'));