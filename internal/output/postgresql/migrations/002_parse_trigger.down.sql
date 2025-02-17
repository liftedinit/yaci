BEGIN;

DROP INDEX IF EXISTS api.message_main_mentions_idx;
DROP INDEX IF EXISTS api.message_main_sender_idx;

REVOKE EXECUTE ON FUNCTION api.get_messages_for_address(TEXT) FROM web_anon;
REVOKE SELECT ON api.messages_main FROM web_anon;
REVOKE SELECT ON api.messages_raw FROM web_anon;
REVOKE SELECT ON api.transactions_raw FROM web_anon;
REVOKE SELECT ON api.transactions_main FROM web_anon;
REVOKE SELECT ON api.blocks_raw FROM web_anon;

DROP FUNCTION IF EXISTS api.get_messages_for_address(TEXT);

DROP TRIGGER IF EXISTS new_message_update ON api.messages_raw;
DROP TRIGGER IF EXISTS new_transaction_update ON api.transactions_raw;

DROP FUNCTION IF EXISTS update_message_main();
DROP FUNCTION IF EXISTS update_transaction_main();
DROP FUNCTION IF EXISTS extract_proposal_ids(JSONB);
DROP FUNCTION IF EXISTS extract_proposal_failure_logs(json_data JSONB);
DROP FUNCTION IF EXISTS extract_metadata(JSONB);

DROP TABLE api.messages_main;
DROP TABLE api.messages_raw;
DROP TABLE api.transactions_main;

ALTER TABLE api.transactions_raw RENAME TO transactions;
ALTER TABLE api.blocks_raw RENAME TO blocks;

GRANT SELECT ON api.blocks TO web_anon;
GRANT SELECT ON api.transactions TO web_anon;

CREATE OR REPLACE FUNCTION api.get_address_filtered_transactions_and_successful_proposals(address TEXT)
RETURNS TABLE (id VARCHAR(64), data JSONB)
AS $$
WITH base_messages AS (
  SELECT
    t.id,
    t.data,
    msg.value AS message
  FROM
    api.transactions t,
    LATERAL jsonb_array_elements(t.data -> 'tx' -> 'body' -> 'messages') AS msg(value)
  WHERE
    -- Exclude messages that are MsgSubmitProposal
    msg.value ->> '@type' != '/cosmos.group.v1.MsgSubmitProposal'
),
filtered_messages AS (
  SELECT
    id,
    data
  FROM
    base_messages
  WHERE
    -- Include only desired message types
    message ->> '@type' IN (
      '/cosmos.bank.v1beta1.MsgSend',
      '/osmosis.tokenfactory.v1beta1.MsgMint',
      '/osmosis.tokenfactory.v1beta1.MsgBurn'
    )
    -- Check if the message contains the given address anywhere in its content
    AND message::text ILIKE '%' || address || '%'
),
submit_proposals AS (
  SELECT
    t.id AS submit_id,
    t.data AS submit_data,
    proposal_attr.attr ->> 'value' AS proposal_id
  FROM
    api.transactions t
    JOIN LATERAL jsonb_array_elements(t.data -> 'tx' -> 'body' -> 'messages') AS msg(value) ON TRUE
    JOIN LATERAL (
      SELECT attr
      FROM jsonb_array_elements(t.data -> 'txResponse' -> 'events') AS event,
           jsonb_array_elements(event -> 'attributes') AS attr
      WHERE event ->> 'type' = 'cosmos.group.v1.EventSubmitProposal'
        AND attr ->> 'key' = 'proposal_id'
    ) AS proposal_attr ON TRUE
  WHERE
    msg.value ->> '@type' = '/cosmos.group.v1.MsgSubmitProposal'
    AND EXISTS (
      SELECT 1
      FROM jsonb_array_elements(msg.value -> 'messages') AS nested_msg(value)
      WHERE nested_msg.value::text ILIKE '%' || address || '%'
    )
    AND EXISTS (
      SELECT 1
      FROM jsonb_array_elements(msg.value -> 'messages') AS nested_msg(value)
      WHERE nested_msg.value ->> '@type' IN (
        '/cosmos.bank.v1beta1.MsgSend',
        '/osmosis.tokenfactory.v1beta1.MsgMint',
        '/osmosis.tokenfactory.v1beta1.MsgBurn',
        '/liftedinit.manifest.v1.MsgPayout',
        '/liftedinit.manifest.v1.MsgBurnHeldBalance'
      )
    )
),
execs AS (
  SELECT
    t.id AS exec_id,
    t.data AS exec_data,
    attrs.attr_map ->> 'proposal_id' AS proposal_id,
    attrs.attr_map ->> 'result' AS result
  FROM
    api.transactions t
    JOIN LATERAL (
      SELECT event
      FROM jsonb_array_elements(t.data -> 'txResponse' -> 'events') AS event
      WHERE event ->> 'type' = 'cosmos.group.v1.EventExec'
      LIMIT 1
    ) AS exec_event ON TRUE
    JOIN LATERAL (
      SELECT jsonb_object_agg(attr ->> 'key', attr ->> 'value') AS attr_map
      FROM jsonb_array_elements(exec_event.event -> 'attributes') AS attr
    ) AS attrs(attr_map) ON TRUE
),
matching_proposals AS (
  SELECT
    sp.submit_id AS id,
    sp.submit_data AS data
  FROM
    submit_proposals sp
    JOIN execs e ON sp.proposal_id = e.proposal_id
)
SELECT DISTINCT id, data
FROM
(
  SELECT
    id,
    data
  FROM filtered_messages
  WHERE COALESCE((data->'txResponse'->>'code')::int, 0) = 0
  UNION
  SELECT
    id,
    data
  FROM matching_proposals
  WHERE COALESCE((data->'txResponse'->>'code')::int, 0) = 0
) combined;
$$ LANGUAGE SQL STABLE;

COMMIT;
