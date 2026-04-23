-- Habilitar extensiones requeridas
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";    -- Para IDs únicos globales
CREATE EXTENSION IF NOT EXISTS "pg_trgm";      -- Para similitud de texto (trigramas)
CREATE EXTENSION IF NOT EXISTS "fuzzystrmatch";-- Para algoritmos Levenshtein/Soundex

-- Crear esquema dedicado para organizar la lógica
CREATE SCHEMA IF NOT EXISTS screening;

DO $$
BEGIN
	IF NOT EXISTS (
		SELECT 1 FROM pg_type t JOIN pg_namespace n ON n.oid = t.typnamespace WHERE t.typname = 'alert_status' AND n.nspname = 'screening'
		) THEN
			CREATE TYPE screening.alert_status AS ENUM ('PENDING', 'REVIEWING', 'CONFIRMED', 'DISMISSED');
	END IF;
END $$;
