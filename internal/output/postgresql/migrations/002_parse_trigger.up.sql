BEGIN;

REVOKE SELECT ON api.blocks FROM web_anon;
REVOKE SELECT ON api.transactions FROM web_anon;

ALTER TABLE api.blocks RENAME TO blocks_raw;
ALTER TABLE api.transactions RENAME TO transactions_raw;

-- This table stores the parsed transaction data
CREATE TABLE IF NOT EXISTS api.transactions_main (
    id VARCHAR(64) PRIMARY KEY REFERENCES api.transactions_raw(id),
    fee JSONB,
    memo TEXT,
    error TEXT,
    height TEXT NOT NULL,
    timestamp TEXT NOT NULL
);

-- This table stores the raw message data from the transaction
CREATE TABLE IF NOT EXISTS api.messages_raw(
    id VARCHAR(64) REFERENCES api.transactions_raw(id),
    message_index BIGINT,
    data JSONB,
    PRIMARY KEY (id, message_index)
);

CREATE TABLE IF NOT EXISTS api.messages_main(
    id VARCHAR(64),
    message_index BIGINT,
    type TEXT,
    sender TEXT,
    mentions TEXT[],
    metadata JSONB,
    PRIMARY KEY (id, message_index),
    FOREIGN KEY (id, message_index) REFERENCES api.messages_raw(id, message_index)
);

CREATE OR REPLACE FUNCTION extract_addresses(msg JSONB)
RETURNS TEXT[]
LANGUAGE SQL STABLE
AS $$
WITH addresses AS (
  SELECT unnest(
    regexp_matches(
      -- Convert the JSONB to text, then do a pattern match
      msg::text,
      -- Very rough bech32-like pattern:
      --   - 2-83 chars of [a-z0-9], plus '1', plus 38+ chars of the set [qpzry9x8gf2tvdw0s3jn54khce6mua7l]
      --   We allow trailing chars because some addresses can be longer if they contain e.g. valoper style, etc.
      E'(?<=[\\"\'\\\\s]|^)([a-z0-9]{2,83}1[qpzry9x8gf2tvdw0s3jn54khce6mua7l]{38,})(?=[\\"\'\\\\s]|$)',
      'g'
    )
  ) AS addr
)
SELECT array_agg(DISTINCT addr)
FROM addresses;
$$;

CREATE OR REPLACE FUNCTION extract_metadata(msg JSONB)
RETURNS JSONB
LANGUAGE SQL STABLE
AS $$
  WITH keys_to_remove AS (
      SELECT ARRAY['@type', 'sender', 'executor', 'admin', 'voter', 'messages', 'proposalId', 'proposers', 'authority', 'fromAddress', 'metadata']::text[] AS keys
  )
  SELECT
    CASE
      -- If 'metadata' key exists and is a JSON object, merge its contents into the top-level JSON
      WHEN msg ? 'metadata' AND jsonb_typeof(msg->'metadata') = 'object' THEN
        (msg - (SELECT keys FROM keys_to_remove)) || (msg->'metadata')
      ELSE
        msg - (SELECT keys FROM keys_to_remove)
    END
$$;

CREATE OR REPLACE FUNCTION extract_proposal_failure_logs(json_data JSONB)
RETURNS TEXT
LANGUAGE sql
AS $$
WITH
  events AS (
    SELECT jsonb_array_elements(json_data->'txResponse'->'events') AS event
  ),

  typed_attributes AS (
    SELECT
      event->>'type' AS event_type,
      jsonb_array_elements(event->'attributes') AS attribute
    FROM events
  )

  SELECT
    TRIM(BOTH '"' FROM typed_attributes.attribute->>'value') AS logs
  FROM typed_attributes
  WHERE
    typed_attributes.event_type = 'cosmos.group.v1.EventExec'
    AND typed_attributes.attribute->>'key' = 'logs'
    AND EXISTS (
      SELECT 1
      FROM typed_attributes t2
      WHERE t2.event_type = typed_attributes.event_type
        AND t2.attribute->>'key' = 'result'
        AND t2.attribute->>'value' = '"PROPOSAL_EXECUTOR_RESULT_FAILURE"'
    )
  LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION update_transaction_main()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  error_text TEXT;
BEGIN
  error_text := NEW.data->'txResponse'->>'rawLog';

  IF error_text IS NULL THEN
    error_text := extract_proposal_failure_logs(NEW.data);
  END IF;

  INSERT INTO api.transactions_main (id, fee, memo, error, height, timestamp)
  VALUES (
            NEW.id,
            NEW.data->'tx'->'authInfo'->'fee',
            NEW.data->'tx'->'body'->>'memo',
            error_text,
            NEW.data->'txResponse'->>'height',
            NEW.data->'txResponse'->>'timestamp'
         )
  ON CONFLICT (id) DO UPDATE
  SET fee = EXCLUDED.fee,
      memo = EXCLUDED.memo,
      error = EXCLUDED.error,
      height = EXCLUDED.height,
      timestamp = EXCLUDED.timestamp;

  -- Insert top level messages
  INSERT INTO api.messages_raw (id, message_index, data)
  SELECT NEW.id, message_index - 1, message
  FROM jsonb_array_elements(NEW.data->'tx'->'body'->'messages') WITH ORDINALITY AS message(message, message_index);

  INSERT INTO api.messages_raw (id, message_index, data)
  SELECT
    NEW.id,
    -- We make a derived index for nested messages so they don't collide with top level messages
    (top_level.msg_index - 1) * 1000 + sub_level.sub_index,
    sub_level.sub_msg
  FROM jsonb_array_elements(NEW.data->'tx'->'body'->'messages')
       WITH ORDINALITY AS top_level(msg, msg_index)
       CROSS JOIN LATERAL (
         SELECT sub_msg, sub_index
         FROM jsonb_array_elements(top_level.msg->'messages')
              WITH ORDINALITY AS inner_msg(sub_msg, sub_index)
       ) AS sub_level
  WHERE top_level.msg->>'@type' = '/cosmos.group.v1.MsgSubmitProposal'
    AND top_level.msg->'messages' IS NOT NULL;

  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION update_message_main()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  sender TEXT;
  mentions TEXT[];
  metadata JSONB;
BEGIN
  sender := COALESCE(
    NULLIF(NEW.data->>'sender', ''),
    NULLIF(NEW.data->>'fromAddress', ''),
    NULLIF(NEW.data->>'admin', ''),
    NULLIF(NEW.data->>'voter', ''),
    NULLIF(NEW.data->>'address', ''),
    NULLIF(NEW.data->>'executor', ''),
    NULLIF(NEW.data->>'authority', ''),
    (
      SELECT jsonb_array_elements_text(NEW.data->'proposers')
      LIMIT 1
    ),
    (
      CASE
        WHEN jsonb_typeof(NEW.data->'inputs') = 'array'
             AND jsonb_array_length(NEW.data->'inputs') > 0
        THEN NEW.data->'inputs'->0->>'address'
        ELSE NULL
      END
    )
  );

  mentions := extract_addresses(NEW.data);
  metadata := extract_metadata(NEW.data);

  INSERT INTO api.messages_main (id, message_index, type, sender, mentions, metadata)
  VALUES (
           NEW.id,
           NEW.message_index,
           NEW.data->>'@type',
           sender,
           mentions,
           metadata
         )
  ON CONFLICT (id, message_index) DO NOTHING;

  RETURN NEW;
END;
$$;

-- Parse transaction on insert or update
CREATE OR REPLACE TRIGGER new_transaction_update
AFTER INSERT OR UPDATE
ON api.transactions_raw
FOR EACH ROW
EXECUTE FUNCTION update_transaction_main();

-- Parse message on insert or update
CREATE OR REPLACE TRIGGER new_message_update
AFTER INSERT OR UPDATE
ON api.messages_raw
FOR EACH ROW
EXECUTE FUNCTION update_message_main();

GRANT SELECT ON api.blocks_raw TO web_anon;
GRANT SELECT ON api.transactions_main TO web_anon;
GRANT SELECT ON api.transactions_raw TO web_anon;
GRANT SELECT ON api.messages_raw TO web_anon;
GRANT SELECT ON api.messages_main TO web_anon;

-- Use a staging table to convert the historical data to the new format
CREATE TABLE IF NOT EXISTS api.transactions_staging (
    id VARCHAR(64) PRIMARY KEY,
    data JSONB NOT NULL
);

CREATE OR REPLACE TRIGGER staging_transaction_update
AFTER INSERT OR UPDATE
ON api.transactions_staging
FOR EACH ROW
EXECUTE FUNCTION update_transaction_main();

INSERT INTO api.transactions_staging(id, data)
SELECT id, data FROM api.transactions_raw;

DROP TRIGGER staging_transaction_update ON api.transactions_staging;

DROP TABLE api.transactions_staging;

-- Create indexes
CREATE INDEX ON api.messages_main USING GIN (mentions);

COMMIT;
