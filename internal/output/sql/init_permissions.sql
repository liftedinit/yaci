-- TODO: Doesn't work, fix this
-- Revoke EXECUTE privilege on specific functions from web_anon role
REVOKE EXECUTE ON FUNCTION api.parse_msg_send FROM web_anon;
REVOKE EXECUTE ON FUNCTION api.parse_msg_payout FROM web_anon;
REVOKE EXECUTE ON FUNCTION api.parse_msg_burn_held_balance FROM web_anon;
REVOKE EXECUTE ON FUNCTION api.parse_msg_submit_proposal FROM web_anon;
REVOKE EXECUTE ON FUNCTION api.parse_msg_vote FROM web_anon;
REVOKE EXECUTE ON FUNCTION api.parse_msg_exec FROM web_anon;
REVOKE EXECUTE ON FUNCTION api.parse_msg_update_group_members FROM web_anon;
REVOKE EXECUTE ON FUNCTION api.parse_msg_create_group_with_policy FROM web_anon;
REVOKE EXECUTE ON FUNCTION api.parse_msg_update_group_metadata FROM web_anon;
REVOKE EXECUTE ON FUNCTION api.parse_msg_update_group_policy_metadata FROM web_anon;
REVOKE EXECUTE ON FUNCTION api.parse_msg_update_group_policy_decision_policy FROM web_anon;
REVOKE EXECUTE ON FUNCTION api.parse_msg_withdraw_proposal FROM web_anon;
REVOKE EXECUTE ON FUNCTION api.parse_msg_leave_group FROM web_anon;
REVOKE EXECUTE ON FUNCTION api.parse_group_txs FROM web_anon;
REVOKE EXECUTE ON FUNCTION api.parse_msg_create_denom FROM web_anon;
REVOKE EXECUTE ON FUNCTION api.parse_set_denom_metadata FROM web_anon;
REVOKE EXECUTE ON FUNCTION api.parse_tokenfactory_txs FROM web_anon;
REVOKE EXECUTE ON FUNCTION api.parse_tx FROM web_anon;
REVOKE EXECUTE ON FUNCTION api.txs_containing FROM web_anon;
REVOKE EXECUTE ON FUNCTION api.executed_proposals_containing FROM web_anon;
