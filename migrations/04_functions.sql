SET search_path TO screening, public;

CREATE OR REPLACE FUNCTION screening.normalize_tax_id(p_tax TEXT) 
RETURNS TEXT AS $$
BEGIN
    RETURN UPPER(REGEXP_REPLACE(p_tax, '[^a-zA-Z0-9]', '', 'g'));
END;
$$ LANGUAGE plpgsql IMMUTABLE;


CREATE OR REPLACE FUNCTION screening.search_by_tax_id(
    p_tax_id TEXT,
    p_country TEXT DEFAULT NULL
) RETURNS TABLE (
    list_name TEXT,
    entry_id UUID,
    matched_tax_id TEXT,
    match_type TEXT,
    confidence NUMERIC,
    is_suspicious BOOLEAN
) 
LANGUAGE plpgsql 
SECURITY DEFINER 
SET search_path = screening, public, pg_temp -- Por seguridad al usar SECURITY DEFINER
STABLE
AS $$
DECLARE
    v_norm_input TEXT;
    v_is_bad_pattern BOOLEAN;

/*
Autor: Franco Salvioli
Fecha: 2026-04-19
Desc: Realiza una búsqueda inteligente de identificadores fiscales (CUIT, RUT, SSN, etc.). 
      Normaliza el input (eliminando puntos, guiones y espacios) y permite búsquedas 
      globales si no se especifica un país. Detecta patrones sospechosos (documentos muy 
      cortos o repetitivos) y devuelve coincidencias clasificadas como EXACT, 
      NORMALIZED o FUZZY con un score de confianza.

Ejemplo de ejecucion:
SELECT * FROM screening.search_by_tax_id('20-30444555-6', 'AR');
*/

BEGIN

    v_norm_input := UPPER(REGEXP_REPLACE(p_tax_id, '[^a-zA-Z0-9]', '', 'g'));

    -- esto para detectar si es demasiado corto, nos ayuda a que si llega '123' no busque todo sino que como es demasiado corto lo detecta como sospechoso
    v_is_bad_pattern := (v_norm_input ~ '^(.)\1+$') OR (LENGTH(v_norm_input) < 5);


    RETURN QUERY
    SELECT 
        l.name AS list_name,
        e.id AS entry_id,
        e.tax_id AS matched_tax_id,
        CASE 
            WHEN e.tax_id = p_tax_id THEN 'EXACT'
            WHEN UPPER(REGEXP_REPLACE(e.tax_id, '[^a-zA-Z0-9]', '', 'g')) = v_norm_input THEN 'NORMALIZED'
            ELSE 'FUZZY'
        END AS match_type,
        CASE 
            WHEN e.tax_id = p_tax_id THEN 1.0
            WHEN UPPER(REGEXP_REPLACE(e.tax_id, '[^a-zA-Z0-9]', '', 'g')) = v_norm_input THEN 0.95
            ELSE similarity(e.tax_id, p_tax_id)::NUMERIC
        END AS confidence,
        v_is_bad_pattern
    FROM screening.list_entries e
    JOIN screening.lists l ON e.list_id = l.id
    WHERE 
        -- Filtro por país si se provee
        (p_country IS NULL OR e.country_code = p_country)
        AND (
            e.tax_id = p_tax_id -- Coincidencia exacta
            OR UPPER(REGEXP_REPLACE(e.tax_id, '[^a-zA-Z0-9]', '', 'g')) = v_norm_input -- Coincidencia normalizada
            OR (LENGTH(v_norm_input) > 6 AND e.tax_id % p_tax_id)
        )
    ORDER BY confidence DESC;
END;
$$;

------------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION screening.calculate_similarity(
    p_name_input TEXT,
    p_name_db TEXT,
    p_tax_input TEXT DEFAULT NULL,
    p_tax_db TEXT DEFAULT NULL,
    p_dob_input DATE DEFAULT NULL,
    p_dob_db DATE DEFAULT NULL,
    p_threshold NUMERIC DEFAULT 0.8
) RETURNS TABLE (
    similarity_score NUMERIC,
    match_type TEXT,
    details JSONB
) 
LANGUAGE plpgsql 
SECURITY DEFINER 
SET search_path = screening, public, pg_temp -- Por seguridad al usar SECURITY DEFINER
STABLE
AS $$
DECLARE
    v_name_score NUMERIC;
    v_tax_score NUMERIC := 0;
    v_date_score NUMERIC := 0;
    v_final_score NUMERIC;
    v_details JSONB;

/*
Autor: Franco Salvioli
Fecha: 2026-04-20
Desc: Evalúa el nivel de riesgo comparando múltiples dimensiones de una entidad contra 
      una entrada de la lista. Aplica una ponderación inteligente (60% nombre, 30% documento, 
      10% fecha de nacimiento) y soporta coincidencias parciales de fechas. 
      Devuelve un objeto JSONB con el desglose de los puntajes para auditoría humana.

Ejemplo de ejecucion:
SELECT * FROM screening.calculate_similarity(
    p_person_id => 'uuid-de-la-persona',
    p_list_entry_id => 'uuid-de-la-lista'
);
*/

BEGIN
    -- 1. Similitud de Nombres (Trigramas + Limpieza de acentos)
    v_name_score := similarity(unaccent(p_name_input), unaccent(p_name_db))::NUMERIC;

    -- 2. Similitud de Documentos
    IF p_tax_input IS NOT NULL AND p_tax_db IS NOT NULL THEN
        IF screening.normalize_tax_id(p_tax_input) = screening.normalize_tax_id(p_tax_db) THEN
            v_tax_score := 1.0;
        ELSE
            v_tax_score := similarity(p_tax_input, p_tax_db)::NUMERIC;
        END IF;
    END IF;

    -- 3. Similitud de Fechas (Matching Parcial)
    IF p_dob_input IS NOT NULL AND p_dob_db IS NOT NULL THEN
        IF p_dob_input = p_dob_db THEN v_date_score := 1.0;
        ELSIF EXTRACT(YEAR FROM p_dob_input) = EXTRACT(YEAR FROM p_dob_db) AND 
              EXTRACT(MONTH FROM p_dob_input) = EXTRACT(MONTH FROM p_dob_db) THEN v_date_score := 0.8;
        ELSIF EXTRACT(YEAR FROM p_dob_input) = EXTRACT(YEAR FROM p_dob_db) THEN v_date_score := 0.5;
        END IF;
    END IF;

    -- 4. Cálculo de Score Final (Promedio ponderado)
    -- Si el documento es idéntico, le damos prioridad máxima (0.95+)
    IF v_tax_score = 1.0 THEN
        v_final_score := 0.95 + (v_name_score * 0.05);
    ELSE
        v_final_score := (v_name_score * 0.6) + (v_tax_score * 0.3) + (v_date_score * 0.1);
    END IF;

    -- Convertir a escala 0-100
    v_final_score := ROUND(v_final_score * 100, 2);

    -- Armar el JSON de auditoría
    v_details := jsonb_build_object(
        'name_match', v_name_score,
        'tax_match', v_tax_score,
        'date_match', v_date_score,
        'threshold_used', p_threshold
    );

    -- 5. Retorno si supera el umbral (convertido a escala 0-1)
    IF v_final_score >= (p_threshold * 100) THEN
        RETURN QUERY SELECT 
            v_final_score,
            CASE 
                WHEN v_final_score >= 95 THEN 'STRONG_MATCH'
                WHEN v_final_score >= 75 THEN 'POTENTIAL_MATCH'
                ELSE 'WEAK_MATCH'
            END,
            v_details;
    END IF;
END;
$$;

-------------------------------------------------------------

CREATE OR REPLACE FUNCTION screening.run_screening(
    p_entity_type TEXT, 
    p_entity_id UUID,
    p_lists TEXT[] DEFAULT NULL
) RETURNS TABLE (
    alert_id UUID,
    list_name TEXT,
    matched_entry_id UUID,
    similarity_score NUMERIC,
    match_details JSONB
) 
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_entity_name TEXT;
    v_entity_tax TEXT;
    v_entity_dob DATE;
    v_tenant_id UUID;

/*
Autor: Franco Salvioli
Fecha: 2026-04-20
Desc: Orquestador principal del sistema que procesa entidades (PERSON o COMPANY) contra 
      las listas de control de manera dinámica. Utiliza CROSS JOIN LATERAL para cálculos 
      en tiempo real y una estrategia de Upsert (ON CONFLICT DO UPDATE) para evitar la 
      duplicidad de alertas, actualizando el score si el hallazgo ya existía.

Ejemplo de ejecucion:
SELECT screening.run_screening(
    p_entity_id => 'uuid-entidad',
    p_entity_type => 'PERSON',
    p_threshold => 0.85
);
*/

BEGIN

    IF p_entity_type = 'PERSON' THEN
        SELECT full_name, tax_id, birth_date, tenant_id 
            INTO v_entity_name, v_entity_tax, v_entity_dob, v_tenant_id
        FROM screening.persons
        WHERE id = p_entity_id;
    END IF;

    IF p_entity_type = 'COMPANY' THEN
        SELECT business_name, tax_id, created_at, tenant_id 
            INTO v_entity_name, v_entity_tax, v_entity_dob, v_tenant_id
        FROM screening.companies
        WHERE id = p_entity_id;
    END IF;

    RETURN QUERY
    WITH potential_matches AS (
        SELECT 
            l.name as l_name,
            e.id as e_id,
            sim.similarity_score as s_score,
            sim.details as s_details
        FROM screening.list_entries e
        JOIN screening.lists l ON e.list_id = l.id
        CROSS JOIN LATERAL screening.calculate_similarity(
            v_entity_name, e.full_name, 
            v_entity_tax, e.tax_id, 
            v_entity_dob, CAST(e.metadata->>'birth_date' AS DATE)
        ) sim
        WHERE (p_lists IS NULL OR l.name = ANY(p_lists))
        AND sim.similarity_score > 70 
    )
    INSERT INTO screening.alerts (
        id,
        tenant_id, 
        status,
        entity_type, 
        entity_id, 
        list_entry_id, 
        similarity_score, 
        match_details,
        created_at
    )
    SELECT 
        gen_random_uuid(), -- ID de la alerta
        v_tenant_id, 
        'PENDING',
        p_entity_type, 
        p_entity_id, 
        pm.e_id, 
        pm.s_score, 
        pm.s_details,
        NOW()
    FROM potential_matches pm
    ---
    ON CONFLICT (id, created_at) 
    DO UPDATE SET 
        similarity_score = EXCLUDED.similarity_score,
        match_details = EXCLUDED.match_details
    RETURNING id, l_name, list_entry_id, similarity_score, match_details;
END;
$$;