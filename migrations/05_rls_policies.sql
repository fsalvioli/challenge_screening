SET search_path TO screening, public;


ALTER TABLE screening.persons ENABLE ROW LEVEL SECURITY;
ALTER TABLE screening.companies ENABLE ROW LEVEL SECURITY;
ALTER TABLE screening.alerts ENABLE ROW LEVEL SECURITY;

-- Política para la tabla de alertas
CREATE POLICY tenant_alerts_isolation ON screening.alerts
    USING (tenant_id = current_setting('app.current_tenant')::UUID);

-- Política para la tabla de personas
CREATE POLICY tenant_persons_isolation ON screening.persons
    USING (tenant_id = current_setting('app.current_tenant')::UUID);

-- Política para la tabla de empresas
CREATE POLICY tenant_companies_isolation ON screening.companies
    USING (tenant_id = current_setting('app.current_tenant')::UUID);