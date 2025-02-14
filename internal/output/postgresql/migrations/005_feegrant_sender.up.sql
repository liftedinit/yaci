BEGIN;


CREATE OR REPLACE FUNCTION update_message_main()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  sender TEXT;
  mentions TEXT[];
  metadata JSONB;
  decoded_bytes BYTEA;
  decoded_text TEXT;
  decoded_json JSONB;
  new_addresses TEXT[];
BEGIN
  sender := COALESCE(
    NULLIF(NEW.data->>'sender', ''),
    NULLIF(NEW.data->>'fromAddress', ''),
    NULLIF(NEW.data->>'admin', ''),
    NULLIF(NEW.data->>'voter', ''),
    NULLIF(NEW.data->>'address', ''),
    NULLIF(NEW.data->>'executor', ''),
    NULLIF(NEW.data->>'authority', ''),
    NULLIF(New.data->>'granter', ''),
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

  -- Extract the decoded data from the IBC packet
  IF NEW.data->>'@type' = '/ibc.core.channel.v1.MsgRecvPacket' THEN
    IF metadata->'packet' ? 'data' THEN
      BEGIN
        decoded_bytes := decode(metadata->'packet'->>'data', 'base64');
        decoded_text := convert_from(decoded_bytes, 'UTF8');
        decoded_json := decoded_text::jsonb;
        metadata := metadata || jsonb_build_object('decodedData', decoded_json);
        IF decoded_json ? 'sender' THEN
          sender := decoded_json->>'sender';
        END IF;
        new_addresses := extract_addresses(decoded_json);
        SELECT array_agg(DISTINCT addr) INTO mentions
        FROM unnest(mentions || new_addresses) AS addr;
      EXCEPTION WHEN OTHERS THEN
        -- On error, update the error field in the matching transaction
        UPDATE api.transactions_main
        SET error = 'Error decoding base64 packet data'
        WHERE id = NEW.id;
      END;
    END IF;
  END IF;

  INSERT INTO api.messages_main (id, message_index, type, sender, mentions, metadata)
  VALUES (
           NEW.id,
           NEW.message_index,
           NEW.data->>'@type',
           sender,
           mentions,
           metadata
         )
  ON CONFLICT (id, message_index) DO UPDATE
  SET type = EXCLUDED.type,
      sender = EXCLUDED.sender,
      mentions = EXCLUDED.mentions,
      metadata = EXCLUDED.metadata;

  RETURN NEW;
END;
$$;

---
-- Convert the existing data to the new schema using a staging table and our update triggers
---
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
SELECT id, data
FROM api.transactions_raw;

DROP TRIGGER staging_transaction_update ON api.transactions_staging;
DROP TABLE api.transactions_staging;

COMMIT;