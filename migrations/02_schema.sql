SET search_path TO screening, public;

CREATE TABLE "screening"."tenants" (
  "id" uuid PRIMARY KEY DEFAULT (uuid_generate_v4()),
  "name" text NOT NULL,
  "created_at" timestamptz DEFAULT (now())
);

CREATE TABLE "screening"."persons" (
  id uuid PRIMARY KEY DEFAULT (uuid_generate_v4()),
  "tenant_id" uuid,
  "first_name" text NOT NULL,
  "last_name" text NOT NULL,
  full_name text GENERATED ALWAYS AS (first_name || ' ' || last_name) STORED,
  "birth_date" date,
  "tax_type" text,
  "tax_id" text NOT NULL,
  "tax_country" text,
  "normalized_tax_id" text,
  "nationality" varchar(3),
  "metadata" jsonb,
  "created_at" timestamptz DEFAULT (now())
);

CREATE TABLE "screening"."companies" (
  "id" uuid PRIMARY KEY DEFAULT (uuid_generate_v4()),
  "tenant_id" uuid,
  "business_name" text NOT NULL,
  "tax_type" text,
  "tax_id" text NOT NULL,
  "normalized_tax_id" text,
  "tax_country" text,
  "metadata" jsonb,
  "created_at" timestamptz DEFAULT (now())
);

CREATE TABLE "screening"."accounts" (
  "id" uuid PRIMARY KEY DEFAULT (uuid_generate_v4()),
  "tenant_id" uuid,
  "account_number" text NOT NULL,
  "entity_type" text CHECK (entity_type IN ('PERSON', 'COMPANY')),
  "entity_id" uuid NOT NULL,
  "status" text DEFAULT 'ACTIVE',
  "created_at" timestamptz DEFAULT (now())
);

CREATE TABLE "screening"."users" (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL,
    full_name TEXT NOT NULL,
    role TEXT CHECK (role IN ('ANALYST', 'SUPERVISOR')),
    is_active BOOLEAN DEFAULT true
);

CREATE TABLE "screening"."lists" (
  "id" uuid PRIMARY KEY DEFAULT (uuid_generate_v4()),
  "name" text UNIQUE NOT NULL,
  "description" text,
  "list_type" text,
  "last_updated" timestamptz DEFAULT (now()),
  "metadata" jsonb
);

CREATE TABLE "screening"."list_entries" (
  "id" uuid PRIMARY KEY DEFAULT (uuid_generate_v4()),
  "list_id" uuid,
  "full_name" text NOT NULL,
  "tax_id" text,
  "normalized_tax_id" text,
  "birth_date_raw" text,
  "country_code" varchar(3),
  "risk_level" int DEFAULT 1,
  "metadata" jsonb,
  "created_at" timestamptz DEFAULT (now())
);

CREATE TABLE "screening"."alerts" (
  "id" uuid NOT NULL,
  "tenant_id" uuid,
  "assigned_to_id" uuid REFERENCES screening.users(id),
  "status" alert_status DEFAULT 'PENDING',
  "entity_type" text,
  "entity_id" uuid,
  "list_entry_id" uuid,
  "similarity_score" numeric,
  "match_details" jsonb,
  "created_at" timestamptz DEFAULT (now()),
  PRIMARY KEY (id, created_at)
) PARTITION BY RANGE (created_at);

CREATE TABLE "screening"."alerts_default" PARTITION OF screening.alerts 
    FOR VALUES FROM ('2020-01-01') TO ('2030-01-01');

CREATE TABLE screening.alert_comments (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    alert_id UUID NOT NULL,
    alert_created_at TIMESTAMPTZ NOT NULL,
    comment TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    FOREIGN KEY (alert_id, alert_created_at) REFERENCES screening.alerts (id, created_at)
);

CREATE TABLE "screening"."alert_history" (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    alert_id UUID,
    user_id UUID REFERENCES screening.users(id),
    alert_created_at TIMESTAMPTZ NOT NULL,
    old_status screening.alert_status,
    new_status screening.alert_status,
    changed_at TIMESTAMPTZ DEFAULT NOW(),
    FOREIGN KEY (alert_id, alert_created_at) REFERENCES screening.alerts (id, created_at)
);


COMMENT ON COLUMN "screening"."persons"."full_name" IS 'Generated: first + last';

COMMENT ON COLUMN "screening"."accounts"."entity_type" IS 'PERSON or COMPANY';

COMMENT ON TABLE "screening"."alerts" IS 'Table Partitioned by created_at';

ALTER TABLE "screening"."persons" ADD FOREIGN KEY ("tenant_id") REFERENCES "screening"."tenants" ("id") DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE "screening"."companies" ADD FOREIGN KEY ("tenant_id") REFERENCES "screening"."tenants" ("id") DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE "screening"."accounts" ADD FOREIGN KEY ("tenant_id") REFERENCES "screening"."tenants" ("id") DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE "screening"."list_entries" ADD FOREIGN KEY ("list_id") REFERENCES "screening"."lists" ("id") DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE "screening"."alerts" ADD FOREIGN KEY ("tenant_id") REFERENCES "screening"."tenants" ("id") DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE "screening"."alerts" ADD FOREIGN KEY ("list_entry_id") REFERENCES "screening"."list_entries" ("id") DEFERRABLE INITIALLY IMMEDIATE;

-- Ajuste de Autovacuum para la tabla de alertas (más agresivo)
ALTER TABLE screening.alerts SET (
  autovacuum_vacuum_scale_factor = 0.05,  -- Se dispara cuando cambia el 5% de la tabla
  autovacuum_analyze_scale_factor = 0.02, -- Actualiza estadísticas más seguido
  autovacuum_vacuum_cost_limit = 1000     -- Le damos más "permiso" de usar CPU
);