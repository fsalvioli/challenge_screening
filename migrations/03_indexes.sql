SET search_path TO screening, public;

-- 1. Índices para búsqueda de nombres (Trigramas)
-- Uso GIN porque es más rápido para lectura en grandes volúmenes de datos
CREATE INDEX IF NOT EXISTS idx_persons_full_name_trgm 
ON persons USING GIN (full_name gin_trgm_ops);

CREATE INDEX IF NOT EXISTS idx_companies_name_trgm 
ON companies USING GIN (business_name gin_trgm_ops);

CREATE INDEX IF NOT EXISTS idx_list_entries_name_trgm 
ON list_entries USING GIN (full_name gin_trgm_ops);

-- 2. Índices para búsqueda de documentos (Normalizados)
CREATE INDEX IF NOT EXISTS idx_persons_tax_id_norm ON persons (normalized_tax_id);
CREATE INDEX IF NOT EXISTS idx_companies_tax_id_norm ON companies (normalized_tax_id);
CREATE INDEX IF NOT EXISTS idx_list_entries_tax_id_norm ON list_entries (normalized_tax_id);

-- 3. Índice para la tabla particionada de Alertas
CREATE INDEX IF NOT EXISTS idx_alerts_tenant_status 
ON alerts (tenant_id, status);