# Demo Account Rotation Runbook (All Weather EA)

## Goal
Support demo account resets (typically every ~30 days) without losing portfolio state.

## Procedure
1. **Export terminal files** (optional backup):
   - Copy `MQL5/Files/portfolio_bridge/state/` and `MQL5/Files/portfolio_bridge/logs/`.
2. **Switch to new demo account** in the MT5 terminal.
3. **Reattach the EA** to the same chart/symbol set.
4. **Verify bootstrap**:
   - EA detects account signature mismatch.
   - EA runs bootstrap to recreate target-weight positions.
5. **Review logs**:
   - Check `MQL5/Files/portfolio_bridge/logs/portfolio_log.txt` for `Bootstrap start/end` and account mismatch.

## Notes
- The EA stores `account_signature` (login + server) and uses it to decide bootstrap.
- State is account-agnostic because it survives account changes via file persistence.
