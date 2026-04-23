-- =============================================================================
-- SMOKE TEST: Validación del Motor de Screening
-- Propósito: Verificar que run_screening genera alertas basadas en similitud.
-- =============================================================================

DO $$ 
DECLARE 
    v_test_person_id UUID;
    v_alert_count INTEGER;
    v_score NUMERIC;
BEGIN
    RAISE NOTICE 'Iniciando Smoke Test...';

    -- 1. Preparación: Buscamos o creamos un Tenant de prueba
    -- (Asumimos que el seed.sql ya corrió, sino lo manejamos aquí)
    
    -- 2. Identificar una entidad de prueba (Pablo Escobar de persons)
    SELECT id INTO v_test_person_id 
    FROM screening.persons 
    WHERE last_name = 'Escobar' LIMIT 1;

    IF v_test_person_id IS NULL THEN
        RAISE EXCEPTION 'Error: No se encontró la entidad de prueba. ¿Corriste el seed.sql?';
    END IF;

    -- 3. Ejecutar el motor de screening para esta persona
    RAISE NOTICE 'Ejecutando run_screening para la persona ID: %', v_test_person_id;
    
    PERFORM screening.run_screening('PERSON', v_test_person_id);

    -- 4. Verificación de resultados en la tabla de alertas
    SELECT COUNT(*), MAX(similarity_score) 
    INTO v_alert_count, v_score
    FROM screening.alerts 
    WHERE entity_id = v_test_person_id;

    -- 5. Aserciones (Validaciones lógicas)
    IF v_alert_count > 0 THEN
        RAISE NOTICE 'TEST PASADO: Se generaron % alertas.', v_alert_count;
        RAISE NOTICE 'Score de coincidencia detectado: %', v_score;
        
        IF v_score < 90 THEN
            RAISE WARNING 'El score (%) es más bajo de lo esperado para un match exacto.', v_score;
        END IF;
    ELSE
        RAISE EXCEPTION 'TEST FALLIDO: No se generaron alertas para un match conocido.';
    END IF;

    -- 6. Validar accesibilidad desde las vistas del Día 4
    IF EXISTS (SELECT 1 FROM screening.vw_analyst_pending_dashboard WHERE entity_name ILIKE '%Escobar%') THEN
        RAISE NOTICE 'TEST PASADO: La alerta es visible en el Dashboard de Analistas.';
    ELSE
        RAISE EXCEPTION 'TEST FALLIDO: La alerta no aparece en la vista de Dashboard.';
    END IF;

    RAISE NOTICE 'Smoke Test finalizado con éxito.';
END $$;